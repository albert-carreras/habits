# CLAUDE.md — Habits

## What is this project?

A minimal, aesthetically pleasing iOS habit tracker. SwiftUI + SwiftData, no external dependencies.

## Key docs

- [PRD](./docs/PRD.md) — product requirements
- [Tech Overview](./docs/TECH_OVERVIEW.md) — architecture and data model

## Architecture

- **Language:** Swift 6, iOS 17+
- **UI:** SwiftUI
- **Persistence:** SwiftData
- **Pattern:** Lightweight MVVM
- **Widgets:** WidgetKit (Small + Medium)
- **Notifications:** Local only via UserNotifications

## Project layout

```
Habits/             → main app target
HabitsWidget/       → widget extension target
```

## Conventions

- No external dependencies. Everything uses Apple frameworks.
- SwiftData `@Model` classes live in `Models/`.
- Views are in `Views/`, one file per view.
- Business logic goes in `ViewModels/`, not in views.
- Keep views small and composable.
- Follow system dark/light mode — no custom theme toggle.
- Use `AppTheme` for color, radius, spacing, and supported font-weight tokens.
- Habits are sorted alphabetically in the list.

## Build

Project uses XcodeGen (`project.yml`) to generate `Habits.xcodeproj`. After changing `project.yml`, run `xcodegen generate`.

```bash
open Habits.xcodeproj
# or
xcodebuild -scheme Habits -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

- Bundle ID: `com.albertc.habit`
- Widget bundle: `com.albertc.habit.widget`
- Available simulator: iPhone 17 Pro (iOS 26.4)

## Development process

Every change MUST follow these steps before reporting completion:

1. **Update documentation** — if behavior, architecture, or conventions change, update the relevant docs (this file, PRD, Tech Overview).
2. **Add or update tests** — every new feature or bug fix must have corresponding test coverage.
3. **Run the full test suite** — `./scripts/test-ai.sh` must pass with zero failures.
4. **Verify the build** — included in `./scripts/test-ai.sh`; use `./scripts/test-ai.sh --build` for a build-only check.

Do not skip steps. Do not report work as done until all four pass.

## Common tasks

- **Agent test loop:** Run `./scripts/test-ai.sh --unit` for model/view-model changes, `./scripts/test-ai.sh --ui` for user-flow changes, and `./scripts/test-visual.sh` for layout or styling changes that need a screenshot.
- **Add a new view:** Create file in `Habits/Views/`, keep it focused on presentation.
- **Change the data model:** Edit files in `Habits/Models/`. SwiftData handles lightweight migration automatically.
- **Widget changes:** Edit files in `HabitsWidget/`. Widget reads from the shared App Group container.
- **Change project structure/targets:** Edit `project.yml`, then run `xcodegen generate`.
