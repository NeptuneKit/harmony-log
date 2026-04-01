export enum HarmonyLogLevel {
  TRACE = 10,
  DEBUG = 20,
  INFO = 30,
  NOTICE = 35,
  WARNING = 40,
  ERROR = 50,
  CRITICAL = 60
}

export type HarmonyLogMetadataValue = string | number | boolean | null;

export class HarmonyLogMetadata {
  private values: Map<string, HarmonyLogMetadataValue> = new Map();

  set(key: string, value: HarmonyLogMetadataValue): void {
    this.values.set(key, value);
  }

  remove(key: string): void {
    this.values.delete(key);
  }

  get(key: string): HarmonyLogMetadataValue | undefined {
    return this.values.get(key);
  }

  isEmpty(): boolean {
    return this.values.size === 0;
  }

  keys(): Array<string> {
    return Array.from(this.values.keys());
  }

  clone(): HarmonyLogMetadata {
    const next = new HarmonyLogMetadata();
    const allKeys = this.keys();
    for (let i = 0; i < allKeys.length; i += 1) {
      const key = allKeys[i];
      const value = this.values.get(key);
      if (value !== undefined) {
        next.set(key, value);
      }
    }
    return next;
  }

  mergeFrom(other?: HarmonyLogMetadata): void {
    if (!other) {
      return;
    }
    const allKeys = other.keys();
    for (let i = 0; i < allKeys.length; i += 1) {
      const key = allKeys[i];
      const value = other.get(key);
      if (value !== undefined) {
        this.values.set(key, value);
      }
    }
  }

  toText(): string {
    const allKeys = this.keys();
    if (allKeys.length === 0) {
      return '';
    }
    allKeys.sort((left, right) => left.localeCompare(right));
    const parts: Array<string> = [];
    for (let i = 0; i < allKeys.length; i += 1) {
      const key = allKeys[i];
      const value = this.values.get(key);
      parts.push(key + '=' + HarmonyLogMetadata.valueToText(value));
    }
    return parts.join(',');
  }

  static valueToText(value: HarmonyLogMetadataValue | undefined): string {
    if (value === undefined) {
      return 'undefined';
    }
    if (value === null) {
      return 'null';
    }
    return String(value);
  }
}

export class HarmonyLogRecord {
  timestamp: number;
  label: string;
  level: HarmonyLogLevel;
  message: string;
  metadata?: HarmonyLogMetadata;
  source?: string;
  file?: string;
  functionName?: string;
  line?: number;

  constructor(
    timestamp: number,
    label: string,
    level: HarmonyLogLevel,
    message: string,
    metadata?: HarmonyLogMetadata,
    source?: string,
    file?: string,
    functionName?: string,
    line?: number
  ) {
    this.timestamp = timestamp;
    this.label = label;
    this.level = level;
    this.message = message;
    this.metadata = metadata;
    this.source = source;
    this.file = file;
    this.functionName = functionName;
    this.line = line;
  }
}

export interface HarmonyLogMetadataProvider {
  get(): HarmonyLogMetadata;
}

export interface HarmonyLogHandler {
  minimumLevel: HarmonyLogLevel;
  log(record: HarmonyLogRecord): void;
  metadataProvider?: HarmonyLogMetadataProvider;
}

export class MultiplexLogHandler implements HarmonyLogHandler {
  private handlers: Array<HarmonyLogHandler>;
  private levelValue: HarmonyLogLevel;

  constructor(handlers: Array<HarmonyLogHandler>) {
    if (handlers.length === 0) {
      throw new Error('MultiplexLogHandler.handlers MUST NOT be empty');
    }
    this.handlers = handlers;
    this.levelValue = handlers[0].minimumLevel;
    for (let i = 1; i < handlers.length; i += 1) {
      if (handlers[i].minimumLevel < this.levelValue) {
        this.levelValue = handlers[i].minimumLevel;
      }
    }
  }

  get minimumLevel(): HarmonyLogLevel {
    return this.levelValue;
  }

  set minimumLevel(value: HarmonyLogLevel) {
    this.levelValue = value;
    for (let i = 0; i < this.handlers.length; i += 1) {
      this.handlers[i].minimumLevel = value;
    }
  }

  log(record: HarmonyLogRecord): void {
    for (let i = 0; i < this.handlers.length; i += 1) {
      const handler = this.handlers[i];
      if (record.level >= handler.minimumLevel) {
        handler.log(record);
      }
    }
  }
}

