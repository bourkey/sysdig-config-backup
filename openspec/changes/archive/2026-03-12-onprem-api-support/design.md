## Context

All API calls flow through `sysdig_get()` in `lib/common.sh`. Currently, `curl` uses the system trust store with no TLS overrides. On-prem Sysdig deployments routinely present certificates signed by a private CA (or self-signed), causing `curl` to abort with a TLS verification error before any API work begins. `SYSDIG_API_URL` is already configurable; TLS behaviour is the only remaining blocker.

All scripts must remain bash 3.2 compatible (macOS system shell).

## Goals / Non-Goals

**Goals:**
- Allow operators to disable TLS verification via `SYSDIG_TLS_INSECURE=true`
- Allow operators to supply a custom CA bundle via `SYSDIG_CA_CERT=/path/to/ca.pem`
- Fail fast with a clear error if `SYSDIG_CA_CERT` is set but the file does not exist
- Warn if both flags are set simultaneously (redundant combination)
- Zero behaviour change when neither variable is set

**Non-Goals:**
- Client certificate (mTLS) authentication — not required by on-prem Sysdig
- Per-request TLS overrides — all requests share the same TLS policy
- Modifying individual exporter scripts — they inherit behaviour via `sysdig_get()`

## Decisions

### 1. Build TLS flags inside `sysdig_get()`, not at config load time

**Decision:** Evaluate `SYSDIG_TLS_INSECURE` and `SYSDIG_CA_CERT` on each call to `sysdig_get()` rather than constructing a shared variable at startup.

**Rationale:** Bash arrays cannot be exported across subprocess boundaries (bash 3.2 limitation). Exporters run as subprocesses via `bash exporter.sh`; any array built in the parent would not be visible. Evaluating the env vars directly inside `sysdig_get()` works reliably across all subprocess invocations.

**Alternative considered:** A single `CURL_TLS_OPTS` string variable. Rejected — string splitting of paths with spaces is error-prone and hard to test.

### 2. `SYSDIG_TLS_INSECURE` is a boolean string, checked as `== "true"`

**Decision:** Only the exact string `true` activates insecure mode.

**Rationale:** Avoids surprises from empty string, `1`, `yes`, or unset variable. Consistent with how `DRY_RUN` and `RUN_TERRAFORM` are handled in `backup.sh`.

### 3. Validate `SYSDIG_CA_CERT` path in `validate_config()`, not lazily

**Decision:** If `SYSDIG_CA_CERT` is set and the file does not exist, exit with a clear error during startup — before any exports run.

**Rationale:** A missing CA cert would cause every `curl` call to fail with a cryptic error. Early validation gives the operator a single actionable message.

### 4. Warn (do not error) when both `SYSDIG_TLS_INSECURE=true` and `SYSDIG_CA_CERT` are set

**Decision:** Print a warning to stderr and proceed; `--insecure` takes precedence and `--cacert` becomes a no-op.

**Rationale:** The combination is redundant but not harmful. Erroring would block operators who set both out of caution.

## Risks / Trade-offs

- **Security:** `SYSDIG_TLS_INSECURE=true` disables all certificate validation — susceptible to MITM if used outside a trusted network. Mitigation: document the risk clearly in `config.sh.example`; prefer `SYSDIG_CA_CERT` where possible.
- **Path with spaces in `SYSDIG_CA_CERT`:** Standard quoting in `curl --cacert "${SYSDIG_CA_CERT}"` handles this correctly.
- **No validation that the CA cert is actually valid PEM:** `curl` will emit its own error. Acceptable — we can't easily validate cert format in bash 3.2 without additional dependencies.

## Migration Plan

1. Update `lib/common.sh` — add TLS logic to `sysdig_get()` and path check to `validate_config()`
2. Update `config.sh.example` — document both new variables with usage notes
3. No rollback needed — both variables default to unset, preserving existing behaviour
4. No changes to exporters, `backup.sh`, or `generate-terraform.sh`
