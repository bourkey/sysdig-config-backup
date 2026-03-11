# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## Project Overview

This repository contains bash scripts to back up Sysdig Secure SaaS configuration to git. It exports policies, alerts, notification channels, custom Falco rules, and teams as JSON files and commits changes on each run.

## Architecture

```
backup.sh                  # Main entrypoint — orchestrates all exporters
lib/common.sh              # Shared functions: API auth, HTTP, file writing, metadata
exporters/
  export-policies.sh       # GET /api/v2/policies
  export-alerts.sh         # GET /api/v2/alerts
  export-notification-channels.sh  # GET /api/notificationChannels
  export-rules.sh          # GET /api/secure/rules/summaries + /api/secure/rules/{id}
  export-teams.sh          # GET /api/teams
backups/                   # Output directory — all exported JSON files land here
config.sh.example          # Template for local config (copy to config.sh)
```

## Configuration

All configuration is via environment variables or a sourced `config.sh` file (gitignored):

| Variable | Required | Default |
|---|---|---|
| `SYSDIG_API_TOKEN` | Yes | — |
| `SYSDIG_API_URL` | No | `https://secure.sysdig.com` |

## Running

```bash
./backup.sh            # Full backup + git commit
./backup.sh --dry-run  # Export files only, no git commit
```

## API Notes

- Auth endpoint: `GET /api/user/me`
- Policies return a **direct JSON array** (not wrapped in a field) — use `.[]` not `.policies[]`
- Rules require a two-step fetch: summaries → per-ID via `/api/secure/rules/{id}`
  - Only exports rules with origin `"Customer"` or `"Secure UI"` (skips Sysdig defaults)
  - Using `/api/secure/rules/groups?name=...` returns HTTP 400 for rules with multiple sources
- API specs are in `openapi.json` and `public-api-spec.yaml` (gitignored — internal use only)

## Adding a New Exporter

1. Copy an existing exporter from `exporters/` as a template
2. Set the correct API path and `jq` filter for the response envelope
3. Call `record_export_count "<type>" "${count}"` before returning
4. Add the script path to the `EXPORTERS` array in `backup.sh`
5. `chmod +x exporters/export-<type>.sh`

## Key Implementation Details

- `lib/common.sh` must be bash 3.2 compatible (macOS default) — no `declare -A`
- Export counts are tracked via `backups/.counts/<type>` temp files (not env vars) so they survive subprocess boundaries
- `BACKUP_DIR`, `SYSDIG_API_TOKEN`, and `SYSDIG_API_URL` are exported from `load_config()` so subprocess exporters inherit them
- `backups/.counts/` is gitignored
