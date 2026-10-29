#!/usr/bin/env bash
# Offline acceptance checks (macOS).
#
#   scripts/offline-test.sh          # build first, then run the test suite with IP networking denied
#   scripts/offline-test.sh --app    # launch the built app with IP networking denied
#
# Uses the built-in sandbox-exec with a profile that denies all outbound IP traffic for
# the process and its children. Any attempt by the code under test to open a network
# connection fails (and is logged by the kernel as a sandbox violation).
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE='(version 1)
(allow default)
(deny network-outbound (remote ip))
(deny network-inbound (local ip))'

if [[ "${1:-}" == "--app" ]]; then
  APP_BIN="build/${APP_NAME:-Local Explorer}.app/Contents/MacOS/LocalExplorer"
  [[ -x "$APP_BIN" ]] || { echo "Build the app first: scripts/build-app.sh" >&2; exit 1; }
  echo "Launching with outbound networking denied. Watch for violations with:"
  echo "  log stream --predicate 'eventMessage CONTAINS \"deny(1) network\"' --style compact"
  exec sandbox-exec -p "$PROFILE" "$APP_BIN"
fi

# Build while networking is available (no dependencies are fetched, but keep the
# build step separate so the offline run measures only the code under test).
swift build --build-tests
echo "==> Running tests with outbound networking denied"
sandbox-exec -p "$PROFILE" swift test --skip-build
