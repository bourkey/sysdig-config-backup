## Why

Exported notification channel JSON files committed to git may contain real credentials (service keys, API keys, webhook tokens). While `config.sh` is gitignored, the `backups/` directory is not — meaning live secrets land in version history on every run. Simple redaction (replacing with `REDACTED`) prevents commits of live secrets but also destroys the backup's restore value.

## What Changes

- Before committing, known credential fields in exported JSON are encrypted using AES-256 (openssl) with a passphrase supplied via `SYSDIG_BACKUP_PASSPHRASE`
- Encrypted values are stored inline in the JSON as `enc:v1:<base64ciphertext>`, preserving field names and structure
- If `SYSDIG_BACKUP_PASSPHRASE` is unset, the script falls back to replacing with `"REDACTED"` and logs a warning
- A `restore.sh` script (or flag) can decrypt `enc:v1:` values back to plaintext for use during a Sysdig configuration restore
- `generate-terraform.sh` behaviour is unchanged — it already replaces credentials with `# REPLACE_WITH_SECRET` comments in HCL output

## Capabilities

### New Capabilities
- `credential-encryption`: Pre-commit encryption of known credential fields in exported JSON backup files, with a corresponding decrypt path for restore

### Modified Capabilities
- `resource-export`: Export behaviour is unchanged, but the post-export / pre-commit pipeline now includes an encrypt pass before `git add`

## Impact

- `backup.sh` — invokes credential encryption between export and git commit
- `lib/common.sh` — encryption/decryption logic added here (bash 3.2 compatible)
- `exporters/export-notification-channels.sh` — no change to export logic
- `backups/notification-channels/*.json` — credential field values stored as `enc:v1:<base64>` instead of plaintext
- `SYSDIG_BACKUP_PASSPHRASE` — new optional environment variable; documented in `config.sh.example`
- Existing committed history is not rewritten (out of scope); only future commits are protected
