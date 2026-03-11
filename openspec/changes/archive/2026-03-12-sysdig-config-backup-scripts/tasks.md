## 1. Repository Structure & Configuration

- [x] 1.1 Create top-level directory layout: `exporters/`, `backups/`, `lib/`
- [x] 1.2 Create `config.sh.example` with `SYSDIG_API_TOKEN` and `SYSDIG_API_URL` placeholders and comments
- [x] 1.3 Add `config.sh` to `.gitignore` to prevent token leakage
- [x] 1.4 Add `backups/` directory with a `.gitkeep` so the directory is tracked but exports are committed individually

## 2. Shared Library

- [x] 2.1 Create `lib/common.sh` — shared functions for loading config, validating required vars, and setting defaults
- [x] 2.2 Implement `sysdig_get()` function in `lib/common.sh` — wraps `curl` with auth headers, base URL, error handling, and returns JSON
- [x] 2.3 Implement `sanitize_filename()` function — lowercases, replaces spaces/special chars with hyphens
- [x] 2.4 Implement `write_resource()` function — writes JSON to target path, handles filename collision with ID suffix

## 3. API Authentication

- [x] 3.1 Add auth validation step to `lib/common.sh` — makes a lightweight API call to verify token is valid
- [x] 3.2 Exit with error message and code 1 if token is missing or validation returns 401/403
- [x] 3.3 Test auth validation against the Sysdig API with a valid token (US region default)
- [x] 3.4 Test auth validation with an invalid token and confirm error output

## 4. Resource Exporters

- [x] 4.1 Create `exporters/export-policies.sh` — fetches all runtime security policies and writes to `backups/policies/`
- [x] 4.2 Create `exporters/export-alerts.sh` — fetches all alerts and writes to `backups/alerts/`
- [x] 4.3 Create `exporters/export-notification-channels.sh` — fetches all notification channels and writes to `backups/notification-channels/`
- [x] 4.4 Create `exporters/export-rules.sh` — fetches all custom Falco rules and writes to `backups/rules/`
- [x] 4.5 Create `exporters/export-teams.sh` — fetches all teams and writes to `backups/teams/`
- [x] 4.6 Verify each exporter handles empty API responses without error
- [x] 4.7 Verify each exporter logs a clear error and returns non-zero on API failure without aborting others

## 5. Metadata

- [x] 5.1 Implement metadata writer in `lib/common.sh` or the runner — collects per-type export counts and writes `backups/metadata.json` with timestamp and summary
- [x] 5.2 Confirm metadata is written even when one or more exporters fail

## 6. Backup Runner

- [x] 6.1 Create `backup.sh` — sources `lib/common.sh`, runs auth validation, invokes all exporters in sequence
- [x] 6.2 Implement `--dry-run` flag — skips git commit step and logs dry-run notice
- [x] 6.3 Implement git commit step — stages `backups/`, checks for changes, commits with `backup: <ISO8601 timestamp>` message if changes exist
- [x] 6.4 Implement exit code contract — exits 0 on full or partial success, exits 1 only if auth fails or all exporters fail
- [x] 6.5 Make `backup.sh` executable (`chmod +x`)
- [x] 6.6 Test full run non-interactively (simulating cron: no TTY, config from env)
- [x] 6.7 Test `--dry-run` confirms no git commit is created

## 7. Documentation

- [x] 7.1 Write `README.md` — project overview, prerequisites (`curl`, `jq`, `git`), setup steps, configuration reference
- [x] 7.2 Document cron setup with example crontab entry and log redirection
- [x] 7.3 Document how to add a new resource type exporter
- [x] 7.4 Document the backup directory structure and file naming convention
