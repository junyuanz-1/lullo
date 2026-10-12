#!/usr/bin/env bash
# Screenshot diff tests (Tests/TinytideSnapshotTests).
#
#   scripts/snapshots.sh           compare against the reference images
#   scripts/snapshots.sh record    re-record the reference images
#
# Reference images depend on the exact Xcode and simulator, so they are
# recorded on CI (the "Record snapshots" workflow). Locally, use the same
# Xcode as CI or expect small differences.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-verify}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=latest}"
DERIVED="${DERIVED_DATA:-build/DerivedData}"
RESULTS="${RESULTS_DIR:-build/snapshot-results}"
ARTIFACTS="${SNAPSHOT_ARTIFACTS:-$PWD/build/snapshot-diffs}"
# language:region pairs; English also covers dark mode and large text.
LANGUAGES="${SNAPSHOT_LANGUAGES:-en:US zh-Hans:CN de:DE}"

case "$MODE" in
  verify) RECORD=never ;;
  record) RECORD=all ;;
  *) echo "usage: $0 [verify|record]" >&2; exit 2 ;;
esac

pretty() { if command -v xcbeautify >/dev/null; then xcbeautify --quiet; else cat; fi; }

rm -rf "$RESULTS" "$ARTIFACTS"
mkdir -p "$RESULTS" "$ARTIFACTS"

# SKIP_BUILD=1 when the TinytideSnapshots scheme was already built into $DERIVED_DATA.
if [ "${SKIP_BUILD:-0}" != "1" ]; then
  xcodebuild build-for-testing \
    -project Tinytide.xcodeproj -scheme TinytideSnapshots \
    -destination "$DESTINATION" -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO | pretty
fi

status=0
for pair in $LANGUAGES; do
  language="${pair%%:*}"
  region="${pair##*:}"
  echo "▸ Snapshots: $language ($region), $MODE"
  # TEST_RUNNER_ variables are passed (without the prefix) to the test process.
  TEST_RUNNER_SNAPSHOT_TESTING_RECORD="$RECORD" \
  TEST_RUNNER_SNAPSHOT_ARTIFACTS="$ARTIFACTS" \
  xcodebuild test-without-building \
    -project Tinytide.xcodeproj -scheme TinytideSnapshots \
    -destination "$DESTINATION" -derivedDataPath "$DERIVED" \
    -testLanguage "$language" -testRegion "$region" \
    -resultBundlePath "$RESULTS/$language.xcresult" | pretty || status=$?
done

if [ "$MODE" = record ]; then
  # Recording reports every assertion as a failure; what matters is the images.
  count=$(find Tests/TinytideSnapshotTests/__Snapshots__ -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
  echo "Recorded $count reference images in Tests/TinytideSnapshotTests/__Snapshots__"
  [ "$count" -gt 0 ]
else
  if [ "$status" -ne 0 ]; then
    echo "Snapshots differ. Failed images and diffs: $ARTIFACTS" >&2
  fi
  exit "$status"
fi
