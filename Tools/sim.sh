#!/bin/zsh
# Helpers for the DashUp iPad simulator.
#   Tools/sim.sh build                 build + install the iPad app
#   Tools/sim.sh launch [args...]      relaunch the app with launch arguments (e.g. -demo -screen claude)
#   Tools/sim.sh shot <name>           save a landscape screenshot to .context/shots/<name>.png
set -e
cd "${0:A:h}/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
UDID=$(cat .context/sim-udid)
BUNDLE=com.tejasbaid.dashup.pad
case "$1" in
  build)
    xcodebuild -project DashUp.xcodeproj -scheme DashUpPad -configuration Debug -destination "id=$UDID" \
      -derivedDataPath .build/xcode build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sort -u
    xcrun simctl install $UDID .build/xcode/Build/Products/Debug-iphonesimulator/DashUp.app ;;
  launch)
    shift
    xcrun simctl terminate $UDID $BUNDLE 2>/dev/null || true
    xcrun simctl launch $UDID $BUNDLE "$@" >/dev/null ;;
  shot)
    mkdir -p .context/shots
    xcrun simctl io $UDID screenshot --type=png /tmp/dashup-shot.png >/dev/null 2>&1
    # The framebuffer is portrait; the app runs in landscape.
    w=$(sips -g pixelWidth /tmp/dashup-shot.png | awk '/pixelWidth/{print $2}')
    h=$(sips -g pixelHeight /tmp/dashup-shot.png | awk '/pixelHeight/{print $2}')
    if [ "$h" -gt "$w" ]; then sips -r 270 /tmp/dashup-shot.png --out .context/shots/$2.png >/dev/null; else cp /tmp/dashup-shot.png .context/shots/$2.png; fi
    echo .context/shots/$2.png ;;
esac
