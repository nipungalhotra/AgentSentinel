#!/bin/sh
# Runs as a normal user, the way someone would install loggdin from the release zip.
set -e
cd ~
mkdir -p ~/.claude ~/.codex           # pretend Claude Code and Codex are installed
echo '{"model":"opus","permissions":{"allow":["Bash(ls:*)"]}}' > ~/.claude/settings.json
unzip -q "${LOGGDIN_ZIP:?set LOGGDIN_ZIP to the portable zip}"
cd "$(basename "${LOGGDIN_ZIP}" .zip)"   # folder name follows the version in the zip name
echo "=== install.sh"
./install.sh
export PATH="$HOME/.local/bin:$PATH"
echo "=== loggdin status / doctor"
loggdin status | head -4
loggdin doctor
echo "=== settings.json kept + hooked"
python3 - <<'PY'
import json, os
c = json.load(open(os.path.expanduser("~/.claude/settings.json")))
print("model kept:", c["model"], "| permissions kept:", c["permissions"])
print("PermissionRequest hook:", c["hooks"]["PermissionRequest"][0]["hooks"][0]["command"])
x = json.load(open(os.path.expanduser("~/.codex/hooks.json")))
print("codex events:", sorted(x["hooks"]))
PY
HOOK_CMD=$(python3 -c 'import json,os;print(json.load(open(os.path.expanduser("~/.claude/settings.json")))["hooks"]["PermissionRequest"][0]["hooks"][0]["command"])')
ask() {  # $1 = command the agent wants to run; runs the hook exactly as Claude Code would (sh -c)
  printf '{"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$HOME" "$1" \
    | sh -c "$HOOK_CMD" > /tmp/hook.out 2>/tmp/hook.err &
  HP=$!
  for i in $(seq 1 50); do loggdin pending --json | grep -q "\"command\": \"$1\"" && break; sleep 0.1; done
}
echo "=== agent asks, user denies"
ask "rm -rf build"; loggdin pending | sed -n 2,4p; loggdin deny; wait $HP; cat /tmp/hook.out
grep -q '"behavior": "deny"' /tmp/hook.out || { echo "FAILED: agent did not get deny"; exit 1; }
echo "=== agent asks, user allows once"
ask "npm run test"; loggdin allow once; wait $HP; cat /tmp/hook.out
grep -q '"behavior": "allow"' /tmp/hook.out || { echo "FAILED: agent did not get allow"; exit 1; }
echo "=== non-blocking event is fast"
start=$(date +%s%N); echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | sh -c "${HOOK_CMD% PermissionRequest} PostToolUse"; echo "PostToolUse took $(( ($(date +%s%N)-start)/1000000 )) ms"
echo "=== daemon restarts on demand after being stopped"
loggdin stop; ask "make build"; loggdin status | head -1; loggdin allow once; wait $HP; cat /tmp/hook.out
grep -q '"behavior": "allow"' /tmp/hook.out || { echo "FAILED: daemon did not restart on demand"; exit 1; }
echo "=== autostart entry"
cat ~/.config/autostart/loggdin.desktop | grep Exec
echo "=== audit chain"
python3 ~/.config/loggdin/loggdin.py doctor >/dev/null; curl -s -H "X-Loggdin-Token: $(cat ~/.config/loggdin/token)" http://127.0.0.1:$(cat ~/.config/loggdin/port)/audit/verify; echo
echo "=== uninstall"
./install.sh --uninstall
test ! -e ~/.local/bin/loggdin && echo "CLI removed"
test ! -e ~/.config/autostart/loggdin.desktop && echo "autostart removed"
! grep -q sentinel-hook ~/.claude/settings.json
echo "Linux end-user scenario passed."
