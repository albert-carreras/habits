# CLAUDE.md — Habits

## What is this project?

A minimal, aesthetically pleasing habits and things app for iOS and macOS. SwiftUI + SwiftData, with Supabase for remote auth and backup.

## Key docs

- [PRD](./docs/PRD.md) — product requirements
- [Tech Overview](./docs/TECH_OVERVIEW.md) — architecture and data model
- [Supabase Setup](./docs/SUPABASE.md) — remote auth and backup setup

## Architecture

- **Language:** Swift 6, iOS 17+, macOS 14+
- **UI:** SwiftUI
- **Persistence:** SwiftData + Supabase remote backup
- **Pattern:** Lightweight MVVM
- **Widgets:** WidgetKit (Small + Medium + Lock Screen)
- **Notifications:** Local only via UserNotifications

## Project layout

```
Habits/             → shared app source for iOS and macOS
HabitsMac/          → macOS target plist and entitlements
HabitsMacTests/     → macOS command/shell unit tests
HabitsWidget/       → widget extension target
```

## Conventions

- External dependencies are managed through XcodeGen package entries in `project.yml`; keep additions deliberate and documented.
- SwiftData `@Model` classes live in `Models/`.
- Views are in `Views/`, one file per view.
- Business logic goes in `ViewModels/`, not in views.
- Keep views small and composable.
- Follow system dark/light mode, with user-selectable palettes stored in `AppTheme.paletteStorageKey`.
- Use `AppTheme` for color, radius, spacing, and supported font-weight tokens.
- Habits are sorted alphabetically in the list.
- Things are sorted by due date ascending, then title ascending.

## Build

Project uses XcodeGen (`project.yml`) to generate `Habits.xcodeproj`. After changing `project.yml`, run `xcodegen generate`.

```bash
open Habits.xcodeproj
# or
xcodebuild -scheme Habits -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

- iOS bundle ID: `com.albertc.habit`
- macOS bundle ID: `com.albertc.habit.mac`
- Widget bundle: `com.albertc.habit.widget`
- Available simulator: iPhone 17 Pro (iOS 26.4)
- Mac target: `HabitsMac` builds with `xcodebuild -project Habits.xcodeproj -scheme HabitsMac -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO` when no local Mac provisioning profile is installed.
- Mac helpers: `./scripts/app.sh mac-test` verifies the Mac build without signing, `./scripts/app.sh mac-dmg` builds a signed Release macOS app and packages it as a DMG.
- App Store submission: `./scripts/app.sh submit` archives and uploads iOS to App Store Connect; `./scripts/app.sh mac-submit` does the same for macOS.

## Development process

Every change MUST follow these steps before reporting completion:

1. **Update documentation** — if behavior, architecture, or conventions change, update the relevant docs (this file, PRD, Tech Overview).
2. **Add or update tests** — every new feature or bug fix must have corresponding test coverage.
3. **Run the full test suite** — `./scripts/test-ai.sh` must pass with zero failures.
4. **Verify the build** — included in `./scripts/test-ai.sh`; use `./scripts/test-ai.sh --build` for an iOS build-only check or `./scripts/test-ai.sh --mac-test` for a Mac build-only check.

Do not skip steps. Do not report work as done until all four pass.

## Common tasks

- **Agent test loop:** Run `./scripts/test-ai.sh --unit` for model/view-model changes, `./scripts/test-ai.sh --ui` for user-flow changes, `./scripts/test-ai.sh --mac-test` for a Mac-only build check, and `./scripts/test-visual.sh` for layout or styling changes that need a screenshot. Use `./scripts/test-ai.sh --kill` to stop a stuck agent test/build run.
- **Add a new view:** Create file in `Habits/Views/`, keep it focused on presentation.
- **Change the data model:** Edit files in `Habits/Models/`. SwiftData handles lightweight migration automatically.
- **Widget changes:** Edit files in `HabitsWidget/`. Widget reads from the shared App Group container.
- **Change project structure/targets/packages:** Edit `project.yml`, then run `xcodegen generate`.
