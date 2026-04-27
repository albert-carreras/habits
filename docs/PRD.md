# Habits — Product Requirements Document

**Version:** 1.0
**Date:** 2026-04-27

## Overview

Habits is a minimal, aesthetically pleasing iOS habit tracker. One screen, zero friction. Users create habits, track completions, and get gentle reminders — nothing more.

## Target Platform

- iOS 17+ (iPhone and iPad)
- Widgets: Small (1×1), Medium (2×1), and Lock Screen accessory

## Core User Flow

1. **Open app** → see today's habits in a single list view
2. **Tap "+"** → sheet slides up to create a new habit
3. **Tap a habit** → mark a single-completion habit done/undone, or increment a counter habit by one
4. **Swipe a habit** → edit, clear counter progress when applicable, or delete with confirmation

## Habit Model

| Field | Type | Constraints |
|---|---|---|
| Name | String | Max 100 characters |
| Frequency | Enum | Daily, Weekly, Monthly, Yearly, Custom |
| Custom Interval | Int + Unit | Every X days/weeks/months (only when frequency = Custom) |
| Times to Complete | Int | ≥ 1, default 1. Represents a counter (e.g. "50 pushups") |
| Start Date | Date | Defaults to today |
| Notifications | Bool | On/Off toggle, default Off |

## Screens & Interactions

### Main List View
- Shows habits due today first, with a Later section underneath for habits whose next scheduled date is after today
- Each row: habit name, frequency label, shorthand next date, completion indicator (checkmark or counter progress like "3/50")
- Floating "+" button to add a new habit
- Pull-to-refresh not needed (reactive data)

### Add/Edit Habit Sheet
- Presented as a `.sheet` modal
- Fields: name, frequency picker, custom interval (conditional), times-to-complete stepper, start date picker, notification toggle
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

- When enabled for a habit, send a local notification at a sensible default time (9:00 AM) on the habit's frequency schedule
- No notification customization in v1 (just on/off)

## Non-Goals (v1)

- No accounts or sync
- No Mac
- No statistics / charts
- No categories or tags
- No habit reordering (alphabetical)
- No dark/light mode toggle (follow system)
- No onboarding flow
