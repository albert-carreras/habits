#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCHEME="${HABITS_SCHEME:-Habits}"
PROJECT="${HABITS_PROJECT:-Habits.xcodeproj}"
DERIVED_DATA="${HABITS_DERIVED_DATA:-/tmp/habits-visual-derived-data}"
SCREENSHOT_PATH="${HABITS_SCREENSHOT_PATH:-/tmp/habits-screenshot.png}"
BUNDLE_ID="${HABITS_BUNDLE_ID:-com.albertc.habit}"

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required tool: $1" >&2
        exit 127
    fi
}

ensure_project_current() {
    if [[ -f project.yml && ( ! -f "$PROJECT/project.pbxproj" || project.yml -nt "$PROJECT/project.pbxproj" ) ]]; then
        require_tool xcodegen
        echo "Regenerating $PROJECT from project.yml"
        xcodegen generate
    fi
}

resolve_simulator_udid() {
    if [[ -n "${HABITS_SIMULATOR_UDID:-}" ]]; then
        printf '%s\n' "$HABITS_SIMULATOR_UDID"
        return
    fi

    local preferred
    preferred="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone 17 Pro/ { print $2; exit }')"
    if [[ -n "$preferred" ]]; then
        printf '%s\n' "$preferred"
        return
    fi

    local fallback
    fallback="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $2; exit }')"
    if [[ -n "$fallback" ]]; then
        printf '%s\n' "$fallback"
        return
    fi

    echo "No available iPhone simulator found. Set HABITS_SIMULATOR_UDID explicitly." >&2
    exit 1
}

require_tool xcodebuild
require_tool xcrun
ensure_project_current

UDID="$(resolve_simulator_udid)"
DESTINATION="id=$UDID"

echo "Building $SCHEME for simulator $UDID"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    build

APP_PATH="$(find "$DERIVED_DATA/Build/Products/Debug-iphonesimulator" -maxdepth 2 -type d -name "Habits.app" | head -n 1)"
if [[ -z "$APP_PATH" ]]; then
    echo "Could not find built Habits.app under $DERIVED_DATA" >&2
    exit 1
fi

echo "Booting simulator"
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b

echo "Installing and launching $APP_PATH"
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" -ui-testing
sleep 2

xcrun simctl io "$UDID" screenshot "$SCREENSHOT_PATH"
echo "Screenshot: $SCREENSHOT_PATH"
