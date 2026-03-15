#!/usr/bin/env bash
# generate-terraform.sh — Generate Terraform HCL from Sysdig Secure backup files
#
# Usage:
#   ./generate-terraform.sh          Generate all .tf files from backups/
#
# Output:
#   terraform/provider.tf            Sysdig provider block (written once)
#   terraform/policies.tf            sysdig_secure_policy resources
#   terraform/notification-channels.tf  sysdig_secure_notification_channel_* resources
#   terraform/rules.tf               sysdig_secure_rule_falco resources
#   terraform/teams.tf               sysdig_secure_team resources
#   terraform/alerts.tf              sysdig_monitor_alert_v2 resources
#   terraform/main.tf                Combined file with all resource types

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# Ensure BACKUP_DIR is set (load_config sets it; allow override via env)
BACKUP_DIR="${BACKUP_DIR:-${SCRIPT_DIR}/backups}"
TF_DIR="${SCRIPT_DIR}/terraform"
TF_SRC_DIR="${TF_DIR}/src"
SYSDIG_TF_CHUNK_SIZE="${SYSDIG_TF_CHUNK_SIZE:-200}"

mkdir -p "${TF_DIR}" "${TF_SRC_DIR}"

# Track generated files and counts for summary
GENERATED_FILES=()
GENERATED_COUNTS=()

# ---------------------------------------------------------------------------
# HCL helpers
# ---------------------------------------------------------------------------

