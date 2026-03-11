## Context

The backup scripts produce per-resource JSON files in `backups/<type>/`. Each file is the raw API response for a single Sysdig Secure resource. The Sysdig Terraform provider (`sysdiglabs/sysdig`) uses HCL resource blocks whose arguments map closely but not identically to the API JSON fields — some fields are read-only (IDs, timestamps), some are renamed, and some composite API structures map to nested HCL blocks.

The generator must bridge this gap: read JSON, drop or comment out fields that don't belong in Terraform (e.g., `id`, `createdAt`), rename fields where the provider uses a different attribute name, and format values correctly as HCL literals.

## Goals / Non-Goals

**Goals:**
- Produce syntactically valid HCL that `terraform plan` can parse after `terraform init`
- Cover all five resource types currently backed up: policies, notification channels, rules, teams, alerts
- Make unmapped or read-only fields visible as comments rather than silently dropping them
- Be runnable standalone or via `backup.sh --terraform`
- Produce both per-type files and a combined `main.tf`

**Non-Goals:**
- Guarantee that `terraform apply` will succeed without modification — some fields may need operator review (e.g., team membership, notification channel credentials)
- Import existing Sysdig resources into Terraform state (`terraform import`) — that is an operator step after generation
- Support round-trip restore of Sysdig Monitor resources (alerts are included as best-effort)
- Validate the generated HCL against the live provider schema at generation time

## Decisions

### Bash + jq for generation (not Python or Go)
**Decision**: Implement `generate-terraform.sh` in bash using `jq` for JSON parsing and string building for HCL output.

**Rationale**: Consistent with the existing codebase (all scripts are bash + jq). No new runtime dependency. The HCL format for these resource types is straightforward enough that jq's `@sh` and string interpolation handles it without a templating engine. Operators can read and modify the generator without installing anything extra.

**Alternative considered**: Python with a Jinja2 template — rejected because it introduces a Python runtime dependency and virtualenv management for what is essentially a text transformation.

---

### One generator function per resource type
**Decision**: `generate-terraform.sh` contains one `generate_<type>()` function per resource type, each responsible for reading its backup directory and writing its output file.

**Rationale**: Mirrors the one-exporter-per-type pattern from the backup scripts. Each resource type has different field mappings and provider resource names, so isolation prevents complexity creep. Easy to add or remove a type.

---

### Read-only and unmapped fields emitted as HCL comments
**Decision**: Fields that are API-managed (e.g., `id`, `createdAt`, `modifiedAt`, `version`) and fields with no known provider equivalent are written as `# <field> = <value>` comments rather than omitted.

**Rationale**: Silently dropping fields risks operators missing important context when reviewing the generated HCL. Comments make the full picture visible while keeping the HCL valid. Operators can promote a commented field to an active argument if the provider adds support later.

---

### provider.tf written once, not overwritten
**Decision**: `generate-terraform.sh` writes `terraform/provider.tf` only if it does not already exist.

**Rationale**: Operators will customise `provider.tf` (e.g., add a backend block, pin the provider version, set a workspace). Overwriting it on every run would destroy those customisations. Per-type and combined files are always overwritten since they are fully derived from backup data.

---

### terraform/ directory gitignored by default
**Decision**: Add `terraform/` to `.gitignore`. Operators opt in to committing it.

**Rationale**: Generated Terraform is a point-in-time artefact derived from the backups. Committing it alongside the backups creates redundancy and potential confusion. Operators who want to version the Terraform output can remove the gitignore entry explicitly.

---

### --terraform flag on backup.sh (opt-in, non-fatal)
**Decision**: Terraform generation is opt-in via `./backup.sh --terraform`. Generation failure does not prevent the backup commit.

**Rationale**: The backup is the primary function of the repo. Terraform generation is a secondary convenience. Making it non-fatal ensures that a bug in the generator or an unsupported resource type never silently blocks the backup run.

## Risks / Trade-offs

- **Provider schema drift** → The `sysdiglabs/sysdig` provider evolves; generated HCL may reference removed or renamed arguments. Mitigation: emit provider version constraint in `provider.tf`; operator runs `terraform validate` before applying.
- **Notification channel credential fields** → Channels include sensitive fields (tokens, keys) in backup JSON. These will appear in generated HCL in plaintext. Mitigation: document that operators should replace credential values with `var.*` references or use `sensitive = true` before committing Terraform.
- **Team membership complexity** → Team JSON includes user lists that may reference user IDs not easily reproducible in Terraform. Mitigation: emit user-related fields as comments with a note to review.
- **Large number of resources** → 60+ policies each producing a resource block in both `policies.tf` and `main.tf` creates large files. Mitigation: acceptable trade-off; files are machine-generated and not intended for manual editing.

## Open Questions

- Which exact `sysdig_secure_notification_channel_*` resource type names does the provider use for each channel `type` value in the API JSON? This needs to be confirmed against the provider registry during implementation.
- Do any policy fields (e.g., `ruleNames`, `notificationChannelIds`) require cross-references to other Terraform resources, or can they be set as plain strings/IDs on initial apply?
