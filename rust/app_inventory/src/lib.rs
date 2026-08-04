//! 已安装应用与目标卷盘点：通过本机 PowerShell 读取注册表/磁盘信息。

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashSet;
use std::process::Command;

const SCAN_APPS_SCRIPT: &str = include_str!("../scripts/scan_apps.ps1");
const SCAN_VOLUMES_SCRIPT: &str = include_str!("../scripts/scan_volumes.ps1");

/// 可迁移应用条目（字段与 Flutter / 计划 JSON 对齐）。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MigratableApp {
    pub id: String,
    pub name: String,
    pub version: String,
    pub publisher: String,
    pub bitness: String,
    pub install_path: String,
    pub executable_path: String,
    pub size_bytes: u64,
    pub running: bool,
    pub compatibility: String,
    pub reasons: Vec<String>,
}

/// 可作为迁移目标的本地固定卷。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MigrationTargetVolume {
    pub drive: String,
    pub file_system: String,
    pub total_bytes: u64,
    pub free_bytes: u64,
}

/// 扫描 C 盘可迁移 Win32 应用；按安装路径去重后按体积降序。
pub fn scan_apps() -> Result<Vec<MigratableApp>, String> {
    let payload = run_powershell(SCAN_APPS_SCRIPT)?;
    let apps = payload
        .get("apps")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();

    let mut seen = HashSet::new();
    let mut result = Vec::new();
    for item in apps {
        let Some(app) = parse_app(&item) else {
            continue;
        };
        let key = format!(
            "{}\u{0000}{}",
            app.name.to_lowercase(),
            app.install_path.to_lowercase()
        );
        if seen.insert(key) {
            result.push(app);
        }
    }
    result.sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes));
    Ok(result)
}

/// 扫描本机固定磁盘卷，供迁移目标选择。
pub fn scan_target_volumes() -> Result<Vec<MigrationTargetVolume>, String> {
    let payload = run_powershell(SCAN_VOLUMES_SCRIPT)?;
    let volumes = payload
        .get("volumes")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    Ok(volumes.iter().filter_map(parse_volume).collect())
}

fn parse_app(value: &Value) -> Option<MigratableApp> {
    let name = value.get("name")?.as_str()?.trim().to_string();
    let install_path = value.get("installPath")?.as_str()?.trim().to_string();
    if name.is_empty() || install_path.is_empty() {
        return None;
    }
    let reasons = value
        .get("reasons")
        .and_then(|v| v.as_array())
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.as_str().map(|s| s.to_string()))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    Some(MigratableApp {
        id: value
            .get("id")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string(),
        name,
        version: value
            .get("version")
            .and_then(|v| v.as_str())
            .unwrap_or("未知")
            .to_string(),
        publisher: value
            .get("publisher")
            .and_then(|v| v.as_str())
            .unwrap_or("未知发布者")
            .to_string(),
        bitness: value
            .get("bitness")
            .and_then(|v| v.as_str())
            .unwrap_or("未知")
            .to_string(),
        install_path,
        executable_path: value
            .get("executablePath")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string(),
        size_bytes: value
            .get("sizeBytes")
            .and_then(|v| v.as_u64())
            .or_else(|| {
                value
                    .get("sizeBytes")
                    .and_then(|v| v.as_i64())
                    .map(|n| n.max(0) as u64)
            })
            .unwrap_or(0),
        running: value.get("running").and_then(|v| v.as_bool()).unwrap_or(false),
        compatibility: value
            .get("compatibility")
            .and_then(|v| v.as_str())
            .unwrap_or("unsupported")
            .to_string(),
        reasons: if reasons.is_empty() {
            vec!["未命中明确风险".into()]
        } else {
            reasons
        },
    })
}

fn parse_volume(value: &Value) -> Option<MigrationTargetVolume> {
    let drive = value.get("drive")?.as_str()?.trim().to_string();
    if drive.is_empty() {
        return None;
    }
    Some(MigrationTargetVolume {
        drive,
        file_system: value
            .get("fileSystem")
            .and_then(|v| v.as_str())
            .unwrap_or("未知")
            .to_string(),
        total_bytes: value
            .get("totalBytes")
            .and_then(|v| v.as_u64())
            .or_else(|| {
                value
                    .get("totalBytes")
                    .and_then(|v| v.as_i64())
                    .map(|n| n.max(0) as u64)
            })
            .unwrap_or(0),
        free_bytes: value
            .get("freeBytes")
            .and_then(|v| v.as_u64())
            .or_else(|| {
                value
                    .get("freeBytes")
                    .and_then(|v| v.as_i64())
                    .map(|n| n.max(0) as u64)
            })
            .unwrap_or(0),
    })
}

fn run_powershell(script: &str) -> Result<Value, String> {
    let output = Command::new("powershell")
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script])
        .output()
        .map_err(|err| format!("启动 PowerShell 失败: {err}"))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("应用盘点扫描失败: {stderr}"));
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    serde_json::from_str(stdout.trim()).map_err(|err| format!("解析扫描结果失败: {err}"))
}

/// 供烟雾测试使用。
pub fn crate_id() -> &'static str {
    "c_drive_manager_app_inventory"
}
