## MODIFIED Requirements

### Requirement: Single entrypoint script
The system SHALL provide a single entrypoint script (`backup.sh`) that orchestrates authentication validation and all resource exports in sequence. This script MUST be executable without arguments when configuration is provided via environment or config file. An optional `--terraform` flag SHALL invoke the Terraform generator after a successful export run.

#### Scenario: Full backup run succeeds
- **WHEN** `./backup.sh` is executed with valid configuration
- **THEN** all resource exporters run, results are written to `backups/`, and the script exits 0

#### Scenario: Run fails on auth failure
- **WHEN** authentication validation fails
- **THEN** no export scripts run and the runner exits with a non-zero status code

#### Scenario: Terraform generation invoked after backup
- **WHEN** `./backup.sh --terraform` is executed and the export succeeds
- **THEN** `generate-terraform.sh` is called after all exporters complete and before the git commit step

#### Scenario: Terraform generation failure does not abort commit
- **WHEN** `./backup.sh --terraform` is executed and `generate-terraform.sh` exits non-zero
- **THEN** the runner logs the failure but still commits the backup files and exits 0
