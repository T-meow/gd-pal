# 开发与发布

## 环境与源码运行

工程使用 Godot **4.7.2 .NET**。Windows 目标为 `net8.0`；Android 目标为 `net9.0`，还需 .NET 9 SDK、对应 mono Android 导出模板、Java 与 Android SDK。设置 `ANDROID_HOME` 或 `ANDROID_SDK_ROOT` 指向包含 build-tools 的 SDK，以便用 `apksigner` 和 `aapt` 核对发布签名。保持引擎、导出模板和 `gd-pal.csproj` 中 Godot SDK 版本一致。

图片不纳入 Git。先从对应 Release 下载肥鱼初始包，将其中的 `assets/` 合并到工程根目录，再构建并用 Godot 打开 `project.godot`：

```powershell
dotnet build ./gd-pal.csproj
```

等待 Godot 完成资源导入后运行。桌面启动时附加 `-- --mobile-ui` 可预览移动布局；真机输入、生命周期和性能仍需在 Android 上确认。

## 工程结构

| 路径 | 职责 |
| --- | --- |
| `scenes/app/app.tscn`、`scripts/app/` | 应用入口、大厅、移动界面、设置和面板管理 |
| `scripts/characters/` | 伙伴档案、运行实例、立绘清单和 VRM 加载 |
| `scripts/presenters/`、`scripts/behavior/` | 2D／3D 表现、动作播放与行为 |
| `scripts/desktop/` | Windows 原生窗口、托盘、拖动、穿透与边缘吸附 |
| `scripts/conversation/` | 模型协议、聊天、图片、Markdown 设定、整理和数据包 |
| `scripts/agents/` | 本机 ACP 进程、任务和权限交互 |
| `scripts/storage/` | v1 会话与外观恢复 |
| `assets/` | 界面资源、角色清单、模型和动作 |
| `addons/` | VRM、MToon、开发桥接与导出插件 |
| `tools/` | 构建、发布、资源处理和按需验证 |

聊天服务直接编译进本工程，不依赖相邻 Yumo 仓库、额外角色核心或外部记忆服务。Yumo 移植来源保留在 `licenses/yumo/`。

伙伴身份与表现器分离；大厅和桌宠使用同一伙伴状态。窗口宿主负责布局与输入，表现器负责立绘或 VRM，聊天输出通过表现队列播放动作和朗读。Android 使用移动宿主及 2D 表现器。

## 本地数据

存档与数据包始终为 **v1**。数据位于 Godot `user://`，不纳入仓库或发布包。

| 文件或目录 | 内容 |
| --- | --- |
| `pal_session.json` | 伙伴、外观、衣装与桌面状态 |
| `ui_state.cfg` | 主题和界面状态 |
| `companion/<profile_id>/profile.json` | 名字、朗读开关、当前会话等元数据 |
| 同目录的 `persona.md`、`memory_long_term.md`、`memory_active.md`、`world.md` | 可直接编辑的人设、长期／活跃记忆、世界设定 |
| `persona_before_summary.md` | 整理追加前的人设 |
| `conversations/`、`images/` | JSON／Markdown 会话、图片和缩略图 |
| `summary.json`、`diagnostics/` | 整理草稿与诊断信息 |
| `backups/memory-merge-*` | 应用记忆合并稿前的备份 |
| `work/` | Agent 配置、任务和独立日志 |

请求前重新读取设定文件。聊天使用最近最多 40 条、合计最多 24000 字的有效消息，并加入当前设定；图片请求最多携带最近四张图片。后台服务结果通过 Godot 主线程派发，按伙伴和请求标识匹配。

## Android 发布证书

新项目首次发布时生成专用证书：

```powershell
./tools/setup-android-signing.ps1
```

脚本通过 JDK `keytool` 生成 RSA 发布证书和随机密码，保存到 `release-signing/android-release.keystore` 与 `release-signing/android-release.json`。这个目录已被 Git 和 Godot 导出排除；Windows 上只授予当前账户访问权限。脚本拒绝覆盖已有证书。

**请私下备份 keystore 和 JSON 两个文件，后续版本必须使用同一证书。** 不要将签名目录附到 Release。新的电脑可恢复整个签名目录。

已有签名系统也可设置以下三个环境变量；必须完整提供，优先于默认本地配置：

- `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`
- `GODOT_ANDROID_KEYSTORE_RELEASE_USER`
- `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`

单独导出时可用 `-SigningConfig` 指定另一份 JSON 配置。签名密码仅传给导出子进程，导出后恢复调用进程原有环境变量。

## 构建 Release

需要 Node.js、PowerShell 和已经导入角色图片的工程。准备签名后执行：

```powershell
./tools/build-release.ps1 -GodotPath 'D:/路径/Godot.exe' -Version '0.1.0'
```

发布脚本固定导出 Windows Release 和**正式签名 Android Release**，不使用 debug APK。导出后核对 APK 签名和非调试标记，并在发布说明记录证书 SHA-256。它还生成肥鱼初始包、发布说明与文件校验信息，统一写入 `exports/releases/v0.1.0/`。同名目录已存在时先手动移走旧目录，避免混入旧附件。

发布附件为 Windows ZIP、Android APK、肥鱼初始包 ZIP、`SHA256SUMS.txt` 与 `RELEASE_NOTES.md`。将这些文件附到同一版本 Release。源码 ZIP 不含图片，程序内已包含所需立绘；初始包同时提供源码补齐用的图片和可在应用中导入的 `persona.zip`。

单独导出：

```powershell
./tools/export-windows.ps1 -GodotPath 'D:/路径/Godot.exe'
./tools/export-android.ps1 -GodotPath 'D:/路径/Godot.exe' -Release
```

Android 脚本不加 `-Release` 时仅生成本地测试 APK，不用于 Release。脚本不会安装到设备或上传远程仓库。Windows 包保留完整运行时目录，不能只复制 EXE。

## 日常开发

默认由人工确认画面和交互，不自动运行整套检查。需要时仅使用现有统一入口：

```powershell
./tools/validate.ps1 -GodotPath 'D:/路径/Godot.exe'
```

临时数据与日志位于 `.godot/checks/`。Windows 的窗口透明、拖动、任务栏、多屏 DPI 和输入法，以及 Android 的横竖屏、输入法、后台恢复与性能，需要在实际设备确认。

Godot MCP 桥接仅在 debug 构建且显式设置 `GODOT_MCP_ENABLED=1` 时监听回环地址；普通运行不启用。此开发桥接不属于应用使用或正式发布的前置条件。
