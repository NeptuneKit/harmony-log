export enum HarmonyLogLevel {
  TRACE = 10,
  DEBUG = 20,
  INFO = 30,
  NOTICE = 35,
  WARNING = 40,
  ERROR = 50,
  CRITICAL = 60
}

export type HarmonyLogMetadataScalar = string | number | boolean | null;
export type HarmonyLogMetadataValue =
  | HarmonyLogMetadataScalar
  | HarmonyLogMetadataValue[]
  | { [key: string]: HarmonyLogMetadataValue }
  | undefined;
export type HarmonyLogMetadata = Record<string, HarmonyLogMetadataValue>;
export type HarmonyLogMessage = string | (() => string);
export type HarmonyLogMetadataInput = HarmonyLogMetadata | (() => HarmonyLogMetadata | undefined);

export interface HarmonyLogRecord {
  timestamp: number;
  label: string;
  level: HarmonyLogLevel;
  message: string;
  metadata?: HarmonyLogMetadata;
  source?: string;
  file?: string;
  function?: string;
  line?: number;
}

export interface HarmonyLogHandler {
  minimumLevel: HarmonyLogLevel;
  log(record: HarmonyLogRecord): void;
  metadataProvider?: HarmonyLogMetadataProvider;
}

export interface HarmonyLogMetadataProvider {
  get(): HarmonyLogMetadata;
}

export type HarmonyLogStreamTarget = 'stdout' | 'stderr';

export class MultiplexLogHandler implements HarmonyLogHandler {
  private handlers: HarmonyLogHandler[];
  private _minimumLevel: HarmonyLogLevel;

  constructor(handlers: HarmonyLogHandler[]) {
    if (handlers.length === 0) {
      throw new Error('MultiplexLogHandler.handlers MUST NOT be empty');
    }
    this.handlers = [...handlers];
    this._minimumLevel = this.handlers.reduce(
      (minLevel, handler) => (handler.minimumLevel < minLevel ? handler.minimumLevel : minLevel),
      this.handlers[0].minimumLevel
    );
  }

  get minimumLevel(): HarmonyLogLevel {
    return this._minimumLevel;
  }

  set minimumLevel(value: HarmonyLogLevel) {
    this._minimumLevel = value;
    this.handlers.forEach(handler => {
      handler.minimumLevel = value;
    });
  }

  log(record: HarmonyLogRecord): void {
    this.handlers.forEach(handler => {
      if (record.level >= handler.minimumLevel) {
        handler.log(record);
      }
    });
  }
}

export class HarmonyLogNoOpHandler implements HarmonyLogHandler {
  private _minimumLevel: HarmonyLogLevel = HarmonyLogLevel.CRITICAL;

  get minimumLevel(): HarmonyLogLevel {
    return this._minimumLevel;
  }

  set minimumLevel(_: HarmonyLogLevel) {
    // Keep no-op behavior stable.
  }

  log(_: HarmonyLogRecord): void {
    // Intentionally no-op.
  }
}

export interface InMemoryLogEntry {
  level: HarmonyLogLevel;
  message: string;
  metadata: HarmonyLogMetadata;
}

export class InMemoryLogHandler implements HarmonyLogHandler {
  minimumLevel: HarmonyLogLevel = HarmonyLogLevel.INFO;
  metadataProvider?: HarmonyLogMetadataProvider;
  private metadata: HarmonyLogMetadata = {};
  private entries: InMemoryLogEntry[] = [];

  log(record: HarmonyLogRecord): void {
    if (record.level < this.minimumLevel) {
      return;
    }
    const withProvider = Logger.mergeMetadata(this.metadata, this.metadataProvider?.get());
    const merged = Logger.mergeMetadata(withProvider, record.metadata);
    this.entries.push({
      level: record.level,
      message: record.message,
      metadata: merged
    });
  }

  setMetadata(key: string, value: HarmonyLogMetadataValue): void {
    if (value === undefined) {
      delete this.metadata[key];
      return;
    }
    this.metadata[key] = value;
  }

  getMetadata(): HarmonyLogMetadata {
    return { ...this.metadata };
  }

  getEntries(): InMemoryLogEntry[] {
    return this.entries.map(entry => ({ ...entry, metadata: { ...entry.metadata } }));
  }

