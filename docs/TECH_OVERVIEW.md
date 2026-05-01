# Habits — Technical Overview

**Date:** 2026-05-01

## Stack

| Layer | Choice |
|---|---|
| Language | Swift 6 |
| UI | SwiftUI |
| Persistence | SwiftData |
| Remote Backend | Supabase Auth + Postgres |
| Architecture | MVVM (lightweight) |
| Minimum Target | iOS 17.0, macOS 14.0 |
| Supported Devices | iPhone, iPad, and Mac |
| Widgets | WidgetKit on iOS |
| Notifications | UserNotifications (local only) |

## Project Structure

```
Habits/
├── HabitsApp.swift              # App entry point
├── Models/
│   ├── Habit.swift              # SwiftData @Model
│   ├── HabitCompletion.swift    # Completion records
│   └── Thing.swift               # One-off thing model
├── ViewModels/
│   ├── HabitListViewModel.swift # Habit list routing and behavior
│   ├── SupabaseAccountViewModel.swift # Supabase auth state/actions
│   └── ThingListViewModel.swift  # Thing sectioning, labels, and completion
├── Views/
│   ├── HabitListView.swift      # iOS main list screen
│   ├── MacHabitListView.swift   # macOS window shell, toolbar, settings sheet, commands
│   ├── MacHabitCommands.swift   # macOS command menu routing
│   ├── HabitRowView.swift       # Single row in the list
│   ├── HabitFormView.swift      # Add/Edit habit sheet
│   ├── CompletedThingsView.swift # Native completed things history list
│   ├── SettingsView.swift       # Theme, account, things history, backup import/export
│   ├── ThingRowView.swift        # Single thing row
│   └── ThingFormView.swift       # Add/Edit thing sheet
├── Services/
│   ├── BackupService.swift       # Versioned JSON backup import/export
│   ├── HabitWidgetSyncService.swift # App-to-widget snapshot writes
│   ├── NotificationService.swift    # Local notification scheduling
│   ├── SyncService.swift            # Supabase record sync service
│   └── SupabaseService.swift        # Supabase client/config
├── Shared/
│   ├── HabitSchedule.swift       # Shared schedule/date rules
│   └── HabitWidgetSnapshot.swift # App Group JSON snapshot for widgets
├── Utilities/
│   ├── AppHaptics.swift         # Native haptic feedback mapping; no-op on macOS
│   └── DateHelpers.swift        # Frequency/period helpers
├── PrivacyInfo.xcprivacy        # App privacy manifest
└── Assets.xcassets/

HabitsMac/
├── Info.plist                   # macOS app plist without UIApplication keys
└── HabitsMac.entitlements       # sandbox, app group, sign-in, network, file/keychain access

HabitsMacTests/
└── MacHabitCommandModelTests.swift # macOS command routing and haptics compatibility

HabitsWidget/
├── PrivacyInfo.xcprivacy        # Widget privacy manifest
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
- `notificationHour: Int?`
- `notificationMinute: Int?`
- `createdAt: Date`
- sync metadata: `syncUpdatedAt`, `syncDeletedAt`, `syncRemoteUpdatedAt`, `syncNeedsPush`
- `completions: [HabitCompletion]` (relationship)

### HabitCompletion (SwiftData `@Model`)
- `id: UUID`
- `date: Date`
- `periodStart: Date?` (period key for record sync)
- `count: Int` (how many times completed in this record)
- sync metadata: `syncUpdatedAt`, `syncDeletedAt`, `syncRemoteUpdatedAt`, `syncNeedsPush`
- `habit: Habit` (inverse relationship)

### Thing (SwiftData `@Model`)
- `id: UUID`
- `title: String` (max 400 characters)
- `dueDate: Date` (stored at start of day)
- `isCompleted: Bool`
- `completedAt: Date?`
- sync metadata: `syncUpdatedAt`, `syncDeletedAt`, `syncRemoteUpdatedAt`, `syncNeedsPush`

## Key Design Decisions

1. **SwiftData over Core Data** — cleaner Swift-native API, automatic CloudKit readiness if we ever add sync.
2. **Supabase for remote account/data plumbing** — the app uses `supabase-swift` for authenticated Postgres-backed record sync. Apple and Google sign in with native identity-token flows, then exchange those tokens with Supabase. SwiftData remains the local source of truth.
3. **Completion records per period** — each frequency period gets one aggregate `HabitCompletion`. New synced completions use deterministic IDs from `(habitID, periodStart)`, so two devices target the same row for the same habit period. Counter conflicts use per-row last-writer-wins.
4. **Schedule dates come from start date** — the main list uses `startDate` as the anchor for weekly, monthly, yearly, and custom schedules so habits can be split into Today and Later.
5. **Schedule rules are shared** — app logic and widget timeline logic both use `HabitSchedule` from `Habits/Shared`, with `DateHelpers` acting as the app-facing wrapper around the Swift enums. This keeps daily, weekly, monthly, yearly, custom interval, and clamped date behavior consistent across targets.
6. **Widgets share data via App Group** — the app writes a JSON snapshot to `group.com.albertc.habits`; widgets read that snapshot through WidgetKit/AppIntents. The snapshot includes schedule metadata and completion records so widget timelines can recalculate current progress after day and period boundaries without requiring the app to relaunch. Widgets use the same start-date anchored schedule rules as the app, showing "Day off" on unscheduled days and count-style progress on due days. Snapshot writes return success/failure and log failures in debug builds.
7. **Things are one-off tasks** — things do not repeat and do not have notifications. They are split into Today and Later by due date. Incomplete overdue things remain in Today with a relative due label; completed overdue things remain visible only on the day they are completed and disappear after the next date rollover. Settings exposes a simple native completed-things history grouped by completion day. The things summary count includes only incomplete Today/overdue things, not future Later items. Things due tomorrow or later cannot be toggled complete until their due day. A thing row has a contextual date action: Today/overdue rows can move to tomorrow, and Later rows can move to today. Moving a thing also clears any completion state.
8. **Local notifications only for habits** — scheduled via `UNUserNotificationCenter` after authorization is granted. The app creates upcoming one-shot notifications at the habit's configured time on the actual scheduled dates, including custom intervals and clamped monthly dates, and removes/reschedules them whenever a habit is edited or deleted. Reminder time defaults to 9:00 AM and is stored as hour/minute fields on the habit. If scheduling fails, partially added requests are removed and the habit is saved without reminders.
9. **Backups and sync are separate features** — settings exposes JSON import/export through native document picker flows for offline backup. The backup envelope uses `format = com.albertc.habits.backup` and `schemaVersion = 1`, includes habits, nested completions, things, and reminder fields. Merge imports upsert habits and things by stable ID; completions merge by habit period and use deterministic sync IDs. Supabase Force Sync uses per-record tables, soft deletes, per-device `client_id`, and `(updated_at, id)` cursors. Pulls build per-table local lookup maps before applying remote rows, and completion pulls require a local or fetchable parent habit before inserting. Thing sync tracks local title, due-date, completion, and deletion edits separately after a row has been acknowledged remotely, so cross-device changes to different fields can be pushed without clearing unrelated remote state. New or fallback Thing writes upsert a full row, while acknowledged Thing rows with only selected local field edits use `UPDATE` so sparse payloads do not become `null` values for required Postgres columns. Nullable sync columns are encoded as explicit `null` when cleared to avoid stale PostgREST values. Successful full sync timestamps, stale-sync throttles, debounced pushes, and retry pushes are scoped by Supabase user ID so account switches do not inherit another account's sync state or push stale local rows into a new session. Full account restores snapshot visible local data before deletion, reset that user's cursors, and restore the local snapshot if remote pull fails. Remote sync refreshes both habit and thing widget snapshots, and remote habit notification changes remove or reschedule local reminders. The alpha Supabase schema is resettable and defined in `supabase/schema.sql`; there is no legacy remote backup migration path.
10. **Auth is handled by Supabase** — Settings exposes Continue with Apple and Continue with Google. Apple uses the native `AuthenticationServices` sheet and exchanges Apple's identity token with Supabase through `signInWithIdToken`. Google uses the native `GoogleSignIn` SDK with configured iOS and Web client IDs, then exchanges Google's ID token with Supabase through `signInWithIdToken`. Provider rows show provider-specific progress while opening, and a sign-in attempt times out after 30 seconds with a retryable account error so a stalled provider or network request does not leave Settings stuck. The app registers both the app callback scheme and Google's reverse client ID scheme, and forwards opened URLs to GoogleSignIn first, then Supabase. Supabase auth opts into immediate local initial-session emission and ignores expired initial sessions until refresh, matching the next-major SDK behavior. Signing out first attempts a final sync, then signs out before removing local account data from the device so a local deletion failure cannot leave a signed-in empty store; if the final sync fails, the user must choose whether to stay signed in, sign out while keeping local data as signed-out data, or sign out and remove local data. When a user creates data while signed out and then signs in, sync is paused until they choose to merge that local data into the account, replace it with account data, or cancel the sign-in. Signed-in users can hard-delete their account through a Supabase Edge Function at `functions/v1/delete-account`; the iOS app sends only the current access token, while the Edge Function derives the user ID from the JWT, uses the service-role secret server-side, deletes cloud rows, and then admin-deletes the Auth user. After success, the app signs out locally and can physically remove local SwiftData records when the user chooses that option. Supabase dashboard provider setup, redirect allow-list entries, table/RLS policies, Edge Function deployment, and required secrets are documented in `docs/SUPABASE.md`.
11. **macOS is a separate native shell over shared data** — `HabitsMac` compiles the same SwiftData models, view models, sync, backup, settings sections, forms, and theme, but uses `MacHabitListView` for a desktop window shell. The Mac shell has a custom toolbar mode switcher, toolbar add/settings actions, row-wide toggle taps, themed card rows without list selection chrome, context menus, command routing for New/View/Settings, and a settings sheet that includes completed things history. iOS keeps its custom header, bottom switcher, floating add button, row-wide taps, and swipe actions.
12. **Haptics are centralized** — `AppHaptics` maps semantic app events to native `UIFeedbackGenerator` calls on iOS and is API-compatible no-op behavior on macOS. UI-test launches disable haptics through `AppEnvironment` for deterministic automation.

## Design System

The app follows system light/dark mode and resolves app colors through `AppTheme`. Settings exposes the Modern, Kandinsky, Mondrian, and Albers palettes; the selected palette is stored in `AppTheme.paletteStorageKey` so SwiftUI views refresh reactively when it changes.

Radius, spacing, liquid glass helpers, and supported font-weight tokens also live in `AppTheme` so views can share the same design scale.

## Build & Run

```bash
# Open in Xcode
open Habits.xcodeproj

