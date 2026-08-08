# Contributing

## Setup

1. Install Flutter (stable channel) + Android toolchain; `flutter doctor` must be clean.
2. `flutter pub get`, then `flutter run` on a device or emulator.
3. Point the app at a backend in Settings (server URL + app password). No credentials live in the repo.

## Working in this codebase

**Read `AGENTS.md` first** — it lists this repo's dependency pins and build landmines (some pins look outdated but are load-bearing; the file says why). It is also loaded automatically by our coding harnesses (Claude Code, Codex, Hermes), so record new hard-won knowledge there.

- `flutter analyze` must be clean before a PR — but after any plugin MAJOR bump, also run a real `flutter build apk`: analyze cannot see a broken Android plugin registrant.
- Dependency upgrades are done across all three companion apps (`book-dashboard-app`, `phils-brain-app`, `yt-dashboard-app`) in one pass — check each repo's AGENTS.md before bumping shared packages.
- Features mirror the web dashboard (`phils-library`); port changes in the same pass to avoid drift.

## Change flow

Branch → PR → review. Push to `main` triggers the APK build workflow and updates the GitHub release, so `main` must always build.
