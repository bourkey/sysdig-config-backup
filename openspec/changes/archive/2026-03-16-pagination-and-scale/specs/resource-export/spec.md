## MODIFIED Requirements

### Requirement: Export policies
The system SHALL export all Sysdig Secure runtime security policies to `backups/policies/` as individual JSON files, one per policy, named by policy ID or sanitized policy name. The exporter MUST fetch all pages of the policies API using paginated requests until no further records remain, guaranteeing a complete export regardless of total policy count.

#### Scenario: Policies exported successfully
- **WHEN** the export script runs and the API returns a list of policies
- **THEN** each policy is written to `backups/policies/<policy-name>.json`

#### Scenario: No policies found
- **WHEN** the API returns an empty list of policies
- **THEN** the export completes without error and the directory is left empty

#### Scenario: Policies span multiple pages
- **WHEN** the tenant has more policies than the configured page size
- **THEN** all policies across all pages are exported, and the total exported count matches the total policy count in the API

### Requirement: Export alerts
The system SHALL export all configured Sysdig Secure alerts to `backups/alerts/` as individual JSON files, one per alert. The exporter MUST fetch all pages of the alerts API using paginated requests until no further records remain, guaranteeing a complete export regardless of total alert count.

#### Scenario: Alerts exported successfully
- **WHEN** the export script runs and the API returns a list of alerts
- **THEN** each alert is written to `backups/alerts/<alert-name>.json`

#### Scenario: API error during alert export
- **WHEN** the alerts API endpoint returns a non-2xx response
- **THEN** the script logs the error and continues exporting other resource types (non-fatal)

#### Scenario: Alerts span multiple pages
- **WHEN** the tenant has more alerts than the configured page size
- **THEN** all alerts across all pages are exported, and the total exported count matches the total alert count in the API
