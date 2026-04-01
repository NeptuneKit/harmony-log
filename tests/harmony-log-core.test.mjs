import test from 'node:test';
import assert from 'node:assert/strict';
import { execSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { pathToFileURL } from 'node:url';

async function loadCoreModule() {
  const workdir = mkdtempSync(join(tmpdir(), 'harmony-log-test-'));
  const outfile = join(workdir, 'HarmonyLogCore.cjs');
  execSync(
    `npx --yes esbuild src/main/ets/HarmonyLogCore.ets --bundle --platform=node --format=cjs --loader:.ets=ts --outfile=${outfile}`,
    { cwd: process.cwd(), stdio: 'ignore' }
  );
  const mod = await import(pathToFileURL(outfile).href);
  return {
    mod,
    cleanup: () => rmSync(workdir, { recursive: true, force: true })
  };
}

test('bootstrap 只能初始化一次', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { LoggingSystem, Logger, HarmonyLogLevel } = mod;
  try {
    LoggingSystem.resetForTesting();
    Logger.setGlobalHandlers([]);

    LoggingSystem.bootstrap(() => ({
      minimumLevel: HarmonyLogLevel.TRACE,
      log() {}
    }));

    assert.equal(LoggingSystem.isBootstrapped(), true);
    assert.throws(() => {
      LoggingSystem.bootstrap(() => ({
        minimumLevel: HarmonyLogLevel.TRACE,
        log() {}
      }));
    }, /only be initialized once/);
  } finally {
    cleanup();
  }
});

test('bootstrap 工厂按 logger label 生成 handler', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { LoggingSystem, Logger, HarmonyLogLevel } = mod;

  try {
    LoggingSystem.resetForTesting();
    Logger.setGlobalHandlers([]);

    const seenLabels = [];
    const records = [];

    LoggingSystem.bootstrap((label) => {
      seenLabels.push(label);
      return {
        minimumLevel: HarmonyLogLevel.TRACE,
        log(record) {
          records.push(record);
        }
      };
    });

    const loggerA = Logger.logger('ModuleA');
    const loggerB = Logger.logger('ModuleB');
    loggerA.info('from-a');
    loggerB.info('from-b');

    assert.deepEqual(seenLabels, ['ModuleA', 'ModuleB']);
    assert.equal(records.length, 2);
    assert.equal(records[0].label, 'ModuleA');
    assert.equal(records[1].label, 'ModuleB');
  } finally {
    cleanup();
  }
});

test('日志调用点上下文会透传到 record', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { LoggingSystem, Logger, HarmonyLogLevel } = mod;

  try {
    LoggingSystem.resetForTesting();
    Logger.setGlobalHandlers([]);

    const records = [];
    LoggingSystem.bootstrap(() => ({
      minimumLevel: HarmonyLogLevel.TRACE,
      log(record) {
        records.push(record);
      }
    }));

    const logger = Logger.logger('Auth');
    logger.info(
      'login-start',
      { requestId: 'req-1' },
      'AuthService',
      'src/main/ets/Auth.ets',
      'login',
      88
    );

    assert.equal(records.length, 1);
    assert.equal(records[0].source, 'AuthService');
    assert.equal(records[0].file, 'src/main/ets/Auth.ets');
    assert.equal(records[0].function, 'login');
    assert.equal(records[0].line, 88);
  } finally {
    cleanup();
  }
});

test('formatRecord 会输出调用点上下文', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { Logger, HarmonyLogLevel } = mod;

  try {
    const text = Logger.formatRecord({
      timestamp: Date.now(),
      label: 'Auth',
      level: HarmonyLogLevel.ERROR,
      message: 'boom',
      metadata: { requestId: 'r-1' },
      source: 'AuthService',
      file: 'src/main/ets/Auth.ets',
      function: 'login',
      line: 101
    });

    assert.match(text, /source=AuthService/);
    assert.match(text, /file=src\/main\/ets\/Auth\.ets/);
    assert.match(text, /func=login/);
    assert.match(text, /line=101/);
  } finally {
    cleanup();
  }
});

