# 参考项目：apple/swift-log

- 仓库地址：https://github.com/apple/swift-log
- 参考目的：作为 `harmony-log` 的 API 设计与行为语义对齐基线
- 对齐范围：Logger API、LogHandler 协议、Metadata 语义、全局 bootstrap、组合 handler、测试基线
- 对照快照：`swift-log` @ `8c0f217`（2026-04-01 拉取）

## 当前对齐现状（概要）

已具备：
- 日志级别：`trace/debug/info/notice/warning/error/critical`
- 基础 Logger：按级别日志方法、全局 handler、logger 级 metadata
- 可插拔 handler：`HarmonyLogHandler` + 内置 `ConsoleLogHandler`/`HiLogHandler`

主要未对齐：
- `LoggingSystem.bootstrap` 一次性全局工厂机制与 metadataProvider 注入
- 结构化 `MetadataValue`（字符串/数组/字典/可插值）
- `LogEvent` 调用点上下文（`source/file/function/line`）
- `MultiplexLogHandler` 标准语义（effective log level/metadata 合并规则）
- `SwiftLogNoOpLogHandler`、`StreamLogHandler` 等标准后端语义
- 编译期裁剪（`MaxLogLevel*`）
- MDC / MetadataProvider 上下文注入能力
- 完整测试矩阵（value semantics、autoclosure 惰性求值、并发安全等）

## 建议优先级

1. 先对齐 `LoggingSystem.bootstrap` + `LogEvent` 调用点信息
2. 再补 `MetadataValue` 结构化能力与 metadata 合并规则
3. 再实现 `MultiplexLogHandler` 与 NoOp Handler
4. 最后补齐测试矩阵并考虑编译期 log-level 裁剪
