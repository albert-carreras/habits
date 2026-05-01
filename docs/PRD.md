# Habits — Product Requirements Document

**Version:** 1.1
**Date:** 2026-04-28

## Overview

Habits is a minimal, aesthetically pleasing iOS app for recurring habits and one-off Things (the app's name for tasks/todos). One screen, zero friction. Users switch between habits and things, track completions, and get gentle reminders for habits only.

## Target Platform

- iOS 17+ (iPhone and iPad)
- Widgets: Small (1×1), Medium (2×1), and Lock Screen accessory

## Core User Flow

1. **Open app** → see today's habits in a single list view
2. **Switch mode** → use the floating Habits/Things segment at the bottom-left
3. **Tap "+"** → sheet slides up to create the active type
4. **Tap a row** → complete a thing, or mark/increment a habit
5. **Swipe a row** → edit or delete with confirmation; habits also expose clear counter progress when applicable
6. **Feel feedback** → light haptics confirm mode changes, saves, completions, clears, date moves, and destructive actions without becoming noisy

## Habit Model

| Field | Type | Constraints |
|---|---|---|
| Name | String | Max 100 characters |
| Frequency | Enum | Daily, Weekly, Monthly, Yearly, Custom |
| Custom Interval | Int + Unit | Every X days/weeks/months (only when frequency = Custom) |
| Times to Complete | Int | ≥ 1, default 1. Represents a counter (e.g. "50 pushups") |
| Start Date | Date | Defaults to today |
| Notifications | Bool + Time | On/Off toggle, default Off. Reminder time defaults to 9:00 AM and is configurable per habit. |

## Thing Model

| Field | Type | Constraints |
|---|---|---|
| Title | String | Max 400 characters |
| Due Date | Date | Today or future when created/edited; overdue things can exist as dates roll forward |
| Completed | Bool + Date | Completion state plus completion timestamp |

## Screens & Interactions

### Main List View
- Shows habits due today first, with a Later section underneath for habits whose next scheduled date is after today
- Each row: habit name, frequency label, shorthand next date, completion indicator (checkmark or counter progress like "3/50")
- Header shows the current date above the active mode title, with a settings button to the right of the title
- Floating Habits/Things segment at bottom-left and floating "+" button at bottom-right
- Settings button opens a settings sheet
- The things summary counts only incomplete things due today or overdue, not future Later items
- Pull-to-refresh not needed (reactive data)

### Settings
- Settings includes a Data section for local backup import and export
- Settings includes a Things section with a simple completed-things history grouped by completion day
- Settings includes an Account section for Supabase-backed Apple/Google sign-in
- Export creates a JSON backup containing habits, habit completions, things, and habit reminder settings
- Import accepts a Habits JSON backup and asks whether to merge with existing data or replace all local data
- Merge preserves local-only records, updates matching habits and things by stable ID, and updates habit completions by habit period
- Replace soft-deletes local habits, completions, and things before restoring the backup, so signed-in devices can sync tombstones
- Invalid or unsupported backup files fail without changing local data
- Local import/export does not require an account
- Signed-in users can Force Sync record-level changes through Supabase; local dirty rows push first, then remote rows pull with per-row last-writer-wins and soft-delete tombstones
- Signed-in users see the last successful full sync time in Settings, scoped to the current account
- Signed-in users can Delete Account from Settings; after remote account and cloud data deletion succeeds, they choose whether this device keeps or removes its local habits and things
- If account deletion fails, the user remains signed in and sees an Account Error

### Thing List View
- Shows things due today and incomplete overdue things in Today, with future things in Later
- Completed things remain visible for their due day; completed overdue things remain visible on the day they are completed and disappear after the next date rollover
- Each row: thing title, completion indicator, and a localized due label for overdue or future things
- Row actions include Edit, Delete, and a contextual date action; Today/overdue things can move to Tomorrow, while Later things can move to Today
- Things due tomorrow or later are visible in Later but cannot be toggled complete until their due day
- Things sort by due date ascending, then title ascending

### Add/Edit Habit Sheet
- Presented as a `.sheet` modal
- Fields: name, frequency picker, custom interval (conditional), times-to-complete stepper, start date picker, notification toggle, notification time picker
- Save / Cancel buttons
- Styled with the same rounded, glassy card language as the main list

### Delete
- Swipe-to-delete on the list row
- Confirmation alert before deletion

### Completion
- **Single-completion habits (1×):** tap the row to toggle done/undone
- **Counter habits (N×):** tap the row to increment once
- Edit and Delete are swipe-only row actions
- Counter habits with progress expose Clear as a swipe action
- Haptics stay restrained: light taps for ordinary actions, success on completed items/saves, selection for mode/date changes, and warning only for confirmed destructive or error states

## Widgets

### Small (1×1)
- Displays a single habit's name and whether it's complete today
- Checkmark or progress ring
- On days when the selected habit is not scheduled, displays "Day off" instead of progress
- User selects which habit via widget configuration

### Medium (2×1)
- Same as small but with more room: habit name, streak count, and completion status
- Due days show current progress like "0/1"; unscheduled days show "Day off"
- User selects which habit via widget configuration

### Lock Screen
- Displays a single habit's current progress, e.g. "Meditate 0/1"
- Displays "Day off" when the selected habit is not scheduled today
- User selects which habit via widget configuration

## Notifications

- When enabled for a habit, send a local notification at the configured reminder time on the habit's frequency schedule
- Reminder time defaults to 9:00 AM and can be changed in the add/edit form
- Things do not send notifications

## Non-Goals (v1)

- No real-time sync
- No Mac
- No statistics / charts
- No categories or tags
- No habit reordering (alphabetical)
- No dark/light mode toggle (follow system)
- No onboarding flow