export class HarmonyLogNoOpHandler implements HarmonyLogHandler {
  private levelValue: HarmonyLogLevel = HarmonyLogLevel.CRITICAL;

  get minimumLevel(): HarmonyLogLevel {
    return this.levelValue;
  }

  set minimumLevel(_: HarmonyLogLevel) {
    // no-op
  }

  log(_: HarmonyLogRecord): void {
    // no-op
  }
}

export class InMemoryLogEntry {
  level: HarmonyLogLevel;
  message: string;
  metadata: HarmonyLogMetadata;

  constructor(level: HarmonyLogLevel, message: string, metadata: HarmonyLogMetadata) {
    this.level = level;
    this.message = message;
    this.metadata = metadata;
  }
}

export class InMemoryLogHandler implements HarmonyLogHandler {
  minimumLevel: HarmonyLogLevel = HarmonyLogLevel.INFO;
  metadataProvider?: HarmonyLogMetadataProvider;

  private metadataValue: HarmonyLogMetadata = new HarmonyLogMetadata();
  private entries: Array<InMemoryLogEntry> = [];

  log(record: HarmonyLogRecord): void {
    if (record.level < this.minimumLevel) {
      return;
    }
    const merged = this.metadataValue.clone();
    if (this.metadataProvider) {
      merged.mergeFrom(this.metadataProvider.get());
    }
    merged.mergeFrom(record.metadata);
    this.entries.push(new InMemoryLogEntry(record.level, record.message, merged));
  }

  setMetadata(key: string, value?: HarmonyLogMetadataValue): void {
    if (value === undefined) {
      this.metadataValue.remove(key);
      return;
    }
    this.metadataValue.set(key, value);
  }

  getEntries(): Array<InMemoryLogEntry> {
    return this.entries.slice();
  }

  clear(): void {
    this.entries = [];
  }
}

export class StreamLogHandler implements HarmonyLogHandler {
  minimumLevel: HarmonyLogLevel = HarmonyLogLevel.INFO;
  metadataProvider?: HarmonyLogMetadataProvider;

  private label: string;
  private toError: boolean;
  private metadataValue: HarmonyLogMetadata = new HarmonyLogMetadata();

  constructor(label: string, toError: boolean, metadataProvider?: HarmonyLogMetadataProvider) {
    this.label = label;
    this.toError = toError;
    this.metadataProvider = metadataProvider;
  }

  static standardOutput(label: string, metadataProvider?: HarmonyLogMetadataProvider): StreamLogHandler {
    return new StreamLogHandler(label, false, metadataProvider);
  }

  static standardError(label: string, metadataProvider?: HarmonyLogMetadataProvider): StreamLogHandler {
    return new StreamLogHandler(label, true, metadataProvider);
  }

  setMetadata(key: string, value?: HarmonyLogMetadataValue): void {
    if (value === undefined) {
      this.metadataValue.remove(key);
      return;
    }
    this.metadataValue.set(key, value);
  }

  log(record: HarmonyLogRecord): void {
    if (record.level < this.minimumLevel) {
      return;
    }
    const merged = this.metadataValue.clone();
    if (this.metadataProvider) {
      merged.mergeFrom(this.metadataProvider.get());
    }
    merged.mergeFrom(record.metadata);
    const sourceText = record.source ? record.source : 'n/a';
    const line =
      new Date(record.timestamp).toISOString() +
      ' ' +
      Logger.levelText(record.level) +
      ' ' +
      this.label +
      ': ' +
      (merged.isEmpty() ? '' : merged.toText() + ' ') +
      '[' +
      sourceText +
      '] ' +
      record.message;
    if (this.toError) {
      console.error(line);
    } else {
      console.info(line);
    }
  }
}

export type HarmonyLogHandlerFactory = (label: string) => HarmonyLogHandler;

class LoggerSystem {
  static factory: HarmonyLogHandlerFactory | null = null;
  static metadataProvider: HarmonyLogMetadataProvider | null = null;
  static bootstrapped: boolean = false;
}