test('metadata 支持数组和字典结构化输出', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { Logger, HarmonyLogLevel } = mod;

  try {
    const text = Logger.formatRecord({
      timestamp: Date.now(),
      label: 'Structured',
      level: HarmonyLogLevel.INFO,
      message: 'structured',
      metadata: {
        user: {
          id: 7,
          flags: ['a', 'b']
        },
        tags: ['core', 'align'],
        ok: true
      }
    });

    assert.match(text, /user=\{flags:\[a,b\],id:7\}/);
    assert.match(text, /tags=\[core,align\]/);
    assert.match(text, /ok=true/);
  } finally {
    cleanup();
  }
});

test('metadata 合并遵循 explicit 覆盖 base，undefined 删除键', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { LoggingSystem, Logger, HarmonyLogLevel } = mod;

  try {
    LoggingSystem.resetForTesting();
    Logger.setGlobalHandlers([]);

    const records = [];
    LoggingSystem.bootstrap(() => ({
      minimumLevel: HarmonyLogLevel.TRACE,
      log(record) {
        records.push(record);
      }
    }));

    const logger = Logger.logger('MergeCase');
    logger.setMetadata('requestId', 'base-1');
    logger.setMetadata('removeMe', 'to-delete');
    logger.setMetadata('ctx', { env: 'prod' });
    logger.info('merge', {
      requestId: 'override-2',
      removeMe: undefined,
      extra: [1, 2, 3]
    });

    assert.equal(records.length, 1);
    assert.deepEqual(records[0].metadata, {
      requestId: 'override-2',
      ctx: { env: 'prod' },
      extra: [1, 2, 3]
    });
    assert.equal(records[0].metadata?.removeMe, undefined);
  } finally {
    cleanup();
  }
});

test('setMetadata(undefined) 会移除键', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { Logger } = mod;

  try {
    const logger = Logger.logger('DeleteKey');
    logger.setMetadata('k', 'v');
    logger.setMetadata('k', undefined);
    assert.equal(logger.metadata.k, undefined);
    assert.equal(Object.prototype.hasOwnProperty.call(logger.metadata, 'k'), false);
  } finally {
    cleanup();
  }
});

test('MultiplexLogHandler 只转发到满足级别的子 handler', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { LoggingSystem, Logger, HarmonyLogLevel, MultiplexLogHandler } = mod;

  try {
    LoggingSystem.resetForTesting();
    Logger.setGlobalHandlers([]);

    const infoRecords = [];
    const errorRecords = [];

    const infoHandler = {
      minimumLevel: HarmonyLogLevel.INFO,
      log(record) {
        infoRecords.push(record);
      }
    };
    const errorHandler = {
      minimumLevel: HarmonyLogLevel.ERROR,
      log(record) {
        errorRecords.push(record);
      }
    };

    LoggingSystem.bootstrap(
      () => new MultiplexLogHandler([infoHandler, errorHandler])
    );

    const logger = Logger.logger('Mux');
    logger.info('info-only');
    logger.error('error-both');

    assert.equal(infoRecords.length, 2);
    assert.equal(errorRecords.length, 1);
    assert.equal(errorRecords[0].message, 'error-both');
  } finally {
    cleanup();
  }
});

test('MultiplexLogHandler 默认 minimumLevel 为子 handler 最小值', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { HarmonyLogLevel, MultiplexLogHandler } = mod;

  try {
    const multiplex = new MultiplexLogHandler([
      { minimumLevel: HarmonyLogLevel.WARNING, log() {} },
      { minimumLevel: HarmonyLogLevel.DEBUG, log() {} },
      { minimumLevel: HarmonyLogLevel.ERROR, log() {} }
    ]);
    assert.equal(multiplex.minimumLevel, HarmonyLogLevel.DEBUG);
  } finally {
    cleanup();
  }
});

