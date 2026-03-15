## ADDED Requirements

### Requirement: Paginated API fetching
The system SHALL provide a `sysdig_get_paged()` function in `lib/common.sh` that iterates through all pages of a paginated API endpoint using `limit`/`offset` parameters, accumulates all results, and prints a single merged JSON array to stdout. The function MUST accept a path and an optional envelope field name; when the envelope field is empty or `.`, the response body is treated as a direct JSON array.

#### Scenario: Single page result
- **WHEN** the first page returns fewer items than `SYSDIG_PAGE_SIZE`
- **THEN** `sysdig_get_paged()` makes exactly one request and returns all items as a JSON array

#### Scenario: Multi-page result
- **WHEN** the first page returns exactly `SYSDIG_PAGE_SIZE` items
- **THEN** `sysdig_get_paged()` fetches subsequent pages by incrementing the offset until a short page (fewer than `SYSDIG_PAGE_SIZE` items) is received, then returns all accumulated items as a single JSON array

#### Scenario: Empty result set
- **WHEN** the API returns an empty array on the first page
- **THEN** `sysdig_get_paged()` returns an empty JSON array (`[]`) and does not fetch further pages

#### Scenario: API error during paging
- **WHEN** any page request returns a non-2xx HTTP status or curl error
- **THEN** `sysdig_get_paged()` returns non-zero and prints an error to stderr

### Requirement: Configurable page size
The system SHALL respect a `SYSDIG_PAGE_SIZE` environment variable that controls the number of records requested per API call. The default value SHALL be `100`. The value is passed as the `limit` query parameter on each paginated request.

#### Scenario: Default page size used
- **WHEN** `SYSDIG_PAGE_SIZE` is not set
- **THEN** each API request uses `limit=100`

#### Scenario: Custom page size configured
- **WHEN** `SYSDIG_PAGE_SIZE=500` is set
- **THEN** each API request uses `limit=500`

### Requirement: Wrapped response envelope support
The system SHALL support API responses that wrap the resource array inside a named field. When `sysdig_get_paged()` is called with an envelope field name, it SHALL extract that field from each page response before accumulating items.

#### Scenario: Direct array response
- **WHEN** `sysdig_get_paged()` is called with an empty envelope field
- **THEN** each page response body is treated as a JSON array directly

#### Scenario: Wrapped array response
- **WHEN** `sysdig_get_paged()` is called with envelope field `alerts`
- **THEN** `.alerts` is extracted from each page response before accumulation
