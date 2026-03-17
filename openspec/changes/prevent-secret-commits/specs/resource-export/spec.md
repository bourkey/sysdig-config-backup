## MODIFIED Requirements

### Requirement: Export notification channels
The system SHALL export all configured notification channels (email, Slack, PagerDuty, webhook, etc.) to `backups/notification-channels/` as individual JSON files. Before the exported files are staged for git commit, all known credential fields (see `credential-encryption` capability) SHALL be encrypted so that plaintext secrets are never persisted to the repository.

#### Scenario: Notification channels exported successfully
- **WHEN** the export script runs and the API returns notification channels
- **THEN** each channel is written to `backups/notification-channels/<channel-name>.json`

#### Scenario: Credential fields are encrypted before commit
- **WHEN** an exported notification channel JSON contains a credential field such as `service_key` or `api_key` and `SYSDIG_BACKUP_PASSPHRASE` is set
- **THEN** the value of that field in the committed file is `enc:v1:<base64ciphertext>`, not the live credential value

#### Scenario: Credential fields fall back to REDACTED without passphrase
- **WHEN** an exported notification channel JSON contains a credential field and `SYSDIG_BACKUP_PASSPHRASE` is not set
- **THEN** the value of that field in the committed file is `"REDACTED"` and a warning is logged
