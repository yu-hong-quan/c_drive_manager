//! 跨语言稳定协议：任务版本、错误码与 JSON 响应信封。
//!
//! FFI / Helper / Flutter 都必须通过本 crate 约定交换数据，避免各端自行拼字段。

use serde::{Deserialize, Serialize};

/// 任务事件 schema 版本，需与 shared/schemas/task-event.schema.json 保持同步。
pub const TASK_EVENT_SCHEMA_VERSION: u32 = 1;

/// 稳定错误码，面向 UI 展示与日志映射。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ErrorBody {
    pub code: String,
    pub message: String,
}

/// FFI 统一响应信封：成功带 data，失败带 error。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum ApiResponse<T> {
    Ok { ok: bool, data: T },
    Err { ok: bool, error: ErrorBody },
}

impl<T: Serialize> ApiResponse<T> {
    pub fn success(data: T) -> Self {
        Self::Ok { ok: true, data }
    }

    pub fn failure(code: impl Into<String>, message: impl Into<String>) -> ApiResponse<serde_json::Value> {
        ApiResponse::Err {
            ok: false,
            error: ErrorBody {
                code: code.into(),
                message: message.into(),
            },
        }
    }
}

/// 将任意可序列化成功结果编码为 JSON 字符串。
pub fn encode_ok<T: Serialize>(data: T) -> String {
    serde_json::to_string(&serde_json::json!({ "ok": true, "data": data }))
        .unwrap_or_else(|_| r#"{"ok":false,"error":{"code":"ENCODE_FAILED","message":"序列化失败"}}"#.to_string())
}

/// 将错误编码为 JSON 字符串。
pub fn encode_err(code: &str, message: &str) -> String {
    serde_json::to_string(&serde_json::json!({
        "ok": false,
        "error": { "code": code, "message": message }
    }))
    .unwrap_or_else(|_| r#"{"ok":false,"error":{"code":"ENCODE_FAILED","message":"序列化失败"}}"#.to_string())
}