export class LoggingSystem {
  static bootstrap(factory: HarmonyLogHandlerFactory, metadataProvider?: HarmonyLogMetadataProvider): void {
    if (LoggerSystem.bootstrapped) {
      throw new Error('logging system can only be initialized once per process.');
    }
    LoggerSystem.factory = factory;
    LoggerSystem.metadataProvider = metadataProvider ? metadataProvider : null;
    LoggerSystem.bootstrapped = true;
  }

  static resetForTesting(): void {
    LoggerSystem.factory = null;
    LoggerSystem.metadataProvider = null;
    LoggerSystem.bootstrapped = false;
  }
}

export class MDCStore {
  private values: HarmonyLogMetadata = new HarmonyLogMetadata();

  getMetadata(): HarmonyLogMetadata {
    return this.values.clone();
  }

  set(key: string, value?: HarmonyLogMetadataValue): void {
    if (value === undefined) {
      this.values.remove(key);
      return;
    }
    this.values.set(key, value);
  }

  clear(): void {
    this.values = new HarmonyLogMetadata();
  }
}

class MDCProvider implements HarmonyLogMetadataProvider {
  get(): HarmonyLogMetadata {
    return MDC.global.getMetadata();
  }
}

export class MDC {
  static global: MDCStore = new MDCStore();

  static metadataProvider(): HarmonyLogMetadataProvider {
    return new MDCProvider();
  }
}

export class Logger {
  static globalLevel: HarmonyLogLevel = HarmonyLogLevel.INFO;
  static compileTimeMinimumLevel: HarmonyLogLevel = HarmonyLogLevel.TRACE;
  private static globalHandlers: Array<HarmonyLogHandler> = [];

  label: string;
  metadata: HarmonyLogMetadata = new HarmonyLogMetadata();
  level: HarmonyLogLevel = Logger.globalLevel;
  handlers: Array<HarmonyLogHandler> | null = null;
  metadataProvider: HarmonyLogMetadataProvider | null = null;

  constructor(label: string, metadataProvider?: HarmonyLogMetadataProvider | null) {
    this.label = label;
    this.metadataProvider = metadataProvider ? metadataProvider : LoggerSystem.metadataProvider;
    if (LoggerSystem.factory) {
      this.handlers = [LoggerSystem.factory(label)];
    }
  }

  static setCompileTimeMinimumLevel(level: HarmonyLogLevel): void {
    Logger.compileTimeMinimumLevel = level;
  }

  static setGlobalHandlers(handlers: Array<HarmonyLogHandler>): void {
    Logger.globalHandlers = handlers;
  }

  static addGlobalHandler(handler: HarmonyLogHandler): void {
    Logger.globalHandlers.push(handler);
  }

  static logger(label: string, metadataProvider?: HarmonyLogMetadataProvider): Logger {
    return new Logger(label, metadataProvider ? metadataProvider : null);
  }

  static safeTag(label: string): string {
    const sanitized = label.replace(/[^a-zA-Z0-9_.-]/g, '_');
    if (sanitized.length > 31) {
      return sanitized.substring(0, 31);
    }
    return sanitized;
  }

  static levelText(level: HarmonyLogLevel): string {
    switch (level) {
      case HarmonyLogLevel.TRACE:
        return 'TRACE';
      case HarmonyLogLevel.DEBUG:
        return 'DEBUG';
      case HarmonyLogLevel.INFO:
        return 'INFO';
      case HarmonyLogLevel.NOTICE:
        return 'NOTICE';
      case HarmonyLogLevel.WARNING:
        return 'WARNING';
      case HarmonyLogLevel.ERROR:
        return 'ERROR';
      case HarmonyLogLevel.CRITICAL:
        return 'CRITICAL';
      default:
        return 'INFO';
    }
  }

  static formatRecord(record: HarmonyLogRecord): string {
    const ts = new Date(record.timestamp).toISOString();
    const level = Logger.levelText(record.level);
    const metadataText = record.metadata ? record.metadata.toText() : '';
    const sourcePart = record.source ? 'source=' + record.source : '';
    const filePart = record.file ? 'file=' + record.file : '';
    const functionPart = record.functionName ? 'func=' + record.functionName : '';
    const linePart = record.line !== undefined ? 'line=' + String(record.line) : '';

    const callsiteItems: Array<string> = [];
    if (sourcePart.length > 0) {
      callsiteItems.push(sourcePart);
    }
    if (filePart.length > 0) {
      callsiteItems.push(filePart);
    }
    if (functionPart.length > 0) {
      callsiteItems.push(functionPart);
    }
    if (linePart.length > 0) {
      callsiteItems.push(linePart);
    }

    const callsiteText = callsiteItems.length > 0 ? ' [' + callsiteItems.join(' ') + ']' : '';
    if (metadataText.length > 0) {
      return '[' + ts + '] [' + level + '] [' + record.label + ']' + callsiteText + ' ' + record.message + ' | ' + metadataText;
    }
    return '[' + ts + '] [' + level + '] [' + record.label + ']' + callsiteText + ' ' + record.message;
  }