test('设置 MultiplexLogHandler minimumLevel 会同步到底层 handler', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { HarmonyLogLevel, MultiplexLogHandler } = mod;

  try {
    const handlerA = { minimumLevel: HarmonyLogLevel.INFO, log() {} };
    const handlerB = { minimumLevel: HarmonyLogLevel.ERROR, log() {} };
    const multiplex = new MultiplexLogHandler([handlerA, handlerB]);

    multiplex.minimumLevel = HarmonyLogLevel.TRACE;

    assert.equal(handlerA.minimumLevel, HarmonyLogLevel.TRACE);
    assert.equal(handlerB.minimumLevel, HarmonyLogLevel.TRACE);
    assert.equal(multiplex.minimumLevel, HarmonyLogLevel.TRACE);
  } finally {
    cleanup();
  }
});

test('HarmonyLogNoOpHandler 丢弃日志且保持 minimumLevel 只读语义', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { LoggingSystem, Logger, HarmonyLogLevel, HarmonyLogNoOpHandler } = mod;

  try {
    LoggingSystem.resetForTesting();
    Logger.setGlobalHandlers([]);

    const noOp = new HarmonyLogNoOpHandler();
    const before = noOp.minimumLevel;
    noOp.minimumLevel = HarmonyLogLevel.TRACE;
    assert.equal(before, HarmonyLogLevel.CRITICAL);
    assert.equal(noOp.minimumLevel, HarmonyLogLevel.CRITICAL);

    LoggingSystem.bootstrap(() => noOp);
    const logger = Logger.logger('NoOp');
    logger.critical('drop-me');

    assert.ok(true);
  } finally {
    cleanup();
  }
});

test('LoggingSystem bootstrap metadataProvider 会自动注入日志', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { LoggingSystem, Logger, HarmonyLogLevel } = mod;

  try {
    LoggingSystem.resetForTesting();
    Logger.setGlobalHandlers([]);

    const records = [];
    LoggingSystem.bootstrap(
      () => ({
        minimumLevel: HarmonyLogLevel.TRACE,
        log(record) {
          records.push(record);
        }
      }),
      {
        get() {
          return {
            traceId: 't-1',
            env: 'prod'
          };
        }
      }
    );

    const logger = Logger.logger('Provider');
    logger.info('with-provider');

    assert.equal(records.length, 1);
    assert.deepEqual(records[0].metadata, {
      traceId: 't-1',
      env: 'prod'
    });
  } finally {
    cleanup();
  }
});

test('metadata 合并顺序为 base -> provider -> explicit', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { LoggingSystem, Logger, HarmonyLogLevel } = mod;

  try {
    LoggingSystem.resetForTesting();
    Logger.setGlobalHandlers([]);

    const records = [];
    LoggingSystem.bootstrap(
      () => ({
        minimumLevel: HarmonyLogLevel.TRACE,
        log(record) {
          records.push(record);
        }
      }),
      {
        get() {
          return {
            k: 'provider',
            providerOnly: 'yes',
            willDelete: 'provider-value'
          };
        }
      }
    );

    const logger = Logger.logger('Order');
    logger.setMetadata('k', 'base');
    logger.setMetadata('baseOnly', '1');
    logger.info('merge-order', {
      k: 'explicit',
      willDelete: undefined
    });

    assert.equal(records.length, 1);
    assert.deepEqual(records[0].metadata, {
      k: 'explicit',
      baseOnly: '1',
      providerOnly: 'yes'
    });
  } finally {
    cleanup();
  }
});

test('MDC metadataProvider 可注入上下文并支持清理', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { LoggingSystem, Logger, HarmonyLogLevel, MDC } = mod;

  try {
    LoggingSystem.resetForTesting();
    Logger.setGlobalHandlers([]);
    MDC.global.clear();
    MDC.global.set('requestId', 'r-1');
    MDC.global.set('uid', 42);

    const records = [];
    LoggingSystem.bootstrap(
      () => ({
        minimumLevel: HarmonyLogLevel.TRACE,
        log(record) {
          records.push(record);
        }
      }),
      MDC.metadataProvider()
    );

    const logger = Logger.logger('MDC');
    logger.info('mdc-log');
    assert.equal(records.length, 1);
    assert.deepEqual(records[0].metadata, {
      requestId: 'r-1',
      uid: 42
    });

    MDC.global.set('requestId', undefined);
    assert.equal(MDC.global.get('requestId'), undefined);
    MDC.global.clear();
    assert.deepEqual(MDC.global.metadata, {});
  } finally {
    cleanup();
  }
});

