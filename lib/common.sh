#!/usr/bin/env bash
# lib/common.sh — Shared functions for sysdig-config-backup scripts

# ---------------------------------------------------------------------------
# Configuration loading
# ---------------------------------------------------------------------------

load_config() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

  # Source config.sh if present (takes precedence over existing env vars)
  if [[ -f "${script_dir}/config.sh" ]]; then
    # shellcheck source=/dev/null
    source "${script_dir}/config.sh"
  fi

  # Apply defaults
  SYSDIG_API_URL="${SYSDIG_API_URL:-https://secure.sysdig.com}"
  SYSDIG_PAGE_SIZE="${SYSDIG_PAGE_SIZE:-100}"
  BACKUP_DIR="${script_dir}/backups"

  # Export so subprocess exporters inherit these values
  export SYSDIG_API_TOKEN SYSDIG_API_URL SYSDIG_PAGE_SIZE BACKUP_DIR
}

validate_config() {
  if [[ -z "${SYSDIG_API_TOKEN:-}" ]]; then
    echo "ERROR: SYSDIG_API_TOKEN is not set." >&2
    echo "  Copy config.sh.example to config.sh and set your token, or export SYSDIG_API_TOKEN." >&2
    exit 1
  fi

  if [[ -n "${SYSDIG_CA_CERT:-}" && ! -f "${SYSDIG_CA_CERT}" ]]; then
    echo "ERROR: SYSDIG_CA_CERT is set but the file does not exist: ${SYSDIG_CA_CERT}" >&2
    exit 1
  fi

  if [[ "${SYSDIG_TLS_INSECURE:-}" == "true" && -n "${SYSDIG_CA_CERT:-}" ]]; then
    echo "WARNING: SYSDIG_TLS_INSECURE=true and SYSDIG_CA_CERT are both set; --insecure takes precedence and SYSDIG_CA_CERT will have no effect." >&2
  fi
}

# ---------------------------------------------------------------------------
# API helpers
# ---------------------------------------------------------------------------

# sysdig_get <path>
# Makes an authenticated GET request to the Sysdig API.
# Prints the response body to stdout.
# Returns non-zero on HTTP error.
sysdig_get() {
  local path="$1"
  local url="${SYSDIG_API_URL%/}/${path#/}"
  local http_code
  local response_file
  response_file="$(mktemp)"

  local tls_opts=()
  if [[ "${SYSDIG_TLS_INSECURE:-}" == "true" ]]; then
    tls_opts+=(--insecure)
  elif [[ -n "${SYSDIG_CA_CERT:-}" ]]; then
    tls_opts+=(--cacert "${SYSDIG_CA_CERT}")
  fi

  http_code=$(curl --silent --show-error --write-out "%{http_code}" \
    --output "${response_file}" \
    --header "Authorization: Bearer ${SYSDIG_API_TOKEN}" \
    --header "Content-Type: application/json" \
    "${tls_opts[@]+"${tls_opts[@]}"}" \
    "${url}")

  local exit_code=$?

  if [[ ${exit_code} -ne 0 ]]; then
    echo "ERROR: curl failed for ${url} (exit code ${exit_code})" >&2
    rm -f "${response_file}"
    return 1
  fi

  if [[ "${http_code}" -eq 401 || "${http_code}" -eq 403 ]]; then
    echo "ERROR: Authentication failed for ${url} (HTTP ${http_code}). Check your SYSDIG_API_TOKEN." >&2
    rm -f "${response_file}"
    return 2
  fi

  if [[ "${http_code}" -lt 200 || "${http_code}" -ge 300 ]]; then
    echo "ERROR: API request failed for ${url} (HTTP ${http_code})" >&2
    rm -f "${response_file}"
    return 1
  fi

  cat "${response_file}"
  rm -f "${response_file}"
}

