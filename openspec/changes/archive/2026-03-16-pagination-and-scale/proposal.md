## Why

All exporters currently issue a single API request per resource type and load the entire response into memory — this silently truncates results on tenants with large numbers of resources if the API paginates. Similarly, the Terraform generator writes all resources of a given type into a single `.tf` file, which becomes unwieldy to diff, review, and apply as resource counts grow.

## What Changes

- Add a `sysdig_get_paged()` helper to `lib/common.sh` that iterates through API pages using `limit`/`offset` until all records are retrieved
- Update `export-policies.sh` and `export-alerts.sh` to use paginated fetching (these are the endpoints most likely to have large result sets)
- Add a configurable `SYSDIG_PAGE_SIZE` variable (default: 100) to control request batch size
- Update `generate-terraform.sh` to split output into numbered chunk files (e.g., `policies-001.tf`, `policies-002.tf`) when a resource type exceeds a configurable threshold per file
- Add a `SYSDIG_TF_CHUNK_SIZE` variable (default: 200) to control the split threshold

## Capabilities

### New Capabilities
- `api-pagination`: Paginated API fetching — a `sysdig_get_paged()` function in `lib/common.sh` that accumulates pages until the API signals exhaustion, and exporters updated to use it
- `terraform-chunked-output`: Splitting of large Terraform output into numbered files per resource type when resource count exceeds a configurable threshold

### Modified Capabilities
- `resource-export`: Exporters for policies and alerts SHALL fetch all pages rather than only the first response. The requirement that "all resources" are exported is now guaranteed regardless of dataset size.

## Impact

- **`lib/common.sh`**: new `sysdig_get_paged()` function; `load_config()` gains `SYSDIG_PAGE_SIZE` default
- **`exporters/export-policies.sh`**: switched to paginated fetch
- **`exporters/export-alerts.sh`**: switched to paginated fetch
- **`generate-terraform.sh`**: chunking logic added to per-type generation loops
- **`config.sh.example`**: two new optional variables documented
- Rules exporter is already per-ID fetching (scale tolerant); teams and notification channels are typically small — not updated initially
