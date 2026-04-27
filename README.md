# Habits

A minimal iOS habit tracker built with SwiftUI and SwiftData.

## Agent-Friendly Checks

Use the scripts in `scripts/` when changing the app from the command line:

```bash
./scripts/test-ai.sh          # full test suite, then a standalone build
./scripts/test-ai.sh --unit   # unit tests only
./scripts/test-ai.sh --ui     # XCUITest smoke flow only
./scripts/test-ai.sh --build  # build only
./scripts/test-visual.sh      # build, launch in Simulator, save a screenshot
```

## App Convenience Commands

Use `scripts/app.sh` for local installs and App Store upload:

```bash
./scripts/app.sh sim          # run Debug in the Simulator
./scripts/app.sh phone        # run Debug on the iPhone named "aci"
./scripts/app.sh phone-prod   # run Release on the iPhone named "aci"
./scripts/app.sh submit       # archive Release and upload to App Store Connect
```

Physical-device builds and App Store submissions default to the Albert Carreras
Apple Developer team (`YH4QJW8XNH`). Override with `HABITS_TEAM_ID` only when
you intentionally need another team. For App Store Connect API key upload, set
`HABITS_ASC_KEY_PATH`, `HABITS_ASC_KEY_ID`, and `HABITS_ASC_ISSUER_ID`.
App Store submissions remember the last marketing version and ask whether to
change it before each upload. The build number is reserved as the previous
build plus one every time `submit` runs. The submit state is stored at
`~/.local/state/habits/submit.env`; override that path with
`HABITS_SUBMIT_STATE_PATH`, or set `HABITS_APP_VERSION` for non-interactive
marketing-version changes.

Defaults target the available `iPhone 17 Pro` simulator. Override with:

```bash
HABITS_DESTINATION="platform=iOS Simulator,name=iPhone 17" ./scripts/test-ai.sh
HABITS_SIMULATOR_UDID="<udid>" ./scripts/test-visual.sh
HABITS_SIMULATOR_NAME="iPhone 17" ./scripts/app.sh sim
HABITS_DEVICE_NAME="My iPhone" ./scripts/app.sh phone
```

The UI test launch path uses an in-memory SwiftData store and disables widget timeline writes, so repeated test runs do not depend on local app data.
