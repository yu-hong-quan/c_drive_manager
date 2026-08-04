//! 应用迁移事务：生成计划、复制校验、源目录改名与目录联接。

use c_drive_manager_app_inventory::{MigratableApp, MigrationTargetVolume};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

/// 创建迁移计划的请求体。
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreatePlanRequest {
    pub apps: Vec<MigratableApp>,
    pub target: MigrationTargetVolume,
}

/// 执行单个应用迁移的请求体。
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExecuteAppRequest {
    pub plan_id: String,
    pub app: MigratableApp,
    pub target_drive: String,
    pub target_root_path: Option<String>,
    /// 可选：指向 c_manager_helper.exe，用于普通 mklink 失败后创建联接。
    pub helper_path: Option<String>,
}

/// 计划创建结果。
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CreatePlanResult {
    pub plan: MigrationPlan,
    pub blockers: Vec<String>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MigrationPlan {
    pub id: String,
    pub target_drive: String,
    pub apps: Vec<MigratableApp>,
    pub total_bytes: u64,
    pub created_at: String,
    pub transaction_path: String,
}

/// 单应用执行结果。
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ExecuteAppResult {
    pub app_name: String,
    pub success: bool,
    pub message: String,
    pub backup_path: Option<String>,
    pub target_path: Option<String>,
}

/// 校验并写入迁移事务计划 JSON。
pub fn create_plan(request: CreatePlanRequest) -> Result<CreatePlanResult, String> {
    let mut blockers = Vec::new();
    let mut warnings = Vec::new();
    let total_bytes = request.apps.iter().map(|app| app.size_bytes).sum::<u64>();

    if request.apps.is_empty() {
        blockers.push("请选择至少一个可迁移应用".into());
    }
    if !is_usable_target(&request.target) {
        blockers.push("目标盘必须是非 C 盘的本地固定 NTFS 卷".into());
    }
    if request.target.free_bytes <= ((total_bytes as f64) * 1.15) as u64 {
        blockers.push("目标盘剩余空间不足，需预留至少 15% 校验空间".into());
    }
    if request.apps.iter().any(|app| app.running) {
        warnings.push("存在运行中的应用，执行迁移前需要先正常退出".into());
    }
    if request
        .apps
        .iter()
        .any(|app| app.compatibility == "caution")
    {
        warnings.push("包含“需谨慎”应用，执行前应展开查看风险说明".into());
    }

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|err| err.to_string())?;
    let id = format!("move-{}", now.as_millis());
    let created_at = chrono_like_iso(now.as_millis());
    let transaction_path = transaction_file_path(&id)?;

    let plan = MigrationPlan {
        id: id.clone(),
        target_drive: request.target.drive.clone(),
        apps: request.apps.clone(),
        total_bytes,
        created_at: created_at.clone(),
        transaction_path: transaction_path.clone(),
    };

    let payload = json!({
        "id": id,
        "status": if blockers.is_empty() { "planned" } else { "blocked" },
        "createdAt": created_at,
        "targetDrive": request.target.drive,
        "totalBytes": total_bytes,
        "blockers": blockers,
        "warnings": warnings,
        "apps": request.apps,
        "recipe": [
            "validate-target-volume",
            "request-app-exit",
            "copy-to-target-temp",
            "verify-file-count-size-hash",
            "rename-source-to-backup",
            "create-directory-junction",
            "verify-original-path",
            "mark-backup-for-delayed-cleanup",
        ],
    });

    if let Some(parent) = Path::new(&transaction_path).parent() {
        fs::create_dir_all(parent).map_err(|err| format!("创建事务目录失败: {err}"))?;
    }
    fs::write(
        &transaction_path,
        serde_json::to_string_pretty(&payload).map_err(|err| err.to_string())?,
    )
    .map_err(|err| format!("写入迁移计划失败: {err}"))?;

    Ok(CreatePlanResult {
        plan,
        blockers,
        warnings,
    })
}

