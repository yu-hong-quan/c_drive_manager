//! Flutter 可加载的 Windows DLL（cdylib）入口。
//!
//! 约定：
//! - `cdm_call(method, request_json)` 返回堆上 UTF-8 CString，由 `cdm_free_string` 释放
//! - 所有业务通过 JSON 命令分发，避免逐字段 C 结构体漂移

use c_drive_manager_core::dispatch;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// 返回引擎版本字符串，调用方必须 `cdm_free_string`。
#[no_mangle]
pub extern "C" fn cdm_version() -> *mut c_char {
    to_cstring(env!("CARGO_PKG_VERSION"))
}

/// 释放由本 DLL 分配的 C 字符串。
///
/// # Safety
/// `ptr` 必须来自本库返回的字符串指针，或为空。
#[no_mangle]
pub unsafe extern "C" fn cdm_free_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    drop(CString::from_raw(ptr));
}

/// 统一命令入口：method + request JSON -> response JSON。
///
/// # Safety
/// `method` / `request_json` 必须是有效的 UTF-8 C 字符串；`request_json` 可为 null（视为 `{}`）。
#[no_mangle]
pub unsafe extern "C" fn cdm_call(
    method: *const c_char,
    request_json: *const c_char,
) -> *mut c_char {
    if method.is_null() {
        return to_cstring(r#"{"ok":false,"error":{"code":"BAD_REQUEST","message":"method 为空"}}"#);
    }
    let method = match CStr::from_ptr(method).to_str() {
        Ok(value) => value,
        Err(_) => {
            return to_cstring(
                r#"{"ok":false,"error":{"code":"BAD_REQUEST","message":"method 不是合法 UTF-8"}}"#,
            )
        }
    };
    let request = if request_json.is_null() {
        "{}"
    } else {
        match CStr::from_ptr(request_json).to_str() {
            Ok(value) => value,
            Err(_) => {
                return to_cstring(
                    r#"{"ok":false,"error":{"code":"BAD_REQUEST","message":"request 不是合法 UTF-8"}}"#,
                )
            }
        }
    };

    // 捕获 panic，避免跨 FFI 边界展开导致进程崩溃。
    let result = std::panic::catch_unwind(|| dispatch(method, request));
    match result {
        Ok(json) => to_cstring(&json),
        Err(_) => to_cstring(
            r#"{"ok":false,"error":{"code":"ENGINE_PANIC","message":"Rust 引擎内部异常"}}"#,
        ),
    }
}

fn to_cstring(value: &str) -> *mut c_char {
    CString::new(value.replace('\0', ""))
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

pub fn crate_id() -> &'static str {
    "c_drive_manager_ffi"
}