# sanitize_tf_label <filename>
# Converts a backup filename (without .json) to a valid Terraform resource label.
sanitize_tf_label() {
  local name="$1"
  local label
  label=$(echo "${name%.json}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9_]/_/g' \
    | sed 's/__*/_/g' \
    | sed 's/^_//;s/_$//')
  # Prefix with underscore if starts with digit
  if [[ "${label}" =~ ^[0-9] ]]; then
    label="_${label}"
  fi
  echo "${label}"
}

# hcl_string <value>
# Escapes a value for use inside HCL double quotes.
hcl_string() {
  local val="$1"
  # Escape backslashes then double quotes
  val="${val//\\/\\\\}"
  val="${val//\"/\\\"}"
  echo "${val}"
}

# hcl_bool <value>
# Outputs 'true' or 'false' for HCL boolean fields.
hcl_bool() {
  local val="$1"
  if [[ "${val}" == "true" || "${val}" == "1" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

# ---------------------------------------------------------------------------
# Chunked output helpers
# ---------------------------------------------------------------------------

# clean_tf_type <prefix>
# Removes all existing .tf files for a resource type (both single and chunked)
# from TF_SRC_DIR. Call at the start of each generator to avoid stale files.
clean_tf_type() {
  local prefix="$1"
  rm -f "${TF_SRC_DIR}/${prefix}.tf"
  rm -f "${TF_SRC_DIR}/${prefix}"-[0-9][0-9][0-9].tf
}

# finalize_tf_chunks <prefix>
# Splits TF_SRC_DIR/<prefix>.tf into numbered chunk files when resource count
# exceeds SYSDIG_TF_CHUNK_SIZE. No-ops when threshold is 0 or count is within
# threshold. Always cleans stale numbered chunks from previous larger runs.
finalize_tf_chunks() {
  local prefix="$1"
  local src="${TF_SRC_DIR}/${prefix}.tf"
  local chunk_size="${SYSDIG_TF_CHUNK_SIZE:-200}"

  # Clean numbered chunks from any previous run (monolithic file stays until split)
  rm -f "${TF_SRC_DIR}/${prefix}"-[0-9][0-9][0-9].tf

  [[ -f "${src}" ]] || return 0

  local total
  total=$(grep -c '^resource ' "${src}" 2>/dev/null || echo 0)

  # No split needed
  if [[ "${chunk_size}" -eq 0 || "${total}" -le "${chunk_size}" ]]; then
    return 0
  fi

  echo "  Splitting ${prefix}.tf into chunks (${total} resources, ${chunk_size} per file)..."

  local chunk_num=1
  local count_in_chunk=0
  local chunk_file in_resource
  chunk_file=$(printf "%s/%s-%03d.tf" "${TF_SRC_DIR}" "${prefix}" "${chunk_num}")
  : > "${chunk_file}"
  in_resource=false

  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" =~ ^resource\ \" ]]; then
      in_resource=true
    fi

    printf "%s\n" "${line}" >> "${chunk_file}"

    if [[ "${in_resource}" == true && "${line}" == "}" ]]; then
      in_resource=false
      (( count_in_chunk++ )) || true

      if [[ "${count_in_chunk}" -ge "${chunk_size}" ]]; then
        (( chunk_num++ )) || true
        count_in_chunk=0
        chunk_file=$(printf "%s/%s-%03d.tf" "${TF_SRC_DIR}" "${prefix}" "${chunk_num}")
        : > "${chunk_file}"
      fi
    fi
  done < "${src}"

  rm -f "${src}"
}

# ---------------------------------------------------------------------------
# Provider file (written once, never overwritten)
# ---------------------------------------------------------------------------

write_provider_tf() {
  local provider_file="${TF_DIR}/provider.tf"

  if [[ -f "${provider_file}" ]]; then
    echo "Skipping terraform/provider.tf (already exists — not overwriting operator customisations)"
    return 0
  fi

  cat > "${provider_file}" <<'EOF'
terraform {
  required_providers {
    sysdig = {
      source  = "sysdiglabs/sysdig"
      version = ">= 1.0.0"
    }
  }
}

provider "sysdig" {
  sysdig_secure_api_token = var.sysdig_secure_api_token
}

variable "sysdig_secure_api_token" {
  description = "Sysdig Secure API token"
  type        = string
  sensitive   = true
}
EOF

  echo "Written: terraform/provider.tf"
}

# ---------------------------------------------------------------------------
# Policies
# ---------------------------------------------------------------------------

generate_policies() {
  local in_dir="${BACKUP_DIR}/policies"
  local out_file="${TF_SRC_DIR}/policies.tf"
  local count=0

  clean_tf_type "policies"

  if [[ ! -d "${in_dir}" ]] || [[ -z "$(ls -A "${in_dir}" 2>/dev/null)" ]]; then
    echo "No policies found — skipping policies.tf"
    return 0
  fi

  : > "${out_file}"

  for f in "${in_dir}"/*.json; do
    [[ -f "${f}" ]] || continue
    local label
    label=$(sanitize_tf_label "$(basename "${f}")")
    local json
    json=$(cat "${f}")

    local name enabled severity description scope type tf_resource
    name=$(echo "${json}"        | jq -r '.name // ""')
    enabled=$(echo "${json}"     | jq -r '.enabled // true')
    severity=$(echo "${json}"    | jq -r '.severity // 4')
    description=$(echo "${json}" | jq -r '.description // ""')
    scope=$(echo "${json}"       | jq -r '.scope // ""')
    type=$(echo "${json}"        | jq -r '.type // ""')
    tf_resource=$(policy_tf_resource "${type}")

    if [[ -z "${tf_resource}" ]]; then
      echo "# WARNING: policy type '${type}' for '${name}' has no known Terraform resource — emitting as comment" >> "${out_file}"
      echo "# resource \"sysdig_secure_custom_policy\" \"${label}\" { name = \"$(hcl_string "${name}")\" /* type=${type} — review manually */ }" >> "${out_file}"
      echo "" >> "${out_file}"
      (( count++ )) || true
      continue
    fi

    {
      echo "resource \"${tf_resource}\" \"${label}\" {"
      echo "  name    = \"$(hcl_string "${name}")\""
      echo "  enabled = $(hcl_bool "${enabled}")"
      [[ -n "${scope}" ]] && echo "  scope   = \"$(hcl_string "${scope}")\""

      # managed_policy has no description or severity
      if ! is_managed_policy "${type}"; then
        echo "  description = \"$(hcl_string "${description}")\""
        echo "  severity    = ${severity}"
      fi

      # rule blocks — required by provider schema for most policy types
      # custom_policy uses a `rules` block with a `name` attribute
      if [[ "${tf_resource}" == "sysdig_secure_custom_policy" ]]; then
        local rule_names_json
        rule_names_json=$(echo "${json}" | jq -c '[.rules[]?.ruleName // .rules[]?.name // empty]' 2>/dev/null || true)
        if [[ "${rule_names_json}" == "[]" || -z "${rule_names_json}" ]]; then
          rule_names_json='["# PLACEHOLDER - add rule name"]'
        fi
        echo "${rule_names_json}" | jq -r '.[]' | while IFS= read -r rname; do
          echo "  rules {"
          echo "    name = \"$(hcl_string "${rname}")\""
          echo "  }"
        done
      elif [[ "${tf_resource}" != "sysdig_secure_managed_policy" ]]; then
        # drift, malware, ml, aws_ml, okta_ml — use `rule` block with description
        local rule_names_json
        rule_names_json=$(echo "${json}" | jq -c '[.rules[]?.ruleName // .rules[]?.name // empty]' 2>/dev/null || true)
        if [[ "${rule_names_json}" == "[]" || -z "${rule_names_json}" ]]; then
          rule_names_json='["# PLACEHOLDER - add rule description"]'
        fi
        echo "${rule_names_json}" | jq -r '.[]' | while IFS= read -r rname; do
          echo "  rule {"
          echo "    description = \"$(hcl_string "${rname}")\""
          echo "  }"
        done
      fi

      # Read-only fields as comments
      echo "  # id                    = $(echo "${json}" | jq -r '.id // "unknown"')"
      echo "  # type                  = \"${type}\""
      echo "  # notificationChannelIds = $(echo "${json}" | jq -c '.notificationChannelIds // []')"

      echo "}"
      echo ""
    } >> "${out_file}"

    (( count++ )) || true
  done

  finalize_tf_chunks "policies"
  GENERATED_FILES+=("terraform/src/policies.tf")
  GENERATED_COUNTS+=("${count}")
  echo "terraform/src/policies.tf — ${count} resources"
}

# ---------------------------------------------------------------------------
# Notification Channels
# ---------------------------------------------------------------------------

# Maps Sysdig API channel type → Terraform resource type
channel_tf_resource() {
  local api_type="$1"
  case "${api_type}" in
    SLACK)                      echo "sysdig_secure_notification_channel_slack" ;;
    EMAIL)                      echo "sysdig_secure_notification_channel_email" ;;
    PAGERDUTY|PAGER_DUTY)       echo "sysdig_secure_notification_channel_pagerduty" ;;
    WEBHOOK)                    echo "sysdig_secure_notification_channel_webhook" ;;
    VICTOROPS)                  echo "sysdig_secure_notification_channel_victorops" ;;
    OPSGENIE)                   echo "sysdig_secure_notification_channel_opsgenie" ;;
    MSTEAMS|TEAMS|MS_TEAMS)     echo "sysdig_secure_notification_channel_msteams" ;;
    SNS)                        echo "sysdig_secure_notification_channel_sns" ;;
    PROMETHEUS|PROMETHEUS_ALERT_MANAGER) echo "sysdig_secure_notification_channel_prometheus_alert_manager" ;;
    *)                          echo "" ;;
  esac
}

