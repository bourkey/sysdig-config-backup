#!/usr/bin/env bash
# exporters/export-teams.sh — Export Sysdig Secure teams

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

export_teams() {
  local out_dir="${BACKUP_DIR}/teams"
  local api_path="/api/teams"

  echo "Exporting teams ..."

  local response
  if ! response=$(sysdig_get "${api_path}"); then
    echo "ERROR: Failed to fetch teams" >&2
    return 1
  fi

  # API returns: { "teams": [...] }
  local count
  count=$(echo "${response}" | jq '.teams | length')

  if [[ "${count}" -eq 0 ]]; then
    echo "No teams found."
    record_export_count "teams" 0
    return 0
  fi

  mkdir -p "${out_dir}"

  echo "${response}" | jq -c '.teams[]' | while IFS= read -r team; do
    local name id
    name=$(echo "${team}" | jq -r '.name // ""')
    id=$(echo "${team}" | jq -r '.id // "unknown"')
    write_resource "${out_dir}" "${name}" "${id}" "${team}"
  done

  echo "Exported ${count} teams to backups/teams/"
  record_export_count "teams" "${count}"
}

export_teams
