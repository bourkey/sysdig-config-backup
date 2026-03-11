#!/usr/bin/env bash
# exporters/export-notification-channels.sh — Export Sysdig Secure notification channels

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

export_notification_channels() {
  local out_dir="${BACKUP_DIR}/notification-channels"
  local api_path="/api/notificationChannels"

  echo "Exporting notification channels ..."

  local response
  if ! response=$(sysdig_get "${api_path}"); then
    echo "ERROR: Failed to fetch notification channels" >&2
    return 1
  fi

  # API returns: { "notificationChannels": [...] }
  local count
  count=$(echo "${response}" | jq '.notificationChannels | length')

  if [[ "${count}" -eq 0 ]]; then
    echo "No notification channels found."
    record_export_count "notification-channels" 0
    return 0
  fi

  mkdir -p "${out_dir}"

  echo "${response}" | jq -c '.notificationChannels[]' | while IFS= read -r channel; do
    local name id
    name=$(echo "${channel}" | jq -r '.name // ""')
    id=$(echo "${channel}" | jq -r '.id // "unknown"')
    write_resource "${out_dir}" "${name}" "${id}" "${channel}"
  done

  echo "Exported ${count} notification channels to backups/notification-channels/"
  record_export_count "notification-channels" "${count}"
}

export_notification_channels
