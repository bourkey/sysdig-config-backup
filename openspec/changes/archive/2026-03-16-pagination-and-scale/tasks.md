## 1. Add pagination support to lib/common.sh

- [x] 1.1 Add `SYSDIG_PAGE_SIZE` default (`100`) in `load_config()`
- [x] 1.2 Implement `sysdig_get_paged <path> [envelope_field]` in `lib/common.sh` — loops with `limit`/`offset`, accumulates pages to a temp file, merges with `jq -s 'add'`, prints merged array to stdout
- [x] 1.3 Handle envelope field in `sysdig_get_paged()` — when non-empty, extract `.<field>` from each page before accumulating
- [x] 1.4 Handle termination: stop when page item count < `SYSDIG_PAGE_SIZE` or when `sysdig_get()` returns non-zero

## 2. Update exporters to use paginated fetching

- [x] 2.1 Update `export-policies.sh` to call `sysdig_get_paged "/api/v2/policies"` (no envelope) instead of `sysdig_get`
- [x] 2.2 Update `export-alerts.sh` to call `sysdig_get_paged "/api/v2/alerts" "alerts"` instead of `sysdig_get`

## 3. Add Terraform chunking to generate-terraform.sh

- [x] 3.1 Add `SYSDIG_TF_CHUNK_SIZE` default (`200`) in `generate-terraform.sh` (or `load_config()`)
- [x] 3.2 Add a `write_tf_chunks <type> <src_file>` helper (or inline logic) that splits a generated `.tf` content into numbered files when resource count exceeds threshold; writes single file when at or below threshold or when `SYSDIG_TF_CHUNK_SIZE=0`
- [x] 3.3 Add stale-file cleanup before each resource type is regenerated — remove all `<type>*.tf` files from `terraform/src/` before writing new output
- [x] 3.4 Update the policies generation function to use chunked output
- [x] 3.5 Update the alerts generation function to use chunked output
- [x] 3.6 Update remaining resource type generators (notification-channels, rules, teams) to also clean up stale files and use chunked output for consistency

## 4. Update config.sh.example

- [x] 4.1 Add commented-out `SYSDIG_PAGE_SIZE` entry with note on default and API max
- [x] 4.2 Add commented-out `SYSDIG_TF_CHUNK_SIZE` entry with note on default and `0` to disable

## 5. Manual verification

- [x] 5.1 Run `./backup.sh --dry-run` — confirm policies and alerts exporters complete without error and output counts match expectations
- [x] 5.2 Run `./generate-terraform.sh` with a small dataset — confirm single `.tf` files are produced (no chunking below threshold)
- [x] 5.3 Manually set `SYSDIG_TF_CHUNK_SIZE=2` and run `./generate-terraform.sh` — confirm numbered chunk files are produced and no stale files remain from a previous run
