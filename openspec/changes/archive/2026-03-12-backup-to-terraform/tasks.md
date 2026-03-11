## 1. Setup & Structure

- [x] 1.1 Create `terraform/` output directory with a `.gitkeep`
- [x] 1.2 Add `terraform/` to `.gitignore` (generated output, opt-in to commit)
- [x] 1.3 Create `generate-terraform.sh` with shebang, `set -euo pipefail`, and source `lib/common.sh`
- [x] 1.4 Make `generate-terraform.sh` executable (`chmod +x`)

## 2. Provider File

- [x] 2.1 Implement `write_provider_tf()` in `generate-terraform.sh` — writes `terraform/provider.tf` with `sysdiglabs/sysdig` provider block, version constraint, and `variable "sysdig_secure_api_token"` stub
- [x] 2.2 Implement skip-if-exists logic so `provider.tf` is not overwritten on subsequent runs

## 3. Shared HCL Helpers

- [x] 3.1 Implement `sanitize_tf_label()` — converts filename to valid Terraform resource label (lowercase, hyphens to underscores, strip `.json`, prefix if starts with digit)
- [x] 3.2 Implement `hcl_string()` — escapes a string value for safe HCL output (handles quotes and backslashes)
- [x] 3.3 Implement `hcl_comment()` — formats a JSON key/value as an HCL comment for unmapped/read-only fields

## 4. Per-Type Generators

- [x] 4.1 Implement `generate_policies()` — reads `backups/policies/*.json`, maps fields to `sysdig_secure_policy` arguments, writes `terraform/policies.tf`
- [x] 4.2 Implement `generate_notification_channels()` — reads `backups/notification-channels/*.json`, maps `type` field to the correct `sysdig_secure_notification_channel_*` resource, writes `terraform/notification-channels.tf`
- [x] 4.3 Implement `generate_rules()` — reads `backups/rules/*.json`, maps fields to `sysdig_secure_rule_falco` arguments, writes `terraform/rules.tf`
- [x] 4.4 Implement `generate_teams()` — reads `backups/teams/*.json`, maps fields to `sysdig_secure_team` arguments, writes `terraform/teams.tf`
- [x] 4.5 Implement `generate_alerts()` — reads `backups/alerts/*.json`, maps fields to `sysdig_monitor_alert_v2` arguments, writes `terraform/alerts.tf`
- [x] 4.6 Ensure each generator emits read-only fields (`id`, `createdAt`, `modifiedAt`, `version`) as HCL comments
- [x] 4.7 Ensure each generator skips gracefully (logs + no output file) when its backup directory is empty or missing

## 5. Combined main.tf

- [x] 5.1 Implement `write_combined_tf()` — concatenates all generated per-type files into `terraform/main.tf` with section header comments (e.g., `# === Policies ===`)
- [x] 5.2 Ensure `main.tf` only includes sections for resource types that produced output

## 6. Summary Output

- [x] 6.1 After all generators run, print a summary line per output file: `terraform/<file>.tf — N resources`
- [x] 6.2 Print a total resource count at the end of the summary

## 7. backup.sh Integration

- [x] 7.1 Add `--terraform` flag parsing to `backup.sh`
- [x] 7.2 After successful export (before git commit), invoke `generate-terraform.sh` when `--terraform` is set
- [x] 7.3 Ensure Terraform generation failure is logged but does not cause `backup.sh` to exit non-zero

## 8. Verification

- [x] 8.1 Run `./backup.sh --dry-run` then `./generate-terraform.sh` and confirm all five `.tf` files and `main.tf` are produced
- [x] 8.2 Run `terraform init && terraform validate` in `terraform/` and confirm no syntax errors
- [x] 8.3 Run `./backup.sh --terraform --dry-run` and confirm generation is invoked and summary is printed
- [x] 8.4 Run generator twice and confirm output files are identical (idempotency check)

## 9. Documentation

- [x] 9.1 Update `README.md` — add a "Terraform Generation" section explaining `generate-terraform.sh`, the `--terraform` flag, and how to use the output with `terraform init` / `terraform apply`
- [x] 9.2 Document that credential fields in notification channels require manual replacement before `terraform apply`
- [x] 9.3 Update `CLAUDE.md` — add notes on the generator script and the `terraform/` output directory