  withMetadata(metadata: HarmonyLogMetadata): Logger {
    const next = new Logger(this.label, this.metadataProvider);
    next.level = this.level;
    next.handlers = this.handlers;
    next.metadata = this.metadata.clone();
    next.metadata.mergeFrom(metadata);
    return next;
  }

  copy(): Logger {
    const next = new Logger(this.label, this.metadataProvider);
    next.level = this.level;
    next.handlers = this.handlers;
    next.metadata = this.metadata.clone();
    return next;
  }

  setMetadata(key: string, value?: HarmonyLogMetadataValue): void {
    if (value === undefined) {
      this.metadata.remove(key);
      return;
    }
    this.metadata.set(key, value);
  }

  trace(message: string, metadata?: HarmonyLogMetadata, source?: string, file?: string, func?: string, line?: number): void {
    this.log(HarmonyLogLevel.TRACE, message, metadata, source, file, func, line);
  }

  debug(message: string, metadata?: HarmonyLogMetadata, source?: string, file?: string, func?: string, line?: number): void {
    this.log(HarmonyLogLevel.DEBUG, message, metadata, source, file, func, line);
  }

  info(message: string, metadata?: HarmonyLogMetadata, source?: string, file?: string, func?: string, line?: number): void {
    this.log(HarmonyLogLevel.INFO, message, metadata, source, file, func, line);
  }

  notice(message: string, metadata?: HarmonyLogMetadata, source?: string, file?: string, func?: string, line?: number): void {
    this.log(HarmonyLogLevel.NOTICE, message, metadata, source, file, func, line);
  }

  warning(message: string, metadata?: HarmonyLogMetadata, source?: string, file?: string, func?: string, line?: number): void {
    this.log(HarmonyLogLevel.WARNING, message, metadata, source, file, func, line);
  }

  error(message: string, metadata?: HarmonyLogMetadata, source?: string, file?: string, func?: string, line?: number): void {
    this.log(HarmonyLogLevel.ERROR, message, metadata, source, file, func, line);
  }

  critical(message: string, metadata?: HarmonyLogMetadata, source?: string, file?: string, func?: string, line?: number): void {
    this.log(HarmonyLogLevel.CRITICAL, message, metadata, source, file, func, line);
  }

  log(
    level: HarmonyLogLevel,
    message: string,
    metadata?: HarmonyLogMetadata,
    source?: string,
    file?: string,
    func?: string,
    line?: number
  ): void {
    if (level < Logger.compileTimeMinimumLevel) {
      return;
    }
    if (level < this.level) {
      return;
    }

    const providerMetadata = this.metadataProvider ? this.metadataProvider.get() : undefined;
    const merged = this.metadata.clone();
    merged.mergeFrom(providerMetadata);
    merged.mergeFrom(metadata);

    const actualSource = source ? source : Logger.currentModule(file);
    const record = new HarmonyLogRecord(
      Date.now(),
      this.label,
      level,
      message,
      merged.isEmpty() ? undefined : merged,
      actualSource,
      file,
      func,
      line
    );

    const resolvedHandlers = this.handlers ? this.handlers : Logger.globalHandlers;
    for (let i = 0; i < resolvedHandlers.length; i += 1) {
      const handler = resolvedHandlers[i];
      if (level >= handler.minimumLevel) {
        handler.log(record);
      }
    }
  }

  private static currentModule(file?: string): string {
    if (!file || file.length === 0) {
      return 'n/a';
    }
    const lastSlash = file.lastIndexOf('/');
    if (lastSlash <= 0) {
      return 'n/a';
    }
    const before = file.lastIndexOf('/', lastSlash - 1);
    if (before < 0) {
      return file.substring(0, lastSlash);
    }
    return file.substring(before + 1, lastSlash);
  }
}
