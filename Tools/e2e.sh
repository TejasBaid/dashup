#!/bin/zsh
# End-to-end check: the simulator iPad pairs with the running Mac agent (started with
# DASHUP_PAIR_CODE=424242), a PermissionRequest hook is fired, and the UI test taps Allow.
cd "${0:A:h}/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
UDID=$(cat .context/sim-udid)
TOKEN=$(cat ~/Library/Application\ Support/DashUp/hook-token)
mkdir -p .context/shots .context/logs
rm -f .context/logs/e2e-hook.txt

TEST_RUNNER_DASHUP_PAIR_CODE=424242 TEST_RUNNER_DASHUP_SHOTS=$PWD/.context/shots \
  xcodebuild test -project DashUp.xcodeproj -scheme DashUpPad -destination "id=$UDID" -derivedDataPath .build/xcode \
  -only-testing:DashUpPadUITests/DashUpPadUITests/testPairAndApprove > .context/logs/e2e-test.log 2>&1 &
TEST=$!

# Wait for the iPad to connect.
for i in {1..180}; do
  clients=$(curl -s http://127.0.0.1:47823/health -H "Authorization: Bearer $TOKEN" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["clients"]))' 2>/dev/null)
  [ "$clients" -ge 1 ] 2>/dev/null && break
  sleep 1
done
echo "iPad connected after ${i}s"
sleep 8 # let the test take its Home screenshot first

# A live Claude Code session to attach the request to.
SESSION=$(python3 -c '
import glob, json, os
for f in sorted(glob.glob(os.path.expanduser("~/.claude/sessions/*.json")), key=os.path.getmtime, reverse=True):
    d = json.load(open(f))
    try: os.kill(d["pid"], 0)
    except OSError: continue
    print(d["sessionId"]); break')
curl -s -X POST http://127.0.0.1:47823/hooks/permission -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d "{\"session_id\":\"$SESSION\",\"hook_event_name\":\"PermissionRequest\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"swift test --package-path Packages/DashUpKit\"},\"cwd\":\"$PWD\"}" \
  > .context/logs/e2e-hook.txt
echo "hook answered: $(cat .context/logs/e2e-hook.txt)"
wait $TEST
grep -E "Test Case|error|TEST (SUCCEEDED|FAILED)" .context/logs/e2e-test.log | tail -5
