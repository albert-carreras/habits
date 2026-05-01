#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCHEME="${HABITS_SCHEME:-Habits}"
MAC_SCHEME="${HABITS_MAC_SCHEME:-HabitsMac}"
PROJECT="${HABITS_PROJECT:-Habits.xcodeproj}"
DERIVED_DATA="${HABITS_DERIVED_DATA:-/tmp/habits-derived-data}"
RESULT_ROOT="${HABITS_RESULT_ROOT:-/tmp/habits-xcresults}"
LOG_DIR="${HABITS_LOG_DIR:-/tmp/habits-logs}"
DESTINATION="${HABITS_DESTINATION:-}"
KILL_COMMAND="${HABITS_KILL_COMMAND:-kill}"
KILL_GRACE_SECONDS="${HABITS_KILL_GRACE_SECONDS:-2}"
MODE="all"

usage() {
    cat <<'USAGE'
Usage: ./scripts/test-ai.sh [--all|--unit|--ui|--smoke|--build|--mac-test|--kill] [--destination DESTINATION]

Modes:
  --all      Run all tests, then standalone iOS and Mac app builds. Default.
  --unit     Run only HabitsTests.
  --ui       Run only HabitsUITests.
  --smoke    Alias for --ui.
  --build    Build the app without running tests.
  --mac-test Build the native macOS app without running tests.
  --kill     Stop running Habits test/build processes started by this script.

Environment:
  HABITS_DESTINATION    xcodebuild destination. Defaults to iPhone 17 Pro if available.
  HABITS_DERIVED_DATA   DerivedData directory. Defaults to /tmp/habits-derived-data.
  HABITS_LOG_DIR        Log directory. Defaults to /tmp/habits-logs.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            MODE="all"
            shift
            ;;
        --unit)
            MODE="unit"
            shift
            ;;
        --ui|--smoke)
            MODE="ui"
            shift
            ;;
        --build)
            MODE="build"
            shift
            ;;
        --mac-test)
            MODE="mac-test"
            shift
            ;;
        --kill)
            MODE="kill"
            shift
            ;;
        --destination)
            DESTINATION="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required tool: $1" >&2
        exit 127
    fi
}

matching_test_pids() {
    ps -Ao pid=,command= | awk \
        -v self="$$" \
        -v parent="${PPID:-}" \
        -v project="$PROJECT" \
        -v scheme="$SCHEME" \
        -v derived_data="$DERIVED_DATA" \
        -v result_root="$RESULT_ROOT" '
            {
                pid = $1
                command = $0
                sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "", command)

                if (pid == self || pid == parent) {
                    next
                }

                matched = 0
                if (command ~ /xcodebuild/ && index(command, project) && index(command, scheme)) {
                    matched = 1
                }
                if (command ~ /xcodebuild/ && index(command, derived_data)) {
                    matched = 1
                }
                if (command ~ /xcodebuild/ && index(command, result_root)) {
                    matched = 1
                }
                if (command ~ /[s]cripts\/test-ai\.sh/ && command !~ /--kill/) {
                    matched = 1
                }

                if (matched) {
                    print pid
                }
            }
        '
}

