#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SCHEME="${HABITS_SCHEME:-Habits}"
MAC_SCHEME="${HABITS_MAC_SCHEME:-HabitsMac}"
PROJECT="${HABITS_PROJECT:-Habits.xcodeproj}"
PRODUCT_NAME="${HABITS_PRODUCT_NAME:-Habits}"
BUNDLE_ID="${HABITS_BUNDLE_ID:-com.albertc.habit}"
MAC_BUNDLE_ID="${HABITS_MAC_BUNDLE_ID:-com.albertc.habit.mac}"
DERIVED_DATA="${HABITS_DERIVED_DATA:-/tmp/habits-app-derived-data}"
LOG_DIR="${HABITS_LOG_DIR:-/tmp/habits-logs}"
SIMULATOR_NAME="${HABITS_SIMULATOR_NAME:-iPhone 17 Pro}"
DEVICE_NAME="${HABITS_DEVICE_NAME:-aci}"
ALLOW_PROVISIONING_UPDATES="${HABITS_ALLOW_PROVISIONING_UPDATES:-1}"
TEAM_ID="${HABITS_TEAM_ID:-YH4QJW8XNH}"
ASC_KEY_PATH="${HABITS_ASC_KEY_PATH:-}"
ASC_KEY_ID="${HABITS_ASC_KEY_ID:-}"
ASC_ISSUER_ID="${HABITS_ASC_ISSUER_ID:-}"
SUBMIT_STATE_PATH="${HABITS_SUBMIT_STATE_PATH:-${XDG_STATE_HOME:-$HOME/.local/state}/habits/submit.env}"
APP_VERSION=""
BUILD_NUMBER=""
LAST_BUILT_APP_PATH=""

usage() {
    cat <<'USAGE'
Usage: ./scripts/app.sh <command>

Commands:
  sim            Build, install, and launch the Debug app in the Simulator.
  phone          Build, install, and launch the Debug app on the iPhone named "aci".
  phone-prod     Build, install, and launch the Release app on the iPhone named "aci".
  mac-test       Build the macOS app without code signing (CI/verification).
  mac-dmg        Build Release macOS and package as a DMG for distribution.
  submit         Archive Release iOS and upload to App Store Connect.
  mac-submit     Archive Release macOS and upload to Mac App Store.

Aliases:
  simulator, run-sim
  iphone, device, run-phone
  iphone-prod, device-prod, prod-phone
  store, upload
  mac-store, mac-upload

Environment:
  HABITS_SIMULATOR_NAME    Simulator name. Defaults to iPhone 17 Pro.
  HABITS_DEVICE_NAME       Physical device name. Defaults to aci.
  HABITS_MAC_SCHEME        macOS scheme. Defaults to HabitsMac.
  HABITS_MAC_BUNDLE_ID     macOS bundle ID. Defaults to com.albertc.habit.mac.
  HABITS_TEAM_ID           Apple Developer team ID. Defaults to Albert Carreras (YH4QJW8XNH).
  HABITS_DERIVED_DATA      DerivedData path. Defaults to /tmp/habits-app-derived-data.
  HABITS_ARCHIVE_PATH      Archive path for submit/mac-submit. Defaults to /tmp/habits-archives/<name>-<timestamp>.xcarchive.
  HABITS_EXPORT_PATH       Export/upload output path for submit/mac-submit.
  HABITS_SUBMIT_STATE_PATH Path that stores the last submitted version/build.
                           Defaults to ~/.local/state/habits/submit.env.
  HABITS_APP_VERSION       Non-interactive marketing version override for submit/mac-submit.
                           Stored for future submit prompts when provided.
  HABITS_DMG_DIR           Output directory for mac-dmg. Defaults to /tmp/habits-dmg.

App Store Connect API key auth for submit/mac-submit:
  HABITS_ASC_KEY_PATH      Path to AuthKey_<key-id>.p8.
  HABITS_ASC_KEY_ID        App Store Connect key ID.
  HABITS_ASC_ISSUER_ID     App Store Connect issuer ID.

If the App Store Connect variables are omitted, xcodebuild uses the Apple
account configured in Xcode.
USAGE
}

# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------

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
    preferred="$(xcrun simctl list devices available | awk -F '[()]' -v name="$SIMULATOR_NAME" 'index($0, name) { print $2; exit }')"
    if [[ -n "$preferred" ]]; then
        printf '%s\n' "$preferred"
        return
    fi

    local fallback
    fallback="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $2; exit }')"
    if [[ -n "$fallback" ]]; then
        echo "Simulator \"$SIMULATOR_NAME\" not found; using fallback iPhone simulator $fallback" >&2
        printf '%s\n' "$fallback"
        return
    fi

    echo "No available iPhone simulator found. Set HABITS_SIMULATOR_UDID explicitly." >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Build-setting helpers
# ---------------------------------------------------------------------------

signing_args() {
    if [[ -n "$TEAM_ID" ]]; then
        printf '%s\n' "DEVELOPMENT_TEAM=$TEAM_ID"
    fi
}

provisioning_args() {
    if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]; then
        printf '%s\n' "-allowProvisioningUpdates"
    fi
}

device_provisioning_args() {
    provisioning_args
    if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]; then
        printf '%s\n' "-allowProvisioningDeviceRegistration"
    fi
}

version_args() {
    printf '%s\n' "MARKETING_VERSION=$APP_VERSION"
    printf '%s\n' "CURRENT_PROJECT_VERSION=$BUILD_NUMBER"
}

auth_args() {
    if [[ -z "$ASC_KEY_PATH" && -z "$ASC_KEY_ID" && -z "$ASC_ISSUER_ID" ]]; then
        return
    fi
    printf '%s\n' "-authenticationKeyPath"
    printf '%s\n' "$ASC_KEY_PATH"
    printf '%s\n' "-authenticationKeyID"
    printf '%s\n' "$ASC_KEY_ID"
    printf '%s\n' "-authenticationKeyIssuerID"
    printf '%s\n' "$ASC_ISSUER_ID"
}

validate_auth_args() {
    local has_any_auth=0
    if [[ -n "$ASC_KEY_PATH" || -n "$ASC_KEY_ID" || -n "$ASC_ISSUER_ID" ]]; then
        has_any_auth=1
    fi
    if [[ "$has_any_auth" == "0" ]]; then
        return
    fi
    if [[ -z "$ASC_KEY_PATH" || -z "$ASC_KEY_ID" || -z "$ASC_ISSUER_ID" ]]; then
        echo "Set HABITS_ASC_KEY_PATH, HABITS_ASC_KEY_ID, and HABITS_ASC_ISSUER_ID together." >&2
        exit 2
    fi
}

collect_args() {
    local fn="$1"
    while IFS= read -r arg; do
        printf '%s\n' "$arg"
    done < <("$fn")
}

# ---------------------------------------------------------------------------
# Version / state helpers
# ---------------------------------------------------------------------------

project_setting() {
    local setting="$1"
    if [[ ! -f project.yml ]]; then
        return
    fi
    awk -F: -v setting="$setting" '
        $1 ~ "^[[:space:]]*" setting "[[:space:]]*$" {
            value = $2
            gsub(/^[[:space:]"]+|[[:space:]"]+$/, "", value)
            print value
            exit
        }
    ' project.yml
}

submit_state_value() {
    local key="$1"
    if [[ ! -f "$SUBMIT_STATE_PATH" ]]; then
        return
    fi
    awk -F= -v key="$key" '
        $1 == key {
            value = substr($0, length(key) + 2)
        }
        END {
            if (value != "") {
                print value
            }
        }
    ' "$SUBMIT_STATE_PATH"
}

validate_marketing_version() {
    local value="$1"
    if [[ -z "$value" || "$value" =~ [[:space:]] ]]; then
        echo "Marketing version must be non-empty and contain no whitespace." >&2
        exit 2
    fi
}

