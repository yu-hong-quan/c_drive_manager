# C Drive Manager / C 盘管家

C 盘管家是一个面向 Windows 10/11 的本地磁盘空间管理工具。V1.0 优先交付离线桌面端，围绕安全清理、微信专清、应用迁移、系统信息和隔离恢复展开。

## Architecture

V1.0 使用单仓库、多模块、多产物架构：

- `apps/desktop_flutter`: Flutter Windows 桌面客户端。
- `rust/core`: Rust 领域核心，承载扫描、规则、计划和任务状态机。
- `rust/ffi`: Rust Core 面向 Flutter 的稳定 C ABI 边界。
- `rust/helper`: 按需 UAC 提权的管理员 Helper，不做常驻服务。
- `shared`: 跨语言协议、规则、错误码和 schema。
- `server/rule_server`: V2 Go 规则服务预留，V1 不依赖服务端。

## V1 Rule

V1 必须离线可用。任何清理和迁移能力都要先生成可解释计划，再由用户确认后执行；高风险数据默认不选中。
