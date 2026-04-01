# harmony-log

`harmony-log` 是一个面向 HarmonyOS 的日志库，接口风格对齐 `apple/swift-log`，支持：

- `Logger` 值语义式使用（`copy()`）
- `LoggingSystem.bootstrap(...)` 全局一次性初始化
- 结构化 metadata（标量/数组/字典）
- `MetadataProvider` / `MDC` 上下文注入
- 多后端组合（`MultiplexLogHandler`）
- 标准后端：`Console`、`HiLog`、`Stream`、`InMemory`、`NoOp`
- 惰性消息与日志级别裁剪

## 安装

本库为 Harmony HAR 工程，直接作为依赖引入并从 `Index.ets` 导出使用：

```ts
import { Logger, HarmonyLogLevel } from 'harmony-log';
```

## 快速开始

```ts
import { Logger, HarmonyLogLevel } from 'harmony-log';

const logger = Logger.logger('Order');
logger.level = HarmonyLogLevel.DEBUG;

logger.info('create order', { orderId: 1001 });
logger.error(
  'create failed',
  { orderId: 1001, reason: 'network' },
  'OrderService',
  'src/main/ets/order/OrderService.ets',
  'createOrder',
  42
);
```

## 全局初始化（bootstrap）

`bootstrap` 只能调用一次；后续再次调用会抛错（与 `swift-log` 语义一致）。

```ts
import { LoggingSystem, Logger, HarmonyLogLevel } from 'harmony-log';

LoggingSystem.bootstrap((label: string) => ({
  minimumLevel: HarmonyLogLevel.INFO,
  log(record) {
    console.info(`[${label}] ${record.message}`);
  }
}));

Logger.logger('Network').info('request sent');
```

## Metadata 与合并规则

- 支持结构化值：`string | number | boolean | null | array | dictionary`
- 合并顺序：
  - `logger metadata`
  - `metadata provider`
  - `log-site metadata`
- 同 key 后者覆盖前者
- 值为 `undefined` 时表示删除该 key

## MetadataProvider 与 MDC

```ts
import { LoggingSystem, Logger, MDC, HarmonyLogLevel } from 'harmony-log';

MDC.global.set('requestId', 'req-1001');
MDC.global.set('userId', 42);

LoggingSystem.bootstrap(
  () => ({
    minimumLevel: HarmonyLogLevel.INFO,
    log(record) {
      console.info(record.metadata);
    }
  }),
  MDC.metadataProvider()
);

Logger.logger('Checkout').info('start');
```

## 内置 Handler

### ConsoleLogHandler
- 输出到 `console.debug/info/warn/error`

### HiLogHandler
- 输出到 Harmony `hilog`
- 默认 domain: `0xD001`

### StreamLogHandler
- `standardOutput(label)` / `standardError(label)`
- 适合统一文本流格式输出

```ts
import { StreamLogHandler, Logger, HarmonyLogLevel } from 'harmony-log';

const stream = StreamLogHandler.standardOutput('App');
stream.minimumLevel = HarmonyLogLevel.DEBUG;
stream.setMetadata('service', 'checkout');

Logger.setGlobalHandlers([stream]);
```

### MultiplexLogHandler
- 组合多个 handler
- 会按各子 handler 的 `minimumLevel` 分发

```ts
import {
  Logger,
  MultiplexLogHandler,
  ConsoleLogHandler,
  HiLogHandler
} from 'harmony-log';

Logger.setGlobalHandlers([
  new MultiplexLogHandler([
    new ConsoleLogHandler(),
    new HiLogHandler(0xD002)
  ])
]);
```

### InMemoryLogHandler
- 用于测试、缓冲和调试

```ts
import { InMemoryLogHandler, Logger } from 'harmony-log';

const memory = new InMemoryLogHandler();
Logger.setGlobalHandlers([memory]);

Logger.logger('Test').info('hello');
console.info(memory.getEntries());
memory.clear();
```

### HarmonyLogNoOpHandler
- 丢弃全部日志（压测或静默场景）

```ts
import { Logger, HarmonyLogNoOpHandler } from 'harmony-log';
Logger.setGlobalHandlers([new HarmonyLogNoOpHandler()]);
```

## 自定义后端

实现 `HarmonyLogHandler` 即可接入你自己的日志后端（例如远程上报）：

```ts
import {
  HarmonyLogHandler,
  HarmonyLogLevel,
  HarmonyLogRecord,
  Logger
} from 'harmony-log';

class RemoteLogHandler implements HarmonyLogHandler {
  minimumLevel: HarmonyLogLevel = HarmonyLogLevel.WARNING;
  private queue: HarmonyLogRecord[] = [];

  log(record: HarmonyLogRecord): void {
    if (record.level < this.minimumLevel) {
      return;
    }
    this.queue.push(record);

    if (this.queue.length >= 20 || record.level >= HarmonyLogLevel.ERROR) {
      this.flush();
    }
  }

  private flush(): void {
    const batch = [...this.queue];
    this.queue = [];
    // TODO: 替换为真实网络上报逻辑
    // uploadLogs(batch)
    console.info(`[RemoteLogHandler] upload ${batch.length} logs`);
  }
}

// 方案 1：全局注册
Logger.addGlobalHandler(new RemoteLogHandler());
```

只给某个 logger 使用时：

```ts
const logger = Logger.logger('Payment');
logger.handlers = [new RemoteLogHandler()];
```

## 惰性消息与级别裁剪

消息和 metadata 支持闭包形式，未命中级别时不会求值：

```ts
import { Logger, HarmonyLogLevel } from 'harmony-log';

Logger.setCompileTimeMinimumLevel(HarmonyLogLevel.WARNING);

const logger = Logger.logger('Perf');
let heavyCall = 0;
logger.info(() => {
  heavyCall += 1;
  return 'expensive';
});
// heavyCall 仍为 0
```

## Logger 拷贝语义

```ts
import { Logger, HarmonyLogLevel } from 'harmony-log';

const a = Logger.logger('Copy');
a.level = HarmonyLogLevel.INFO;
a.setMetadata('key', 'v1');

const b = a.copy();
b.level = HarmonyLogLevel.ERROR;
b.setMetadata('key', 'v2');

// a 与 b 的 level/metadata 互不影响
```

## 测试

```bash
node --test tests/harmony-log-core.test.mjs
```

当前测试覆盖：
- bootstrap 单次约束
- metadata 合并/删除
- provider/MDC 注入
- multiplex/no-op/stream/in-memory 行为
- 惰性求值与级别裁剪
- source 推断与 copy 语义
