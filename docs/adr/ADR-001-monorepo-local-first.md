# ADR-001: Monorepo and Local-First V1

## Decision

Use a monorepo for Flutter, Rust, shared schemas, installer assets, and the future Go rule service. V1.0 must run without any server dependency.

## Rationale

The product handles sensitive local paths, WeChat files, migration transactions, and quarantine records. Keeping V1 local-first reduces privacy risk and lets the Rust/Flutter protocol evolve together before remote rules are introduced in V2.

## Consequences

- Go rule service remains an optional V2 module.
- Shared schemas become the contract between Flutter, Rust FFI, Helper IPC, and future server APIs.
- CI should validate cross-language schema compatibility before packaging.
