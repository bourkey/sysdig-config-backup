## 1. Update lib/common.sh

- [x] 1.1 In `validate_config()`, add a check: if `SYSDIG_CA_CERT` is set and the file does not exist, print an error to stderr and exit 1
- [x] 1.2 In `validate_config()`, add a check: if both `SYSDIG_TLS_INSECURE=true` and `SYSDIG_CA_CERT` are set, print a warning to stderr
- [x] 1.3 In `sysdig_get()`, build a local array of TLS curl flags: append `--insecure` when `SYSDIG_TLS_INSECURE=true`, append `--cacert "${SYSDIG_CA_CERT}"` when `SYSDIG_CA_CERT` is non-empty
- [x] 1.4 In `sysdig_get()`, include the TLS flags array in the `curl` invocation

## 2. Update config.sh.example

- [x] 2.1 Add a commented-out `SYSDIG_TLS_INSECURE` entry with a security warning note
- [x] 2.2 Add a commented-out `SYSDIG_CA_CERT` entry with a usage example (e.g., `/etc/ssl/certs/my-ca.pem`)

## 3. Manual verification

- [x] 3.1 Run `./backup.sh --dry-run` against the SaaS endpoint with no new vars set — confirm behaviour is unchanged
- [x] 3.2 Run `./backup.sh --dry-run` with `SYSDIG_CA_CERT` pointing to a non-existent file — confirm early exit with clear error
- [x] 3.3 Run `./backup.sh --dry-run` with `SYSDIG_TLS_INSECURE=true` and `SYSDIG_CA_CERT` both set — confirm warning is printed to stderr and run proceeds
