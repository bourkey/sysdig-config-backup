## ADDED Requirements

### Requirement: Per-type Terraform files
The system SHALL write one `.tf` file per resource type to the `terraform/` directory. Each file SHALL contain only resources of that type.

#### Scenario: Generator produces per-type files
- **WHEN** `generate-terraform.sh` completes a run with all resource types present
- **THEN** `terraform/` contains `policies.tf`, `notification-channels.tf`, `rules.tf`, `teams.tf`, and `alerts.tf` (only for types with at least one resource)

### Requirement: Combined main.tf
The system SHALL produce a `terraform/main.tf` that includes all generated resource types in a single file, suitable for a full environment restore or migration without managing multiple files.

#### Scenario: Combined file produced
- **WHEN** `generate-terraform.sh` completes successfully
- **THEN** `terraform/main.tf` contains all resource blocks from all per-type files concatenated with section headers

#### Scenario: Combined file reflects only available types
- **WHEN** only some resource types have backup files (e.g., no alerts)
- **THEN** `terraform/main.tf` contains only the sections for resource types that were generated

### Requirement: Provider configuration file
The system SHALL produce a `terraform/provider.tf` containing the `sysdiglabs/sysdig` provider block with version constraints and a variable stub for the Sysdig API token, so operators can run `terraform init` immediately after generation.

#### Scenario: Provider file written
- **WHEN** `generate-terraform.sh` runs
- **THEN** `terraform/provider.tf` is written with the provider block and `variable "sysdig_secure_api_token"` stub

#### Scenario: Provider file not overwritten if unchanged
- **WHEN** `terraform/provider.tf` already exists and the generator is run again
- **THEN** the provider file is left unchanged (operators may have customised it)

### Requirement: terraform/ directory gitignored by default
The `terraform/` output directory SHALL be added to `.gitignore` by default, since it is generated output. Operators who wish to commit generated Terraform MUST explicitly remove the entry from `.gitignore`.

#### Scenario: Generated files not accidentally committed
- **WHEN** the repo is freshly cloned and `generate-terraform.sh` is run
- **THEN** `git status` does not show `terraform/` as an untracked directory

### Requirement: Generation summary output
After a run, `generate-terraform.sh` SHALL print a summary to stdout listing each output file written and the number of resources it contains.

#### Scenario: Summary after successful run
- **WHEN** `generate-terraform.sh` completes
- **THEN** stdout shows a line per file: `terraform/policies.tf — 12 resources` and a total count