/// 执行单个应用迁移（复制→校验→备份改名→联接）。
pub fn execute_app(request: ExecuteAppRequest) -> ExecuteAppResult {
    match execute_app_inner(&request) {
        Ok((backup, target, message)) => ExecuteAppResult {
            app_name: request.app.name,
            success: true,
            message,
            backup_path: Some(backup),
            target_path: Some(target),
        },
        Err(message) => ExecuteAppResult {
            app_name: request.app.name,
            success: false,
            message,
            backup_path: None,
            target_path: None,
        },
    }
}

/// 将执行摘要追加到事务 JSON。
pub fn append_execution_log(
    transaction_path: &str,
    migrated: &[String],
    failed: &[String],
    messages: &[String],
) -> Result<(), String> {
    let raw = fs::read_to_string(transaction_path)
        .map_err(|err| format!("读取事务文件失败: {err}"))?;
    let mut data: Value =
        serde_json::from_str(&raw).map_err(|err| format!("解析事务文件失败: {err}"))?;
    let status = if failed.is_empty() {
        "migrated"
    } else if migrated.is_empty() {
        "failed"
    } else {
        "partial"
    };
    data["status"] = json!(status);
    data["executedAt"] = json!(chrono_like_iso(
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0)
    ));
    data["migrated"] = json!(migrated);
    data["failed"] = json!(failed);
    data["messages"] = json!(messages);
    fs::write(
        transaction_path,
        serde_json::to_string_pretty(&data).map_err(|err| err.to_string())?,
    )
    .map_err(|err| format!("写入执行日志失败: {err}"))
}

fn execute_app_inner(request: &ExecuteAppRequest) -> Result<(String, String, String), String> {
    let app = &request.app;
    let source = PathBuf::from(&app.install_path);
    if !source.is_dir() {
        return Err(format!("原安装目录不存在：{}", app.install_path));
    }
    if is_app_running(&app.install_path)? {
        return Err(format!("应用仍在运行，请退出后再迁移：{}", app.name));
    }

    let target_root = normalize_target_root(request.target_root_path.as_deref(), &request.target_drive)?;
    let folder_name = source_folder_name(&app.install_path, &app.name);
    let target_dir = PathBuf::from(format!("{target_root}\\{folder_name}"));
    let temp_dir = PathBuf::from(format!(
        "{}.copying-{}",
        target_dir.to_string_lossy(),
        request.plan_id
    ));
    let backup_dir = PathBuf::from(format!(
        "{}.cdm-backup-{}",
        app.install_path, request.plan_id
    ));

    if target_dir.exists() {
        return Err(format!("目标目录已存在：{}", target_dir.display()));
    }
    if backup_dir.exists() {
        return Err(format!("备份目录已存在：{}", backup_dir.display()));
    }
    fs::create_dir_all(&target_root).map_err(|err| format!("创建目标根目录失败: {err}"))?;
    if temp_dir.exists() {
        fs::remove_dir_all(&temp_dir).map_err(|err| format!("清理临时目录失败: {err}"))?;
    }

    let copy_code = robocopy(&source, &temp_dir)?;
    if copy_code > 7 {
        let _ = fs::remove_dir_all(&temp_dir);
        return Err(format!("复制失败，Robocopy 退出码：{copy_code}"));
    }

    let source_stats = directory_stats(&source)?;
    let target_stats = directory_stats(&temp_dir)?;
    if source_stats.0 != target_stats.0 || source_stats.1 != target_stats.1 {
        let _ = fs::remove_dir_all(&temp_dir);
        return Err(format!(
            "复制校验失败：源 {} 个文件 / {} 字节，目标 {} 个文件 / {} 字节",
            source_stats.0, source_stats.1, target_stats.0, target_stats.1
        ));
    }

    fs::rename(&source, &backup_dir).map_err(|err| format!("创建备份失败: {err}"))?;
    let mut target_promoted = false;
    let result = (|| {
        fs::rename(&temp_dir, &target_dir).map_err(|err| format!("提升目标目录失败: {err}"))?;
        target_promoted = true;
        create_junction(
            &app.install_path,
            &target_dir.to_string_lossy(),
            request.helper_path.as_deref(),
        )?;
        if !Path::new(&app.install_path).exists() {
            return Err(format!("目录联接创建失败：{}", app.name));
        }
        Ok(())
    })();

    if let Err(err) = result {
        rollback_app(
            &app.install_path,
            &backup_dir,
            &target_dir,
            target_promoted,
        );
        return Err(err);
    }

    Ok((
        backup_dir.to_string_lossy().to_string(),
        target_dir.to_string_lossy().to_string(),
        format!("{} 已迁移，备份保留在 {}", app.name, backup_dir.display()),
    ))
}

