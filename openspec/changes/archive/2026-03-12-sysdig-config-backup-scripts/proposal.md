## Why

Sysdig Secure configurations — including policies, alerts, notification channels, teams, and rules — are managed entirely in SaaS and have no built-in export or version control. A single accidental change or misconfiguration can silently degrade security posture with no recovery path. This project provides a scriptable backup mechanism that snapshots all configurable Sysdig Secure resources as files in a git repository, enabling auditability, change tracking, and recovery.

## What Changes

- New shell scripts to authenticate with the Sysdig Secure API and export all configurable resources as JSON/YAML files
- New directory structure for storing backed-up resources organized by resource type
- New cron-compatible entrypoint script for scheduled automated backups
- New configuration file for target region, API token, and backup scope
- New README documenting setup, configuration, and cron usage

## Capabilities

### New Capabilities
- `api-auth`: Handles authentication to the Sysdig Secure API using an API token, with support for multiple regions/endpoints
- `resource-export`: Exports all configurable Sysdig Secure resources (policies, alerts, notification channels, rules, teams, capture settings) to local files organized by type
- `backup-runner`: Top-level orchestration script that invokes all exporters and commits the results; designed to be called directly or via cron

### Modified Capabilities
<!-- None — this is a greenfield project -->

## Impact

- **Sysdig Secure API**: Read-only access required; uses the v1/v2 REST API endpoints for each resource type
- **API Token**: Requires a Sysdig Secure API token with read access to all resource types
- **Repository**: Backup files written to `backups/<resource-type>/` directories within this repo
- **Dependencies**: `curl` or equivalent HTTP client; `jq` for JSON processing; `git` for committing changes
- **Cron**: The runner script is designed to be invoked as a cron job (e.g., nightly) with no interactive input required
