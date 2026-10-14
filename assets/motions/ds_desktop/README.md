默认角色 DS 的桌面派生动作，目标为 `assets/DS-desktop.vrm`。

运行时仅加载 DS 模型。原动作数据及其授权证据继续保存在 `../npc/`，旧角色模型及其专用桌面动作已移除。

DS 与原动作骨架的标准人形局部参考旋转一致。`PalMotionLibrary.source_library(true)` 为 DS 复制原动作数据，移除 DS 不存在的 LeftEye / RightEye 轨道，按两套骨架的 motion_scale 和髋部参考位置修正位移。适配结果缓存并共享；角色骨架与播放进度仍各自独立。模型指纹变化时退回基础互动，不把未知模型当成已适配角色。

`desktop_wave`、`desktop_pickup` 和 `edge_rest` 使用 DS 实际骨架重新烘焙，分别用于掌心朝向用户的挥手、双膝弯曲的提起和窗口／任务栏趴靠。运行 `tools/build-desktop-motions.gd` 会使用 `PalVrmLoader.DEFAULT_AVATAR` 生成本目录。

`edge_rest` 已将原俯卧姿势的高抬腿改为大腿放平、小腿轻微抬起，脚尖向后下方伸展，保留轻微左右差异。桌面自动散步由宿主传入实际方向，表现器将镜头平滑转到左右 75°，保持构图中心和缩放；停止、互动或返回大厅后恢复正面。

动作来源、哈希与许可保留在 `../npc/manifest.json` 和 `../npc/licenses/`；派生动作继承原素材限制。DS 模型授权独立于动画授权。姿势、服装接触和原生桌面效果由用户手动确认。