  clear(): void {
    this.entries = [];
  }
}

export class StreamLogHandler implements HarmonyLogHandler {
  minimumLevel: HarmonyLogLevel = HarmonyLogLevel.INFO;
  metadataProvider?: HarmonyLogMetadataProvider;

  private label: string;
  private target: HarmonyLogStreamTarget;
  private metadata: HarmonyLogMetadata = {};

  constructor(label: string, target: HarmonyLogStreamTarget, metadataProvider?: HarmonyLogMetadataProvider) {
    this.label = label;
    this.target = target;
    this.metadataProvider = metadataProvider;
  }

  static standardOutput(label: string, metadataProvider?: HarmonyLogMetadataProvider): StreamLogHandler {
    return new StreamLogHandler(label, 'stdout', metadataProvider);
  }

  static standardError(label: string, metadataProvider?: HarmonyLogMetadataProvider): StreamLogHandler {
    return new StreamLogHandler(label, 'stderr', metadataProvider);
  }

  setMetadata(key: string, value: HarmonyLogMetadataValue): void {
    if (value === undefined) {
      delete this.metadata[key];
      return;
    }
    this.metadata[key] = value;
  }

  getMetadata(): HarmonyLogMetadata {
    return { ...this.metadata };
  }

  log(record: HarmonyLogRecord): void {
    if (record.level < this.minimumLevel) {
      return;
    }
    const withProvider = Logger.mergeMetadata(this.metadata, this.metadataProvider?.get());
    const merged = Logger.mergeMetadata(withProvider, record.metadata);
    const output = StreamLogHandler.formatLine(this.label, record, merged);
    if (this.target === 'stderr') {
      console.error(output);
      return;
    }
    console.info(output);
  }

  private static formatLine(label: string, record: HarmonyLogRecord, metadata: HarmonyLogMetadata): string {
    const ts = new Date(record.timestamp).toISOString();
    const levelText = Logger.levelText(record.level);
    const metadataText = Logger.metadataToText(metadata);
    const sourceText = record.source ?? 'n/a';
    const labelText = label.length > 0 ? label : record.label;
    if (metadataText.length > 0) {
      return `${ts} ${levelText} ${labelText}: ${metadataText} [${sourceText}] ${record.message}`;
    }
    return `${ts} ${levelText} ${labelText}: [${sourceText}] ${record.message}`;
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
    LoggerSystem.metadataProvider = metadataProvider ?? null;
    LoggerSystem.bootstrapped = true;
  }

  static resetForTesting(): void {
    LoggerSystem.factory = null;
    LoggerSystem.metadataProvider = null;
    LoggerSystem.bootstrapped = false;
  }

  static isBootstrapped(): boolean {
    return LoggerSystem.bootstrapped;
  }

  static getMetadataProvider(): HarmonyLogMetadataProvider | null {
    return LoggerSystem.metadataProvider;
  }
}

export class MDCStore {
  private values: HarmonyLogMetadata = {};

  get metadata(): HarmonyLogMetadata {
    return { ...this.values };
  }

  get(key: string): HarmonyLogMetadataValue {
    return this.values[key];
  }

  set(key: string, value: HarmonyLogMetadataValue): void {
    if (value === undefined) {
      delete this.values[key];
      return;
    }
    this.values[key] = value;
  }

  clear(): void {
    this.values = {};
  }
}

export class MDC {
  static global: MDCStore = new MDCStore();

  static metadataProvider(): HarmonyLogMetadataProvider {
    return {
      get: () => MDC.global.metadata
    };
  }
}

export class Logger {
  static globalLevel: HarmonyLogLevel = HarmonyLogLevel.INFO;
  static compileTimeMinimumLevel: HarmonyLogLevel = HarmonyLogLevel.TRACE;
  private static globalHandlers: HarmonyLogHandler[] = [];

  label: string;
  metadata: HarmonyLogMetadata = {};
  level: HarmonyLogLevel = Logger.globalLevel;
  handlers: HarmonyLogHandler[] | null = null;
  metadataProvider: HarmonyLogMetadataProvider | null = null;