kill_testing() {
    require_tool ps
    require_tool "$KILL_COMMAND"

    local pids=()
    local pid
    while IFS= read -r pid; do
        if [[ -n "$pid" ]]; then
            pids+=("$pid")
        fi
    done < <(matching_test_pids)

    if [[ ${#pids[@]} -eq 0 ]]; then
        echo "No running Habits test processes found."
        return
    fi

    echo "Stopping ${#pids[@]} Habits test process(es): ${pids[*]}"
    "$KILL_COMMAND" -TERM "${pids[@]}" 2>/dev/null || true

    if [[ "$KILL_GRACE_SECONDS" != "0" ]]; then
        sleep "$KILL_GRACE_SECONDS"
    fi

    local still_running=()
    for pid in "${pids[@]}"; do
        if "$KILL_COMMAND" -0 "$pid" 2>/dev/null; then
            still_running+=("$pid")
        fi
    done

    if [[ ${#still_running[@]} -gt 0 ]]; then
        echo "Force-stopping ${#still_running[@]} remaining process(es): ${still_running[*]}"
        "$KILL_COMMAND" -KILL "${still_running[@]}" 2>/dev/null || true
    fi
}

resolve_destination() {
    if [[ -n "$DESTINATION" ]]; then
        printf '%s\n' "$DESTINATION"
        return
    fi

    if xcrun simctl list devices available | grep -q "iPhone 17 Pro"; then
        printf '%s\n' "platform=iOS Simulator,name=iPhone 17 Pro"
        return
    fi

    local fallback
    fallback="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print $1; exit }')"
    if [[ -n "$fallback" ]]; then
        printf 'platform=iOS Simulator,name=%s\n' "$fallback"
        return
    fi

    echo "No available iPhone simulator found. Set HABITS_DESTINATION explicitly." >&2
    exit 1
}

ensure_project_current() {
    if [[ -f project.yml && ( ! -f "$PROJECT/project.pbxproj" || project.yml -nt "$PROJECT/project.pbxproj" ) ]]; then
        require_tool xcodegen
        echo "Regenerating $PROJECT from project.yml"
        xcodegen generate
    fi
}

run_script_regressions() {
    if [[ "$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' Habits/Info.plist)" != "false" ]]; then
        echo "Habits/Info.plist must declare ITSAppUsesNonExemptEncryption=false" >&2
        exit 1
    fi

    if [[ "$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' HabitsWidget/Info.plist)" != "false" ]]; then
        echo "HabitsWidget/Info.plist must declare ITSAppUsesNonExemptEncryption=false" >&2
        exit 1
    fi

    if [[ "$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' HabitsMac/Info.plist)" != "false" ]]; then
        echo "HabitsMac/Info.plist must declare ITSAppUsesNonExemptEncryption=false" >&2
        exit 1
    fi

    if [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSApplicationCategoryType' HabitsMac/Info.plist)" != "public.app-category.productivity" ]]; then
        echo "HabitsMac/Info.plist must declare LSApplicationCategoryType=public.app-category.productivity" >&2
        exit 1
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/habits-app-sh-test.XXXXXX")"
    local bin_dir="$tmp_dir/bin"
    mkdir -p "$bin_dir"

    cat > "$bin_dir/xcodebuild" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$HABITS_DERIVED_DATA/Build/Products/Debug-iphonesimulator/Habits.app"
if [[ -n "${STUB_XCODEBUILD_LOG:-}" ]]; then
    printf '%s\n' "$*" >> "$STUB_XCODEBUILD_LOG"
fi
printf 'stub xcodebuild'
STUB

    cat > "$bin_dir/xcrun" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
exit 0
STUB

    cat > "$bin_dir/open" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
exit 0
STUB

    cat > "$bin_dir/ps" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" != "-Ao pid=,command=" ]]; then
    exit 2
fi
cat <<'PS'
 99101 xcodebuild -project Habits.xcodeproj -scheme Habits -derivedDataPath /tmp/habits-derived-data test
 99102 /usr/bin/env bash ./scripts/test-ai.sh --unit
 99103 /usr/bin/env bash ./scripts/test-ai.sh --kill
 99104 xcodebuild -project Other.xcodeproj -scheme Other test
PS
STUB

    local kill_stub="$bin_dir/kill-stub"
    cat > "$kill_stub" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "-0" ]]; then
    exit 1
fi
printf '%s\n' "$*" >> "$STUB_KILL_LOG"
STUB

    chmod +x "$bin_dir/xcodebuild" "$bin_dir/xcrun" "$bin_dir/open" "$bin_dir/ps" "$kill_stub"

    echo
    echo "==> script-regressions"
    PATH="$bin_dir:$PATH" \
        HABITS_DERIVED_DATA="$tmp_dir/DerivedData" \
        HABITS_LOG_DIR="$tmp_dir/logs" \
        HABITS_SIMULATOR_UDID="TEST-SIM-UDID" \
        ./scripts/app.sh sim > "$tmp_dir/app-sim.log"

    local xcodebuild_log="$tmp_dir/xcodebuild.args"
    local submit_state="$tmp_dir/submit.env"
    PATH="$bin_dir:$PATH" \
        STUB_XCODEBUILD_LOG="$xcodebuild_log" \
        HABITS_DERIVED_DATA="$tmp_dir/DerivedData" \
        HABITS_LOG_DIR="$tmp_dir/logs" \
        HABITS_ARCHIVE_ROOT="$tmp_dir/archives" \
        HABITS_SUBMIT_STATE_PATH="$submit_state" \
        HABITS_ALLOW_PROVISIONING_UPDATES=0 \
        ./scripts/app.sh submit < /dev/null > "$tmp_dir/app-submit.log"

    if ! grep -q "MARKETING_VERSION=1.1" "$xcodebuild_log"; then
        echo "app.sh submit did not pass MARKETING_VERSION=1.1 to xcodebuild" >&2
        exit 1
    fi

    if ! grep -q "CURRENT_PROJECT_VERSION=3" "$xcodebuild_log"; then
        echo "app.sh submit did not increment CURRENT_PROJECT_VERSION to 3" >&2
        exit 1
    fi

    if ! grep -q "DEVELOPMENT_TEAM=YH4QJW8XNH" "$xcodebuild_log"; then
        echo "app.sh submit did not pass the Albert Carreras team to xcodebuild" >&2
        exit 1
    fi

    if ! grep -q "HABITS_LAST_BUILD_NUMBER=3" "$submit_state"; then
        echo "app.sh submit did not persist the reserved build number" >&2
        exit 1
    fi

    : > "$xcodebuild_log"
    PATH="$bin_dir:$PATH" \
        STUB_XCODEBUILD_LOG="$xcodebuild_log" \
        HABITS_DERIVED_DATA="$tmp_dir/DerivedData" \
        HABITS_LOG_DIR="$tmp_dir/logs" \
        HABITS_ARCHIVE_ROOT="$tmp_dir/archives" \
        HABITS_SUBMIT_STATE_PATH="$submit_state" \
        HABITS_APP_VERSION=1.2 \
        HABITS_ALLOW_PROVISIONING_UPDATES=0 \
        ./scripts/app.sh submit < /dev/null > "$tmp_dir/app-submit-version-change.log"

    if ! grep -q "MARKETING_VERSION=1.2" "$xcodebuild_log"; then
        echo "app.sh submit did not pass the updated MARKETING_VERSION to xcodebuild" >&2
        exit 1
    fi

    if ! grep -q "CURRENT_PROJECT_VERSION=4" "$xcodebuild_log"; then
        echo "app.sh submit did not keep incrementing CURRENT_PROJECT_VERSION" >&2
        exit 1
    fi

    if ! grep -q "HABITS_APP_VERSION=1.2" "$submit_state"; then
        echo "app.sh submit did not persist the updated marketing version" >&2
        exit 1
    fi

    : > "$xcodebuild_log"
    PATH="$bin_dir:$PATH" \
        STUB_XCODEBUILD_LOG="$xcodebuild_log" \
        HABITS_DERIVED_DATA="$tmp_dir/DerivedData" \
        HABITS_LOG_DIR="$tmp_dir/logs" \
        HABITS_ARCHIVE_ROOT="$tmp_dir/archives" \
        HABITS_SUBMIT_STATE_PATH="$submit_state" \
        HABITS_ALLOW_PROVISIONING_UPDATES=0 \
        ./scripts/app.sh mac-submit < /dev/null > "$tmp_dir/app-mac-submit.log"

    if ! grep -q "\-scheme HabitsMac" "$xcodebuild_log"; then
        echo "app.sh mac-submit did not use the HabitsMac scheme" >&2
        exit 1
    fi

    if ! grep -q "generic/platform=macOS" "$xcodebuild_log"; then
        echo "app.sh mac-submit did not target macOS platform" >&2
        exit 1
    fi

    if ! grep -q "CURRENT_PROJECT_VERSION=5" "$xcodebuild_log"; then
        echo "app.sh mac-submit did not keep incrementing CURRENT_PROJECT_VERSION" >&2
        exit 1
    fi

    local kill_log="$tmp_dir/kill.args"
    PATH="$bin_dir:$PATH" \
        STUB_KILL_LOG="$kill_log" \
        HABITS_KILL_COMMAND="$kill_stub" \
        HABITS_KILL_GRACE_SECONDS=0 \
        ./scripts/test-ai.sh --kill > "$tmp_dir/test-ai-kill.log"

    if ! grep -q -- "-TERM 99101 99102" "$kill_log"; then
        echo "test-ai.sh --kill did not stop the matching test processes" >&2
        exit 1
    fi

    if grep -Eq "99103|99104" "$kill_log"; then
        echo "test-ai.sh --kill stopped a non-target process" >&2
        exit 1
    fi
}

summarize_failure() {
    local log_file="$1"
    echo
    echo "Key failure lines from $log_file:"
    if command -v rg >/dev/null 2>&1; then
        rg -n "error:|failed:|Testing failed|XCTAssert|#expect" "$log_file" | tail -n 80 || true
    else
        grep -En "error:|failed:|Testing failed|XCTAssert|#expect" "$log_file" | tail -n 80 || true
    fi
}

run_xcodebuild() {
    local label="$1"
    shift

    mkdir -p "$LOG_DIR" "$RESULT_ROOT"
    local destination
    destination="$(resolve_destination)"
    local log_file="$LOG_DIR/${label}.log"
    local result_bundle="$RESULT_ROOT/${label}.xcresult"
    rm -rf "$result_bundle"

    echo
    echo "==> $label"
    echo "Destination: $destination"
    echo "Log: $log_file"

    set +e
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination "$destination" \
        -derivedDataPath "$DERIVED_DATA" \
        -resultBundlePath "$result_bundle" \
        "$@" 2>&1 | tee "$log_file"
    local status=${PIPESTATUS[0]}
    set -e

    if [[ $status -ne 0 ]]; then
        summarize_failure "$log_file"
        echo "Result bundle: $result_bundle"
        exit "$status"
    fi
}

run_mac_test() {
    local previous_scheme="$SCHEME"
    local previous_destination="$DESTINATION"

    SCHEME="$MAC_SCHEME"
    DESTINATION="platform=macOS"
    run_xcodebuild mac-test build CODE_SIGNING_ALLOWED=NO

    SCHEME="$previous_scheme"
    DESTINATION="$previous_destination"
}

if [[ "$MODE" == "kill" ]]; then
    kill_testing
    exit 0
fi

require_tool xcodebuild
require_tool xcrun
ensure_project_current
run_script_regressions

case "$MODE" in
    all)
        run_xcodebuild full-tests test
        run_xcodebuild app-build build
        run_mac_test
        ;;
    unit)
        run_xcodebuild unit-tests test -only-testing:HabitsTests
        ;;
    ui)
        run_xcodebuild ui-smoke test -only-testing:HabitsUITests
        ;;
    build)
        run_xcodebuild app-build build
        ;;
    mac-test)
        run_mac_test
        ;;
esac

echo
echo "Done. Logs are in $LOG_DIR"
