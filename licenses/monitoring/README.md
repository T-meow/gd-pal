# 性能监控依赖

Vanara.PInvoke.Pdh 5.0.5 及其 Vanara.Core 依赖使用 MIT 许可证，来源：https://github.com/dahall/Vanara 。

LibreHardwareMonitorLib 0.9.6 使用 MPL-2.0，未修改其源码，源代码与对应发行版本：https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/tree/v0.9.6 。其独立传感器程序使用 NuGet 原始包；上游组件声明保留在 `LibreHardwareMonitor-THIRD-PARTY-NOTICES.txt`。

由该库引入的 NuGet 依赖包括 DiskInfoToolkit、HidSharp、RAMSPDToolkit-NDD、Mono.Posix.NETStandard，以及 Microsoft 的 System.IO.FileSystem.AccessControl、System.IO.Ports、System.Management 等依赖；使用实际还原版本各包原有许可证。Windows 导出包含独立 .NET 运行时，随发布输出保留其 LICENSE.txt 和 ThirdPartyNotices.txt。

PawnIO 由使用者按上游说明另行安装；GD Pal 不内置或自动安装驱动，不提供风扇调速。
