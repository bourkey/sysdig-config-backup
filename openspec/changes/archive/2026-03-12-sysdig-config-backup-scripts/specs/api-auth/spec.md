## ADDED Requirements

### Requirement: API token configuration
The system SHALL read the Sysdig Secure API token from an environment variable (`SYSDIG_API_TOKEN`) or a configuration file (`.env` or `config.sh`). The token MUST NOT be hardcoded in any script.

#### Scenario: Token loaded from environment variable
- **WHEN** `SYSDIG_API_TOKEN` is set in the environment
- **THEN** all API requests include the token in the `Authorization: Bearer <token>` header

#### Scenario: Token missing
- **WHEN** `SYSDIG_API_TOKEN` is not set and no config file is present
- **THEN** the script exits with a non-zero status code and prints a clear error message indicating the missing token

### Requirement: Region/endpoint configuration
The system SHALL support multiple Sysdig Secure regions by accepting a configurable base URL (`SYSDIG_API_URL`). A default value SHALL be provided for the US region (`https://secure.sysdig.com`).

#### Scenario: Default region used when not configured
- **WHEN** `SYSDIG_API_URL` is not set
- **THEN** the default US endpoint (`https://secure.sysdig.com`) is used for all API requests

#### Scenario: Custom region configured
- **WHEN** `SYSDIG_API_URL` is set to a valid endpoint (e.g., `https://eu1.app.sysdig.com`)
- **THEN** all API requests are sent to the configured endpoint

### Requirement: Authentication validation
The system SHALL validate that the API token is functional before proceeding with any exports by making a lightweight authenticated request to the API.

#### Scenario: Valid token accepted
- **WHEN** the API returns HTTP 200 for the validation request
- **THEN** the script proceeds with the backup run

#### Scenario: Invalid or expired token rejected
- **WHEN** the API returns HTTP 401 or HTTP 403
- **THEN** the script exits with a non-zero status code and prints an error indicating authentication failure