fn is_usable_target(target: &MigrationTargetVolume) -> bool {
    target.drive.to_uppercase() != "C:" && target.file_system.eq_ignore_ascii_case("NTFS")
}

fn transaction_file_path(id: &str) -> Result<String, String> {
    let appdata = std::env::var("APPDATA").or_else(|_| {
        std::env::var("USERPROFILE").map(|p| format!("{p}\\AppData\\Roaming"))
    })
    .map_err(|_| "无法解析 APPDATA".to_string())?;
    Ok(format!(
        "{appdata}\\CDriveManager\\migration_transactions\\{id}.json"
    ))
}

fn normalize_target_root(value: Option<&str>, target_drive: &str) -> Result<String, String> {
    let drive = if target_drive.ends_with(':') {
        target_drive.to_string()
    } else {
        format!("{target_drive}:")
    };
    let raw = match value {
        Some(v) if !v.trim().is_empty() => v.trim().replace('/', "\\"),
        _ => format!("{drive}\\CDriveManager\\MigratedApps"),
    };
    let normalized = if raw.contains(':') {
        raw
    } else {
        join_windows_path(&drive, &raw)
    };
    if !normalized.to_lowercase().starts_with(&drive.to_lowercase()) {
        return Err(format!("目标文件夹必须位于 {drive} 盘内：{normalized}"));
    }
    Ok(normalized)
}

fn source_folder_name(install_path: &str, fallback: &str) -> String {
    let normalized = install_path
        .replace('/', "\\")
        .trim_end_matches('\\')
        .to_string();
    let folder = normalized
        .rsplit('\\')
        .next()
        .filter(|s| !s.is_empty())
        .unwrap_or(fallback);
    safe_file_name(folder)
}

fn safe_file_name(value: &str) -> String {
    let sanitized: String = value
        .chars()
        .map(|ch| match ch {
            '<' | '>' | ':' | '"' | '/' | '\\' | '|' | '?' | '*' => '_',
            c if c.is_control() => '_',
            c => c,
        })
        .collect();
    let trimmed = sanitized.trim();
    if trimmed.is_empty() {
        "app".into()
    } else {
        trimmed.to_string()
    }
}

fn join_windows_path(root: &str, child: &str) -> String {
    let root = root.trim().replace('/', "\\");
    let child = child.trim().replace('/', "\\");
    if root.ends_with('\\') {
        format!("{root}{child}")
    } else {
        format!("{root}\\{child}")
    }
}

fn is_app_running(install_path: &str) -> Result<bool, String> {
    let escaped = install_path.to_lowercase().replace('\'', "''");
    let script = format!(
        "$path = '{escaped}'; $count = @(Get-CimInstance Win32_Process | Where-Object {{ $_.ExecutablePath -and $_.ExecutablePath.ToLowerInvariant().StartsWith($path) }}).Count; Write-Output $count"
    );
    let output = Command::new("powershell")
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", &script])
        .output()
        .map_err(|err| format!("检测运行状态失败: {err}"))?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    Ok(stdout.trim().parse::<u32>().unwrap_or(0) > 0)
}

fn robocopy(source: &Path, target: &Path) -> Result<i32, String> {
    let status = Command::new("robocopy")
        .args([
            source.to_string_lossy().as_ref(),
            target.to_string_lossy().as_ref(),
            "/E",
            "/COPY:DAT",
            "/DCOPY:DAT",
            "/R:1",
            "/W:1",
            "/XJ",
            "/NFL",
            "/NDL",
            "/NP",
        ])
        .status()
        .map_err(|err| format!("启动 Robocopy 失败: {err}"))?;
    Ok(status.code().unwrap_or(16))
}

