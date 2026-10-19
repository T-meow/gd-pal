# 第三方组件与素材

GD Pal 自有代码和文档采用根目录的 [MIT License](LICENSE)。发布包应同时保留本文件及以下第三方声明；根目录 MIT 不替代第三方组件或素材的原有许可。

| 内容 | 许可与来源记录 |
| --- | --- |
| Godot VRM 导入插件 | `addons/vrm/LICENSE` |
| Godot MToon Shader | `addons/Godot-MToon-Shader/LICENSE` |
| Godot MCP 插件 | `addons/godot_mcp/LICENSE` |
| 从 Yumo 移植的聊天、数据包和 Agent 代码 | `licenses/yumo/LICENSE`、`licenses/yumo/PORTING.md` |
| 人形动作库及 DS 动作适配 | `assets/motions/npc/manifest.json`、`assets/motions/npc/licenses/` |
| DS VRM 模型 | `assets/DS-desktop.vrm` 内嵌 VRM 元数据 |
| 肥鱼立绘 | 随 Release 初始包分发；生成来源见 `assets/characters/blue_whale/README.md` |
| Vanara.PInvoke.Pdh 5.0.5（及 Vanara.Core 依赖） | MIT；`licenses/monitoring/Vanara-LICENSE`；来源 https://github.com/dahall/Vanara |
| LibreHardwareMonitorLib 0.9.6（独立传感器进程） | MPL-2.0；`licenses/monitoring/LibreHardwareMonitor-LICENSE` 与上游第三方声明；来源 https://github.com/LibreHardwareMonitor/LibreHardwareMonitor |

Godot 引擎及 .NET 运行时随对应平台程序分发，其第三方声明以所用引擎模板和运行时附带内容为准。

性能监控未修改上述库源码。传感器库依赖项及其来源见 `licenses/monitoring/README.md`。

PawnIO 是用户主动启用的可选温度组件，采用 GPL-2.0-or-later 及上游附加例外条款。默认从 [官方发行页](https://github.com/namazso/PawnIO.Setup/releases/tag/2.2.0)获取未经修改、已签名的安装器；[驱动源码及许可说明](https://github.com/namazso/PawnIO)。若 Windows 发布包通过 `-PawnIOBundlePath` 附带安装器，须同时保留 `components/PawnIO/COPYING`、上游 `README.md` 及包含构建所需子模块的完整对应源码 `PawnIO-2.2.0-source.zip`。桌宠不会在启动时自行安装系统驱动。
