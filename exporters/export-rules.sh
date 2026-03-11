#!/usr/bin/env bash
# exporters/export-rules.sh — Export Sysdig Secure custom Falco rules
#
# Strategy:
#   1. GET /api/secure/rules/summaries — returns all rule name groups with their IDs
#   2. Filter to rules with at least one customer/user origin (Customer, Secure UI)
#      — Sysdig default rules are not backed up as they are managed by Sysdig
#   3. For each qualifying rule ID, fetch full content via GET /api/secure/rules/{id}
#   Each rule ID becomes one JSON file in backups/rules/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

export_rules() {
  local out_dir="${BACKUP_DIR}/rules"

  echo "Exporting custom rules ..."

  # Step 1: get all rule summaries (includes IDs and origins per rule name)
  local summaries
  if ! summaries=$(sysdig_get "/api/secure/rules/summaries"); then
    echo "ERROR: Failed to fetch rule summaries" >&2
    return 1
  fi

  # Step 2: collect IDs of rules with at least one customer/user origin.
  # Each summary item has: { name, ids: [...], publishedBys: [{origin, versionId}] }
  # We want IDs where any publishedBys entry is "Customer" or "Secure UI".
  local customer_ids
  customer_ids=$(echo "${summaries}" | jq -r '
    .[] |
    select(.publishedBys[]?.origin | IN("Customer", "Secure UI")) |
    .ids[]
  ' | sort -nu)

  local count
  count=$(echo "${customer_ids}" | grep -c . || true)

  if [[ "${count}" -eq 0 ]]; then
    echo "No customer rules found."
    record_export_count "rules" 0
    return 0
  fi

  mkdir -p "${out_dir}"

  # Step 3: fetch each rule by ID
  local exported=0
  while IFS= read -r rule_id; do
    local rule_response name
    if rule_response=$(sysdig_get "/api/secure/rules/${rule_id}"); then
      name=$(echo "${rule_response}" | jq -r '.name // ""')
      write_resource "${out_dir}" "${name}" "${rule_id}" "${rule_response}"
      (( exported++ )) || true
    else
      echo "WARNING: Failed to fetch rule ID ${rule_id} — skipping" >&2
    fi
  done <<< "${customer_ids}"

  echo "Exported ${exported}/${count} custom rules to backups/rules/"
  record_export_count "rules" "${exported}"
}

export_rules