fn directory_stats(path: &Path) -> Result<(u64, u64), String> {
    let mut files = 0u64;
    let mut bytes = 0u64;
    visit_files(path, &mut |meta| {
        files += 1;
        bytes += meta.len();
    })?;
    Ok((files, bytes))
}

fn visit_files(path: &Path, on_file: &mut dyn FnMut(fs::Metadata)) -> Result<(), String> {
    let entries = fs::read_dir(path).map_err(|err| format!("读取目录失败: {err}"))?;
    for entry in entries.flatten() {
        let path = entry.path();
        let meta = match entry.metadata() {
            Ok(meta) => meta,
            Err(_) => continue,
        };
        if meta.is_dir() {
            // 不跟随目录联接，避免统计到迁移后的环。
            if is_reparse_point(&meta) {
                continue;
            }
            visit_files(&path, on_file)?;
        } else if meta.is_file() {
            on_file(meta);
        }
    }
    Ok(())
}

fn is_reparse_point(meta: &fs::Metadata) -> bool {
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;
        (meta.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT) != 0
    }
    #[cfg(not(windows))]
    {
        let _ = meta;
        false
    }
}

fn create_junction(link_path: &str, target_path: &str, helper_path: Option<&str>) -> Result<(), String> {
    if try_mklink(link_path, target_path) {
        return Ok(());
    }
    if let Some(helper) = helper_path.filter(|p| !p.trim().is_empty()) {
        if run_helper_junction(helper, link_path, target_path, false) {
            return Ok(());
        }
        if run_helper_junction(helper, link_path, target_path, true) {
            return Ok(());
        }
    }
    Err(format!("目录联接创建失败：{link_path}"))
}

fn try_mklink(link_path: &str, target_path: &str) -> bool {
    let status = Command::new("cmd")
        .args(["/C", "mklink", "/J", link_path, target_path])
        .status();
    matches!(status, Ok(s) if s.success()) && Path::new(link_path).exists()
}

fn run_helper_junction(helper: &str, link_path: &str, target_path: &str, elevate: bool) -> bool {
    let payload = json!({
        "method": "create_junction",
        "linkPath": link_path,
        "targetPath": target_path,
    })
    .to_string();

    if !elevate {
        let output = Command::new(helper)
            .args(["--request", &payload])
            .output();
        return matches!(output, Ok(out) if {
            let text = String::from_utf8_lossy(&out.stdout);
            text.contains("\"ok\":true") || text.contains("\"ok\": true")
        }) && Path::new(link_path).exists();
    }

    // 与 Flutter ElevationHelper 一致：UAC RunAs，并把 stdout 重定向到临时文件。
    let out_file = std::env::temp_dir().join(format!(
        "cdm_helper_{}.json",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0)
    ));
    let helper_q = helper.replace('\'', "''");
    let payload_q = payload.replace('\'', "''");
    let out_q = out_file.to_string_lossy().replace('\'', "''");
    let script = format!(
        "Start-Process -FilePath '{helper_q}' -ArgumentList '--request','{payload_q}' -Verb RunAs -Wait -RedirectStandardOutput '{out_q}'"
    );
    let _ = Command::new("powershell")
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", &script])
        .status();
    let ok = Path::new(link_path).exists();
    let _ = fs::remove_file(&out_file);
    ok
}

fn rollback_app(
    source_path: &str,
    backup_dir: &Path,
    target_dir: &Path,
    target_promoted: bool,
) {
    let _ = Command::new("cmd")
        .args(["/c", "rmdir", source_path])
        .status();
    if target_promoted && target_dir.exists() {
        let _ = fs::remove_dir_all(target_dir);
    }
    if backup_dir.exists() && !Path::new(source_path).exists() {
        let _ = fs::rename(backup_dir, source_path);
    }
}

fn chrono_like_iso(millis: u128) -> String {
    // 使用可被 Dart DateTime.tryParse / 毫秒解析兼容的时间标记。
    format!("{millis}")
}

#[allow(dead_code)]
fn io_err(err: io::Error) -> String {
    err.to_string()
}

/// 供烟雾测试使用。
pub fn crate_id() -> &'static str {
    "c_drive_manager_migrator"
}
