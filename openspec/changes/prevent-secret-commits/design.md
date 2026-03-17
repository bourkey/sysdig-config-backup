## Context

`backup.sh` runs exporters, writes `backups/` JSON files, then calls `git add backups/ && git commit`. No protection occurs between export and staging. Notification channel JSON files contain live credential fields (`service_key`, `apiKey`, `routing_key`, etc.) that are committed verbatim.

The goal is to protect these credentials in git while keeping the backup restorable without any out-of-band secret store. The only external dependency allowed is `openssl` (standard on macOS and Linux) and `jq` (already required). Must be bash 3.2 compatible.

## Goals / Non-Goals

**Goals:**
- Encrypt known credential fields in all `backups/**/*.json` before `git add`
- Store encrypted values inline so the backup is self-contained (repo + passphrase = full restore)
- Provide a decryption path for restore workflows
- Fall back gracefully (log warning + use `REDACTED`) when no passphrase is configured
- Apply in both normal and `--dry-run` modes

**Non-Goals:**
- Rewriting existing git history
- Encrypting entire JSON files (field-level encryption preserves structure and diff readability)
- Encrypting `metadata.json` or the Sysdig API URL
- Key rotation or multi-key support (out of scope for v1)

## Decisions

### 1. Symmetric encryption with openssl AES-256-CBC + PBKDF2

**Chosen:** `openssl enc -aes-256-cbc -pbkdf2 -pass env:SYSDIG_BACKUP_PASSPHRASE`

Encrypted values are stored as `enc:v1:<base64ciphertext>` where `<base64ciphertext>` is the raw openssl output piped through `base64`.

**Alternatives considered:**
- GPG symmetric (`gpg --symmetric`) — more portable key formats but heavier dependency; not guaranteed on minimal systems.
- Age (`age` CLI) — modern and clean, but not pre-installed on most systems; would add a new dependency.
- Base64 only — not encryption; provides no protection.

**Rationale:** `openssl` is universally available, `-pbkdf2` is the modern key derivation flag (avoids deprecated MD5 default), and AES-256-CBC is well-understood. The `enc:v1:` prefix allows format versioning in future.

---

### 2. Encrypt in `lib/common.sh` as `encrypt_credentials` / `decrypt_credentials`

**Chosen:** Two functions added to `lib/common.sh`:
- `encrypt_credentials <file>` — reads file, uses `jq walk()` to find known fields, encrypts each value, writes back via temp file
- `decrypt_credentials <file>` — reads file, detects `enc:v1:` prefixed values, decrypts each, writes to stdout (not in-place, for restore use)

**Alternatives considered:**
- New `lib/secrets.sh` — cleaner separation but adds a source call; `common.sh` already owns file I/O.
- Per-exporter encryption — couples logic to each exporter; new exporters would need to remember to encrypt.

**Rationale:** A centralised post-export pass in `common.sh` covers all exporters automatically.

---

### 3. Credential field allowlist (same as scrubbing approach)

Fields to encrypt:

| Field | Source |
|---|---|
| `service_key` | PagerDuty, VictorOps |
| `apiKey` / `api_key` | OpsGenie, webhook channels |
| `routingKey` / `routing_key` | VictorOps |
| `password` | SMTP, custom channels |
| `token` | Slack, generic token fields |
| `webhookUrl` / `webhook_url` | Webhook notification channels |

`jq walk()` traverses all nesting depths in a single pass.

---

### 4. Graceful fallback when `SYSDIG_BACKUP_PASSPHRASE` is unset

**Chosen:** If the variable is empty or unset, the script logs a warning and replaces credential values with `"REDACTED"` instead of encrypting.

**Rationale:** Avoids silently committing live secrets when the passphrase isn't configured, while not making the passphrase a hard requirement that breaks existing deployments.

---

### 5. Encrypt in both normal and `--dry-run` mode

Encryption runs after all exporters complete, before the git section, unconditionally. Dry-run only skips the commit — local files should never hold live secrets.

---

### 6. `restore.sh` for decryption

A new `restore.sh` script (or `--decrypt` flag) reads a backup directory, finds all `enc:v1:` values, decrypts them using `SYSDIG_BACKUP_PASSPHRASE`, and writes the plaintext JSON to a separate output directory (not modifying the backup in place). This plaintext output can be fed to a future import/restore workflow.

## Risks / Trade-offs

- **Passphrase loss** → credentials in backup are unrecoverable. Mitigation: document prominently that the passphrase must be stored separately (password manager, CI secret).
- **Existing committed live secrets** — encryption only protects future commits; credentials already in history remain. Mitigation: document that operators should rotate any credentials that appeared in prior commits.
- **`jq walk()` requires jq ≥ 1.6** — available via Homebrew on macOS and standard on modern Linux distros. No new constraint beyond what the project already relies on.
- **openssl output is non-deterministic** (random IV per run) — each backup run produces different ciphertext for the same value, creating git diffs even when credentials haven't changed. Mitigation: acceptable trade-off; the diff noise is preferable to deterministic encryption (which would allow known-plaintext attacks). Document this behaviour.
- **`base64` flag differences** — macOS `base64` uses `-b 0` to suppress line wraps; GNU `base64` uses `-w 0`. Implementation must handle both.

## Migration Plan

1. Operator sets `SYSDIG_BACKUP_PASSPHRASE` in their environment or `config.sh`
2. Next backup run encrypts all credential fields going forward
3. Operator runs `restore.sh` to verify a round-trip decrypt succeeds before trusting the encrypted backup
4. Operator rotates any credentials that appeared in unencrypted prior commits
