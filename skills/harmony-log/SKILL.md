---
name: harmony-log
description: 使用 harmony-log（HarmonyOS 日志库）的安装、初始化、结构化日志、MDC 上下文和多 Handler 组合实践。用户提到“harmony-log 怎么用”“如何接入日志库”“如何初始化 LoggingSystem”“如何添加 metadata/MDC”“如何组合 Console/HiLog/Stream/InMemory handler”时使用。
---

# Harmony Log Usage

按以下顺序指导并输出可直接复制的代码。

## 1. 安装与导入

执行安装命令：

```bash
ohpm install harmony-log
```

在 ArkTS 中导入：

```ts
import { Logger, HarmonyLogLevel } from 'harmony-log';
```

## 2. 基础使用

创建 logger，设置级别，输出结构化字段：

```ts
const logger = Logger.logger('App');
logger.level = HarmonyLogLevel.INFO;
logger.info('startup', { env: 'prod', build: 1100 });
```

## 3. 全局初始化

需要统一行为时，先执行 `LoggingSystem.bootstrap(...)`，且只调用一次。

```ts
import { LoggingSystem, Logger, HarmonyLogLevel } from 'harmony-log';

LoggingSystem.bootstrap((label: string) => ({
  minimumLevel: HarmonyLogLevel.INFO,
  log(record) {
    console.info(`[${label}] ${record.message}`);
  }
}));
```

## 4. MDC 上下文注入

需要请求链路字段时，使用 `MDC` 与 `metadataProvider`：

```ts
import { LoggingSystem, MDC } from 'harmony-log';

MDC.global.set('requestId', 'req-1001');
MDC.global.set('userId', 42);

LoggingSystem.bootstrap(
  () => ({
    minimumLevel: 1,
    log(record) {
      console.info(record.metadata);
    }
  }),
  MDC.metadataProvider()
);
```

## 5. Handler 组合

需要多路输出时，优先使用 `MultiplexLogHandler` 组合：

- Console：开发调试
- HiLog：系统日志
- Stream：统一文本流
- InMemory：测试断言

更多可复用片段：见 [references/recipes.md](references/recipes.md)。

## 6. 输出约束

- 始终给出最小可运行示例。
- 明确说明 `bootstrap` 只能初始化一次。
- 同时给出安装命令与 import 语句，避免只写其一。
