# Windows 中文账号管理

此目录保存本 fork 的中文 WPF 桌面账号管理器，以及无控制台启动器的源码。Go CLI 版本保持 `0.5.3`；没有修改官方 Antigravity 客户端，也不额外发布 npm 包或 Release。

## 功能

- 显示当前本机凭据、订阅 / Cloud 模式、项目和地区；添加、保存、删除配置、切换账号与生成单账号快捷方式。
- 高 DPI 清晰字体、分组操作按钮和窗口大小 / 位置 / 最大化状态记忆。
- 一键入口使用 GUI 子系统启动器，PowerShell 后台运行，避免额外的 Windows Terminal 窗口。
- 更新结果窗口根据脚本退出码结束等待；常驻后代继承日志管道不会让“执行中”永久卡住。

## 从源码安装

需要 Windows 10/11 x64、Windows PowerShell 5.1、.NET Framework 4.8、Git、Go 1.24 或更新版本、Antigravity Desktop 和官方 `agy` CLI。GUI 本身不依赖 Node.js。

在仓库根目录的 PowerShell 中运行一次，将示例路径替换为实际安装路径：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\Setup.ps1 `
  -AgyBinary 'C:\path\to\agy.exe' `
  -DesktopBinary 'C:\path\to\Antigravity.exe'
```

若 Go 不在 PATH，可追加 `-GoBinary 'C:\path\to\go.exe'`。Setup 在本机编译 CLI 和启动器、执行假凭据隔离验收、建立仅当前 Windows 用户和 SYSTEM 可访问的 `private/`，并生成 `windows/agy-auth/Account Manager.lnk` 与 `Update Tool.lnk`。已有 `settings.json` 不覆盖。后续直接双击快捷方式，可复制到桌面；旧 `.cmd` 入口也保留兼容，但可能短暂闪过命令行窗口。

关闭账号管理器后可重新运行 Setup 构建源码更新。首次 Setup 是手动命令；日常启动和更新走无控制台入口。

## 账号与计费

点击“添加账号”，填写预期邮箱与配置别名，在 Edge 手动选择相同邮箱并授权，将授权码粘贴回窗口。新增授权先进入隔离临时文件存储，校验邮箱后导入，**不自动激活**。已有登录使用 `add --target=cli` 保存。

点击“切换并启动”才会关闭并重新打开 Antigravity，同时同步 CLI 与桌面凭据；先保存进行中的工作。模式标签仅展示本机配置，不证明服务器登录成功或 Google Cloud 赠金可抵扣。

默认别名示例为 `pro` 与 `cloud-credit`。如使用其他别名，在窗口里选择该配置并生成一键入口。没有启用自动轮换。

选中已保存的配置，点击“修改别名”。窗口预填原别名，保存后列表会刷新，不会切换账号。同邮箱的其他配置不受影响。别名支持中文，不可重名、使用空格或使用纯数字，最长 32 个 UTF-8 字节。通过“生成一键入口”创建的快捷方式按配置 ID 切换，改名后仍然有效；预置 `pro` / `cloud-credit` 入口按别名查找，改名后可用“生成一键入口”替代。

选择已保存的行，点击列表下方“删除配置”，核对邮箱、别名、模式及项目后确认。删除按精确配置 ID 执行，不会连带删除同邮箱的其他配置。默认按钮为“取消”。删除当前配置也不会退出客户端、注销 Google 账号或取消订阅；顶部继续显示当前登录，列表只显示剩余已保存配置。再次切换到已删配置需要重新保存或授权，旧的一键入口会失效。此操作不清理历史备份，不代表彻底擦除所有历史凭据。

## 文件与更新

- `agy-auth/ui/`、PowerShell 脚本、`launcher/*.cs` 是可共享源码。
- `agy-auth/settings.json` 是本机路径配置，可参考 [模板](agy-auth/settings.example.json)。
- `agy-auth/private/` 是本机账号库和临时授权工作区；不要分享或上传。
- `agy-auth/ui-state.json` 是窗口布局，删除后恢复默认大小。自检使用临时布局文件。
- 编译产物、快捷方式、日志、截图、配置和账号文件都被本目录的 `.gitignore` 排除。

“更新工具”仅快进 `unisong/agy-auth` 的 `main`，遇到本地源码改动则停止，校验后重新构建 Go 程序。GUI 源码也随 Git 更新；**C# 启动器修改后，关闭已有窗口并重新运行 Setup**。源码更新不迁移已有账号库，不改 `.gemini` 的个人汉化配置。

更新入口需要 PATH 中可用的 `go.exe`（或既有部署的 `agy-auth/toolchain/go/bin/go.exe`）。Setup 的 `-GoBinary` 参数只适用于本次构建，不修改系统 PATH。

共享启动器保留 `update-theme` / `check-theme` 路由，供原有并列部署的 `antigravity-cn/` 使用；汉化项目是独立项目，本仓库不包含它的源码或本机运行时。纯账号管理不需要该目录。

## 验证

完成 Setup 后运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\Verify.ps1
```

该命令验证模拟账号 UI（包括删除取消/确认）、窗口状态、文件后端假凭据切换及删除、无控制台启动，以及继承输出管道的后台进程继续存活时结果窗口是否正确完成。删除测试验证同邮箱配置隔离和当前凭据保留。不会发起真实 OAuth、删除或切换真实账号、远程更新。测试图片和结果文件不进入 Git。

另运行仓库标准 `go run ./cmd/harness verify --profile full`。上游已有部分测试依赖 Unix 权限、macOS 路径与终端颜色；Windows 上可能失败，不能把针对 GUI 的验证通过表述为整个上游套件通过。
