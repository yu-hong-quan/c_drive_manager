# Error Codes

Error codes are stable user-facing contracts. Native system messages should be logged in sanitized local diagnostics, then mapped to these codes before reaching Flutter.

| Code | Meaning |
| --- | --- |
| `PATH_OUT_OF_BOUNDARY` | Candidate path escaped an allowed cleanup or migration boundary. |
| `FILE_LOCKED` | File is currently locked and was skipped. |
| `ELEVATION_REQUIRED` | Operation requires the Rust Helper with UAC approval. |
| `QUARANTINE_SPACE_INSUFFICIENT` | The selected quarantine volume cannot safely hold recoverable files. |
| `MIGRATION_TARGET_INVALID` | Target volume is not a fixed local NTFS volume or is unhealthy. |
