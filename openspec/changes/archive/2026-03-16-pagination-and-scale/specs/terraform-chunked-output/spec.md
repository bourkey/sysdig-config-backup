## ADDED Requirements

### Requirement: Chunked Terraform output files
The system SHALL split the Terraform output for a resource type into numbered files (`<type>-001.tf`, `<type>-002.tf`, etc.) when the resource count for that type exceeds `SYSDIG_TF_CHUNK_SIZE`. When resource count is at or below the threshold, the output SHALL be written to a single `<type>.tf` file as before.

#### Scenario: Resource count within threshold
- **WHEN** the number of resources for a type is less than or equal to `SYSDIG_TF_CHUNK_SIZE`
- **THEN** all resources are written to a single `<type>.tf` file

#### Scenario: Resource count exceeds threshold
- **WHEN** the number of resources for a type exceeds `SYSDIG_TF_CHUNK_SIZE`
- **THEN** resources are distributed into numbered files `<type>-001.tf`, `<type>-002.tf`, etc., each containing at most `SYSDIG_TF_CHUNK_SIZE` resources

### Requirement: Stale chunk file cleanup
Before regenerating Terraform output for a resource type, the system SHALL remove all existing `<type>*.tf` files for that type to prevent stale chunks from previous runs with larger datasets persisting alongside current output.

#### Scenario: Cleanup before regeneration
- **WHEN** Terraform generation runs for the policies resource type
- **THEN** all existing `policies*.tf` files in the output directory are deleted before new files are written

#### Scenario: Reduced dataset on subsequent run
- **WHEN** a previous run produced `policies-001.tf` through `policies-005.tf` and the current run has fewer resources
- **THEN** only the files needed for the current run are written; no stale files from the previous run remain

### Requirement: Configurable chunk size
The system SHALL respect a `SYSDIG_TF_CHUNK_SIZE` environment variable that controls how many resources are written per Terraform output file. The default value SHALL be `200`. Setting `SYSDIG_TF_CHUNK_SIZE=0` SHALL disable chunking entirely, writing all resources to a single file regardless of count.

#### Scenario: Default chunk size used
- **WHEN** `SYSDIG_TF_CHUNK_SIZE` is not set
- **THEN** files are split when resource count exceeds 200

#### Scenario: Chunking disabled
- **WHEN** `SYSDIG_TF_CHUNK_SIZE=0` is set
- **THEN** all resources for a type are written to a single `<type>.tf` file regardless of count
