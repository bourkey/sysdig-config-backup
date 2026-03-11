#!/usr/bin/env bash
# backup.sh — Sysdig Secure configuration backup runner
#
# Usage:
#   ./backup.sh              Run full backup and commit changes
#   ./backup.sh --dry-run    Run backup but skip git commit
#   ./backup.sh --terraform  Run backup, generate Terraform HCL, then commit

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

DRY_RUN=false
RUN_TERRAFORM=false
for arg in "$@"; do
  case "${arg}" in
    --dry-run)   DRY_RUN=true ;;
    --terraform) RUN_TERRAFORM=true ;;
    *) echo "Unknown argument: ${arg}" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------

load_config
validate_config
validate_auth

if [[ "${DRY_RUN}" == true ]]; then
  echo "DRY RUN mode — no git commit will be created."
fi

# ---------------------------------------------------------------------------
# Run exporters
# ---------------------------------------------------------------------------

EXPORTERS=(
  "${SCRIPT_DIR}/exporters/export-policies.sh"
  "${SCRIPT_DIR}/exporters/export-alerts.sh"
  "${SCRIPT_DIR}/exporters/export-notification-channels.sh"
  "${SCRIPT_DIR}/exporters/export-rules.sh"
  "${SCRIPT_DIR}/exporters/export-teams.sh"
)

FAILED_EXPORTERS=()
SUCCESSFUL_EXPORTERS=0

for exporter in "${EXPORTERS[@]}"; do
  exporter_name="$(basename "${exporter}")"
  if bash "${exporter}"; then
    (( SUCCESSFUL_EXPORTERS++ )) || true
  else
    echo "WARNING: ${exporter_name} failed — skipping" >&2
    FAILED_EXPORTERS+=("${exporter_name}")
  fi
done

# ---------------------------------------------------------------------------
# Write metadata (always, even on partial failure)
# ---------------------------------------------------------------------------

write_metadata

# ---------------------------------------------------------------------------
# Determine exit state
# ---------------------------------------------------------------------------

TOTAL_EXPORTERS=${#EXPORTERS[@]}

if [[ ${SUCCESSFUL_EXPORTERS} -eq 0 ]]; then
  echo "ERROR: All ${TOTAL_EXPORTERS} exporters failed. No backup committed." >&2
  exit 1
fi

if [[ ${#FAILED_EXPORTERS[@]} -gt 0 ]]; then
  echo "WARNING: ${#FAILED_EXPORTERS[@]}/${TOTAL_EXPORTERS} exporters failed: ${FAILED_EXPORTERS[*]}" >&2
fi

# ---------------------------------------------------------------------------
# Terraform generation (opt-in, non-fatal)
# ---------------------------------------------------------------------------

if [[ "${RUN_TERRAFORM}" == true ]]; then
  echo "Running Terraform generation..."
  if bash "${SCRIPT_DIR}/generate-terraform.sh"; then
    echo "Terraform generation succeeded."
  else
    echo "WARNING: Terraform generation failed — backup will still be committed." >&2
  fi
fi

# ---------------------------------------------------------------------------
# Git commit
# ---------------------------------------------------------------------------

if [[ "${DRY_RUN}" == true ]]; then
  echo "Skipping git commit (dry run)."
  exit 0
fi

cd "${SCRIPT_DIR}"

git add backups/

if git diff --cached --quiet; then
  echo "No changes detected — nothing to commit."
  exit 0
fi

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
git commit -m "backup: ${TIMESTAMP}"

echo "Backup committed: ${TIMESTAMP}"
exit 0
