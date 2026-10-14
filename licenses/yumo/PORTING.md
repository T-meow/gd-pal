# Yumo 源码移植

来源：D:/Projects/yumo 的 Yumo.Core 0.2.0，MIT 许可证见本目录 LICENSE。

- scripts/agents/AcpAgentConnector.cs、WorkCoordinator.cs、WorkModels.cs：来自 Work/ 同名文件，移除内置文件执行器、记忆与作品连接，保留外部 ACP、授权、任务队列和生命周期。
- scripts/conversation/PackageCodec.cs：改编 ConversationPackage.cs、ChatEngine.Export.cs 的 v1 清单、ZIP 路径与大小校验、JSON/Markdown 及内容哈希逻辑。
- scripts/conversation/ChatService.Summary.cs：改编 AuthoringService.cs 的素材选择、分批生成、来源约束与确认后应用流程，目标简化为三个文本字段。

移植代码仅依赖 .NET。构建不引用 Yumo 包、工程、知识库或 YamlDotNet。
