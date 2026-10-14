Godot MCP 运行时桥接

来源：[@tugcantopaloglu/godot-mcp](https://github.com/tugcantopaloglu/godot-mcp)，本机版本 3.1.0；MIT 许可随本目录保存，来源提交和脚本哈希见 `provenance.json`。

项目通过 `McpInteractionServer` Autoload 加载桥接。此副本保留本机集成修改：仅 debug 构建且环境变量 `GODOT_MCP_ENABLED=1` 时监听回环地址。默认端口为 `9090`，可通过 `GODOT_MCP_PORT` 指定 `1024–65535` 内的端口。正常 F5 运行不开放监听；不需要在编辑器的插件列表里勾选它。

Codex 已有全局 Godot MCP 服务，项目不再创建重复服务。运行项目工具会隔离用户数据，运行时工具通过这份桥接读写场景。使用方法和验证入口见 [MCP 接入说明](/E:/Projects/gd-pal/docs/mcp-setup.md)。
