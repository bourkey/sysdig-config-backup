## ADDED Requirements

### Requirement: Single entrypoint script
The system SHALL provide a single entrypoint script (`backup.sh`) that orchestrates authentication validation and all resource exports in sequence. This script MUST be executable without arguments when configuration is provided via environment or config file.

#### Scenario: Full backup run succeeds
- **WHEN** `./backup.sh` is executed with valid configuration
- **THEN** all resource exporters run, results are written to `backups/`, and the script exits 0

#### Scenario: Run fails on auth failure
- **WHEN** authentication validation fails
- **THEN** no export scripts run and the runner exits with a non-zero status code

### Requirement: Cron compatibility
The backup runner MUST be executable non-interactively with no TTY, no user prompts, and no assumed shell profile. All configuration MUST come from environment variables or a sourced config file. The script MUST produce log output suitable for redirection to a log file.

#### Scenario: Invoked from cron
- **WHEN** the script is added to a crontab (e.g., `0 2 * * * /path/to/backup.sh >> /var/log/sysdig-backup.log 2>&1`)
- **THEN** it runs fully non-interactively, writes all backup files, and logs progress to stdout/stderr

### Requirement: Git commit of changes
After a successful export, the runner SHALL stage all changes in `backups/` and create a git commit with a timestamped message if any files have changed. If nothing has changed, no commit is made.

#### Scenario: Changes detected after export
- **WHEN** exported files differ from the previous backup
- **THEN** a git commit is created with message `backup: <ISO8601 timestamp>` and the changed files listed

#### Scenario: No changes detected
- **WHEN** all exported files are identical to the previous backup
- **THEN** no git commit is created and the runner logs "No changes detected"

### Requirement: Exit code contract
The backup runner SHALL exit with code `0` on full or partial success (at least one resource type exported) and code `1` on complete failure (auth failure or all exporters failed). Individual exporter failures MUST be logged but MUST NOT cause a non-zero exit unless all exporters fail.

#### Scenario: Partial export succeeds
- **WHEN** 4 out of 5 resource types export successfully and 1 fails
- **THEN** the runner exits 0 and logs the failure for the one resource type

#### Scenario: Total failure
- **WHEN** all resource type exports fail
- **THEN** the runner exits 1 and logs each failure

### Requirement: Dry-run mode
The system SHALL support a `--dry-run` flag that performs all API calls and writes files but skips the git commit step.

#### Scenario: Dry run invoked
- **WHEN** `./backup.sh --dry-run` is executed
- **THEN** all exports run and files are written, but no git commit is created and a message is logged indicating dry-run mode
