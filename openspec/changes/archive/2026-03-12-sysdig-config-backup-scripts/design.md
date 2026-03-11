## Context

Sysdig Secure is a SaaS CNAPP platform with a REST API for reading configuration. There is no native export or versioning feature. This project implements a backup system using shell scripts that call the Sysdig Secure API, write responses as JSON files, and commit changes to git. The system targets operators who want to snapshot their Sysdig configuration on a schedule (e.g., nightly via cron) and track configuration drift over time.

The environment is a standard Unix shell (bash) with `curl`, `jq`, and `git` available. No agent or daemon runs persistently — the backup is a one-shot invocation.

## Goals / Non-Goals

**Goals:**
- Export all major configurable Sysdig Secure resource types to JSON files in this repo
- Run non-interactively from cron with minimal dependencies
- Commit changes to git so configuration history is preserved
- Fail gracefully — partial export is better than total failure
- Be simple enough to audit, modify, and extend by hand

**Non-Goals:**
- Restoring/importing configuration back into Sysdig Secure
- Real-time or event-driven backups (only periodic/manual runs)
- Supporting non-SaaS/on-prem Sysdig deployments
- Encrypting backup files or managing secrets beyond reading from env
- Deduplication, compression, or retention management of backup files

## Decisions

### Shell scripts over Python/Go
**Decision**: Implement in bash with `curl` and `jq`.

**Rationale**: The target environment (cron on a Linux/macOS host or CI runner) reliably has bash, curl, and jq. A Python or Go implementation would require managing a runtime, virtualenv, or binary. Bash keeps the dependency surface minimal and the scripts auditable without toolchain setup. The API interactions are simple HTTP GETs — no complex state machine is needed.

**Alternative considered**: Python with `requests` — rejected due to env management overhead for a scheduled job.

---

### One script per resource type
**Decision**: Each resource type (policies, alerts, teams, etc.) has its own exporter script in `exporters/`. The runner sources or invokes each one independently.

**Rationale**: Isolation prevents a bug or API failure in one exporter from silently corrupting others. It also makes it easy to add or remove resource types without modifying the orchestrator. Each exporter is individually testable.

**Alternative considered**: One monolithic script — rejected because a single failure point would abort all exports.

---

### JSON output format (not YAML)
**Decision**: Store backup files as raw JSON as returned by the Sysdig API.

**Rationale**: The API returns JSON. Converting to YAML introduces a transformation step that could lose precision or introduce diffs unrelated to actual config changes. Raw JSON is also easier to diff programmatically and re-import later if a restore feature is added.

---

### File-per-resource naming
**Decision**: Write one JSON file per resource instance, named by sanitized resource name with ID fallback.

**Rationale**: Per-resource files produce clean, readable git diffs — a change to one policy shows up as a single file change. Alternatives like one-file-per-type (all policies in `policies.json`) produce large diffs that are hard to review.

---

### Git commit in the runner (not a separate step)
**Decision**: `backup.sh` calls `git add` and `git commit` after a successful export.

**Rationale**: Keeps the backup atomic — the commit happens only when export succeeds. Operators can run `backup.sh` from cron and trust that git history reflects actual backup runs. If git commit were a separate step, a failed cron job could leave uncommitted exports.

**Trade-off**: Requires the repo to have a git remote configured and the cron environment to have git credentials if push is desired (push is out of scope).

---

### Configuration via environment variables
**Decision**: `SYSDIG_API_TOKEN` and `SYSDIG_API_URL` are read from environment. A `config.sh` file can be sourced to provide these in non-interactive environments.

**Rationale**: Environment variables are the standard way to pass secrets to cron jobs and CI systems. A `config.sh` source file provides a convenient local alternative without requiring shell profile setup. No config file format parsing (TOML, YAML, INI) is needed.

## Risks / Trade-offs

- **API rate limiting** → Mitigation: Add a short sleep between API calls in each exporter; document this in the config.
- **Token stored in cron environment** → Mitigation: Document use of a secrets manager or restricted-permission `config.sh` file (`chmod 600`).
- **Sysdig API changes** → Mitigation: Each exporter targets a specific versioned endpoint. Failures are logged clearly, making broken endpoints easy to identify and update.
- **Large repos over time** → Mitigation: Git history naturally grows; operators can periodically squash or shallow-clone. Retention management is explicitly out of scope.
- **No push step** → Mitigation: Documented as a post-run step operators can add to their crontab or CI pipeline.

## Open Questions

- Which specific Sysdig API versions (v1 vs v2) should be used for each resource type? This will need to be confirmed against the Sysdig API docs during implementation.
- Should capture settings and scanning configs be included in scope, or deferred to a later iteration?
