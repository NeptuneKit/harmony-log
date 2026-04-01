import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  HarmonyLogHandler,
  HarmonyLogLevel,
  HarmonyLogMetadataProvider,
  InMemoryLogEntry,
  InMemoryLogHandler,
  HarmonyLogNoOpHandler,
  MDC,
  MDCStore,
  StreamLogHandler,
  HarmonyLogMetadata,
  HarmonyLogMetadataValue,
  HarmonyLogRecord,
  Logger
} from './HarmonyLogCore';

export {
  HarmonyLogHandler,
  HarmonyLogLevel,
  HarmonyLogMetadataProvider,
  InMemoryLogEntry,
  InMemoryLogHandler,
  HarmonyLogNoOpHandler,
  MDC,
  MDCStore,
  StreamLogHandler,
  HarmonyLogMetadata,
  HarmonyLogMetadataValue,
  HarmonyLogRecord,
  MultiplexLogHandler
} from './HarmonyLogCore';
export { Logger, LoggingSystem } from './HarmonyLogCore';

export class ConsoleLogHandler implements HarmonyLogHandler {
  minimumLevel: HarmonyLogLevel = HarmonyLogLevel.TRACE;

  log(record: HarmonyLogRecord): void {
    if (record.level < this.minimumLevel) {
      return;
    }
    const output = Logger.formatRecord(record);
    if (record.level >= HarmonyLogLevel.ERROR) {
      console.error(output);
      return;
    }
    if (record.level >= HarmonyLogLevel.WARNING) {
      console.warn(output);
      return;
    }
    if (record.level >= HarmonyLogLevel.INFO) {
      console.info(output);
      return;
    }
    console.debug(output);
  }
}

export class HiLogHandler implements HarmonyLogHandler {
  minimumLevel: HarmonyLogLevel = HarmonyLogLevel.INFO;
  domain: number;

  constructor(domain: number = 0xD001) {
    this.domain = domain;
  }

  log(record: HarmonyLogRecord): void {
    if (record.level < this.minimumLevel) {
      return;
    }
    const output = Logger.formatRecord(record);
    const tag = Logger.safeTag(record.label);
    if (record.level >= HarmonyLogLevel.ERROR) {
      hilog.error(this.domain, tag, '%{public}s', output);
      return;
    }
    if (record.level >= HarmonyLogLevel.WARNING) {
      hilog.warn(this.domain, tag, '%{public}s', output);
      return;
    }
    hilog.info(this.domain, tag, '%{public}s', output);
  }
}

Logger.setGlobalHandlers([new ConsoleLogHandler(), new HiLogHandler()]);
