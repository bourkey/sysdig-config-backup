#!/usr/bin/env bash
# exporters/export-alerts.sh — Export Sysdig Secure alerts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

export_alerts() {
  local out_dir="${BACKUP_DIR}/alerts"
  local api_path="/api/v2/alerts"

  echo "Exporting alerts ..."

  local response
  if ! response=$(sysdig_get "${api_path}"); then
    echo "ERROR: Failed to fetch alerts" >&2
    return 1
  fi

  # API returns: { "alerts": [...] }
  local count
  count=$(echo "${response}" | jq '.alerts | length')

  if [[ "${count}" -eq 0 ]]; then
    echo "No alerts found."
    record_export_count "alerts" 0
    return 0
  fi

  mkdir -p "${out_dir}"

  echo "${response}" | jq -c '.alerts[]' | while IFS= read -r alert; do
    local name id
    name=$(echo "${alert}" | jq -r '.name // ""')
    id=$(echo "${alert}" | jq -r '.id // "unknown"')
    write_resource "${out_dir}" "${name}" "${id}" "${alert}"
  done

  echo "Exported ${count} alerts to backups/alerts/"
  record_export_count "alerts" "${count}"
}

export_alerts