validate_build_number() {
    local value="$1"
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        echo "Build number must be a non-negative integer; got \"$value\"." >&2
        exit 2
    fi
}

write_submit_state() {
    local app_version="$1"
    local build_number="$2"
    local state_dir
    state_dir="$(dirname "$SUBMIT_STATE_PATH")"
    mkdir -p "$state_dir"
    local tmp_path="$SUBMIT_STATE_PATH.tmp.$$"
    {
        printf '%s\n' "# Last version reserved by scripts/app.sh submit."
        printf 'HABITS_APP_VERSION=%s\n' "$app_version"
        printf 'HABITS_LAST_BUILD_NUMBER=%s\n' "$build_number"
    } > "$tmp_path"
    mv "$tmp_path" "$SUBMIT_STATE_PATH"
}

resolve_submit_version() {
    local stored_version stored_build project_version project_build
    stored_version="$(submit_state_value HABITS_APP_VERSION)"
    stored_build="$(submit_state_value HABITS_LAST_BUILD_NUMBER)"
    project_version="$(project_setting MARKETING_VERSION)"
    project_build="$(project_setting CURRENT_PROJECT_VERSION)"

    local current_version="${stored_version:-${project_version:-1.1}}"
    local last_build_number="${stored_build:-${project_build:-2}}"
    validate_marketing_version "$current_version"
    validate_build_number "$last_build_number"

    if [[ -n "${HABITS_APP_VERSION:-}" ]]; then
        APP_VERSION="$HABITS_APP_VERSION"
    elif [[ -t 0 ]]; then
        local answer
        printf 'Marketing version for this submit [%s]: ' "$current_version" >&2
        read -r answer
        APP_VERSION="${answer:-$current_version}"
    else
        APP_VERSION="$current_version"
        echo "Using marketing version $APP_VERSION; set HABITS_APP_VERSION to override in non-interactive runs."
    fi

    validate_marketing_version "$APP_VERSION"
    BUILD_NUMBER="$((last_build_number + 1))"
    write_submit_state "$APP_VERSION" "$BUILD_NUMBER"
}

# ---------------------------------------------------------------------------
# xcodebuild runner
# ---------------------------------------------------------------------------

run_xcodebuild() {
    local label="$1"
    shift
    mkdir -p "$LOG_DIR"
    local log_file="$LOG_DIR/${label}.log"

    echo
    echo "==> $label"
    echo "Log: $log_file"

    xcodebuild "$@" 2>&1 | tee "$log_file"
}

# ---------------------------------------------------------------------------
# Build helpers
# ---------------------------------------------------------------------------

build_app() {
    local scheme="$1"
    local configuration="$2"
    local destination="$3"
    local label="$4"
    shift 4

    local args=()
    while IFS= read -r arg; do args+=("$arg"); done < <(signing_args)

    run_xcodebuild "$label" \
        -project "$PROJECT" \
        -scheme "$scheme" \
        -configuration "$configuration" \
        -destination "$destination" \
        -derivedDataPath "$DERIVED_DATA" \
        ${args[@]+"${args[@]}"} \
        "$@" \
        build
}

