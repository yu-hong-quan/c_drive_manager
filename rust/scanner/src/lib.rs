//! 通用受控目录扫描：只遍历明确根路径，跳过软链接与无法访问项。

use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

#[derive(Debug, Clone, Serialize)]
pub struct ScannedFile {
    pub path: String,
    pub bytes: u64,
    pub modified_ms: u64,
}

/// 扫描强度与性能相关选项，由设置页透传到引擎。
#[derive(Debug, Clone)]
pub struct ScanOptions {
    pub skip_larger_than_bytes: Option<u64>,
    pub max_files_per_root: Option<usize>,
    pub yield_every: usize,
}

impl Default for ScanOptions {
    fn default() -> Self {
        Self {
            skip_larger_than_bytes: Some(200 * 1024 * 1024),
            max_files_per_root: Some(50_000),
            yield_every: 250,
        }
    }
}

/// 在给定根目录集合内扫描普通文件。
///
/// `account_boundary` 若提供，则要求所有路径都落在该前缀下，防止越界。
pub fn scan_roots(
    roots: &[PathBuf],
    account_boundary: Option<&Path>,
    should_cancel: &dyn Fn() -> bool,
    options: &ScanOptions,
) -> (Vec<ScannedFile>, u64, u32) {
    let mut files = Vec::new();
    let mut bytes = 0u64;
    let mut skipped = 0u32;

    for root in roots {
        if should_cancel() {
            break;
        }
        if !root.exists() {
            continue;
        }
        if let Some(boundary) = account_boundary {
            if !is_under(root, boundary) {
                skipped += 1;
                continue;
            }
        }
        if is_drive_root(root) {
            skipped += 1;
            continue;
        }

        let mut stack = vec![root.clone()];
        let mut root_files = 0usize;
        while let Some(current) = stack.pop() {
            if should_cancel() {
                break;
            }
            if let Some(max) = options.max_files_per_root {
                if root_files >= max {
                    skipped += 1;
                    break;
                }
            }
            let entries = match fs::read_dir(&current) {
                Ok(entries) => entries,
                Err(_) => {
                    skipped += 1;
                    continue;
                }
            };
            for entry in entries.flatten() {
                if should_cancel() {
                    break;
                }
                let path = entry.path();
                let meta = match entry.metadata() {
                    Ok(meta) => meta,
                    Err(_) => {
                        skipped += 1;
                        continue;
                    }
                };
                if meta.file_type().is_symlink() {
                    skipped += 1;
                    continue;
                }
                if meta.is_dir() {
                    stack.push(path);
                    continue;
                }
                if meta.is_file() {
                    let size = meta.len();
                    if let Some(limit) = options.skip_larger_than_bytes {
                        if size > limit {
                            // 超大文件仍计入占用，但不进入可勾选明细，避免 UI/清理过重。
                            bytes += size;
                            skipped += 1;
                            continue;
                        }
                    }
                    root_files += 1;
                    bytes += size;
                    files.push(ScannedFile {
                        path: path.to_string_lossy().replace('/', "\\"),
                        bytes: size,
                        modified_ms: system_time_to_ms(meta.modified().ok()),
                    });
                    if options.yield_every > 0 && root_files % options.yield_every == 0 {
                        std::thread::yield_now();
                    }
                }
            }
        }
    }

    files.sort_by(|a, b| b.bytes.cmp(&a.bytes));
    (files, bytes, skipped)
}

fn is_under(path: &Path, boundary: &Path) -> bool {
    let path = normalize(path);
    let boundary = normalize(boundary);
    path.starts_with(&boundary)
}

fn normalize(path: &Path) -> String {
    path.to_string_lossy().replace('/', "\\").to_lowercase()
}

fn is_drive_root(path: &Path) -> bool {
    let text = normalize(path);
    matches!(text.as_str(), x if x.len() <= 3 && x.ends_with(":\\") || x.ends_with(':'))
}

fn system_time_to_ms(time: Option<SystemTime>) -> u64 {
    time.and_then(|t| t.duration_since(SystemTime::UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

pub fn crate_id() -> &'static str {
    "c_drive_manager_scanner"
}
