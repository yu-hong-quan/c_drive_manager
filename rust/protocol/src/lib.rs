//! Shared protocol types for FFI and Helper IPC.
//!
//! Keep this crate free of Flutter, Win32, and persistence dependencies so every
//! process boundary can agree on task IDs, event ordering, and stable errors.

/// Current schema version used by task events exchanged across process boundaries.
pub const TASK_EVENT_SCHEMA_VERSION: u32 = 1;
