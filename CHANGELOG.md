# Changelog

## 1.0.10 - 2026-04-02

- README: add repository URL and issue tracker URL for easier project discovery.

## 1.0.9 - 2026-04-02

- Fix release creation step to use GitHub API (`actions/github-script`) instead of local `gh` CLI on runner.
- Ensure tag publish workflow can always create/update GitHub Release without runner-side gh dependency.

## 1.0.8 - 2026-04-02

- Fix auto-tag workflow to push tags with `RELEASE_BOT_TOKEN` (PAT), ensuring tag push can trigger downstream publish workflow.
- Add explicit guard for missing `RELEASE_BOT_TOKEN` to fail fast with actionable message.

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
