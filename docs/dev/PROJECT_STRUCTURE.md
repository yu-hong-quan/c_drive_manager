# Project Structure

```text
c-drive-manager/
├─ apps/desktop_flutter/        # V1 Windows desktop app
├─ apps/mobile_flutter/         # V2 mobile shell placeholder
├─ rust/                        # Cargo workspace
├─ server/rule_server/          # V2 Go service placeholder
├─ shared/                      # Schemas, builtin rules, errors
├─ assets/                      # Design references and transparent UI assets
├─ docs/                        # PRD, architecture, ADR, development notes
├─ installer/                   # Windows packaging and signing scripts
└─ tools/                       # Local generation and validation scripts
```

## First Implementation Slice

1. Restore static Flutter shell from design references.
2. Define shared task/event/error schemas.
3. Implement Rust `protocol` and `core` handshake.
4. Expose `get_system_info` through FFI.
5. Add SQLite-backed task and settings repositories.
