//! Rust Core：聚合各领域 crate，并向 FFI 暴露统一 JSON 命令分发。

use c_drive_manager_app_inventory::{scan_apps, scan_target_volumes};
use c_drive_manager_cleaner::{
    clean_files, scan_cleanup, CleanupCleanRequest, CleanupScanRequest,
};
use c_drive_manager_migrator::{
    append_execution_log, create_plan, execute_app, CreatePlanRequest, ExecuteAppRequest,
};
use c_drive_manager_protocol::{encode_err, encode_ok};
use c_drive_manager_quarantine::{QuarantineCandidate, QuarantineService};
use c_drive_manager_wechat::{
    clean_selected, discover_accounts, scan_account, validate_custom_root, wechat_running,
    CleanRequest, WechatAccount,
};
use c_drive_manager_windows_api::load_system_info;
use serde::Deserialize;

/// 处理一条 FFI 命令，返回 JSON 字符串（调用方负责释放）。
pub fn dispatch(method: &str, request_json: &str) -> String {
    match method {
        "ping" => encode_ok(serde_json::json!({
            "engine": "rust",
            "version": env!("CARGO_PKG_VERSION")
        })),
        "system_info.get" => match load_system_info() {
            Ok(data) => encode_ok(data),
            Err(message) => encode_err("SYSTEM_INFO_FAILED", &message),
        },
        "cleanup.scan" => {
            let req = serde_json::from_str::<CleanupScanRequest>(request_json)
                .unwrap_or_default();
            encode_ok(scan_cleanup(&req))
        }
        "cleanup.clean" => match serde_json::from_str::<CleanupCleanRequest>(request_json) {
            Ok(req) => encode_ok(clean_files(req)),
            Err(err) => encode_err("BAD_REQUEST", &err.to_string()),
        },
        "wechat.discover" => encode_ok(discover_accounts()),
        "wechat.validate_root" => {
            #[derive(Deserialize)]
            struct Req {
                path: String,
            }
            match serde_json::from_str::<Req>(request_json) {
                Ok(req) => encode_ok(validate_custom_root(&req.path)),
                Err(err) => encode_err("BAD_REQUEST", &err.to_string()),
            }
        }
        "wechat.is_running" => encode_ok(serde_json::json!({ "running": wechat_running() })),
        "wechat.scan" => {
            #[derive(Deserialize)]
            #[serde(rename_all = "camelCase")]
            struct Req {
                account: WechatAccount,
            }
            match serde_json::from_str::<Req>(request_json) {
                Ok(req) => encode_ok(scan_account(&req.account)),
                Err(err) => encode_err("BAD_REQUEST", &err.to_string()),
            }
        }
        "wechat.clean" => match serde_json::from_str::<CleanRequest>(request_json) {
            Ok(req) => encode_ok(clean_selected(req)),
            Err(err) => encode_err("BAD_REQUEST", &err.to_string()),
        },
        "quarantine.resolve_root" => {
            let service = quarantine_from_request(request_json);
            match service.resolve_root() {
                Ok(path) => encode_ok(serde_json::json!({ "path": path.to_string_lossy() })),
                Err(err) => encode_err("QUARANTINE_ROOT_FAILED", &err),
            }
        }
        "quarantine.list" => {
            let service = quarantine_from_request(request_json);
            match service.list_items() {
                Ok(items) => encode_ok(items),
                Err(err) => encode_err("QUARANTINE_LIST_FAILED", &err),
            }
        }
        "quarantine.move" => {
            #[derive(Deserialize)]
            #[serde(rename_all = "camelCase")]
            struct Req {
                quarantine_days: Option<u32>,
                quarantine_path: Option<String>,
                candidates: Vec<QuarantineCandidate>,
            }
            match serde_json::from_str::<Req>(request_json) {
                Ok(req) => {
                    let service = QuarantineService {
                        default_retention_days: req.quarantine_days.unwrap_or(7),
                        configured_root: req.quarantine_path,
                    };
                    match service.quarantine_files(&req.candidates) {
                        Ok(result) => encode_ok(result),
                        Err(err) => encode_err("QUARANTINE_MOVE_FAILED", &err),
                    }
                }
                Err(err) => encode_err("BAD_REQUEST", &err.to_string()),
            }
        }
        "quarantine.restore" => {
            #[derive(Deserialize)]
            struct Req {
                ids: Vec<String>,
                #[serde(default)]
                quarantine_days: Option<u32>,
                #[serde(default)]
                quarantine_path: Option<String>,
            }
            match serde_json::from_str::<Req>(request_json) {
                Ok(req) => {
                    let service = QuarantineService {
                        default_retention_days: req.quarantine_days.unwrap_or(7),
                        configured_root: req.quarantine_path,
                    };
                    match service.restore_items(&req.ids) {
                        Ok(result) => encode_ok(result),
                        Err(err) => encode_err("QUARANTINE_RESTORE_FAILED", &err),
                    }
                }
                Err(err) => encode_err("BAD_REQUEST", &err.to_string()),
            }
        }
        "quarantine.purge" => {
            #[derive(Deserialize)]
            struct Req {
                ids: Vec<String>,
                #[serde(default)]
                quarantine_days: Option<u32>,
                #[serde(default)]
                quarantine_path: Option<String>,
            }
            match serde_json::from_str::<Req>(request_json) {
                Ok(req) => {
                    let service = QuarantineService {
                        default_retention_days: req.quarantine_days.unwrap_or(7),
                        configured_root: req.quarantine_path,
                    };
                    match service.purge_items(&req.ids) {
                        Ok(result) => encode_ok(result),
                        Err(err) => encode_err("QUARANTINE_PURGE_FAILED", &err),
                    }
                }
                Err(err) => encode_err("BAD_REQUEST", &err.to_string()),
            }
        }
        "quarantine.purge_expired" => {
            let service = quarantine_from_request(request_json);
            match service.purge_expired() {
                Ok(result) => encode_ok(result),
                Err(err) => encode_err("QUARANTINE_PURGE_FAILED", &err),
            }
        }
        "quarantine.open_folder" => {
            let service = quarantine_from_request(request_json);
            match service.open_folder() {
                Ok(path) => encode_ok(serde_json::json!({ "path": path })),
                Err(err) => encode_err("QUARANTINE_OPEN_FAILED", &err),
            }
        }
        "migration.scan_apps" => match scan_apps() {
            Ok(apps) => encode_ok(serde_json::json!({ "apps": apps })),
            Err(err) => encode_err("MIGRATION_SCAN_FAILED", &err),
        },
        "migration.scan_targets" => match scan_target_volumes() {
            Ok(volumes) => encode_ok(serde_json::json!({ "volumes": volumes })),
            Err(err) => encode_err("MIGRATION_TARGETS_FAILED", &err),
        },
        "migration.create_plan" => match serde_json::from_str::<CreatePlanRequest>(request_json)
        {
            Ok(req) => match create_plan(req) {
                Ok(result) => encode_ok(result),
                Err(err) => encode_err("MIGRATION_PLAN_FAILED", &err),
            },
            Err(err) => encode_err("BAD_REQUEST", &err.to_string()),
        },
        "migration.execute_app" => match serde_json::from_str::<ExecuteAppRequest>(request_json)
        {
            Ok(req) => encode_ok(execute_app(req)),
            Err(err) => encode_err("BAD_REQUEST", &err.to_string()),
        },
        "migration.append_log" => {
            #[derive(Deserialize)]
            #[serde(rename_all = "camelCase")]
            struct Req {
                transaction_path: String,
                migrated: Vec<String>,
                failed: Vec<String>,
                messages: Vec<String>,
            }
            match serde_json::from_str::<Req>(request_json) {
                Ok(req) => match append_execution_log(
                    &req.transaction_path,
                    &req.migrated,
                    &req.failed,
                    &req.messages,
                ) {
                    Ok(()) => encode_ok(serde_json::json!({ "ok": true })),
                    Err(err) => encode_err("MIGRATION_LOG_FAILED", &err),
                },
                Err(err) => encode_err("BAD_REQUEST", &err.to_string()),
            }
        }
        other => encode_err("UNKNOWN_METHOD", &format!("未知方法: {other}")),
    }
}

fn quarantine_from_request(request_json: &str) -> QuarantineService {
    #[derive(Deserialize, Default)]
    #[serde(rename_all = "camelCase")]
    struct Req {
        quarantine_days: Option<u32>,
        quarantine_path: Option<String>,
    }
    let req: Req = serde_json::from_str(request_json).unwrap_or_default();
    QuarantineService {
        default_retention_days: req.quarantine_days.unwrap_or(7),
        configured_root: req.quarantine_path,
    }
}

/// 供烟雾测试使用。
pub fn crate_id() -> &'static str {
    "c_drive_manager_core"
}
