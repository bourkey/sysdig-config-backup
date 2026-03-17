#!/usr/bin/env bash
# restore.sh — Decrypt credential fields in Sysdig backup JSON files
#
# Usage:
#   ./restore.sh                             Decrypt backups/ → restore-output/
#   ./restore.sh --backup-dir <path>         Source backup directory (default: backups/)
#   ./restore.sh --output-dir <path>         Output directory for decrypted files (default: restore-output/)
#
# Requires SYSDIG_BACKUP_PASSPHRASE to be set to the same passphrase used during backup.
# Source files in --backup-dir are never modified; decrypted copies are written to --output-dir.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

BACKUP_DIR_ARG="${SCRIPT_DIR}/backups"
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup-dir)
      BACKUP_DIR_ARG="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--backup-dir <path>] [--output-dir <path>]" >&2
      exit 1
      ;;
  esac
done

OUTPUT_DIR="${OUTPUT_DIR:-${SCRIPT_DIR}/restore-output}"

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

if [[ -z "${SYSDIG_BACKUP_PASSPHRASE:-}" ]]; then
  echo "ERROR: SYSDIG_BACKUP_PASSPHRASE is not set." >&2
  echo "  Set this to the same passphrase used when the backup was created." >&2
  exit 1
fi

if [[ ! -d "${BACKUP_DIR_ARG}" ]]; then
  echo "ERROR: Backup directory not found: ${BACKUP_DIR_ARG}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Decrypt function
# ---------------------------------------------------------------------------

# decrypt_credentials <source_file> <output_file>
# Reads a JSON file, decrypts all enc:v1: values, writes plaintext JSON to output_file.
# Never modifies the source file.
# Returns non-zero and removes output_file if decryption of any field fails.
decrypt_credentials() {
  local src="$1"
  local dest="$2"

  if ! jq empty "${src}" 2>/dev/null; then
    echo "WARNING: Skipping malformed JSON: ${src}" >&2
    return 1
  fi

  # Get all (path, enc_value) pairs for enc:v1: prefixed strings
  local pairs
  pairs=$(jq -c \
    '[paths as $p |
       select(getpath($p) | type == "string" and startswith("enc:v1:")) |
       [$p, getpath($p)]]
     | .[]' "${src}" 2>/dev/null)

  # Start with a copy of the source
  local tmp
  tmp="$(mktemp)"
  cp "${src}" "${tmp}"

  if [[ -n "${pairs}" ]]; then
    while IFS= read -r pair; do
      [[ -z "${pair}" ]] && continue
      local path_json enc_val plaintext
      path_json=$(printf '%s' "${pair}" | jq -c '.[0]')
      enc_val=$(printf '%s' "${pair}" | jq -r '.[1]')

      plaintext=$(decrypt_value "${enc_val}")
      if [[ $? -ne 0 ]]; then
        echo "ERROR: Decryption failed for a credential field in ${src}." >&2
        echo "  Check that SYSDIG_BACKUP_PASSPHRASE matches the passphrase used at backup time." >&2
        rm -f "${tmp}"
        return 1
      fi

      local updated
      updated="$(mktemp)"
      jq --argjson p "${path_json}" --arg v "${plaintext}" 'setpath($p; $v)' "${tmp}" > "${updated}" \
        && mv "${updated}" "${tmp}"
    done <<< "${pairs}"
  fi

  mkdir -p "$(dirname "${dest}")"
  mv "${tmp}" "${dest}"
  return 0
}

# ---------------------------------------------------------------------------
# Main restore loop
# ---------------------------------------------------------------------------

echo "Restoring from: ${BACKUP_DIR_ARG}"
echo "Output to:      ${OUTPUT_DIR}"
echo ""

TOTAL=0
DECRYPTED=0
FAILED=0

while IFS= read -r -d '' src_file; do
  rel_path="${src_file#${BACKUP_DIR_ARG}/}"
  dest_file="${OUTPUT_DIR}/${rel_path}"

  (( TOTAL++ )) || true

  if decrypt_credentials "${src_file}" "${dest_file}"; then
    (( DECRYPTED++ )) || true
  else
    (( FAILED++ )) || true
  fi
done < <(find "${BACKUP_DIR_ARG}" -name "*.json" -not -path "${BACKUP_DIR_ARG}/.counts/*" -print0)

echo ""
echo "Restore complete: ${DECRYPTED}/${TOTAL} files decrypted to ${OUTPUT_DIR}"

if [[ ${FAILED} -gt 0 ]]; then
  echo "WARNING: ${FAILED} file(s) could not be decrypted." >&2
  exit 1
fi

exit 0
