# GD Pal · 轻量桌宠

一个用 Godot 4.8 beta1 .NET 制作的桌面伙伴。Windows 支持透明桌宠、2D 立绘和 3D VRM；Android 提供适合触屏的 2D 聊天界面。聊天、设定和历史记录保存在本机，模型服务由你自行配置。

项目代码采用 [MIT 许可证](LICENSE)。当前为开发版本，存档与数据包格式统一为 v1。

## 下载与开始使用

在仓库的 **Releases** 页面下载对应文件。每次发布包含：

| 文件 | 用途 |
| --- | --- |
| `GD-Pal-<版本>-Windows-x64.zip` | Windows 程序，包含 .NET 运行时和肥鱼立绘。解压整个目录后运行 `GD-Pal.exe`。 |
| `GD-Pal-<版本>-Android.apk` | 正式签名的 Android Release 安装包，包含肥鱼立绘。 |
| `GD-Pal-<版本>-Blue-Whale-Starter.zip` | 肥鱼初始包：普通人设、完整立绘和素材清单，也用于补齐源码所需图片。 |
| `SHA256SUMS.txt` | 上述文件的 SHA-256 校验值。 |

首次使用：

1. 启动应用，在「连接设置」填写模型 API 地址、模型名称与 Key；语音服务可选。
2. 使用默认肥鱼伙伴，或在「伙伴档案」创建和编辑伙伴。
3. 如需恢复初始人设，解压初始包，在「伙伴档案 → 导入导出」选择其中的 `persona.zip`，预览后导入。初始包不包含私人聊天、记忆、连接凭据或 Agent 配置。
4. Windows 可切换到透明桌宠；关闭大厅会收起到系统托盘，从托盘菜单可以退出应用。Android 使用移动界面，不创建桌宠窗口。

发布程序已带齐所需立绘；普通用户无需另行复制图片。

## 功能

- **陪伴与外观**：2D 全身／近景、女仆与睡裙换装、表情与触摸反馈；Windows 另支持 VRM、拖动、窗口／任务栏边缘停靠和动作播放。
- **聊天**：流式回复、停止与重试、图片附件、历史搜索与切换、Markdown 记录和可选朗读。识图需要模型服务支持。
- **手动设定**：分别编辑人设、长期／当前记忆和世界设定，保存后从下一次回复生效；新对话继续沿用。
- **AI 整理**：选取聊天内容生成候选条目，编辑并确认后加入设定。整理期间可以继续聊天。
- **数据包**：导入／导出 v1 人设和对话 ZIP；导入先预览，重复聊天记录会跳过。
- **Agent**：Windows 可连接本机 ACP 程序，在授权的工作目录运行独立任务，支持继续、取消和工具活动记录。
- **PC 性能监控**：Windows 大厅“性能”页与桌宠悬浮卡共用采样，显示 CPU、内存、GPU、显存、网速和磁盘活动；支持温度、风扇来源选择及可配置高温提醒。部分传感器需额外权限／PawnIO 支持。

桌面窗口观感、Android 真机效果和模型服务接入由使用者手动确认。详细操作见[使用说明](docs/usage.md)。

## 从源码运行

准备 Godot **4.8 beta1 .NET** 和可构建 `net10.0` 的 .NET SDK。Android 构建另需 .NET 10 SDK、匹配的 mono Android 导出模板，以及在 Godot 中配置好的 Java 与 Android SDK。

**图片随 Release 分发，不纳入 Git。** 克隆源码后，先解压对应版本的 `Blue-Whale-Starter.zip`，将其中的 `assets/` 目录合并到项目根目录，使 `assets/characters/blue_whale/images/` 就位。清单、代码、界面 SVG 和图标保留在源码中；`output/`、构建产物及本地凭据不提交。

```powershell
dotnet build ./gd-pal.csproj
```

用 Godot .NET 打开 `project.godot`，完成资源导入后运行。聊天服务直接包含在本工程中，无需相邻项目或额外记忆服务。

## 构建 Release

需要 Node.js、PowerShell 和上述构建环境。先按上一节补齐立绘；首次发布先生成并私下备份项目签名证书：

```powershell
./tools/setup-android-signing.ps1
```

已有证书时恢复本地 `release-signing/` 目录，或配置下述环境变量，不重复生成。然后构建：

```powershell
./tools/build-release.ps1 -GodotPath 'D:/路径/Godot.exe' -Version '0.3.0'
```

脚本依次导出 Windows Release、正式签名的 Android Release APK，生成肥鱼初始包、发布说明和校验文件，统一放在 `exports/releases/v0.3.0/`。缺少签名配置时直接停止，不使用测试签名。它只整理本地发布文件，不上传仓库，也不安装到设备。将该目录中的文件附到同一版本的 Release；GitHub 自动生成的源码 ZIP 不包含立绘。

签名默认读取本地 `release-signing/android-release.json`。也可完整设置以下环境变量以使用已有发布证书：

- `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`
- `GODOT_ANDROID_KEYSTORE_RELEASE_USER`
- `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`

签名文件和密码不提交到 Git，也不随 Release 分发。后续升级必须沿用同一证书；从原测试签名 APK 切换时，先导出个人数据、卸载旧包再安装。单独导出 Android 正式包使用 `tools/export-android.ps1 -Release`；详见[开发与发布](docs/development.md)。

## 数据与开发

存档始终为 v1。外观保存在 `user://pal_session.json`，聊天、手动设定和连接配置保存在 `user://companion/`。API Key 由本机凭据存储管理，不写入人设或对话导出包。聊天会将所选上下文、设定和图片发送到你配置的模型服务。

项目只保留一个按需验证入口，日常修改不默认运行完整检查：

```powershell
./tools/validate.ps1 -GodotPath 'D:/路径/Godot.exe'
```

代码入口在 `scripts/app/`，聊天服务在 `scripts/conversation/`，桌面窗口在 `scripts/desktop/`。完整说明见[文档索引](docs/README.md)、[角色与素材](docs/assets.md)。

## 许可证

自有代码和文档以标准 [MIT License](LICENSE) 开源。第三方插件、动作和模型保留各自许可及来源记录，见 [第三方声明](THIRD_PARTY_NOTICES.md)。肥鱼初始包附带项目许可证和图片生成来源说明。
