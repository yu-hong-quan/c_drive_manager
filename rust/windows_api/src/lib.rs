//! Windows 本机辅助：进程检测、磁盘空间、系统信息采集。
//!
//! 仅使用普通用户权限可完成的查询；需要 UAC 的操作不放在本 crate。

use serde::Serialize;
use std::process::Command;

/// 判断微信相关进程是否仍在运行。
pub fn is_wechat_running() -> bool {
    for image in ["WeChat.exe", "Weixin.exe"] {
        if process_running(image) {
            return true;
        }
    }
    false
}

fn process_running(image: &str) -> bool {
    let output = Command::new("tasklist")
        .args(["/FI", &format!("IMAGENAME eq {image}"), "/FO", "CSV", "/NH"])
        .output();
    match output {
        Ok(out) => {
            let text = String::from_utf8_lossy(&out.stdout).to_lowercase();
            text.contains(&image.to_lowercase())
        }
        Err(_) => false,
    }
}

/// 读取固定磁盘列表（DriveType=3）。
pub fn list_fixed_drives() -> Vec<String> {
    let output = Command::new("wmic")
        .args(["logicaldisk", "where", "DriveType=3", "get", "DeviceID"])
        .output();
    let Ok(out) = output else {
        return Vec::new();
    };
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .map(|line| line.trim().to_string())
        .filter(|line| {
            line.len() == 2 && line.as_bytes()[1] == b':' && line.as_bytes()[0].is_ascii_alphabetic()
        })
        .collect()
}

/// 查询指定盘符可用字节数。
pub fn free_bytes_on_drive(drive: &str) -> Option<u64> {
    let drive = drive.trim_end_matches('\\');
    let output = Command::new("wmic")
        .args([
            "logicaldisk",
            "where",
            &format!("DeviceID='{drive}'"),
            "get",
            "FreeSpace",
            "/value",
        ])
        .output()
        .ok()?;
    let text = String::from_utf8_lossy(&output.stdout);
    for line in text.lines() {
        if let Some(value) = line.trim().strip_prefix("FreeSpace=") {
            return value.parse().ok();
        }
    }
    None
}

#[derive(Debug, Serialize)]
pub struct SystemInfoPayload {
    pub os: serde_json::Value,
    pub cpu: serde_json::Value,
    pub disks: serde_json::Value,
    pub displays: serde_json::Value,
    pub hostname: String,
}

/// 通过 PowerShell CIM 采集非敏感系统信息快照。
pub fn load_system_info() -> Result<SystemInfoPayload, String> {
    let script = r#"
$os = Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,OSArchitecture,LastBootUpTime,TotalVisibleMemorySize,FreePhysicalMemory
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1 Name,NumberOfCores,NumberOfLogicalProcessors,CurrentClockSpeed,LoadPercentage
$disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object DeviceID,FileSystem,Size,FreeSpace
$displays = Get-CimInstance Win32_VideoController | Select-Object Name,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentRefreshRate
@{ os=$os; cpu=$cpu; disks=@($disks); displays=@($displays) } | ConvertTo-Json -Depth 5 -Compress
"#;
    let output = Command::new("powershell")
        .args([
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            script,
        ])
        .output()
        .map_err(|err| format!("启动 PowerShell 失败: {err}"))?;
    if !output.status.success() {
        return Err(format!(
            "PowerShell 退出异常: {}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    let text = String::from_utf8_lossy(&output.stdout);
    let value: serde_json::Value = serde_json::from_str(text.trim())
        .map_err(|err| format!("解析系统信息 JSON 失败: {err}"))?;
    Ok(SystemInfoPayload {
        os: value.get("os").cloned().unwrap_or(serde_json::Value::Null),
        cpu: value.get("cpu").cloned().unwrap_or(serde_json::Value::Null),
        disks: value
            .get("disks")
            .cloned()
            .unwrap_or_else(|| serde_json::json!([])),
        displays: value
            .get("displays")
            .cloned()
            .unwrap_or_else(|| serde_json::json!([])),
        hostname: hostname(),
    })
}

fn hostname() -> String {
    std::env::var("COMPUTERNAME").unwrap_or_else(|_| "unknown".into())
}

/// Returns the crate identifier for early workspace smoke checks.
pub fn crate_id() -> &'static str {
    "c_drive_manager_windows_api"
}