# Maps Sysdig API policy type → Terraform resource type
# Returns empty string for types that have no direct Terraform equivalent
policy_tf_resource() {
  local api_type="$1"
  case "${api_type}" in
    falco|fim)                                      echo "sysdig_secure_custom_policy" ;;
    drift)                                          echo "sysdig_secure_drift_policy" ;;
    malware)                                        echo "sysdig_secure_malware_policy" ;;
    machine_learning)                               echo "sysdig_secure_ml_policy" ;;
    aws_machine_learning)                           echo "sysdig_secure_aws_ml_policy" ;;
    okta_machine_learning)                          echo "sysdig_secure_okta_ml_policy" ;;
    aws_cloudtrail|awscloudtrail|awscloudtrail_stateful|\
    azure_entra|azure_platformlogs|gcp_auditlog|\
    github|guardduty|k8s_audit|okta|windows)        echo "sysdig_secure_managed_policy" ;;
    *)                                              echo "" ;;
  esac
}

# Returns true if a policy type uses the managed_policy schema (no description/severity/rules)
is_managed_policy() {
  case "$1" in
    aws_cloudtrail|awscloudtrail|awscloudtrail_stateful|\
    azure_entra|azure_platformlogs|gcp_auditlog|\
    github|guardduty|k8s_audit|okta|windows) return 0 ;;
    *) return 1 ;;
  esac
}

