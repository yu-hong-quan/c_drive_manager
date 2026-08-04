//! 微信专清领域逻辑：账号发现、分类扫描、运行检测、隔离优先清理。

use c_drive_manager_quarantine::{QuarantineCandidate, QuarantineService};
use c_drive_manager_scanner::{scan_roots, ScanOptions, ScannedFile};
use c_drive_manager_windows_api::is_wechat_running;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WechatAccount {
    pub id: String,
    pub display_name: String,
    pub root_path: String,
    pub layout: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WechatCategoryRule {
    pub id: String,
    pub title: String,
    pub subtitle: String,
    pub risk: String,
    pub default_selected: bool,
    pub recoverable: bool,
    pub retention_days: u32,
    pub allow_clean: bool,
    pub relative_roots: Vec<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WechatCategoryResult {
    pub rule: WechatCategoryRule,
    pub account_id: String,
    pub bytes: u64,
    pub file_count: u32,
    pub files: Vec<ScannedFile>,
    pub skipped: u32,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CleanRequest {
    pub account_id: String,
    pub quarantine_days: u32,
    pub quarantine_path: Option<String>,
    pub selected: Vec<CleanSelection>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CleanSelection {
    pub rule_id: String,
    pub path: String,
    pub bytes: u64,
    pub recoverable: bool,
    pub retention_days: u32,
    pub allow_clean: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WechatCleanResult {
    pub quarantined_bytes: u64,
    pub quarantined_files: u32,
    pub deleted_bytes: u64,
    pub deleted_files: u32,
    pub skipped_files: u32,
    pub failed_files: u32,
    pub error_code: Option<String>,
}

pub fn discover_accounts() -> Vec<WechatAccount> {
    let mut accounts = Vec::new();
    for root in candidate_roots() {
        let Ok(entries) = fs::read_dir(&root) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }
            let Some(layout) = detect_layout(&path) else {
                continue;
            };
            let name = path
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("account");
            accounts.push(WechatAccount {
                id: format!("{layout}_{}", name.to_lowercase()),
                display_name: mask_account_name(name),
                root_path: path.to_string_lossy().replace('/', "\\"),
                layout,
            });
        }
    }
    accounts.sort_by(|a, b| a.display_name.cmp(&b.display_name));
    accounts
}

pub fn validate_custom_root(path: &str) -> Option<WechatAccount> {
    let dir = PathBuf::from(path.trim());
    if !dir.is_dir() {
        return None;
    }
    let layout = detect_layout(&dir)?;
    let name = dir
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("custom");
    Some(WechatAccount {
        id: format!("custom_{}", name.to_lowercase()),
        display_name: mask_account_name(name),
        root_path: dir.to_string_lossy().replace('/', "\\"),
        layout,
    })
}

pub fn scan_account(account: &WechatAccount) -> Vec<WechatCategoryResult> {
    let rules = build_rules(&account.layout);
    let boundary = PathBuf::from(&account.root_path);
    let mut results = Vec::new();
    for rule in rules {
        let roots: Vec<PathBuf> = rule
            .relative_roots
            .iter()
            .map(|rel| boundary.join(rel))
            .collect();
        let (files, _scanned_bytes, skipped) =
            scan_roots(&roots, Some(&boundary), &|| false, &ScanOptions::default());
        let mut files = files;
        if rule.id == "chat_database" {
            files.retain(|file| {
                let lower = file.path.to_lowercase();
                lower.ends_with(".db")
                    || lower.ends_with(".db-wal")
                    || lower.ends_with(".db-shm")
                    || lower.ends_with(".db-journal")
            });
        }
        let file_count = files.len() as u32;
        let bytes = files.iter().map(|f| f.bytes).sum();
        results.push(WechatCategoryResult {
            rule,
            account_id: account.id.clone(),
            bytes,
            file_count,
            files,
            skipped,
        });
    }
    results
}

pub fn clean_selected(request: CleanRequest) -> WechatCleanResult {
    if is_wechat_running() {
        return WechatCleanResult {
            quarantined_bytes: 0,
            quarantined_files: 0,
            deleted_bytes: 0,
            deleted_files: 0,
            skipped_files: 0,
            failed_files: 0,
            error_code: Some("WX_RUNNING".into()),
        };
    }

    let mut to_quarantine = Vec::new();
    let mut to_delete = Vec::new();
    for item in request.selected {
        if !item.allow_clean {
            continue;
        }
        if item.recoverable {
            to_quarantine.push(QuarantineCandidate {
                path: item.path,
                bytes: item.bytes,
                source: "wechat".into(),
                category: item.rule_id,
                retention_days: Some(item.retention_days),
            });
        } else {
            to_delete.push((item.path, item.bytes));
        }
    }

    let quarantine = QuarantineService {
        default_retention_days: request.quarantine_days,
        configured_root: request.quarantine_path.filter(|s| !s.trim().is_empty()),
    };

    let mut quarantined_bytes = 0u64;
    let mut quarantined_files = 0u32;
    let mut deleted_bytes = 0u64;
    let mut deleted_files = 0u32;
    let mut skipped_files = 0u32;
    let mut failed_files = 0u32;
    let mut error_code = None;

    if !to_quarantine.is_empty() {
        match quarantine.quarantine_files(&to_quarantine) {
            Ok(result) => {
                if result.error_code.as_deref() == Some("QUARANTINE_SPACE_INSUFFICIENT") {
                    return WechatCleanResult {
                        quarantined_bytes: 0,
                        quarantined_files: 0,
                        deleted_bytes: 0,
                        deleted_files: 0,
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
        match fs::remove_file(&path) {
            Ok(_) => {
                deleted_bytes += bytes;
                deleted_files += 1;
            }
            Err(_) => failed_files += 1,
        }
    }

    WechatCleanResult {
        quarantined_bytes,
        quarantined_files,
        deleted_bytes,
        deleted_files,
        skipped_files,
        failed_files,
        error_code,
    }
}

pub fn wechat_running() -> bool {
    is_wechat_running()
}

/// 从内置规则包按微信目录布局生成分类规则。
fn build_rules(layout: &str) -> Vec<WechatCategoryRule> {
    c_drive_manager_rules::wechat_rules_for_layout(layout)
        .iter()
        .map(|spec| WechatCategoryRule {
            id: spec.id.clone(),
            title: spec.title.clone(),
            subtitle: spec.subtitle.clone(),
            risk: spec.risk.clone(),
            default_selected: spec.default_selected,
            recoverable: spec.recoverable,
            retention_days: spec.retention_days,
            allow_clean: spec.allow_clean,
            relative_roots: spec.relative_roots.clone(),
        })
        .collect()
}

fn candidate_roots() -> Vec<PathBuf> {
    let mut roots = Vec::new();
    if let Ok(profile) = std::env::var("USERPROFILE") {
        roots.push(PathBuf::from(format!("{profile}\\Documents\\WeChat Files")));
        roots.push(PathBuf::from(format!("{profile}\\Documents\\xwechat_files")));
    }
    if let Ok(appdata) = std::env::var("APPDATA") {
        roots.push(PathBuf::from(format!(
            "{appdata}\\Tencent\\WeChat\\All Users"
        )));
    }
    roots
}

fn detect_layout(account_dir: &Path) -> Option<String> {
    if account_dir.join("FileStorage").is_dir() || account_dir.join("Msg").is_dir() {
        return Some("classic".into());
    }
    if account_dir.join("db_storage").is_dir()
        || account_dir.join("msg").is_dir()
        || account_dir.join("cache").is_dir()
    {
        return Some("xwechat".into());
    }
    None
}

fn mask_account_name(raw: &str) -> String {
    let chars: Vec<char> = raw.chars().collect();
    if chars.len() <= 4 {
        return format!("账号 {raw}");
    }
    let head: String = chars.iter().take(2).collect();
    let tail: String = chars.iter().rev().take(2).collect::<Vec<_>>().into_iter().rev().collect();
    format!("账号 {head}***{tail}")
}

pub fn crate_id() -> &'static str {
    "c_drive_manager_wechat"
}