test('StreamLogHandler.standardOutput 输出到 console.info', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { StreamLogHandler, HarmonyLogLevel } = mod;

  const infoMessages = [];
  const errorMessages = [];
  const originalInfo = console.info;
  const originalError = console.error;
  console.info = (...args) => infoMessages.push(args.join(' '));
  console.error = (...args) => errorMessages.push(args.join(' '));

  try {
    const handler = StreamLogHandler.standardOutput('StreamOut');
    handler.minimumLevel = HarmonyLogLevel.TRACE;
    handler.log({
      timestamp: Date.now(),
      label: 'IgnoredByStreamLabel',
      level: HarmonyLogLevel.INFO,
      message: 'hello-stream',
      source: 'UnitTest'
    });

    assert.equal(infoMessages.length, 1);
    assert.equal(errorMessages.length, 0);
    assert.match(infoMessages[0], /StreamOut/);
    assert.match(infoMessages[0], /hello-stream/);
    assert.match(infoMessages[0], /\[UnitTest\]/);
  } finally {
    console.info = originalInfo;
    console.error = originalError;
    cleanup();
  }
});

test('StreamLogHandler.standardError 输出到 console.error', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { StreamLogHandler, HarmonyLogLevel } = mod;

  const infoMessages = [];
  const errorMessages = [];
  const originalInfo = console.info;
  const originalError = console.error;
  console.info = (...args) => infoMessages.push(args.join(' '));
  console.error = (...args) => errorMessages.push(args.join(' '));

  try {
    const handler = StreamLogHandler.standardError('StreamErr');
    handler.minimumLevel = HarmonyLogLevel.TRACE;
    handler.log({
      timestamp: Date.now(),
      label: 'Any',
      level: HarmonyLogLevel.ERROR,
      message: 'boom',
      source: 'UnitTest'
    });

    assert.equal(infoMessages.length, 0);
    assert.equal(errorMessages.length, 1);
    assert.match(errorMessages[0], /StreamErr/);
    assert.match(errorMessages[0], /boom/);
  } finally {
    console.info = originalInfo;
    console.error = originalError;
    cleanup();
  }
});

test('StreamLogHandler metadata 合并顺序为 handler -> provider -> record', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { StreamLogHandler, HarmonyLogLevel } = mod;

  const infoMessages = [];
  const originalInfo = console.info;
  console.info = (...args) => infoMessages.push(args.join(' '));

  try {
    const handler = StreamLogHandler.standardOutput('MergeLine', {
      get() {
        return {
          k: 'provider',
          providerOnly: '1',
          dropByRecord: 'x'
        };
      }
    });
    handler.minimumLevel = HarmonyLogLevel.TRACE;
    handler.setMetadata('k', 'handler');
    handler.setMetadata('handlerOnly', '1');
    handler.log({
      timestamp: Date.now(),
      label: 'Label',
      level: HarmonyLogLevel.INFO,
      message: 'line',
      source: 'Case',
      metadata: {
        k: 'record',
        dropByRecord: undefined
      }
    });

    assert.equal(infoMessages.length, 1);
    const line = infoMessages[0];
    assert.match(line, /k=record/);
    assert.match(line, /handlerOnly=1/);
    assert.match(line, /providerOnly=1/);
    assert.doesNotMatch(line, /dropByRecord=/);
  } finally {
    console.info = originalInfo;
    cleanup();
  }
});