generate_notification_channels() {
  local in_dir="${BACKUP_DIR}/notification-channels"
  local out_file="${TF_SRC_DIR}/notification-channels.tf"
  local count=0

  clean_tf_type "notification-channels"

  if [[ ! -d "${in_dir}" ]] || [[ -z "$(ls -A "${in_dir}" 2>/dev/null)" ]]; then
    echo "No notification channels found — skipping notification-channels.tf"
    return 0
  fi

  : > "${out_file}"

  for f in "${in_dir}"/*.json; do
    [[ -f "${f}" ]] || continue
    local label
    label=$(sanitize_tf_label "$(basename "${f}")")
    local json
    json=$(cat "${f}")

    local name api_type tf_resource
    name=$(echo "${json}"     | jq -r '.name // ""')
    api_type=$(echo "${json}" | jq -r '.type // ""')
    tf_resource=$(channel_tf_resource "${api_type}")

    if [[ -z "${tf_resource}" ]]; then
      echo "WARNING: Unknown notification channel type '${api_type}' for '${name}' — skipping" >&2
      continue
    fi

    local notify_ok notify_resolved
    notify_ok=$(echo "${json}"       | jq -r '.options.notifyOnOk // false')
    notify_resolved=$(echo "${json}" | jq -r '.options.notifyOnResolve // true')

    {
      echo "resource \"${tf_resource}\" \"${label}\" {"
      echo "  name                    = \"$(hcl_string "${name}")\""
      echo "  notify_when_ok          = $(hcl_bool "${notify_ok}")"
      echo "  notify_when_resolved    = $(hcl_bool "${notify_resolved}")"
      echo "  send_test_notification  = false"

      # Type-specific options
      case "${api_type}" in
        SLACK)
          local url ch
          url=$(echo "${json}" | jq -r '.options.url // ""')
          ch=$(echo "${json}"  | jq -r '.options.channel // ""')
          echo "  url     = \"$(hcl_string "${url}")\""
          echo "  channel = \"$(hcl_string "${ch}")\""
          ;;
        EMAIL)
          local recipients_hcl
          recipients_hcl=$(echo "${json}" | jq -r '.options.emailRecipients // [] | map(@json) | join(", ")')
          echo "  recipients = [${recipients_hcl}]"
          ;;
        PAGERDUTY|PAGER_DUTY)
          local acct svc_key svc_name
          acct=$(echo "${json}"     | jq -r '.options.account // ""')
          svc_key=$(echo "${json}"  | jq -r '.options.serviceKey // ""')
          svc_name=$(echo "${json}" | jq -r '.options.serviceName // ""')
          echo "  account      = \"$(hcl_string "${acct}")\""
          echo "  service_key  = \"REPLACE_WITH_SECRET\"  # was: $(hcl_string "${svc_key}")"
          echo "  service_name = \"$(hcl_string "${svc_name}")\""
          ;;
        WEBHOOK)
          local url
          url=$(echo "${json}" | jq -r '.options.url // ""')
          echo "  url = \"$(hcl_string "${url}")\""
          ;;
        MSTEAMS|TEAMS|MS_TEAMS)
          local ms_url
          ms_url=$(echo "${json}" | jq -r '.options.url // ""')
          echo "  url = \"$(hcl_string "${ms_url}")\""
          ;;
        VICTOROPS)
          local api_key routing_key
          api_key=$(echo "${json}" | jq -r '.options.apiKey // ""')
          routing_key=$(echo "${json}" | jq -r '.options.routingKey // ""')
          echo "  # api_key     = \"REPLACE_WITH_SECRET\"  # was: $(hcl_string "${api_key}")"
          echo "  routing_key  = \"$(hcl_string "${routing_key}")\""
          ;;
        OPSGENIE)
          local api_key
          api_key=$(echo "${json}" | jq -r '.options.apiKey // ""')
          echo "  # api_key = \"REPLACE_WITH_SECRET\"  # was: $(hcl_string "${api_key}")"
          ;;
        PROMETHEUS|PROMETHEUS_ALERT_MANAGER)
          local prom_url
          prom_url=$(echo "${json}" | jq -r '.options.url // ""')
          echo "  url = \"$(hcl_string "${prom_url}")\""
          ;;
        SNS)
          local topics
          topics=$(echo "${json}" | jq -r '.options.snsTopicARNs // [] | join("\", \"")' 2>/dev/null || true)
          [[ -n "${topics}" ]] && echo "  topics = [\"${topics}\"]"
          ;;
      esac

      echo "  # id   = $(echo "${json}" | jq -r '.id // "unknown"')"
      echo "  # type = \"${api_type}\""
      echo "}"
      echo ""
    } >> "${out_file}"

    (( count++ )) || true
  done

  finalize_tf_chunks "notification-channels"
  GENERATED_FILES+=("terraform/src/notification-channels.tf")
  GENERATED_COUNTS+=("${count}")
  echo "terraform/src/notification-channels.tf — ${count} resources"
}

# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------

generate_rules() {
  local in_dir="${BACKUP_DIR}/rules"
  local out_file="${TF_SRC_DIR}/rules.tf"
  local count=0

  clean_tf_type "rules"

  if [[ ! -d "${in_dir}" ]] || [[ -z "$(ls -A "${in_dir}" 2>/dev/null)" ]]; then
    echo "No rules found — skipping rules.tf"
    return 0
  fi

  : > "${out_file}"

  for f in "${in_dir}"/*.json; do
    [[ -f "${f}" ]] || continue
    local label
    label=$(sanitize_tf_label "$(basename "${f}")")
    local json
    json=$(cat "${f}")

    # Rules may be a single object or an array; handle both
    local rule
    if echo "${json}" | jq -e 'type == "array"' > /dev/null 2>&1; then
      rule=$(echo "${json}" | jq '.[0]')
    else
      rule="${json}"
    fi

    local name description tags condition output priority source
    name=$(echo "${rule}"        | jq -r '.name // ""')
    description=$(echo "${rule}" | jq -r '.description // ""')
    tags=$(echo "${rule}"        | jq -r '.tags // [] | join("\", \"")' 2>/dev/null || true)
    # Escape newlines so multi-line conditions become single-line HCL strings
    condition=$(echo "${rule}"   | jq -r '.details.condition.condition // .details.condition // ""' 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g;s/^ //;s/ $//' || true)
    output=$(echo "${rule}"      | jq -r '.details.output // ""' 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g;s/^ //;s/ $//' || true)
    # Priority must be lowercase for the provider (API returns uppercase)
    priority=$(echo "${rule}"    | jq -r '.details.priority // ""' 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
    source=$(echo "${rule}"      | jq -r '.details.source // ""' 2>/dev/null || true)

    {
      echo "resource \"sysdig_secure_rule_falco\" \"${label}\" {"
      echo "  name        = \"$(hcl_string "${name}")\""
      echo "  description = \"$(hcl_string "${description}")\""
      [[ -n "${tags}" ]]      && echo "  tags        = [\"${tags}\"]"
      [[ -n "${condition}" ]] && echo "  condition   = \"$(hcl_string "${condition}")\""
      [[ -n "${output}" ]]    && echo "  output      = \"$(hcl_string "${output}")\""
      [[ -n "${priority}" ]]  && echo "  priority    = \"$(hcl_string "${priority}")\""
      # Valid provider sources: syscall k8s_audit aws_cloudtrail gcp_auditlog azure_platformlogs awscloudtrail okta github guardduty
      if [[ -n "${source}" ]]; then
        case "${source}" in
          syscall|k8s_audit|aws_cloudtrail|gcp_auditlog|azure_platformlogs|awscloudtrail|okta|github|guardduty)
            echo "  source      = \"$(hcl_string "${source}")\""
            ;;
          *)
            echo "  # source   = \"${source}\"  # not a supported provider source value — review manually"
            ;;
        esac
      fi

      echo "  # id         = $(echo "${rule}" | jq -r '.id // "unknown"')"
      echo "  # origin     = $(echo "${rule}" | jq -r '.origin // "unknown"')"
      echo "  # versionId  = $(echo "${rule}" | jq -r '.versionId // "unknown"')"
      echo "  # modifiedOn = $(echo "${rule}" | jq -r '.modifiedOn // "unknown"')"
      echo "}"
      echo ""
    } >> "${out_file}"

    (( count++ )) || true
  done

  finalize_tf_chunks "rules"
  GENERATED_FILES+=("terraform/src/rules.tf")
  GENERATED_COUNTS+=("${count}")
  echo "terraform/src/rules.tf — ${count} resources"
}

# ---------------------------------------------------------------------------
# Teams
# ---------------------------------------------------------------------------

generate_teams() {
  local in_dir="${BACKUP_DIR}/teams"
  local out_file="${TF_SRC_DIR}/teams.tf"
  local count=0

  clean_tf_type "teams"

  if [[ ! -d "${in_dir}" ]] || [[ -z "$(ls -A "${in_dir}" 2>/dev/null)" ]]; then
    echo "No teams found — skipping teams.tf"
    return 0
  fi

  : > "${out_file}"

  for f in "${in_dir}"/*.json; do
    [[ -f "${f}" ]] || continue
    local label
    label=$(sanitize_tf_label "$(basename "${f}")")
    local json
    json=$(cat "${f}")

    local name description filter scope_by use_capture default_team
    name=$(echo "${json}"         | jq -r '.name // ""')
    description=$(echo "${json}"  | jq -r '.description // ""')
    filter=$(echo "${json}"       | jq -r '.filter // ""')
    scope_by=$(echo "${json}"     | jq -r '.show // "host"')
    use_capture=$(echo "${json}"  | jq -r '.canUseSysdigCapture // false')
    default_team=$(echo "${json}" | jq -r '.defaultTeam // false')

    {
      echo "resource \"sysdig_secure_team\" \"${label}\" {"
      echo "  name         = \"$(hcl_string "${name}")\""
      echo "  description  = \"$(hcl_string "${description}")\""
      echo "  scope_by     = \"$(hcl_string "${scope_by}")\""
      [[ -n "${filter}" ]] && echo "  filter       = \"$(hcl_string "${filter}")\""
      echo "  use_sysdig_capture = $(hcl_bool "${use_capture}")"
      echo "  default_team       = $(hcl_bool "${default_team}")"

      # User memberships — require manual review as they reference user accounts
      local user_count
      user_count=$(echo "${json}" | jq '.userRoles // [] | length')
      echo "  # userRoles (${user_count} members) — add user_roles blocks manually if needed"
      echo "  # id           = $(echo "${json}" | jq -r '.id // "unknown"')"
      echo "}"
      echo ""
    } >> "${out_file}"

    (( count++ )) || true
  done

  finalize_tf_chunks "teams"
  GENERATED_FILES+=("terraform/src/teams.tf")
  GENERATED_COUNTS+=("${count}")
  echo "terraform/src/teams.tf — ${count} resources"
}

# ---------------------------------------------------------------------------
# Alerts
# ---------------------------------------------------------------------------

generate_alerts() {
  local in_dir="${BACKUP_DIR}/alerts"
  local out_file="${TF_SRC_DIR}/alerts.tf"
  local count=0

  clean_tf_type "alerts"

  if [[ ! -d "${in_dir}" ]] || [[ -z "$(ls -A "${in_dir}" 2>/dev/null)" ]]; then
    echo "No alerts found — skipping alerts.tf"
    return 0
  fi

  : > "${out_file}"

  for f in "${in_dir}"/*.json; do
    [[ -f "${f}" ]] || continue
    local label
    label=$(sanitize_tf_label "$(basename "${f}")")
    local json
    json=$(cat "${f}")

    local name description enabled severity
    name=$(echo "${json}"        | jq -r '.name // ""')
    description=$(echo "${json}" | jq -r '.description // ""')
    enabled=$(echo "${json}"     | jq -r '.enabled // true')
    severity=$(echo "${json}"    | jq -r '.severity // 4')

    {
      echo "resource \"sysdig_monitor_alert_v2\" \"${label}\" {"
      echo "  name        = \"$(hcl_string "${name}")\""
      echo "  description = \"$(hcl_string "${description}")\""
      echo "  enabled     = $(hcl_bool "${enabled}")"
      echo "  severity    = ${severity}"

      # Remaining fields as comments — alert types vary widely
      echo "  # Full alert config — review and expand from source JSON:"
      echo "  # $(echo "${json}" | jq -c 'del(.name,.description,.enabled,.severity,.id,.createdOn,.modifiedOn)')"
      echo "  # id = $(echo "${json}" | jq -r '.id // "unknown"')"
      echo "}"
      echo ""
    } >> "${out_file}"

    (( count++ )) || true
  done

  finalize_tf_chunks "alerts"
  GENERATED_FILES+=("terraform/src/alerts.tf")
  GENERATED_COUNTS+=("${count}")
  echo "terraform/src/alerts.tf — ${count} resources"
}

# ---------------------------------------------------------------------------
# Combined main.tf
# ---------------------------------------------------------------------------

write_combined_tf() {
  local out_file="${TF_DIR}/main.tf"
  local type_labels=(
    "policies:Policies"
    "notification-channels:Notification Channels"
    "rules:Rules"
    "teams:Teams"
    "alerts:Alerts"
  )

  : > "${out_file}"

  local total=0
  for entry in "${type_labels[@]}"; do
    local prefix="${entry%%:*}"
    local label="${entry##*:}"
    local wrote_header=false

    # Collect both single file and numbered chunk files for this type
    local src
    for src in "${TF_SRC_DIR}/${prefix}.tf" "${TF_SRC_DIR}/${prefix}"-[0-9][0-9][0-9].tf; do
      [[ -f "${src}" ]] && [[ -s "${src}" ]] || continue

      if [[ "${wrote_header}" == false ]]; then
        {
          echo "# ============================================================"
          echo "# ${label}"
          echo "# ============================================================"
          echo ""
        } >> "${out_file}"
        wrote_header=true
      fi

      cat "${src}" >> "${out_file}"

      local n
      n=$(grep -c '^resource ' "${src}" 2>/dev/null || echo 0)
      (( total += n )) || true
    done
  done

  echo "terraform/main.tf — ${total} total resources (combined, used by terraform init)"
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

print_summary() {
  local total=0
  echo ""
  echo "=== Terraform generation complete ==="
  for i in "${!GENERATED_FILES[@]}"; do
    echo "  ${GENERATED_FILES[$i]} — ${GENERATED_COUNTS[$i]} resources"
    (( total += GENERATED_COUNTS[$i] )) || true
  done
  echo "  terraform/main.tf — combined"
  echo "  terraform/provider.tf — provider config"
  echo "  Total: ${total} resources"
  echo ""
  echo "Next steps:"
  echo "  cd terraform && terraform init && terraform validate"
  echo "  Review credential fields marked with REPLACE_WITH_SECRET"
  echo "  Run: terraform plan"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

write_provider_tf
generate_policies
generate_notification_channels
generate_rules
generate_teams
generate_alerts
write_combined_tf
print_summary
