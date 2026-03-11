## ADDED Requirements

### Requirement: TLS insecure mode
The system SHALL support disabling TLS certificate verification for all API requests via the `SYSDIG_TLS_INSECURE` environment variable. When set to the exact string `true`, the system MUST pass `--insecure` to every `curl` invocation. This option SHALL be documented as a security risk in configuration examples.

#### Scenario: Insecure mode disabled by default
- **WHEN** `SYSDIG_TLS_INSECURE` is not set or is set to any value other than `true`
- **THEN** all `curl` calls use the default system trust store for TLS verification

#### Scenario: Insecure mode enabled
- **WHEN** `SYSDIG_TLS_INSECURE=true` is set in the environment or `config.sh`
- **THEN** all `curl` calls include `--insecure`, bypassing TLS certificate verification

### Requirement: Custom CA certificate
The system SHALL support specifying a custom CA certificate bundle for TLS verification via the `SYSDIG_CA_CERT` environment variable. When set to a non-empty string, the system MUST pass `--cacert <path>` to every `curl` invocation using the provided path.

#### Scenario: Custom CA not configured
- **WHEN** `SYSDIG_CA_CERT` is not set or is empty
- **THEN** all `curl` calls use the default system trust store without `--cacert`

#### Scenario: Custom CA configured
- **WHEN** `SYSDIG_CA_CERT` is set to the path of an existing PEM file
- **THEN** all `curl` calls include `--cacert <path>`, trusting the specified CA bundle

### Requirement: Custom CA certificate path validation
The system SHALL validate that the file referenced by `SYSDIG_CA_CERT` exists before executing any exports. If the file does not exist, the system MUST exit with a non-zero status code and print a clear error message identifying the missing file path.

#### Scenario: CA cert file exists
- **WHEN** `SYSDIG_CA_CERT` is set and the file at that path exists
- **THEN** the system proceeds with the backup run normally

#### Scenario: CA cert file missing
- **WHEN** `SYSDIG_CA_CERT` is set to a path that does not exist on the filesystem
- **THEN** the system exits with a non-zero status code and prints an error message containing the invalid path before running any exporters

### Requirement: Redundant TLS configuration warning
The system SHALL emit a warning to stderr when both `SYSDIG_TLS_INSECURE=true` and `SYSDIG_CA_CERT` are set simultaneously, as `--insecure` makes the CA cert superfluous.

#### Scenario: Both TLS options set together
- **WHEN** `SYSDIG_TLS_INSECURE=true` and `SYSDIG_CA_CERT` are both set
- **THEN** the system prints a warning to stderr indicating the combination is redundant, then proceeds normally with `--insecure` taking effect
