## 1. Core encryption functions in lib/common.sh

- [x] 1.1 Add `encrypt_value <plaintext>` helper that encrypts a string with `openssl enc -aes-256-cbc -pbkdf2 -pass env:SYSDIG_BACKUP_PASSPHRASE` and returns `enc:v1:<base64ciphertext>`, handling the macOS (`-b 0`) vs GNU (`-w 0`) base64 flag difference
- [x] 1.2 Add `decrypt_value <enc_string>` helper that strips the `enc:v1:` prefix, base64-decodes, and decrypts with openssl, returning the plaintext
- [x] 1.3 Add `encrypt_credentials <file>` function that uses `jq walk/1` to find all known credential fields (`service_key`, `apiKey`, `api_key`, `routingKey`, `routing_key`, `password`, `token`, `webhookUrl`, `webhook_url`), encrypts each value via `encrypt_value`, and writes back via a temp file + `mv`
- [x] 1.4 Implement the `SYSDIG_BACKUP_PASSPHRASE` unset fallback in `encrypt_credentials`: replace credential values with `"REDACTED"` and print a warning to stderr instead of encrypting
- [x] 1.5 Make `encrypt_credentials` non-fatal per file: log a warning and continue if `jq` fails on a malformed file

## 2. Wire encryption into backup.sh

- [x] 2.1 Add an `encrypt_all_backups` step in `backup.sh` that iterates all `.json` files under `$BACKUP_DIR` and calls `encrypt_credentials` on each — place this after `write_metadata` and before the git section
- [x] 2.2 Verify the encrypt step runs in both normal and `--dry-run` mode (it must run before the `if DRY_RUN` branch that skips git commit)

## 3. restore.sh

- [x] 3.1 Create `restore.sh` script that accepts a `--backup-dir <path>` argument (defaults to `backups/`) and an `--output-dir <path>` argument for decrypted output
- [x] 3.2 Implement `decrypt_credentials <file> <output_file>` function using `jq walk/1` to detect `enc:v1:` prefixed values and call `decrypt_value` on each, writing plaintext JSON to the output path (never modifying the source file)
- [x] 3.3 Iterate all `.json` files in `--backup-dir`, call `decrypt_credentials` for each, mirror the directory structure under `--output-dir`
- [x] 3.4 Exit with a clear error message if `SYSDIG_BACKUP_PASSPHRASE` is unset when `restore.sh` is run
- [x] 3.5 Exit with a clear error message if `openssl` decryption fails (wrong passphrase), and do not write any partial output files

## 4. Configuration and documentation

- [x] 4.1 Add `SYSDIG_BACKUP_PASSPHRASE` to `config.sh.example` with a comment explaining its purpose, the `enc:v1:` format, and that losing the passphrase makes encrypted backups unrestorable
- [x] 4.2 Update `README.md` (or `CLAUDE.md` Running section) to document `restore.sh` usage and passphrase management guidance
- [x] 4.3 Add `SYSDIG_BACKUP_PASSPHRASE` to the configuration table in `CLAUDE.md`

## 5. Validation

- [x] 5.1 Manually verify encrypt round-trip: run `backup.sh --dry-run`, inspect a notification channel JSON for `enc:v1:` values, then run `restore.sh` and confirm plaintext is recovered correctly
- [x] 5.2 Verify fallback: unset `SYSDIG_BACKUP_PASSPHRASE`, run `backup.sh --dry-run`, confirm warning is printed and files contain `"REDACTED"`
- [x] 5.3 Run `bash -n lib/common.sh` and `bash -n restore.sh` to confirm bash 3.2 syntax compatibility
- [x] 5.4 Verify no credential plaintext appears in `git diff --cached` output after a normal backup run with passphrase set
