## ADDED Requirements

### Requirement: Generate Terraform for policies
The system SHALL read all JSON files from `backups/policies/` and produce a `terraform/policies.tf` file containing one `sysdig_secure_policy` resource block per policy.

#### Scenario: Policies exported and generator run
- **WHEN** `generate-terraform.sh` is executed and `backups/policies/` contains JSON files
- **THEN** `terraform/policies.tf` is written with one `resource "sysdig_secure_policy" "<resource_name>"` block per file, mapping JSON fields to provider arguments

#### Scenario: No policies backup files
- **WHEN** `backups/policies/` is empty or does not exist
- **THEN** no `policies.tf` is written and the generator logs that no policies were found

### Requirement: Generate Terraform for notification channels
The system SHALL read all JSON files from `backups/notification-channels/` and produce a `terraform/notification-channels.tf` file. Each channel SHALL use the appropriate type-specific resource (`sysdig_secure_notification_channel_email`, `sysdig_secure_notification_channel_slack`, `sysdig_secure_notification_channel_pagerduty`, `sysdig_secure_notification_channel_webhook`, etc.) based on the `type` field in the JSON.

#### Scenario: Mixed channel types
- **WHEN** `backups/notification-channels/` contains channels of different types
- **THEN** each channel is written with the correct provider resource type matching its `type` field

#### Scenario: Unknown channel type
- **WHEN** a notification channel JSON has a `type` value not mapped to a known provider resource
- **THEN** the generator logs a warning for that channel and skips it rather than producing invalid HCL

### Requirement: Generate Terraform for custom rules
The system SHALL read all JSON files from `backups/rules/` and produce a `terraform/rules.tf` file containing one `sysdig_secure_rule_falco` resource block per rule file.

#### Scenario: Rules exported and generator run
- **WHEN** `generate-terraform.sh` is executed and `backups/rules/` contains JSON files
- **THEN** `terraform/rules.tf` is written with one `resource "sysdig_secure_rule_falco" "<resource_name>"` block per file

### Requirement: Generate Terraform for teams
The system SHALL read all JSON files from `backups/teams/` and produce a `terraform/teams.tf` file containing one `sysdig_secure_team` resource block per team.

#### Scenario: Teams exported and generator run
- **WHEN** `generate-terraform.sh` is executed and `backups/teams/` contains JSON files
- **THEN** `terraform/teams.tf` is written with one `resource "sysdig_secure_team" "<resource_name>"` block per file

### Requirement: Generate Terraform for alerts
The system SHALL read all JSON files from `backups/alerts/` and produce a `terraform/alerts.tf` file containing one `sysdig_monitor_alert_v2` resource block per alert.

#### Scenario: Alerts exported and generator run
- **WHEN** `generate-terraform.sh` is executed and `backups/alerts/` contains JSON files
- **THEN** `terraform/alerts.tf` is written with one `resource "sysdig_monitor_alert_v2" "<resource_name>"` block per file

#### Scenario: No alerts
- **WHEN** `backups/alerts/` is empty
- **THEN** no `alerts.tf` is written

### Requirement: Resource name sanitisation
The system SHALL derive a valid Terraform resource identifier from each backup filename by converting to lowercase, replacing hyphens and spaces with underscores, stripping the `.json` extension, and prefixing with the resource type short name to avoid collisions.

#### Scenario: Filename with hyphens
- **WHEN** the backup file is `my-policy-name.json`
- **THEN** the Terraform resource label is `my_policy_name`

#### Scenario: Filename starting with a digit
- **WHEN** the sanitised label would start with a digit
- **THEN** the label is prefixed with the resource type (e.g., `policy_42`)

### Requirement: Field mapping completeness
For each resource type, the generator SHALL map all fields present in the JSON that have a direct equivalent in the Terraform provider schema. Fields with no provider equivalent SHALL be emitted as comments in the HCL output so operators are aware of any data not captured by the provider.

#### Scenario: Unknown JSON field
- **WHEN** a JSON backup contains a field not mapped to any provider argument
- **THEN** the field is written as an HCL comment (`# unmapped: <field> = <value>`) rather than silently dropped

### Requirement: Idempotent generation
Running `generate-terraform.sh` multiple times with the same backup files SHALL produce identical output. The generator MUST overwrite existing `.tf` files rather than appending to them.

#### Scenario: Generator run twice
- **WHEN** `generate-terraform.sh` is run twice without changes to `backups/`
- **THEN** the output files are identical and no duplicates are introduced
