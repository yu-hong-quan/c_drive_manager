# ADR-002: On-Demand Elevated Helper Boundary

## Decision

Use a Rust Helper executable only for operations that require administrator rights. The helper is started on demand through UAC and exits after the requested task completes, is cancelled, or times out.

## Rationale

A permanent service would enlarge the privileged attack surface. C 盘管家 only needs elevation for a subset of cleanup, migration, link creation, and rollback tasks.

## Consequences

- Flutter and Rust Core run with normal user privileges by default.
- Helper IPC must use structured commands, authentication, path revalidation, and stable error codes.
- The helper must reject arbitrary shell commands and unknown schema versions.
