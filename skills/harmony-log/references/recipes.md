# Recipes

## Multiplex 输出

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

## Stream 输出

```ts
import { StreamLogHandler, Logger, HarmonyLogLevel } from 'harmony-log';

const stream = StreamLogHandler.standardOutput('App');
stream.minimumLevel = HarmonyLogLevel.DEBUG;
Logger.setGlobalHandlers([stream]);
```

## InMemory 测试

```ts
import { InMemoryLogHandler, Logger } from 'harmony-log';

const memory = new InMemoryLogHandler();
Logger.setGlobalHandlers([memory]);
Logger.logger('Test').info('hello');
console.info(memory.getEntries());
memory.clear();
```
