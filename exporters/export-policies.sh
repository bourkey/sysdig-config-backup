#!/usr/bin/env bash
# exporters/export-policies.sh — Export Sysdig Secure runtime security policies

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

export_policies() {
  local out_dir="${BACKUP_DIR}/policies"
  # API returns a direct JSON array (not wrapped in a field)
  local api_path="/api/v2/policies"

  echo "Exporting policies ..."

  local response
  if ! response=$(sysdig_get "${api_path}"); then
    echo "ERROR: Failed to fetch policies" >&2
    return 1
  fi

  local count
  count=$(echo "${response}" | jq '. | length')

  if [[ "${count}" -eq 0 ]]; then
    echo "No policies found."
    record_export_count "policies" 0
    return 0
  fi

  mkdir -p "${out_dir}"

  echo "${response}" | jq -c '.[]' | while IFS= read -r policy; do
    local name id
    name=$(echo "${policy}" | jq -r '.name // ""')
    id=$(echo "${policy}" | jq -r '.id // .policyId // "unknown"')
    write_resource "${out_dir}" "${name}" "${id}" "${policy}"
  done

  echo "Exported ${count} policies to backups/policies/"
  record_export_count "policies" "${count}"
}

export_policies
