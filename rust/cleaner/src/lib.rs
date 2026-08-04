//! 安全清理引擎：扫描明确根目录；可恢复项优先移入隔离区，不可恢复项直接删除。

use c_drive_manager_quarantine::{QuarantineCandidate, QuarantineService};
use c_drive_manager_scanner::{scan_roots, ScanOptions, ScannedFile};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CleanupRule {
    pub id: String,
    pub title: String,
    pub subtitle: String,
    pub source: String,
    pub risk: String,
    pub default_selected: bool,
    pub recoverable: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CleanupCategoryResult {
    pub rule: CleanupRule,
    pub bytes: u64,
    pub file_count: u32,
    pub files: Vec<ScannedFile>,
    pub skipped: u32,
}

#[derive(Debug, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct CleanupScanRequest {
    #[serde(default)]
    pub scan_mode: Option<String>,
    #[serde(default)]
    pub skip_large_files: Option<bool>,
    #[serde(default)]
    pub game_mode: Option<bool>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CleanupCleanRequest {
    pub items: Vec<CleanupItem>,
    #[serde(default)]
    pub quarantine_days: Option<u32>,
    #[serde(default)]
    pub quarantine_path: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CleanupItem {
    pub path: String,
    pub bytes: u64,
    pub category: String,
    pub recoverable: bool,
    #[serde(default)]
    pub retention_days: Option<u32>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CleanupExecutionResult {
    pub deleted_bytes: u64,
    pub deleted_files: u32,
    pub quarantined_bytes: u64,
    pub quarantined_files: u32,
    pub skipped_files: u32,
    pub failed_files: u32,
    pub error_code: Option<String>,
}

struct RuleDef {
    rule: CleanupRule,
    roots: Vec<PathBuf>,
}

pub fn scan_cleanup(request: &CleanupScanRequest) -> Vec<CleanupCategoryResult> {
    let options = scan_options_from(request);
    build_rules()
        .into_iter()
        .map(|def| {
            let (files, bytes, skipped) = scan_roots(&def.roots, None, &|| false, &options);
            CleanupCategoryResult {
                rule: def.rule,
                bytes,
                file_count: files.len() as u32,
                files,
                skipped,
            }
        })
        .collect()
}

/// 执行清理：可恢复项进隔离；不可恢复项直接删除。
pub fn clean_files(request: CleanupCleanRequest) -> CleanupExecutionResult {
    let mut to_quarantine = Vec::new();
    let mut to_delete = Vec::new();
    let mut seen = std::collections::HashSet::new();

    for item in request.items {
        let key = item.path.replace('/', "\\").to_lowercase();
        if !seen.insert(key) {
            continue;
        }
        if item.recoverable {
            to_quarantine.push(QuarantineCandidate {
                path: item.path,
                bytes: item.bytes,
                source: "cleanup".into(),
                category: item.category,
                retention_days: item.retention_days.or(Some(7)),
            });
        } else {
            to_delete.push((item.path, item.bytes));
        }
    }

    let mut deleted_bytes = 0u64;
    let mut deleted_files = 0u32;
    let mut quarantined_bytes = 0u64;
    let mut quarantined_files = 0u32;
    let mut skipped_files = 0u32;
    let mut failed_files = 0u32;
    let mut error_code = None;

    if !to_quarantine.is_empty() {
        let service = QuarantineService {
            default_retention_days: request.quarantine_days.unwrap_or(7),
            configured_root: request.quarantine_path.filter(|s| !s.trim().is_empty()),
        };
        match service.quarantine_files(&to_quarantine) {
            Ok(result) => {
                if result.error_code.as_deref() == Some("QUARANTINE_SPACE_INSUFFICIENT") {
                    return CleanupExecutionResult {
                        deleted_bytes: 0,
                        deleted_files: 0,
                        quarantined_bytes: 0,
                        quarantined_files: 0,
                        skipped_files: (to_quarantine.len() + to_delete.len()) as u32,
                        failed_files: 0,
                        error_code: Some("QUARANTINE_SPACE_INSUFFICIENT".into()),
                    };
                }
                quarantined_bytes = result.moved_bytes;
                quarantined_files = result.moved_files;
                skipped_files += result.skipped_files;
                failed_files += result.failed_files;
                error_code = result.error_code;
            }
            Err(_) => failed_files += to_quarantine.len() as u32,
        }
    }

    for (path, bytes) in to_delete {
        let file = PathBuf::from(&path);
        if !file.exists() {
            skipped_files += 1;
            continue;
        }
        match fs::remove_file(&file) {
            Ok(_) => {
                deleted_bytes += bytes;
                deleted_files += 1;
            }
            Err(_) => failed_files += 1,
        }
    }

    CleanupExecutionResult {
        deleted_bytes,
        deleted_files,
        quarantined_bytes,
        quarantined_files,
        skipped_files,
        failed_files,
        error_code,
    }
}

fn scan_options_from(request: &CleanupScanRequest) -> ScanOptions {
    let mode = request.scan_mode.as_deref().unwrap_or("balanced");
    let skip_large = request.skip_large_files.unwrap_or(true);
    let game_mode = request.game_mode.unwrap_or(false);
    match mode {
        "light" => ScanOptions {
            // 轻量模式：跳过超大文件详情，限制单根枚举规模。
            skip_larger_than_bytes: if skip_large {
                Some(32 * 1024 * 1024)
            } else {
                None
            },
            max_files_per_root: Some(8_000),
            yield_every: if game_mode { 800 } else { 200 },
        },
        "deep" => ScanOptions {
            skip_larger_than_bytes: None,
            max_files_per_root: None,
            yield_every: if game_mode { 1200 } else { 400 },
        },
        _ => ScanOptions {
            skip_larger_than_bytes: if skip_large {
                Some(200 * 1024 * 1024)
            } else {
                None
            },
            max_files_per_root: Some(50_000),
            yield_every: if game_mode { 1000 } else { 250 },
        },
    }
}

/// 从内置规则包构建扫描定义，避免在代码里硬编码分类路径。
fn build_rules() -> Vec<RuleDef> {
    c_drive_manager_rules::builtin_cleanup_rules()
        .rules
        .iter()
        .map(|spec| RuleDef {
            rule: CleanupRule {
                id: spec.id.clone(),
                title: spec.title.clone(),
                subtitle: spec.subtitle.clone(),
                source: spec.source.clone(),
                risk: spec.risk.clone(),
                default_selected: spec.default_selected,
                recoverable: spec.recoverable,
            },
            roots: c_drive_manager_rules::resolve_cleanup_roots(&spec.roots),
        })
        .collect()
}

pub fn crate_id() -> &'static str {
    "c_drive_manager_cleaner"
}