find_built_app() {
    local configuration="$1"
    local platform="$2"
    local products_dir
    if [[ -n "$platform" ]]; then
        products_dir="$DERIVED_DATA/Build/Products/${configuration}-${platform}"
    else
        products_dir="$DERIVED_DATA/Build/Products/${configuration}"
    fi

    if [[ ! -d "$products_dir" ]]; then
        echo "Build products directory not found: $products_dir" >&2
        exit 1
    fi

    local app_path
    app_path="$(find "$products_dir" -maxdepth 2 -type d -name "$PRODUCT_NAME.app" -print -quit)"
    if [[ -z "$app_path" ]]; then
        local app_paths=()
        while IFS= read -r path; do app_paths+=("$path"); done < <(find "$products_dir" -maxdepth 1 -type d -name "*.app" -print)
        if [[ ${#app_paths[@]} -eq 1 ]]; then
            app_path="${app_paths[0]}"
        fi
    fi
    if [[ -z "$app_path" ]]; then
        echo "Could not find $PRODUCT_NAME.app under $products_dir" >&2
        exit 1
    fi

    printf '%s\n' "$app_path"
}

create_export_options_plist() {
    local export_options_plist="$1"
    local team_entry=""

    if [[ -n "$TEAM_ID" ]]; then
        team_entry="    <key>teamID</key>
    <string>$TEAM_ID</string>"
    fi

    cat > "$export_options_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>upload</string>
    <key>manageAppVersionAndBuildNumber</key>
    <true/>
    <key>method</key>
    <string>app-store-connect</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
$team_entry
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
PLIST
}

# ---------------------------------------------------------------------------
# Simulator / device commands
# ---------------------------------------------------------------------------

run_simulator() {
    require_tool xcodebuild
    require_tool xcrun

    local udid
    udid="$(resolve_simulator_udid)"
    local destination="id=$udid"

    build_app "$SCHEME" Debug "$destination" simulator-debug

    local app_path
    app_path="$(find_built_app Debug iphonesimulator)"

    echo
    echo "Booting simulator $udid"
    xcrun simctl boot "$udid" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$udid" -b
    if command -v open >/dev/null 2>&1; then
        open -a Simulator >/dev/null 2>&1 || true
    fi

    echo "Installing and launching $app_path"
    xcrun simctl install "$udid" "$app_path"
    xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl launch "$udid" "$BUNDLE_ID"
}

run_phone() {
    local configuration="$1"
    local label="$2"
    require_tool xcodebuild
    require_tool xcrun

    local provisioning=()
    while IFS= read -r arg; do provisioning+=("$arg"); done < <(device_provisioning_args)

    build_app "$SCHEME" "$configuration" "platform=iOS,name=$DEVICE_NAME" "$label" ${provisioning[@]+"${provisioning[@]}"}

    local app_path
    app_path="$(find_built_app "$configuration" iphoneos)"

    echo
    echo "Installing and launching $app_path on $DEVICE_NAME"
    xcrun devicectl device install app --device "$DEVICE_NAME" "$app_path"
    xcrun devicectl device process launch --device "$DEVICE_NAME" --terminate-existing "$BUNDLE_ID"
}

# ---------------------------------------------------------------------------
# macOS build commands
# ---------------------------------------------------------------------------

build_mac() {
    local configuration="$1"
    local allows_unsigned="$2"
    require_tool xcodebuild

    local extra_args=()
    if [[ "$allows_unsigned" == "1" ]]; then
        extra_args+=("CODE_SIGNING_ALLOWED=NO")
    else
        while IFS= read -r arg; do extra_args+=("$arg"); done < <(provisioning_args)
    fi

    local label
    label="mac-$(printf '%s' "$configuration" | tr '[:upper:]' '[:lower:]')"
    build_app "$MAC_SCHEME" "$configuration" "platform=macOS" "$label" ${extra_args[@]+"${extra_args[@]}"}
    LAST_BUILT_APP_PATH="$(find_built_app "$configuration" "")"
}

build_mac_test() {
    build_mac Debug 1

    echo
    echo "Build verified (unsigned): $LAST_BUILT_APP_PATH"
}

build_mac_dmg() {
    require_tool hdiutil

    build_mac Release 0

    local dmg_dir="${HABITS_DMG_DIR:-/tmp/habits-dmg}"
    local dmg_path="$dmg_dir/$PRODUCT_NAME.dmg"
    mkdir -p "$dmg_dir"

    local staging="$dmg_dir/.staging"
    rm -rf "$staging"
    mkdir -p "$staging"
    cp -R "$LAST_BUILT_APP_PATH" "$staging/"
    ln -s /Applications "$staging/Applications"

    hdiutil create -volname "$PRODUCT_NAME" -srcfolder "$staging" -ov -format UDZO "$dmg_path"
    rm -rf "$staging"

    echo
    echo "DMG created: $dmg_path"
}

# ---------------------------------------------------------------------------
# App Store submission (shared by iOS and macOS)
# ---------------------------------------------------------------------------

archive_and_upload() {
    local scheme="$1"
    local platform_dest="$2"
    require_tool xcodebuild
    validate_auth_args
    resolve_submit_version

    local timestamp
    timestamp="$(date +"%Y%m%d-%H%M%S")"
    local archive_root="${HABITS_ARCHIVE_ROOT:-/tmp/habits-archives}"
    local archive_path="${HABITS_ARCHIVE_PATH:-$archive_root/$PRODUCT_NAME-$timestamp.xcarchive}"
    local export_path="${HABITS_EXPORT_PATH:-$archive_root/$PRODUCT_NAME-$timestamp-export}"
    local export_options_plist="${HABITS_EXPORT_OPTIONS_PLIST:-$export_path/ExportOptions.plist}"

    mkdir -p "$archive_root" "$export_path"
    create_export_options_plist "$export_options_plist"

    local signing=()
    local version=()
    local provisioning=()
    local auth=()
    while IFS= read -r arg; do signing+=("$arg"); done < <(signing_args)
    while IFS= read -r arg; do version+=("$arg"); done < <(version_args)
    while IFS= read -r arg; do provisioning+=("$arg"); done < <(provisioning_args)
    while IFS= read -r arg; do auth+=("$arg"); done < <(auth_args)

    if [[ ${#auth[@]} -eq 0 ]]; then
        echo "No App Store Connect API key env vars set; xcodebuild will use the account configured in Xcode."
    fi
    echo "Submitting version $APP_VERSION ($BUILD_NUMBER)."

    run_xcodebuild archive-release \
        -project "$PROJECT" \
        -scheme "$scheme" \
        -configuration Release \
        -destination "$platform_dest" \
        -archivePath "$archive_path" \
        -derivedDataPath "$DERIVED_DATA" \
        ${signing[@]+"${signing[@]}"} \
        ${version[@]+"${version[@]}"} \
        ${provisioning[@]+"${provisioning[@]}"} \
        ${auth[@]+"${auth[@]}"} \
        archive

    run_xcodebuild app-store-upload \
        -exportArchive \
        -archivePath "$archive_path" \
        -exportPath "$export_path" \
        -exportOptionsPlist "$export_options_plist" \
        ${provisioning[@]+"${provisioning[@]}"} \
        ${auth[@]+"${auth[@]}"}

    echo
    echo "Submitted archive: $archive_path"
    echo "Export output: $export_path"
}

# ---------------------------------------------------------------------------
# Command dispatch
# ---------------------------------------------------------------------------

COMMAND="${1:-}"
case "$COMMAND" in
    sim|simulator|run-sim)
        ensure_project_current
        run_simulator
        ;;
    phone|iphone|device|run-phone)
        ensure_project_current
        run_phone Debug phone-debug
        ;;
    phone-prod|iphone-prod|device-prod|prod-phone)
        ensure_project_current
        run_phone Release phone-release
        ;;
    mac-test)
        ensure_project_current
        build_mac_test
        ;;
    mac-dmg)
        ensure_project_current
        build_mac_dmg
        ;;
    submit|store|upload)
        ensure_project_current
        archive_and_upload "$SCHEME" "generic/platform=iOS"
        ;;
    mac-submit|mac-store|mac-upload)
        ensure_project_current
        archive_and_upload "$MAC_SCHEME" "generic/platform=macOS"
        ;;
    -h|--help|help)
        usage
        ;;
    "")
        usage >&2
        exit 2
        ;;
    *)
        echo "Unknown command: $COMMAND" >&2
        usage >&2
        exit 2
        ;;
esac