test('低于 logger level 时 message/metadata 闭包不应求值', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { LoggingSystem, Logger, HarmonyLogLevel } = mod;

  try {
    LoggingSystem.resetForTesting();
    Logger.setGlobalHandlers([]);
    Logger.setCompileTimeMinimumLevel(HarmonyLogLevel.TRACE);

    const records = [];
    LoggingSystem.bootstrap(() => ({
      minimumLevel: HarmonyLogLevel.TRACE,
      log(record) {
        records.push(record);
      }
    }));

    const logger = Logger.logger('Lazy');
    logger.level = HarmonyLogLevel.ERROR;

    let messageEval = 0;
    let metadataEval = 0;
    logger.info(
      () => {
        messageEval += 1;
        return 'not-run';
      },
      () => {
        metadataEval += 1;
        return { k: 'v' };
      }
    );

    assert.equal(records.length, 0);
    assert.equal(messageEval, 0);
    assert.equal(metadataEval, 0);
  } finally {
    cleanup();
  }
});

test('低于 compileTimeMinimumLevel 时不记录日志且不求值', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { LoggingSystem, Logger, HarmonyLogLevel } = mod;

  try {
    LoggingSystem.resetForTesting();
    Logger.setGlobalHandlers([]);
    Logger.setCompileTimeMinimumLevel(HarmonyLogLevel.WARNING);

    const records = [];
    LoggingSystem.bootstrap(() => ({
      minimumLevel: HarmonyLogLevel.TRACE,
      log(record) {
        records.push(record);
      }
    }));

    const logger = Logger.logger('CompileCut');
    let evaluated = 0;
    logger.info(() => {
      evaluated += 1;
      return 'should-cut';
    });
    logger.warning('should-pass');

    assert.equal(evaluated, 0);
    assert.equal(records.length, 1);
    assert.equal(records[0].message, 'should-pass');
  } finally {
    cleanup();
  }
});

test('source 未显式传入时从 file 推断模块名', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { LoggingSystem, Logger, HarmonyLogLevel } = mod;

  try {
    LoggingSystem.resetForTesting();
    Logger.setGlobalHandlers([]);
    Logger.setCompileTimeMinimumLevel(HarmonyLogLevel.TRACE);

    const records = [];
    LoggingSystem.bootstrap(() => ({
      minimumLevel: HarmonyLogLevel.TRACE,
      log(record) {
        records.push(record);
      }
    }));

    Logger.logger('SourceInfer').info(
      'with-file',
      undefined,
      undefined,
      'src/main/ets/Auth/Login.ets'
    );

    assert.equal(records.length, 1);
    assert.equal(records[0].source, 'Auth');
  } finally {
    cleanup();
  }
});

test('Logger.copy 后修改副本不影响原 logger', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { Logger, HarmonyLogLevel } = mod;

  try {
    const original = Logger.logger('CopyCase');
    original.level = HarmonyLogLevel.INFO;
    original.setMetadata('k', 'v1');

    const copied = original.copy();
    copied.level = HarmonyLogLevel.ERROR;
    copied.setMetadata('k', 'v2');
    copied.setMetadata('extra', 'x');

    assert.equal(original.level, HarmonyLogLevel.INFO);
    assert.equal(copied.level, HarmonyLogLevel.ERROR);
    assert.equal(original.metadata.k, 'v1');
    assert.equal(copied.metadata.k, 'v2');
    assert.equal(original.metadata.extra, undefined);
  } finally {
    cleanup();
  }
});

test('InMemoryLogHandler 可收集与清理日志', async () => {
  const { mod, cleanup } = await loadCoreModule();
  const { Logger, HarmonyLogLevel, InMemoryLogHandler } = mod;

  try {
    const memory = new InMemoryLogHandler();
    memory.minimumLevel = HarmonyLogLevel.DEBUG;
    memory.setMetadata('service', 'test');
    memory.metadataProvider = {
      get() {
        return { provider: 'p1' };
      }
    };

    const logger = Logger.logger('InMemory');
    logger.handlers = [memory];
    logger.info('hello', { requestId: 'r1' });

    const entries = memory.getEntries();
    assert.equal(entries.length, 1);
    assert.equal(entries[0].message, 'hello');
    assert.deepEqual(entries[0].metadata, {
      service: 'test',
      provider: 'p1',
      requestId: 'r1'
    });

    memory.clear();
    assert.equal(memory.getEntries().length, 0);
  } finally {
    cleanup();
  }
});
