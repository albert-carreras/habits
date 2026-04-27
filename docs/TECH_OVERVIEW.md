# Habits — Technical Overview

**Date:** 2026-04-27

## Stack

| Layer | Choice |
|---|---|
| Language | Swift 6 |
| UI | SwiftUI |
| Persistence | SwiftData |
| Architecture | MVVM (lightweight) |
| Minimum Target | iOS 17.0 |
| Supported Devices | iPhone and iPad |
| Widgets | WidgetKit |
| Notifications | UserNotifications (local only) |

## Project Structure

```
Habits/
├── HabitsApp.swift              # App entry point
├── Models/
│   ├── Habit.swift              # SwiftData @Model
│   └── HabitCompletion.swift    # Completion records
├── ViewModels/
│   └── HabitListViewModel.swift # Business logic for the list
├── Views/
│   ├── HabitListView.swift      # Main list screen
│   ├── HabitRowView.swift       # Single row in the list
│   └── HabitFormView.swift      # Add/Edit sheet
├── Services/
│   ├── HabitWidgetSyncService.swift # App-to-widget snapshot writes
│   └── NotificationService.swift    # Local notification scheduling
├── Shared/
│   ├── HabitSchedule.swift       # Shared schedule/date rules
│   └── HabitWidgetSnapshot.swift # App Group JSON snapshot for widgets
├── Utilities/
│   └── DateHelpers.swift        # Frequency/period helpers
└── Assets.xcassets/

HabitsWidget/
├── HabitsWidget.swift           # Widget entry point
├── SmallWidgetView.swift        # 1×1 widget
├── MediumWidgetView.swift       # 2×1 widget
├── LockScreenWidgetView.swift   # Lock Screen accessory widgets
└── WidgetProvider.swift         # Timeline provider
```

## Data Model

### Habit (SwiftData `@Model`)
- `id: UUID`
- `name: String`
- `frequency: HabitFrequency` (enum, raw value stored)
- `customIntervalValue: Int?`
- `customIntervalUnit: CustomIntervalUnit?`
- `timesToComplete: Int`
- `startDate: Date`
- `notificationsEnabled: Bool`
- `createdAt: Date`
- `completions: [HabitCompletion]` (relationship)

### HabitCompletion (SwiftData `@Model`)
- `id: UUID`
- `date: Date`
- `count: Int` (how many times completed in this record)
- `habit: Habit` (inverse relationship)

## Key Design Decisions

1. **SwiftData over Core Data** — cleaner Swift-native API, automatic CloudKit readiness if we ever add sync.
2. **No external dependencies** — zero SPM packages. Everything ships with Apple's frameworks.
3. **Completion records per period** — each frequency period gets its own `HabitCompletion`. For a daily habit, there's one record per day. This makes widget queries and "is it done today?" checks simple.
4. **Schedule dates come from start date** — the main list uses `startDate` as the anchor for weekly, monthly, yearly, and custom schedules so habits can be split into Today and Later.
5. **Schedule rules are shared** — app logic and widget timeline logic both use `HabitSchedule` from `Habits/Shared`, with `DateHelpers` acting as the app-facing wrapper around the Swift enums. This keeps daily, weekly, monthly, yearly, custom interval, and clamped date behavior consistent across targets.
6. **Widgets share data via App Group** — the app writes a JSON snapshot to `group.com.albertc.habits`; widgets read that snapshot through WidgetKit/AppIntents. The snapshot includes schedule metadata and completion records so widget timelines can recalculate current progress after day and period boundaries without requiring the app to relaunch. Widgets use the same start-date anchored schedule rules as the app, showing "Day off" on unscheduled days and count-style progress on due days. Snapshot writes return success/failure and log failures in debug builds.
7. **Local notifications only** — scheduled via `UNUserNotificationCenter` after authorization is granted. The app creates upcoming one-shot notifications at 9:00 AM on the habit's actual scheduled dates, including custom intervals and clamped monthly dates, and removes/reschedules them whenever a habit is edited or deleted. If scheduling fails, partially added requests are removed and the habit is saved without reminders.

## Design System

The app follows system light/dark mode and resolves app colors through `AppTheme`. The palette uses warm neutral surfaces, green foreground/accent tones in light mode, and amber accent tones in dark mode:

| Token | Light | Dark |
|---|---|---|
| Background | `#f4efe0` | `#0b1812` |
| Surface | `#ece6d4` | `#122119` |
| Surface High | `#e4ddc8` | `#172a20` |
| Border | `#ccc4a8` | `#1f3828` |
| Text | `#132018` | `#f0ead8` |
| Muted | `#6a7860` | `#5a8870` |
| Accent | `#1e4a38` | `#e8a020` |
| Tag | `#e8a020` | `#40b088` |
| Danger | `#c94428` | `#c94428` |

Radius, spacing, and supported font-weight tokens also live in `AppTheme` so views can share the same design scale.

## Build & Run

```bash
# Open in Xcode
open Habits.xcodeproj

# Or run the agent-friendly full check
./scripts/test-ai.sh
```

## Developer Experience

- `./scripts/test-ai.sh` is the default command-line verification path. It regenerates the Xcode project from `project.yml` when needed, runs the full test suite, and then performs a standalone app build.
- `./scripts/test-ai.sh --unit` runs only `HabitsTests`.
- `./scripts/test-ai.sh --ui` runs only the XCUITest smoke flow in `HabitsUITests`.
- `./scripts/test-visual.sh` builds the app, launches it in Simulator with an isolated UI-test store, and writes a screenshot to `/tmp/habits-screenshot.png`.
- UI-test launches pass `-ui-testing`, which makes the app use an in-memory SwiftData store and disables widget timeline writes for deterministic repeat runs.
