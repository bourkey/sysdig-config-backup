## Why

The backup scripts capture Sysdig Secure configuration as JSON, but restoring that configuration after a disaster or migrating to a new environment requires manually recreating each resource. Converting backed-up JSON to Terraform HCL using the Sysdig Terraform provider (`sysdiglabs/sysdig`) enables one-command restore and treats configuration as code.

## What Changes

- New `terraform/` directory in the repo to hold generated `.tf` files
- New `generate-terraform.sh` script that reads all JSON files from `backups/` and produces Terraform HCL
- One `.tf` file per resource type: `policies.tf`, `notification-channels.tf`, `rules.tf`, `teams.tf`, `alerts.tf`
- One combined `main.tf` aggregating all resource types (for full environment restore/migration)
- New `terraform/provider.tf` with the Sysdig provider block and variable stubs
- The generator script can be run standalone or called from `backup.sh` as an optional post-export step

## Capabilities

### New Capabilities
- `terraform-generator`: Reads JSON backup files and produces valid Terraform HCL for each resource type using the `sysdiglabs/sysdig` provider
- `terraform-output-structure`: Defines the layout of the `terraform/` output directory, the per-type file structure, and the combined `main.tf`

### Modified Capabilities
- `backup-runner`: Add an optional `--terraform` flag to `backup.sh` that invokes the generator after a successful export run

## Impact

- **New script**: `generate-terraform.sh` — reads from `backups/`, writes to `terraform/`
- **Sysdig Terraform provider resources used**:
  - `sysdig_secure_policy` — policies
  - `sysdig_secure_notification_channel_*` — notification channels (type-specific resources)
  - `sysdig_secure_rule_falco` — custom Falco rules
  - `sysdig_secure_team` — teams
  - `sysdig_monitor_alert_v2` — alerts (if present)
- **Dependencies**: `jq` (already required), `bash`; no Terraform binary required to generate files
- **terraform/ directory**: gitignored by default (generated output); operators can choose to commit it
- **No changes to existing backup logic** — generator is purely a reader of `backups/`
