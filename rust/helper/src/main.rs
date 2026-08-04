//! 按需提权 Helper：仅接受结构化 JSON 命令，不提供通用 shell。
//!
//! 用法（已提权进程）：
//! `c_manager_helper.exe --request "{\"method\":\"create_junction\",\"...\"}"`

use c_drive_manager_protocol::{encode_err, encode_ok};
use serde::Deserialize;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::{Command, Stdio};

fn main() {
    let args: Vec<String> = env::args().collect();
    let request = parse_request(&args);
    let response = match request {
        Ok(req) => dispatch(req),
        Err(message) => encode_err("BAD_REQUEST", &message),
    };
    println!("{response}");
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HelperRequest {
    method: String,
    #[serde(default)]
    link_path: Option<String>,
    #[serde(default)]
    target_path: Option<String>,
}

fn parse_request(args: &[String]) -> Result<HelperRequest, String> {
    let mut raw = None;
    let mut i = 1;
    while i < args.len() {
        if args[i] == "--request" {
            raw = args.get(i + 1).cloned();
            break;
        }
        i += 1;
    }
    let Some(raw) = raw else {
        return Err("缺少 --request JSON 参数".into());
    };
    serde_json::from_str(&raw).map_err(|err| err.to_string())
}

fn dispatch(request: HelperRequest) -> String {
    match request.method.as_str() {
        "ping" => encode_ok(serde_json::json!({
            "helper": "c_manager_helper",
            "elevated": is_elevated(),
        })),
        "create_junction" => {
            let Some(link) = request.link_path.filter(|s| !s.trim().is_empty()) else {
                return encode_err("BAD_REQUEST", "缺少 linkPath");
            };
            let Some(target) = request.target_path.filter(|s| !s.trim().is_empty()) else {
                return encode_err("BAD_REQUEST", "缺少 targetPath");
            };
            match create_junction(&link, &target) {
                Ok(path) => encode_ok(serde_json::json!({ "linkPath": path })),
                Err(message) => encode_err("HELPER_JUNCTION_FAILED", &message),
            }
        }
        other => encode_err("UNKNOWN_METHOD", &format!("未知 Helper 方法: {other}")),
    }
}

fn create_junction(link_path: &str, target_path: &str) -> Result<String, String> {
    let link = PathBuf::from(link_path);
    let target = PathBuf::from(target_path);
    if !target.is_dir() {
        return Err(format!("目标目录不存在: {target_path}"));
    }
    if link.exists() {
        return Err(format!("链接路径已存在: {link_path}"));
    }
    if let Some(parent) = link.parent() {
        fs::create_dir_all(parent).map_err(|err| err.to_string())?;
    }

    // Windows 目录联接：mklink /J <link> <target>
    let status = Command::new("cmd")
        .args(["/C", "mklink", "/J", link_path, target_path])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .status()
        .map_err(|err| err.to_string())?;
    if !status.success() {
        return Err(format!("mklink 失败，退出码 {:?}", status.code()));
    }
    Ok(link_path.to_string())
}

fn is_elevated() -> bool {
    // 通过尝试打开需要管理员权限的注册表键做轻量探测。
    Command::new("reg")
        .args([
            "query",
            r"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System",
            "/v",
            "EnableLUA",
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}
