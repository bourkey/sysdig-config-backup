## ADDED Requirements

### Requirement: Encrypt credential fields before commit
The system SHALL encrypt known credential fields in all JSON files under `backups/` before staging changes with `git add`. Encryption MUST replace the plaintext value of each matched field with a string of the form `enc:v1:<base64ciphertext>`, where the ciphertext is produced by AES-256-CBC symmetric encryption using a passphrase from `SYSDIG_BACKUP_PASSPHRASE`. The following fields MUST be encrypted regardless of nesting depth: `service_key`, `apiKey`, `api_key`, `routingKey`, `routing_key`, `password`, `token`, `webhookUrl`, `webhook_url`.

#### Scenario: Notification channel with service key encrypted
- **WHEN** `SYSDIG_BACKUP_PASSPHRASE` is set and a notification channel JSON file contains `"service_key": "<live-value>"`
- **THEN** the committed file contains `"service_key": "enc:v1:<base64ciphertext>"` and all other fields are unchanged

#### Scenario: Nested credential field encrypted
- **WHEN** a credential field appears at any depth within a JSON object (e.g. inside an `options` sub-object)
- **THEN** the value is encrypted regardless of nesting level

#### Scenario: No credential fields present
- **WHEN** a JSON file contains none of the known credential fields
- **THEN** the file is left byte-for-byte identical after the encrypt pass

#### Scenario: Multiple files encrypted in one run
- **WHEN** the backup run exports multiple notification channels each containing credential fields
- **THEN** all matching files are encrypted before any file is staged for commit

### Requirement: Fallback to REDACTED when passphrase is unset
If `SYSDIG_BACKUP_PASSPHRASE` is empty or unset, the system SHALL replace credential field values with the string `"REDACTED"` instead of encrypting and MUST log a warning informing the operator that backups will not be restorable without a passphrase.

#### Scenario: No passphrase configured
- **WHEN** `SYSDIG_BACKUP_PASSPHRASE` is not set and a backup run completes
- **THEN** credential fields in committed JSON contain `"REDACTED"`, a warning is printed, and the run does not exit with an error

#### Scenario: Passphrase configured
- **WHEN** `SYSDIG_BACKUP_PASSPHRASE` is set to a non-empty value
- **THEN** credential fields are encrypted with `enc:v1:<base64ciphertext>` and no warning is printed

### Requirement: Encryption applies in all run modes
The system SHALL perform credential encryption after all exporters complete and before any `git add`, including when invoked with `--dry-run`. Dry-run mode MUST NOT skip encryption; it only skips the git commit step.

#### Scenario: Dry-run still encrypts
- **WHEN** `backup.sh --dry-run` is executed with `SYSDIG_BACKUP_PASSPHRASE` set
- **THEN** credential fields are encrypted in `backups/` JSON files on disk, and no git commit is made

#### Scenario: Normal run encrypts then commits
- **WHEN** `backup.sh` is executed without `--dry-run` and `SYSDIG_BACKUP_PASSPHRASE` is set
- **THEN** credential fields are encrypted before `git add`, so the committed files never contain plaintext credential values

### Requirement: Decrypt credentials for restore
The system SHALL provide a `restore.sh` script that reads a backup directory, identifies all JSON fields containing `enc:v1:<base64ciphertext>` values, decrypts them using `SYSDIG_BACKUP_PASSPHRASE`, and writes the plaintext JSON output to a separate directory without modifying the backup files in place.

#### Scenario: Successful decrypt round-trip
- **WHEN** `restore.sh` is run against a backup directory with `SYSDIG_BACKUP_PASSPHRASE` set to the same passphrase used during backup
- **THEN** all `enc:v1:` values are decrypted to their original plaintext and written to the output directory

#### Scenario: Wrong passphrase
- **WHEN** `restore.sh` is run with a passphrase that does not match the one used during backup
- **THEN** decryption fails with a clear error message and no output files are written

#### Scenario: Decrypt skips non-encrypted fields
- **WHEN** a JSON file contains a mix of `enc:v1:` values and regular string values
- **THEN** only `enc:v1:` prefixed values are decrypted; all other fields are passed through unchanged

### Requirement: Encryption is non-fatal per file
A failure encrypting a single file (e.g. malformed JSON) MUST NOT abort the overall backup run. The system SHALL log a warning for any file that could not be processed and continue with remaining files.

#### Scenario: One file fails to encrypt
- **WHEN** one exported JSON file is malformed and `jq` returns a non-zero exit code
- **THEN** a warning is logged for that file, encryption continues for all other files, and the backup run does not exit with an error due to the encryption failure

### Requirement: Implementation uses openssl and jq
The encryption function SHALL use `openssl enc -aes-256-cbc -pbkdf2` for encryption and `jq walk/1` for field traversal. The implementation MUST be compatible with bash 3.2 and MUST handle the `base64` line-wrap flag difference between macOS (`-b 0`) and GNU/Linux (`-w 0`).

#### Scenario: Cross-platform base64 encoding
- **WHEN** the backup script runs on macOS
- **THEN** the `enc:v1:` ciphertext is produced without line breaks, matching the format expected by the decrypt function

#### Scenario: Cross-platform base64 decoding
- **WHEN** `restore.sh` runs on Linux to decrypt a backup created on macOS (or vice versa)
- **THEN** decryption succeeds and produces the correct plaintext value
