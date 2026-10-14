# 轻量聊天

`ChatService.cs` 处理聊天、v1 本地存储和手动设定，`ChatService.Connection.cs` 处理聊天连接与可选 HTTP TTS。只依赖 .NET 和 Godot，不引用外部角色核心。

聊天设置直接显示思考强度，支持服务默认与各接口的强度选项。`ChatProviders.cs` 提供 DeepSeek、OpenCode Console / Zen、OpenCode Go、OpenRouter、OpenAI、Anthropic、Gemini 和自定义地址预设。`ChatProtocol.cs` 统一构造 Chat Completions、Responses、Messages、Gemini 请求及解析流式/普通返回，聊天、连接测试与 AI 整理共用。选择服务默认时不发送思考参数；仅 Messages 接口要求设置输出额度，其他接口沿用服务默认额度。

OpenCode 按模型选择 API 格式，也可在高级设置手动覆盖。接口依据：[OpenCode Inference](https://opencode.ai/v2/docs/console/api/inference/)、[OpenCode Go](https://opencode.ai/v2/docs/console/go/)、[OpenAI reasoning](https://developers.openai.com/api/docs/guides/reasoning)。

`manual_context_panel.gd` 为记忆和世界设定共用的文本编辑器；人设在伙伴档案中编辑。`summary_panel.gd` 与 `ChatService.Summary.cs` 处理按需 AI 整理：模型自动归类候选条目，用户编辑、加入或忽略；确认时原子追加到最新字段，并按审核状态与正文去重。`package_panel.gd`、`PackageCodec.cs` 与 `ChatService.Packages.cs` 处理数据包预览、导入和导出。

每位伙伴的资料位于 `user://companion/<profile_id>/`。`profile.json` 只保存名字、朗读开关和当前会话等 v1 元数据；`ProfileDocuments.cs` 分别管理 `persona.md`（人设）、`memory_long_term.md`（长期记忆）、`memory_active.md`（活跃记忆）和 `world.md`（世界设定）。`persona_before_summary.md` 保留本次 AI 整理追加前的人设。发送聊天请求和生成整理候选前重新读取文档，再组合注入；普通会话保存不重写文档。编辑界面只提交改过的字段，检测到外部修改时提示重新载入。

记忆页面提供长期／活跃两个标签页和打开当前文件、重新载入入口。AI 整理把稳定偏好、重要经历和长期约定归入长期记忆，把当前场景、临时状态和待办事项归入活跃记忆；候选正文优先 1～2 句、40～100 字，不裁切模型原文。没有明确归属的候选暂放活跃记忆，仍需用户确认。

AI 整理可勾选「同时整理已有记忆文件」。先分批提取所选多段对话中的新增信息，最后额外调用模型统一整理已有长期记忆、活跃记忆、世界设定与全部候选，生成三份完整合并稿。也可不选对话，只整理已有文件。界面提供生成时原文与可编辑合并稿对照、变更说明和待核对冲突；手写人设不参与全文替换，人设建议仍逐条审核。合并期间不会写入设定，点击「应用合并稿」才保存三份文档，并先备份到伙伴目录下的 `backups/memory-merge-*`。生成期间文件有外部修改时拒绝覆盖，要求重新生成；应用后仍按原流程清空已完成列表。选项会保留到下次生成。

`agent_panel.gd` 与 `ChatService.Work.cs` 桥接 `scripts/agents/` 中抽取的 ACP 实现。任务、日志和额外权限独立于聊天；一条任务队列，同一时刻执行一个任务。所有 Godot 信号回到主线程，并按伙伴与请求 ID 匹配结果。

`conversation_panel.gd`、`history_panel.gd` 负责对话和历史。`performance_queue.gd` 只处理当前回复的本地动作和朗读，不写记忆或角色设定。

每轮仅发送一次聊天请求。中文和英文圆括号中的内容统一视作动作/旁白，不是用户或角色的台词，旁白不朗读。输入框的动作按钮会插入括号并把光标留在其中，选中文字时会包裹选区；仍按原来的发送方式提交。

空输入时发送按钮显示“继续”。继续操作只追加角色回复，控制指令仅在请求时发送，不作为用户发言写进聊天、记忆或整理素材。回复在 v1 消息中记录 `is_continuation`，重试继续回复不会删除更早的角色回复。

新建空会话只在当前运行中存在，有实际文字或动作后才写入记录；仅有空白或尚无正文的继续回复不持久化。历史、整理素材和导出均排除空会话。

聊天支持 PNG、JPEG、静态 WebP 图片：Windows 和 Android 使用系统文件选择器，桌面输入框支持 Ctrl+V / Cmd+V 和右键「粘贴图片」（截图或复制的图片像素）。手机暂不接图片剪贴板。每条最多 4 张，可单独发图；文字和图片都为空才是「继续」。发送前可预览、移除，聊天内可点击放大。草稿附件按伙伴及会话隔离，处理图片时暂不可发送，回复失败会在空草稿中恢复附件。

`ChatService.Images.cs` 通过 Godot FileAccess 读取 Android content:// URI，逐张后台处理图片；源文件上限 20 MB、3200 万像素，JPEG 按 EXIF 方向纠正，归一化到最长边 1600、每张不超过 2 MB，生成 240 像素缩略图。图片位于伙伴目录的 `images/`，v1 消息只保存文件引用和尺寸。`ChatImages.cs` 构造最多携带最近 4 张图片的请求，较早图片明确标注未附带；纯图片消息也保留。四种 API 格式各自转换图片内容，不改变用户所选模型；模型及接入服务须支持识图。

对话 ZIP 包含二进制图片及校验信息，导入重新分配图片文件名并生成缩略图。应用内 Markdown 使用相对图片链接；Android 导出含图会话时使用 ZIP，纯文字仍导出 Markdown。AI 整理继续使用文字及伙伴的识图回复。接口格式依据：[OpenAI images](https://developers.openai.com/api/docs/guides/images-vision)、[Claude vision](https://platform.claude.com/docs/en/build-with-claude/vision)、[Gemini image inputs](https://ai.google.dev/gemini-api/docs/generate-content/image-understanding)。
