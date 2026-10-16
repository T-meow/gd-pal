# PC 性能监控：方案评估与 UI 草案

日期：2026-10-16。范围：Windows 桌宠与大厅；本轮为资料评估和 SVG 设计，尚未安装监控库、驱动或接入实时数据。图中硬件名称和读数均为示例。

建议采用 **Windows／.NET 基础采集 + LibreHardwareMonitor 温度与风扇 + 共用 C# 数据服务**。自己写采样、统计口径和界面适配；复用现成的系统接口与传感器支持。温度和风扇纳入首轮实现目标，具体可读项目由硬件、驱动及权限决定。

## 开源方案比较

| 方案 | 质量与适用范围 | 接入代价／限制 | 本项目判断 |
| --- | --- | --- | --- |
| [LibreHardwareMonitorLib](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor) | 现成 C# 传感器库；覆盖 Intel／AMD CPU、NVIDIA／AMD／Intel GPU、主板、存储、网卡；包含温度、负载、风扇等。查询时最新正式发行页为 [v0.9.6](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/tag/v0.9.6)，仍有硬件支持更新。 | MPL-2.0，另有第三方组件；部分传感器需要管理员权限与底层驱动。传感器名称、数量、可用性随设备变化。 | **温度／风扇首选**，能明显减少厂商适配工作。基础占用率单独采集，减少对传感器环境的依赖。 |
| [Hardware.Info](https://github.com/Jinjinov/Hardware.Info) | MIT；.NET Standard 2.0；跨平台硬件清单及部分动态指标。查询时正式版本为 [110.0.0.1](https://github.com/Jinjinov/Hardware.Info/releases/tag/v110.0.0.1)。 | Windows 依赖 WMI；公开接口偏硬件清单。CPU／网络刷新有采样等待参数，README 还记录了裁剪与 PerformanceCounter 相关限制。没有看到可一次满足本需求的跨厂商 GPU、温度和风扇监控接口。 | 不作为实时监控主干；将来需要详细硬件档案时再考虑。 |
| [Vanara](https://github.com/dahall/Vanara) | MIT；按 Windows DLL 拆分的 C# P/Invoke 封装。[PDH 包](https://www.nuget.org/packages/Vanara.PInvoke.Pdh/)包含计数器读取、语言无关计数器与句柄管理相关接口。 | 它是接口封装，采样、GPU 聚合、网卡选择和缺失状态仍须自己实现；仅适用于 Windows。 | **建议复用 PDH 封装**，按需引入；不拉整个 API 集合。 |
| 自写全部采集／硬件访问 | 简单系统指标可以用少量代码完成。 | 自行覆盖 CPU 温度、主板 Super I/O、嵌入式控制器、各厂商 GPU 和风扇，维护成本远高于 UI 本身。 | 只写业务采集层，不自研传感器驱动或厂商适配库。 |

以上是官方文档、发行记录与项目结构的静态评估，不是实机兼容性或性能跑分。当前工程是 Godot 4.8 dev7、C# `net10.0`，具备直接接入 C# 库的条件；具体包版本的构建与导出兼容性留到实现阶段确认。

## 指标与统计口径

| 指标 | 建议来源 | 展示／处理规则 |
| --- | --- | --- |
| CPU 占用 | Windows `GetSystemTimes`，必要时 PDH | 两次采样的 `1 - Δidle / (Δkernel + Δuser)`。Kernel 已包含 idle。超过 64 个逻辑处理器时不能直接把单处理器组结果当全机，改用覆盖全机的计数器方案。与任务管理器的频率加权口径可能不同。 |
| 物理内存 | `GlobalMemoryStatusEx` | 显示已用／总量与百分比；已用 = 总物理内存 − 可用物理内存，不把提交量当物理占用。 |
| GPU 占用 | PDH 的 GPU Engine 计数器 | 按适配器 LUID、物理 GPU、引擎标识归组，先聚合同一引擎的进程实例，再取该 GPU 最忙引擎。不能把所有引擎相加，也不能只取一个进程的最大值。允许选择显卡。 |
| 显存 | GPU Adapter Memory 计数器 + 适配器容量信息 | 使用整张卡的专用显存占用；共享显存另列。不要累加各进程显存；集显不虚构独立显存容量。 |
| 下载／上传 | `.NET NetworkInterface.GetIPStatistics()` | 字节差除以真实经过时间，显示 MiB/s 或 KiB/s。默认选择当前路由对应的活动接口，可手选网卡；避免把 VPN、虚拟网卡与物理网卡重复累计。网卡链路速率不等于互联网带宽，不默认提供“宽带占用百分比”。 |
| CPU 温度 | LibreHardwareMonitor 温度传感器 | 优先已识别的 CPU Package／Tdie 等合适来源，保留来源名称；不要把主板温度或 ACPI 热区误标为 CPU 温度。无法可靠映射时允许选择传感器。 |
| GPU 温度 | LibreHardwareMonitor GPU 温度传感器 | 默认核心温度；热点、显存温度如可用则放详情，不能混为同一个读数。 |
| 风扇转速 | LibreHardwareMonitor GPU／主板／控制器传感器 | 区分 CPU、GPU、机箱；主板泛称 Fan #1 不直接猜成 CPU 风扇，允许绑定与重命名。RPM 与转速百分比分开；只有百分比时不换算虚假的 RPM。 |
| 磁盘活动／读写 | PDH PhysicalDisk | 默认显示选定磁盘的活动时间和读写速率；不要用磁盘容量占用代替 IO 活跃度。 |

微软依据：[CPU 时间](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getsystemtimes)、[物理内存](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-globalmemorystatusex)、[GPU 引擎与显存口径](https://devblogs.microsoft.com/directx/gpus-in-the-task-manager/)、[接口字节计数](https://learn.microsoft.com/en-us/dotnet/api/system.net.networkinformation.ipinterfacestatistics?view=net-10.0)。

PDH 使用 [PdhAddEnglishCounter](https://learn.microsoft.com/en-us/windows/win32/api/pdh/nf-pdh-pdhaddenglishcounterw) 处理中文／英文系统差异，通配实例按文档枚举与更新，并检查每条读数的状态。采样默认 1 秒，可选 2／5 秒；微软说明[性能计数器不适合高于每秒一次的采集](https://learn.microsoft.com/en-us/windows/win32/perfctrs/about-performance-counters)。

## 温度与风扇的接入边界

新版 LibreHardwareMonitor 的部分底层读数依赖 PawnIO。[上游维护者说明](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/discussions/2149)：缺少 PawnIO 时库仍可启动，但很多传感器无法提供数据。因此“装了 NuGet 包”不代表所有温度和风扇就都可用，尤其是笔记本机箱风扇。

传感器读取采用独立 helper 进程，以便隔离硬件读取阻塞，并在确实需要时仅提升该 helper 的权限。桌宠主进程保持普通权限。默认读取当前能提供的数据；需要额外访问条件时，在“温度与风扇设置”显示具体原因和用户主动启用入口。驱动安装属于后续明确操作，本轮未执行。该功能只读取状态，不调用风扇控制接口。

首次集成时只启用需要的 CPU、GPU、主板／控制器类别，硬件列表缓存，避免每秒重新打开／扫描所有硬件。传感器与基础指标分别容错；helper 失败时，CPU、内存、网速等基础视图仍可用。第三方声明按实际引入的库与驱动分别保留原许可证。

## 项目接入建议

沿用现有 C# 服务 + GDScript 界面的结构，在根场景放置一个 `PcMonitorService`，与 `ChatService` 类似。后台生成不可变快照，主线程再更新 Godot 控件；大厅、桌宠以及多只桌宠共享同一次采样。Windows Provider 与空 Provider 分离，Android 不加载 Windows 库或显示 PC 监控入口。

拟新增 `scripts/monitoring/` 放服务、快照、Windows 采集与传感器 helper 协议。`scripts/app/app.gd` 负责生命周期和导航，`companion_hall.gd` 加“性能”标签；桌宠由 `desktop_pet_window.gd` 关联悬浮卡。悬浮卡宜使用独立无边框小窗，跟随角色并自动避开屏幕边缘，避免扩大角色窗口后影响现有贴边与拖动。卡片、角色和空白区域分别处理点击穿透。

快照含时间戳、设备 ID、来源、单位及 `valid / warming_up / unavailable / permission_required / stale / error` 状态。首轮差分、恢复休眠、网卡切换或计数器归零时重新建立基线；没有数据用 `—`，有效的零负载、风扇停转才显示 `0`。单项失败不清空其他指标；超过三个采样周期未更新则标记“数据已过期”，断开曲线，避免把旧数据伪装成当前值。

内存只保留最近 60 秒趋势。所有监控视图关闭且未启用提醒时停止采样；提醒开启则按配置继续。提醒基于本地持续时间和阈值判断，无须调用聊天模型；高温阈值按设备／传感器配置，避免给所有 CPU 套用同一个“安全温度”。偏好继续存 v1，只保存开关、选定设备和界面位置，不写入监控历史。

## SVG 设计

输出目录：`D:/Projects/gd-pal/output/performance-monitor-design/`。

| 文件 | 设计内容 |
| --- | --- |
| `desktop-compact.svg` | 桌宠旁的简洁卡：CPU／内存／GPU、CPU／GPU 温度、上下行网速；工具栏一键展开。 |
| `desktop-expanded.svg` | 展开卡：占用、最近 60 秒趋势、温度、CPU／GPU 风扇、网速、显存／磁盘，以及大厅详情入口。 |
| `hall.svg` | 大厅新增“性能”页：四个主指标、可切换趋势、温度与散热、网卡与显卡选择、显存／磁盘；保留伙伴和返回通话入口。 |

颜色沿用 `PalUi` 的深蓝灰纸面、浅蓝主色，辅以柔和绿／紫／暖黄区分指标。状态除了颜色，还显示文字；风扇未知的样例为“— 未提供”。实际界面继续响应已有浅色／自定义主题。SVG 为静态草案，按钮不执行操作；角色使用现有立绘的缩小嵌入，UI 形状、文字与曲线均为可编辑矢量。

实现顺序：先贯通共享基础采样与两种视图，再接入温度／风扇 helper、映射与缺失状态，最后接提醒及自定义项目。后续实机重点人工观察 NVIDIA／AMD／Intel、休眠恢复、切换网卡、缺少传感器与普通权限场景；本轮没有执行项目构建或测试。
