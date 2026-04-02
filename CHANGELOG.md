# Changelog

## 1.0.7 - 2026-04-02

- CI: add `auto-tag-on-main` workflow to create a new semantic version tag for each commit on `main`.
- CI: keep tag-driven publish flow so each new tag triggers OHPM publish workflow.
- CI: after successful tag publish, automatically create or update the corresponding GitHub Release.

## 1.0.6 - 2026-04-02

- Policy update: package artifact is generated and committed for each repository change.
- Generate and commit `dist/harmony_log-1.0.6.har`.

## 1.0.5 - 2026-04-02

- Unify published package name to `harmony-log`.
- Align README installation command to `ohpm install harmony-log` / `ohpm i harmony-log`.
- Keep import usage as `import { ... } from 'harmony-log'`.

## 1.0.4 - 2026-04-02

- Add explicit ohpm installation command in README for review compliance.
- Document supported install commands: `ohpm install ...` and `ohpm i ...`.

## 1.0.0 - 2026-04-01

- Initial HarmonyOS release of `harmony-log`.
- Provides SwiftLog-style logging API for ArkTS/HarmonyOS.
- Includes custom log handlers and metadata support.
