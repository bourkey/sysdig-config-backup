## Context

All exporters call `sysdig_get()` once and process the entire response body as a single in-memory string. The Sysdig API uses `limit`/`offset` pagination on collection endpoints — without it the API silently returns only the first page (typically 100–200 items). The Terraform generator writes one `.tf` file per resource type; at scale these become large diffs and slow `terraform plan` parse times.

All code must remain bash 3.2 compatible (macOS system shell): no `mapfile`, no associative arrays.

## Goals / Non-Goals

**Goals:**
- `sysdig_get_paged()` accumulates all pages transparently, so exporters do not need to manage loop state
- Policies and alerts exporters use paginated fetching to guarantee complete exports regardless of tenant size
- `SYSDIG_PAGE_SIZE` controls request batch size (default: 100)
- Terraform output splits into numbered files (`policies-001.tf`, etc.) when resource count exceeds `SYSDIG_TF_CHUNK_SIZE` (default: 200)
- Stale chunk files are cleaned before each Terraform generation run

**Non-Goals:**
- Parallelising exporter HTTP requests — sequential paging is sufficient and simpler
- Paginating rules, teams, or notification-channels exporters in this iteration (rules are already per-ID; teams and channels are typically small)
- Streaming/incremental write during pagination — all pages are accumulated then written

## Decisions

### 1. `sysdig_get_paged()` accumulates pages via a temp file with `jq -s 'add'`

**Decision:** Each page response is appended to a temp file as a JSON array (one per line). After the loop, `jq -s 'add'` merges them into a single flat array. The function prints the merged array to stdout, matching the interface of `sysdig_get()`.

**Rationale:** Bash 3.2 has no `mapfile` or associative arrays. String concatenation of large JSON is fragile. A temp file with jq merge is robust, handles embedded newlines correctly, and is idiomatic for this codebase (which already uses temp files in `sysdig_get()`).

**Alternative considered:** Multiple calls to `sysdig_get()` with the caller managing offset. Rejected — pagination loop logic would be duplicated in every exporter.

### 2. Termination condition: page count < limit, or HTTP 404

**Decision:** Stop paging when the number of items in the returned page is less than `SYSDIG_PAGE_SIZE`, or when `sysdig_get()` returns non-zero (including 404).

**Rationale:** The Sysdig API does not consistently include a `total` field across all endpoints. The "short page" pattern (last page has fewer items than the limit) is universally reliable. A 404 on page >0 is treated as end-of-results rather than an error.

**Alternative considered:** Using a `total` field from the response envelope. Rejected — not all endpoints return it, and the short-page pattern is sufficient.

### 3. `sysdig_get_paged()` accepts an envelope field argument

**Decision:** The function signature is `sysdig_get_paged <path> <envelope_field>`. When `<envelope_field>` is empty or `.`, the response is treated as a direct array. When set (e.g., `alerts`), the function extracts `.alerts` from each page before accumulating.

**Rationale:** Policies return a direct array; alerts return `{ "alerts": [...] }`. A single function handles both without callers needing to unwrap envelopes after accumulation.

### 4. Terraform chunking uses numbered output files; `main.tf` is rebuilt from chunks

**Decision:** When resource count for a type exceeds `SYSDIG_TF_CHUNK_SIZE`, the generator writes `<type>-001.tf`, `<type>-002.tf`, etc. instead of a single `<type>.tf`. The combined `main.tf` is always rebuilt from all per-type files (chunked or not).

**Rationale:** Keeps individual files reviewable in git. The numbered naming makes chunk sequence obvious and supports straightforward glob-based stale-file cleanup.

**Stale chunk cleanup:** Before regenerating a resource type, all existing `<type>*.tf` files in `terraform/src/` are removed. This prevents orphaned chunks from previous runs with larger datasets.

**Alternative considered:** Always using chunked filenames (even for small datasets with just `-001`). Rejected — breaks existing setups and adds noise; only split when needed.

### 5. `SYSDIG_TF_CHUNK_SIZE=0` disables chunking

**Decision:** Setting `SYSDIG_TF_CHUNK_SIZE=0` disables splitting entirely — all resources for a type go into a single file regardless of count.

**Rationale:** Operators who prefer monolithic `.tf` files (e.g., for simpler CI pipelines) can opt out without removing the variable.

## Risks / Trade-offs

- **Many API calls on large tenants:** A tenant with 1,000 policies and `SYSDIG_PAGE_SIZE=100` requires 10 sequential HTTP requests. Mitigation: page size is configurable up to API maximum.
- **Temp file accumulation for very large datasets:** Accumulating all pages before writing could use significant disk space for tenants with tens of thousands of resources. Mitigation: temp files are cleaned up after each exporter run; acceptable for current scale targets.
- **Chunk file count changes between runs:** Reducing from 5 chunks to 3 would leave `policies-004.tf` and `policies-005.tf` as stale files. Mitigation: pre-run cleanup of all `<type>*.tf` files before regenerating each type.

## Migration Plan

1. Add `sysdig_get_paged()` to `lib/common.sh` and `SYSDIG_PAGE_SIZE` default in `load_config()`
2. Update `export-policies.sh` and `export-alerts.sh` to call `sysdig_get_paged()`
3. Add chunking logic and stale-file cleanup to `generate-terraform.sh`; add `SYSDIG_TF_CHUNK_SIZE` default
4. Update `config.sh.example` with both new variables
5. No rollback needed — both variables default to existing behaviour (page size 100 fetches same data as before on small tenants; chunk size 200 means no split on most deployments)