  constructor(label: string, metadataProvider?: HarmonyLogMetadataProvider | null) {
    this.label = label;
    this.metadataProvider = metadataProvider ?? LoggerSystem.metadataProvider;
    if (LoggerSystem.factory !== null) {
      this.handlers = [LoggerSystem.factory(label)];
    }
  }

  static setGlobalHandlers(handlers: HarmonyLogHandler[]): void {
    Logger.globalHandlers = handlers;
  }

  static addGlobalHandler(handler: HarmonyLogHandler): void {
    Logger.globalHandlers.push(handler);
  }

  static logger(label: string, metadataProvider?: HarmonyLogMetadataProvider): Logger {
    return new Logger(label, metadataProvider);
  }

  static setCompileTimeMinimumLevel(level: HarmonyLogLevel): void {
    Logger.compileTimeMinimumLevel = level;
  }

  static safeTag(label: string): string {
    const sanitized = label.replace(/[^a-zA-Z0-9_.-]/g, '_');
    return sanitized.length > 31 ? sanitized.substring(0, 31) : sanitized;
  }

  static formatRecord(record: HarmonyLogRecord): string {
    const ts = new Date(record.timestamp).toISOString();
    const level = Logger.levelText(record.level);
    const metadataText = Logger.metadataToText(record.metadata);
    const callsite = Logger.callsiteToText(record);
    if (metadataText.length > 0) {
      return `[${ts}] [${level}] [${record.label}]${callsite} ${record.message} | ${metadataText}`;
    }
    return `[${ts}] [${level}] [${record.label}]${callsite} ${record.message}`;
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

  static metadataToText(metadata?: HarmonyLogMetadata): string {
    if (!metadata) {
      return '';
    }
    const entries = Object.entries(metadata).sort(([left], [right]) => left.localeCompare(right));
    if (entries.length === 0) {
      return '';
    }
    return entries
      .map(([key, value]) => `${key}=${Logger.metadataValueToText(value)}`)
      .join(',');
  }

  private static metadataValueToText(value: HarmonyLogMetadataValue): string {
    if (value === undefined) {
      return 'undefined';
    }
    if (value === null) {
      return 'null';
    }
    if (Array.isArray(value)) {
      return `[${value.map(item => Logger.metadataValueToText(item)).join(',')}]`;
    }
    if (typeof value === 'object') {
      const entries = Object.entries(value).sort(([left], [right]) => left.localeCompare(right));
      return `{${entries.map(([key, entryValue]) => `${key}:${Logger.metadataValueToText(entryValue)}`).join(',')}}`;
    }
    return String(value);
  }

  private static callsiteToText(record: HarmonyLogRecord): string {
    const sourcePart = record.source ? `source=${record.source}` : '';
    const filePart = record.file ? `file=${record.file}` : '';
    const functionPart = record.function ? `func=${record.function}` : '';
    const linePart = record.line !== undefined ? `line=${record.line}` : '';
    const items = [sourcePart, filePart, functionPart, linePart].filter(item => item.length > 0);
    if (items.length === 0) {
      return '';
    }
    return ` [${items.join(' ')}]`;
  }

  withMetadata(metadata: HarmonyLogMetadata): Logger {
    const next = new Logger(this.label);
    next.level = this.level;
    next.handlers = this.handlers;
    next.metadataProvider = this.metadataProvider;
    next.metadata = Logger.mergeMetadata(this.metadata, metadata);
    return next;
  }

  copy(): Logger {
    const next = new Logger(this.label, this.metadataProvider);
    next.level = this.level;
    next.handlers = this.handlers ? [...this.handlers] : null;
    next.metadata = { ...this.metadata };
    return next;
  }

  withMetadataProvider(metadataProvider: HarmonyLogMetadataProvider | null): Logger {
    const next = new Logger(this.label, metadataProvider);
    next.level = this.level;
    next.handlers = this.handlers;
    next.metadata = { ...this.metadata };
    return next;
  }

  setMetadata(key: string, value: HarmonyLogMetadataValue): void {
    if (value === undefined) {
      delete this.metadata[key];
      return;
    }
    this.metadata[key] = value;
  }

  trace(
    message: HarmonyLogMessage,
    metadata?: HarmonyLogMetadataInput,
    source?: string,
    file?: string,
    func?: string,
    line?: number
  ): void {
    this.log(HarmonyLogLevel.TRACE, message, metadata, source, file, func, line);
  }

  debug(
    message: HarmonyLogMessage,
    metadata?: HarmonyLogMetadataInput,
    source?: string,
    file?: string,
    func?: string,
    line?: number
  ): void {
    this.log(HarmonyLogLevel.DEBUG, message, metadata, source, file, func, line);
  }

  info(
    message: HarmonyLogMessage,
    metadata?: HarmonyLogMetadataInput,
    source?: string,
    file?: string,
    func?: string,
    line?: number
  ): void {
    this.log(HarmonyLogLevel.INFO, message, metadata, source, file, func, line);
  }

  notice(
    message: HarmonyLogMessage,
    metadata?: HarmonyLogMetadataInput,
    source?: string,
    file?: string,
    func?: string,
    line?: number
  ): void {
    this.log(HarmonyLogLevel.NOTICE, message, metadata, source, file, func, line);
  }

  warning(
    message: HarmonyLogMessage,
    metadata?: HarmonyLogMetadataInput,
    source?: string,
    file?: string,
    func?: string,
    line?: number
  ): void {
    this.log(HarmonyLogLevel.WARNING, message, metadata, source, file, func, line);
  }

  error(
    message: HarmonyLogMessage,
    metadata?: HarmonyLogMetadataInput,
    source?: string,
    file?: string,
    func?: string,
    line?: number
  ): void {
    this.log(HarmonyLogLevel.ERROR, message, metadata, source, file, func, line);
  }

  critical(
    message: HarmonyLogMessage,
    metadata?: HarmonyLogMetadataInput,
    source?: string,
    file?: string,
    func?: string,
    line?: number
  ): void {
    this.log(HarmonyLogLevel.CRITICAL, message, metadata, source, file, func, line);
  }

  log(
    level: HarmonyLogLevel,
    message: HarmonyLogMessage,
    metadata?: HarmonyLogMetadataInput,
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
    const resolvedMessage = Logger.materializeMessage(message);
    const resolvedSource = source ?? Logger.currentModule(file);
    const resolvedMetadataInput = Logger.materializeMetadata(metadata);
    const fromProvider = this.metadataProvider?.get() ?? undefined;
    const mergedWithProvider = Logger.mergeMetadata(this.metadata, fromProvider);
    const resolvedMetadata = Logger.mergeMetadata(mergedWithProvider, resolvedMetadataInput);
    const record: HarmonyLogRecord = {
      timestamp: Date.now(),
      label: this.label,
      level: level,
      message: resolvedMessage,
      metadata: Object.keys(resolvedMetadata).length === 0 ? undefined : resolvedMetadata,
      source: resolvedSource,
      file,
      function: func,
      line
    };

    const resolvedHandlers = this.handlers ?? Logger.globalHandlers;
    resolvedHandlers.forEach((handler: HarmonyLogHandler) => {
      if (level >= handler.minimumLevel) {
        handler.log(record);
      }
    });
  }

  static mergeMetadata(base: HarmonyLogMetadata, explicit?: HarmonyLogMetadata): HarmonyLogMetadata {
    const merged: HarmonyLogMetadata = { ...base };
    if (!explicit) {
      return merged;
    }
    for (const [key, value] of Object.entries(explicit)) {
      if (value === undefined) {
        delete merged[key];
        continue;
      }
      merged[key] = value;
    }
    return merged;
  }

  private static materializeMessage(message: HarmonyLogMessage): string {
    return typeof message === 'function' ? message() : message;
  }

  private static materializeMetadata(metadata?: HarmonyLogMetadataInput): HarmonyLogMetadata | undefined {
    if (metadata === undefined) {
      return undefined;
    }
    return typeof metadata === 'function' ? metadata() : metadata;
  }

  private static currentModule(file?: string): string {
    if (!file || file.length === 0) {
      return 'n/a';
    }
    const slash = file.lastIndexOf('/');
    if (slash <= 0) {
      return 'n/a';
    }
    const previous = file.lastIndexOf('/', slash - 1);
    if (previous < 0) {
      return file.substring(0, slash);
    }
    return file.substring(previous + 1, slash);
  }
}