# Or run the agent-friendly full check, including the unsigned Mac build
./scripts/test-ai.sh

# Mac-only build check for machines without a Mac provisioning profile
./scripts/test-ai.sh --mac-build

# Build a local unsigned Mac artifact for build verification
./scripts/app.sh mac-unsigned

# Build, sign, and launch the native Mac app after provisioning is configured
./scripts/app.sh mac
```

## Developer Experience

- `./scripts/test-ai.sh` is the default command-line verification path. It regenerates the Xcode project from `project.yml` when needed, runs the full iOS test suite, performs a standalone iOS app build, and then performs an unsigned `HabitsMac` build with `CODE_SIGNING_ALLOWED=NO`.
- `./scripts/test-ai.sh --unit` runs only `HabitsTests`.
- `./scripts/test-ai.sh --ui` runs only the XCUITest smoke flow in `HabitsUITests`.
- `./scripts/test-ai.sh --mac-build` builds the native macOS target without requiring local provisioning.
- `./scripts/test-ai.sh --kill` stops a stuck `test-ai.sh` or matching `xcodebuild` run for this project.
- `./scripts/app.sh mac-unsigned` builds the macOS app without signing for verification only. It does not prove provisioning, app groups, Sign in with Apple, or keychain-backed Google Sign-In.
- `./scripts/app.sh mac-build` and `./scripts/app.sh mac` use the configured Apple Developer team and require a provisioning profile for `com.albertc.habit.mac` with sandbox, app group, Sign in with Apple, and keychain entitlements.
- `./scripts/test-visual.sh` builds the app, launches it in Simulator with an isolated UI-test store, and writes a screenshot to `/tmp/habits-screenshot.png`.
- UI-test launches pass `-ui-testing`, which makes the app use an in-memory SwiftData store and disables widget timeline writes for deterministic repeat runs.
