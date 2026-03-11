## ADDED Requirements

### Requirement: Export policies
The system SHALL export all Sysdig Secure runtime security policies to `backups/policies/` as individual JSON files, one per policy, named by policy ID or sanitized policy name.

#### Scenario: Policies exported successfully
- **WHEN** the export script runs and the API returns a list of policies
- **THEN** each policy is written to `backups/policies/<policy-name>.json`

#### Scenario: No policies found
- **WHEN** the API returns an empty list of policies
- **THEN** the export completes without error and the directory is left empty

### Requirement: Export alerts
The system SHALL export all configured Sysdig Secure alerts to `backups/alerts/` as individual JSON files, one per alert.

#### Scenario: Alerts exported successfully
- **WHEN** the export script runs and the API returns a list of alerts
- **THEN** each alert is written to `backups/alerts/<alert-name>.json`

#### Scenario: API error during alert export
- **WHEN** the alerts API endpoint returns a non-2xx response
- **THEN** the script logs the error and continues exporting other resource types (non-fatal)

### Requirement: Export notification channels
The system SHALL export all configured notification channels (email, Slack, PagerDuty, webhook, etc.) to `backups/notification-channels/` as individual JSON files.

#### Scenario: Notification channels exported successfully
- **WHEN** the export script runs and the API returns notification channels
- **THEN** each channel is written to `backups/notification-channels/<channel-name>.json`

### Requirement: Export rules
The system SHALL export all custom Falco rules and rule sets to `backups/rules/` as individual JSON files.

#### Scenario: Rules exported successfully
- **WHEN** the export script runs and the API returns rules
- **THEN** each rule set is written to `backups/rules/<rule-name>.json`

### Requirement: Export teams
The system SHALL export all configured Sysdig Secure teams and their settings to `backups/teams/` as individual JSON files.

#### Scenario: Teams exported successfully
- **WHEN** the export script runs and the API returns teams
- **THEN** each team is written to `backups/teams/<team-name>.json`

### Requirement: Sanitized file naming
The system SHALL sanitize resource names for use as filenames by replacing spaces and special characters with hyphens, converting to lowercase, and falling back to the resource ID if the name is empty or results in a collision.

#### Scenario: Resource name with spaces
- **WHEN** a resource has name "My Policy Name"
- **THEN** it is saved as `my-policy-name.json`

#### Scenario: Duplicate sanitized names
- **WHEN** two resources would produce the same sanitized filename
- **THEN** the second is disambiguated using its resource ID (e.g., `my-policy-name-<id>.json`)

### Requirement: Atomic export per resource type
Each resource type export SHALL be independent. A failure exporting one resource type MUST NOT prevent other resource types from being exported.

#### Scenario: One exporter fails
- **WHEN** the teams API is unavailable but all other APIs succeed
- **THEN** teams are skipped with an error logged, and all other resource types are exported successfully

### Requirement: Export metadata file
The system SHALL write a `backups/metadata.json` file on each run containing the timestamp, API base URL (redacted token), and a summary count of resources exported per type.

#### Scenario: Metadata written after export
- **WHEN** the export run completes (even partially)
- **THEN** `backups/metadata.json` is written with run timestamp and per-type counts
