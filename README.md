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

## 本地开发

Flutter 工程目录：

```powershell
cd apps\desktop_flutter
flutter run -d windows
```

构建并复制 Rust FFI DLL（清理 / 微信 / 隔离 / 系统信息走此引擎）：

```powershell
# 仓库根目录执行
powershell -ExecutionPolicy Bypass -File .\tools\build_ffi.ps1
```

## 生成 Windows 安装包

需要本机已安装 [Inno Setup 6](https://jrsoftware.org/isinfo.php)。一键打包会编译 Flutter Release、拷贝 FFI，并生成 Setup 安装程序：

```powershell
# 仓库根目录执行
powershell -ExecutionPolicy Bypass -File .\tools\build_installer.ps1
```

安装包输出路径：

```text
dist\CDriveManager-Setup-1.0.0.exe
```

用户双击该安装程序，按向导即可安装到电脑（开始菜单可启动，支持卸载）。

卸载方式：
- 开始菜单 →「卸载 C 盘管家」
- 安装目录中的 `Uninstall.exe` 或「卸载 C 盘管家」快捷方式
- Windows「应用和功能」中卸载

**中文路径已支持：** 若安装到含中文的目录，启动时会自动通过 `C:\Users\Public\CDriveManager\run` 目录联接兼容运行（本机已关闭 8.3 短文件名时也能用）。也可直接装到英文路径如 `C:\Program Files\CDriveManager`。

## 开发阶段进度

- 阶段1（已完成）：安全清理可恢复项进隔离；设置驱动扫描强度；隔离区进度动画与结果弹窗
- 阶段2（已完成）：Helper/UAC 提权骨架，迁移目录联接可走提权 Helper
- 后续：迁移引擎迁 Rust FFI、规则包、设计切图、任务 SQLite 持久化
