//! 隔离区引擎：移入、索引、恢复、到期清理。
//!
//! 空间不足时返回 QUARANTINE_SPACE_INSUFFICIENT，禁止自动永久删除。

use c_drive_manager_windows_api::{free_bytes_on_drive, list_fixed_drives};
use chrono::{Duration as ChronoDuration, Local, Utc};
use serde::{Deserialize, Serialize};
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QuarantineItem {
    pub id: String,
    pub original_path: String,
    pub quarantine_path: String,
    pub bytes: u64,
    pub fingerprint: String,
    pub source: String,
    pub category: String,
    pub display_name: String,
    pub created_at: String,
    pub expire_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QuarantineCandidate {
    pub path: String,
    pub bytes: u64,
    pub source: String,
    pub category: String,
    pub retention_days: Option<u32>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MoveResult {
    pub moved_bytes: u64,
    pub moved_files: u32,
    pub skipped_files: u32,
    pub failed_files: u32,
    pub items: Vec<QuarantineItem>,
    pub error_code: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ActionResult {
    pub success_count: u32,
    pub failed_count: u32,
    pub bytes: u64,
}

#[derive(Debug, Deserialize)]
struct IndexFile {
    items: Vec<QuarantineItem>,
}

/// 隔离服务：索引保存在 APPDATA，文件本体放在非 C 盘或用户指定目录。
pub struct QuarantineService {
    pub default_retention_days: u32,
    pub configured_root: Option<String>,
}

impl Default for QuarantineService {
    fn default() -> Self {
        Self {
            default_retention_days: 7,
            configured_root: None,
        }
    }
}

impl QuarantineService {
    pub fn resolve_root(&self) -> Result<PathBuf, String> {
        if let Some(root) = self
            .configured_root
            .as_ref()
            .map(|s| s.trim())
            .filter(|s| !s.is_empty())
        {
            let path = PathBuf::from(root);
            fs::create_dir_all(&path).map_err(|e| e.to_string())?;
            return Ok(path);
        }
        if let Some(auto) = prefer_non_system_drive_root() {
            return Ok(auto);
        }
        let fallback = PathBuf::from(format!(
            "{}\\Documents\\CDriveManagerQuarantine",
            std::env::var("USERPROFILE").unwrap_or_else(|_| ".".into())
        ));
        fs::create_dir_all(&fallback).map_err(|e| e.to_string())?;
        Ok(fallback)
    }

    pub fn list_items(&self) -> Result<Vec<QuarantineItem>, String> {
        let mut items = load_index()?;
        items.sort_by(|a, b| b.created_at.cmp(&a.created_at));
        Ok(items)
    }

    pub fn quarantine_files(&self, candidates: &[QuarantineCandidate]) -> Result<MoveResult, String> {
        let list = dedupe(candidates);
        let needed: u64 = list.iter().map(|c| c.bytes).sum();
        let root = self.resolve_root()?;
        if !has_enough_space(&root, needed) {
            return Ok(MoveResult {
                moved_bytes: 0,
                moved_files: 0,
                skipped_files: 0,
                failed_files: 0,
                items: vec![],
                error_code: Some("QUARANTINE_SPACE_INSUFFICIENT".into()),
            });
        }

        let mut index = load_index()?;
        let mut created = Vec::new();
        let mut moved_bytes = 0u64;
        let mut moved_files = 0u32;
        let mut skipped_files = 0u32;
        let mut failed_files = 0u32;

        for candidate in list {
            let source = PathBuf::from(&candidate.path);
            if !source.exists() {
                skipped_files += 1;
                continue;
            }
            match self.move_one(&source, &candidate, &root) {
                Ok(item) => {
                    moved_bytes += item.bytes;
                    moved_files += 1;
                    created.push(item.clone());
                    index.push(item);
                }
                Err(_) => failed_files += 1,
            }
        }
        save_index(&index)?;
        Ok(MoveResult {
            moved_bytes,
            moved_files,
            skipped_files,
            failed_files,
            items: created,
            error_code: None,
        })
    }

    pub fn restore_items(&self, ids: &[String]) -> Result<ActionResult, String> {
        let mut index = load_index()?;
        let mut success = 0u32;
        let mut failed = 0u32;
        let mut bytes = 0u64;
        for id in ids {
            let Some(pos) = index.iter().position(|item| &item.id == id) else {
                failed += 1;
                continue;
            };
            let item = index[pos].clone();
            let quarantined = PathBuf::from(&item.quarantine_path);
            let target = PathBuf::from(&item.original_path);
            if !quarantined.exists() || target.exists() {
                failed += 1;
                continue;
            }
            if let Some(parent) = target.parent() {
                let _ = fs::create_dir_all(parent);
            }
            match fs::copy(&quarantined, &target) {
                Ok(_) => {
                    let _ = fs::remove_file(&quarantined);
                    bytes += item.bytes;
                    success += 1;
                    index.remove(pos);
                }
                Err(_) => failed += 1,
            }
        }
        save_index(&index)?;
        Ok(ActionResult {
            success_count: success,
            failed_count: failed,
            bytes,
        })
    }

    pub fn purge_items(&self, ids: &[String]) -> Result<ActionResult, String> {
        let mut index = load_index()?;
        let mut success = 0u32;
        let mut failed = 0u32;
        let mut bytes = 0u64;
        for id in ids {
            let Some(pos) = index.iter().position(|item| &item.id == id) else {
                failed += 1;
                continue;
            };
            let item = index.remove(pos);
            let path = PathBuf::from(&item.quarantine_path);
            if path.exists() {
                if fs::remove_file(&path).is_err() {
                    failed += 1;
                    index.push(item);
                    continue;
                }
            }
            bytes += item.bytes;
            success += 1;
        }
        save_index(&index)?;
        Ok(ActionResult {
            success_count: success,
            failed_count: failed,
            bytes,
        })
    }

    pub fn purge_expired(&self) -> Result<ActionResult, String> {
        let now = Utc::now();
        let expired: Vec<String> = self
            .list_items()?
            .into_iter()
            .filter(|item| {
                chrono::DateTime::parse_from_rfc3339(&item.expire_at)
                    .map(|dt| dt.with_timezone(&Utc) <= now)
                    .unwrap_or(false)
            })
            .map(|item| item.id)
            .collect();
        self.purge_items(&expired)
    }

    pub fn open_folder(&self) -> Result<String, String> {
        let root = self.resolve_root()?;
        Command::new("explorer")
            .arg(&root)
            .spawn()
            .map_err(|e| e.to_string())?;
        Ok(root.to_string_lossy().to_string())
    }

    fn move_one(
        &self,
        source: &Path,
        candidate: &QuarantineCandidate,
        root: &Path,
    ) -> Result<QuarantineItem, String> {
        let now = SystemTime::now();
        let retention = candidate
            .retention_days
            .unwrap_or(self.default_retention_days)
            .clamp(1, 30);
        let day = format_day(now);
        let day_folder = root.join("items").join(day);
        fs::create_dir_all(&day_folder).map_err(|e| e.to_string())?;

        let id = format!(
            "{}_{:x}",
            now.duration_since(UNIX_EPOCH)
                .map(|d| d.as_micros())
                .unwrap_or(0),
            simple_hash(&candidate.path)
        );
        let safe_name = safe_file_name(
            source
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("file"),
        );
        let target = day_folder.join(format!("{id}_{safe_name}"));
        let same_volume = drive_letter(source) == drive_letter(&target);
        if same_volume {
            fs::rename(source, &target).map_err(|e| e.to_string())?;
        } else {
            fs::copy(source, &target).map_err(|e| e.to_string())?;
            fs::remove_file(source).map_err(|e| e.to_string())?;
        }
        let meta = fs::metadata(&target).map_err(|e| e.to_string())?;
        let bytes = if candidate.bytes > 0 {
            candidate.bytes
        } else {
            meta.len()
        };
        let created_at = Utc::now().to_rfc3339();
        let expire_at = (Utc::now() + ChronoDuration::days(retention as i64)).to_rfc3339();
        Ok(QuarantineItem {
            id,
            original_path: candidate.path.replace('/', "\\"),
            quarantine_path: target.to_string_lossy().replace('/', "\\"),
            bytes,
            fingerprint: format!(
                "{bytes}:{}:{}",
                system_time_to_ms(meta.modified().ok()),
                candidate.path.to_lowercase()
            ),
            source: candidate.source.clone(),
            category: candidate.category.clone(),
            display_name: safe_name,
            created_at,
            expire_at,
        })
    }
}

fn prefer_non_system_drive_root() -> Option<PathBuf> {
    for drive in list_fixed_drives() {
        if drive.to_uppercase().starts_with('C') {
            continue;
        }
        let candidate = PathBuf::from(format!("{drive}\\CDriveManagerQuarantine"));
        if fs::create_dir_all(&candidate).is_err() {
            continue;
        }
        let probe = candidate.join(".write_probe");
        if fs::write(&probe, b"ok").is_ok() {
            let _ = fs::remove_file(&probe);
            return Some(candidate);
        }
    }
    None
}

fn has_enough_space(root: &Path, needed: u64) -> bool {
    let Some(drive) = drive_letter(root) else {
        return true;
    };
    let Some(free) = free_bytes_on_drive(&drive) else {
        return true;
    };
    const BUFFER: u64 = 200 * 1024 * 1024;
    free > needed + BUFFER
}

fn index_path() -> PathBuf {
    let appdata = std::env::var("APPDATA").unwrap_or_else(|_| {
        format!(
            "{}\\AppData\\Roaming",
            std::env::var("USERPROFILE").unwrap_or_else(|_| ".".into())
        )
    });
    PathBuf::from(appdata).join("CDriveManager").join("quarantine_index.json")
}

fn load_index() -> Result<Vec<QuarantineItem>, String> {
    let path = index_path();
    if !path.exists() {
        return Ok(vec![]);
    }
    let mut file = fs::File::open(&path).map_err(|e| e.to_string())?;
    let mut text = String::new();
    file.read_to_string(&mut text).map_err(|e| e.to_string())?;
    let parsed: IndexFile = serde_json::from_str(&text).unwrap_or(IndexFile { items: vec![] });
    Ok(parsed.items)
}

fn save_index(items: &[QuarantineItem]) -> Result<(), String> {
    let path = index_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let payload = serde_json::json!({
        "schemaVersion": 1,
        "updatedAt": chrono_like_now(),
        "items": items,
    });
    let mut file = fs::File::create(&path).map_err(|e| e.to_string())?;
    file.write_all(payload.to_string().as_bytes())
        .map_err(|e| e.to_string())
}

fn dedupe(candidates: &[QuarantineCandidate]) -> Vec<QuarantineCandidate> {
    let mut seen = std::collections::HashSet::new();
    let mut out = Vec::new();
    for item in candidates {
        let key = item.path.replace('/', "\\").to_lowercase();
        if seen.insert(key) {
            out.push(item.clone());
        }
    }
    out
}

fn drive_letter(path: &Path) -> Option<String> {
    let text = path.to_string_lossy();
    let bytes = text.as_bytes();
    if bytes.len() >= 2 && bytes[1] == b':' {
        Some(format!("{}:", (bytes[0] as char).to_ascii_uppercase()))
    } else {
        None
    }
}

fn safe_file_name(name: &str) -> String {
    let sanitized: String = name
        .chars()
        .map(|c| match c {
            '<' | '>' | ':' | '"' | '/' | '\\' | '|' | '?' | '*' => '_',
            other => other,
        })
        .collect();
    if sanitized.is_empty() {
        "file.bin".into()
    } else if sanitized.len() > 120 {
        sanitized.chars().take(120).collect()
    } else {
        sanitized
    }
}

fn format_day(_now: SystemTime) -> String {
    Local::now().format("%Y%m%d").to_string()
}

fn chrono_like_now() -> String {
    Utc::now().to_rfc3339()
}

fn system_time_to_ms(time: Option<SystemTime>) -> u64 {
    time.and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

fn simple_hash(input: &str) -> u64 {
    let mut hash = 0xcbf29ce484222325u64;
    for b in input.bytes() {
        hash ^= b as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

pub fn crate_id() -> &'static str {
    "c_drive_manager_quarantine"
}
