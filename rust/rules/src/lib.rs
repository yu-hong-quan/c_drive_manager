//! 内置规则包加载器：从 `shared/rules/builtin` 嵌入 JSON，供清理 / 微信引擎读取。

use serde::Deserialize;
use std::path::PathBuf;
use std::sync::OnceLock;

const CLEANUP_RULES_JSON: &str =
    include_str!("../../../shared/rules/builtin/cleanup_rules.json");
const WECHAT_RULES_JSON: &str =
    include_str!("../../../shared/rules/builtin/wechat_rules.json");

static CLEANUP_PACK: OnceLock<CleanupRulePack> = OnceLock::new();
static WECHAT_PACK: OnceLock<WechatRulePack> = OnceLock::new();

/// 清理规则包中的根路径描述：支持环境变量、子路径或绝对路径。
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CleanupRootSpec {
    pub env: Option<String>,
    pub child: Option<String>,
    pub absolute: Option<String>,
}

/// 单条安全清理规则（元数据 + 扫描根）。
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CleanupRuleSpec {
    pub id: String,
    pub title: String,
    pub subtitle: String,
    pub source: String,
    pub risk: String,
    pub default_selected: bool,
    pub recoverable: bool,
    pub roots: Vec<CleanupRootSpec>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CleanupRulePack {
    pub version: u32,
    pub rules: Vec<CleanupRuleSpec>,
}

/// 微信分类规则（相对账号根目录的路径）。
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WechatCategorySpec {
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

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WechatRulePack {
    pub version: u32,
    pub layouts: WechatLayouts,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WechatLayouts {
    pub classic: Vec<WechatCategorySpec>,
    pub xwechat: Vec<WechatCategorySpec>,
}

/// 加载并缓存内置清理规则包；解析失败时 panic，因规则应在编译期固定。
pub fn builtin_cleanup_rules() -> &'static CleanupRulePack {
    CLEANUP_PACK.get_or_init(|| {
        serde_json::from_str(CLEANUP_RULES_JSON)
            .expect("内置 cleanup_rules.json 解析失败")
    })
}

/// 加载并缓存内置微信规则包。
pub fn builtin_wechat_rules() -> &'static WechatRulePack {
    WECHAT_PACK.get_or_init(|| {
        serde_json::from_str(WECHAT_RULES_JSON)
            .expect("内置 wechat_rules.json 解析失败")
    })
}

/// 按布局返回微信分类规则；未知布局回退到 classic。
pub fn wechat_rules_for_layout(layout: &str) -> &'static [WechatCategorySpec] {
    let pack = builtin_wechat_rules();
    if layout == "xwechat" {
        &pack.layouts.xwechat
    } else {
        &pack.layouts.classic
    }
}

/// 将清理根描述解析为实际路径列表（缺失环境变量的项会被跳过）。
pub fn resolve_cleanup_roots(specs: &[CleanupRootSpec]) -> Vec<PathBuf> {
    let mut roots = Vec::new();
    for spec in specs {
        if let Some(absolute) = &spec.absolute {
            roots.push(PathBuf::from(absolute));
            continue;
        }
        let Some(env_name) = &spec.env else {
            continue;
        };
        let Ok(base) = std::env::var(env_name) else {
            continue;
        };
        if let Some(child) = &spec.child {
            roots.push(PathBuf::from(format!("{base}\\{child}")));
        } else {
            roots.push(PathBuf::from(base));
        }
    }
    roots
}

/// 供烟雾测试使用。
pub fn crate_id() -> &'static str {
    "c_drive_manager_rules"
}