# sysdig_get_paged <path> [envelope_field]
# Fetches all pages of a paginated API endpoint using limit/offset parameters.
# envelope_field: when set, extracts .<field> from each page response before
#   accumulating (e.g. "alerts" for endpoints that return { "alerts": [...] }).
#   When empty or omitted, the response body is treated as a direct JSON array.
# Prints a single merged JSON array to stdout.
# Returns non-zero if any page request fails.
sysdig_get_paged() {
  local path="$1"
  local envelope="${2:-}"
  local page_size="${SYSDIG_PAGE_SIZE:-100}"
  local offset=0
  local accumulator page_file merged_file
  accumulator="$(mktemp)"
  page_file="$(mktemp)"
  merged_file="$(mktemp)"
  echo "[]" > "${accumulator}"

  while true; do
    local page_response page_items page_count
    if ! page_response=$(sysdig_get "${path}?limit=${page_size}&offset=${offset}"); then
      rm -f "${accumulator}" "${page_file}" "${merged_file}"
      return 1
    fi

    if [[ -n "${envelope}" ]]; then
      page_items=$(echo "${page_response}" | jq -c ".${envelope} // []")
    else
      page_items="${page_response}"
    fi

    page_count=$(echo "${page_items}" | jq 'length')

    if [[ "${page_count}" -eq 0 ]]; then
      break
    fi

    echo "${page_items}" > "${page_file}"
    jq -s 'add' "${accumulator}" "${page_file}" > "${merged_file}"
    mv "${merged_file}" "${accumulator}"

    if [[ "${page_count}" -lt "${page_size}" ]]; then
      break
    fi

    (( offset += page_size )) || true
  done

  cat "${accumulator}"
  rm -f "${accumulator}" "${page_file}"
}

# ---------------------------------------------------------------------------
# Authentication validation
# ---------------------------------------------------------------------------

# validate_auth
# Makes a lightweight API call to confirm the token is valid.
# Exits with code 1 on failure.
validate_auth() {
  echo "Validating API credentials against ${SYSDIG_API_URL} ..."
  local response
  response=$(sysdig_get "/api/user/me" 2>&1)
  local rc=$?

  if [[ ${rc} -eq 2 ]]; then
    echo "ERROR: Invalid or expired API token. Aborting." >&2
    exit 1
  elif [[ ${rc} -ne 0 ]]; then
    echo "ERROR: Could not reach Sysdig API at ${SYSDIG_API_URL}. Check SYSDIG_API_URL and network connectivity." >&2
    exit 1
  fi

  echo "Authentication OK."
}

# ---------------------------------------------------------------------------
# File naming helpers
# ---------------------------------------------------------------------------

# sanitize_filename <name>
# Lowercases, replaces spaces and special chars with hyphens.
# Trims leading/trailing hyphens.
sanitize_filename() {
  local name="$1"
  echo "${name}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9_-]/-/g' \
    | sed 's/--*/-/g' \
    | sed 's/^-//;s/-$//'
}

# write_resource <dir> <name> <id> <json>
# Writes JSON to <dir>/<sanitized-name>.json.
# If the filename already exists (collision), appends -<id>.
write_resource() {
  local dir="$1"
  local name="$2"
  local id="$3"
  local json="$4"

  mkdir -p "${dir}"

  local base_name
  base_name="$(sanitize_filename "${name}")"

  # Fallback to id if name sanitizes to empty
  if [[ -z "${base_name}" ]]; then
    base_name="${id}"
  fi

  local target="${dir}/${base_name}.json"

  # Handle filename collision
  if [[ -f "${target}" ]]; then
    target="${dir}/${base_name}-${id}.json"
  fi

  echo "${json}" > "${target}"
}

# ---------------------------------------------------------------------------
# Metadata tracking (file-based, compatible with bash 3)
# ---------------------------------------------------------------------------

# record_export_count <resource_type> <count>
# Writes count to a temp file so the runner can collect it after subprocesses finish.
record_export_count() {
  local resource_type="$1"
  local count="$2"
  local counts_dir="${BACKUP_DIR}/.counts"
  mkdir -p "${counts_dir}"
  echo "${count}" > "${counts_dir}/${resource_type}"
}

# write_metadata
# Reads count files written by exporters and produces backups/metadata.json.
write_metadata() {
  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local counts_dir="${BACKUP_DIR}/.counts"

  local counts_json="{"
  local first=true

  if [[ -d "${counts_dir}" ]]; then
    for count_file in "${counts_dir}"/*; do
      [[ -f "${count_file}" ]] || continue
      local resource_type count
      resource_type="$(basename "${count_file}")"
      count="$(cat "${count_file}")"
      if [[ "${first}" == true ]]; then
        first=false
      else
        counts_json+=","
      fi
      counts_json+="\"${resource_type}\": ${count}"
    done
  fi
  counts_json+="}"

  cat > "${BACKUP_DIR}/metadata.json" <<EOF
{
  "timestamp": "${timestamp}",
  "api_url": "${SYSDIG_API_URL}",
  "counts": ${counts_json}
}
EOF

  echo "Metadata written to backups/metadata.json"
}
