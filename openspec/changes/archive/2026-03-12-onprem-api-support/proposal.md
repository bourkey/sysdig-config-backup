## Why

On-premises Sysdig Secure deployments commonly use private CA certificates or self-signed TLS certificates, and there is currently no way to configure TLS verification behaviour in this backup tool — all `curl` requests use the system trust store with no override. This blocks operators running on-prem instances from successfully running backups.

## What Changes

- Add `SYSDIG_TLS_INSECURE` flag (default: `false`) — when set to `true`, passes `--insecure` to all `curl` calls, disabling TLS certificate verification
- Add `SYSDIG_CA_CERT` variable — when set to a file path, passes `--cacert <path>` to all `curl` calls, trusting a custom CA bundle
- Update `lib/common.sh` `sysdig_get()` to incorporate TLS options based on these variables
- Update `config.sh.example` to document the new variables
- Update `validate_config()` to warn if both `SYSDIG_TLS_INSECURE=true` and `SYSDIG_CA_CERT` are set (redundant combination)

## Capabilities

### New Capabilities
- `onprem-tls-config`: Configuration and runtime behaviour for TLS certificate handling when connecting to Sysdig API endpoints, covering insecure mode and custom CA certificate support

### Modified Capabilities
_(none — existing `api-auth` requirements around token and URL configuration are unchanged)_

## Impact

- **`lib/common.sh`**: `sysdig_get()` and `load_config()` / `validate_config()` modified
- **`config.sh.example`**: New variables documented
- **All exporters**: Inherit TLS behaviour automatically via `sysdig_get()` — no changes required in individual exporter scripts
- **No breaking changes**: Defaults preserve existing behaviour (TLS verification on, no custom CA)
