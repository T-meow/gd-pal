# PC 房间资源

三间房间源自本项目独立 UI 原型中的原创 SVG：`night-study.svg`（夜间书房）、`warm-bedroom.svg`（暖光卧室）、`rainy-lounge.svg`（雨夜客厅）。家具集中两侧，中央留作角色画面。SVG 同时用于背景与房间卡片缩略图，可单独替换缩略图。

## 添加房间

将资源放在本目录或其他正式资源目录，在 `catalog.json` 的 `rooms` 数组中追加条目，然后重新打开房间页。清单版本为 1。

| 字段 | 用途 |
| --- | --- |
| `id` | 唯一 ID，用于保存本地选择 |
| `name` | 中文房间名称 |
| `english` | 卡片的小标题，可省略 |
| `kind` | `image` 或 `scene3d` |
| `resource` | 背景的 `res://` 资源路径 |
| `thumbnail` | 卡片缩略图路径，使用 Texture2D 资源 |
| `caption` | 通话画面的简短氛围文字 |
| `description` | 房间卡片说明 |
| `mood` | 卡片底部的氛围关键词 |

`image` 通过 TextureRect 等比例填充背景，可使用 SVG 或 Godot 支持的图片资源。标题、聊天和角色不绘制在图片里。

## 3D 扩展

`PalRoomStage` 已提供 `scene3d` 分支：`resource` 指向一个以 Node3D 为根且包含 Camera3D 的 `.tscn`。场景自身提供相机、灯光、环境和家具；宿主为它创建独立的 World3D 和 SubViewport，并在页面隐藏时停止渲染。多个相机时使用遍历到的首个相机。缩略图仍应另配图片。

当前只交付三个 SVG 房间，没有实际 3D 房间。背景宿主与角色视口独立，尚不共享灯光、深度遮挡或物理交互；正式制作 3D 房间时再对齐场景尺度和相机。无需将聊天界面写进房间场景。

切换背景不调用剧情或聊天 API，不改变会话、世界资料或角色存档。清单通过 FileAccess 读取，`export_presets.cfg` 已显式包含 `assets/rooms/catalog.json`。原型目录仍被 `.gdignore` 排除。
