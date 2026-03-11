# sysdig-config-backup

Automated backup of Sysdig Secure configuration to git. Exports policies, alerts, notification channels, rules, and teams as JSON files and commits any changes on each run.

## Prerequisites

- `bash` 4+
- `curl`
- `jq`
- `git` (configured with a user name and email for commits)
- A Sysdig Secure API token with read access to all resource types

## Setup

1. **Clone this repository**

   ```bash
   git clone <repo-url>
   cd sysdig-config-backup
   ```

2. **Create your configuration file**

   ```bash
   cp config.sh.example config.sh
   ```

   Edit `config.sh` and set your values:

   ```bash
   export SYSDIG_API_TOKEN="your-api-token-here"
   export SYSDIG_API_URL="https://secure.sysdig.com"  # adjust for your region
   ```

   `config.sh` is gitignored — it will never be committed.

3. **Test manually**

   ```bash
   ./backup.sh --dry-run
   ```

   This runs all exporters and writes files but does not create a git commit.

4. **Run a full backup**

   ```bash
   ./backup.sh
   ```

## Configuration Reference

| Variable | Required | Default | Description |
|---|---|---|---|
| `SYSDIG_API_TOKEN` | Yes | — | Sysdig Secure API token |
| `SYSDIG_API_URL` | No | `https://secure.sysdig.com` | API base URL for your region |

### Sysdig Secure regions

| Region | URL |
|---|---|
| US (default) | `https://secure.sysdig.com` |
| EU | `https://eu1.app.sysdig.com` |
| US2 | `https://us2.app.sysdig.com` |
| AU | `https://app.au1.sysdig.com` |

## Cron Setup

Run the backup nightly and log output to a file:

```cron
0 2 * * * SYSDIG_API_TOKEN=your-token-here /path/to/sysdig-config-backup/backup.sh >> /var/log/sysdig-backup.log 2>&1
```

Or if you prefer to use `config.sh`:

```cron
0 2 * * * /path/to/sysdig-config-backup/backup.sh >> /var/log/sysdig-backup.log 2>&1
```

The script is fully non-interactive and requires no TTY. It exits `0` on success (full or partial) and `1` only if authentication fails or all exporters fail.

To push the committed backup to a remote after each run, append a push command:

```cron
0 2 * * * /path/to/sysdig-config-backup/backup.sh && git -C /path/to/sysdig-config-backup push >> /var/log/sysdig-backup.log 2>&1
```

## Backup Directory Structure

After a run, the `backups/` directory will contain:

```
backups/
├── metadata.json                    # Run summary (timestamp, counts per type)
├── policies/
│   ├── my-policy-name.json
│   └── another-policy.json
├── alerts/
│   └── high-severity-alert.json
├── notification-channels/
│   ├── slack-security.json
│   └── pagerduty-oncall.json
├── rules/
│   └── custom-rules.json
└── teams/
    ├── platform-team.json
    └── security-team.json
```

Each file is the raw JSON object as returned by the Sysdig Secure API for that resource. File names are derived from the resource's `name` field: lowercased, with spaces and special characters replaced by hyphens. If two resources produce the same filename, the second is disambiguated with its resource ID (e.g., `my-policy-42.json`).

`metadata.json` is updated on every run and contains:

```json
{
  "timestamp": "2024-01-15T02:00:05Z",
  "api_url": "https://secure.sysdig.com",
  "counts": {
    "policies": 12,
    "alerts": 8,
    "notification-channels": 3,
    "rules": 2,
    "teams": 4
  }
}
```

## Adding a New Resource Type

1. Create `exporters/export-<resource>.sh` using an existing exporter as a template.
2. Set the correct API path for the resource.
3. Adjust the `jq` filter to match the response envelope (e.g., `.resources[]`).
4. Call `record_export_count "<resource>" "${count}"` before returning.
5. Add the new script path to the `EXPORTERS` array in `backup.sh`.
6. Make it executable: `chmod +x exporters/export-<resource>.sh`

Each exporter is independent — a failure in one will be logged but will not prevent others from running.

## Flags

| Flag | Description |
|---|---|
| `--dry-run` | Run all exports and write files, but skip the git commit |
