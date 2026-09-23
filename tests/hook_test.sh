#!/bin/bash
# Exercises hooks/attention-hook.sh with sample Claude Code payloads.
# Usage: tests/hook_test.sh   (needs python3 to validate the JSON it writes)
set -euo pipefail

hook="$(cd "$(dirname "$0")/.." && pwd)/hooks/attention-hook.sh"
export ATTENTION_STATE_DIR=$(mktemp -d)
trap 'rm -rf "$ATTENTION_STATE_DIR"' EXIT
sessions="$ATTENTION_STATE_DIR/sessions"
id=6f1c2a9e-1111-4c2b-9d7a-0123456789ab
failures=0

fail() { echo "FAIL: $*"; failures=$((failures + 1)); }
run() { printf '%s' "$1" | "$hook"; }
field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["event"].get(sys.argv[2], ""))' "$1" "$2"; }

run '{"session_id":"'$id'","transcript_path":"/tmp/t.jsonl","cwd":"/Users/me/My \"quoted\" app","hook_event_name":"UserPromptSubmit","prompt":"Fix the \"cwd\": \"/nope\" bug\nplease"}'
file="$sessions/$id/UserPromptSubmit.json"
[[ -f "$file" ]] || fail "UserPromptSubmit not recorded"
[[ "$(field "$file" prompt)" == $'Fix the "cwd": "/nope" bug\nplease' ]] || fail "prompt not preserved"
[[ "$(field "$file" cwd)" == '/Users/me/My "quoted" app' ]] || fail "cwd not preserved"

run '{"session_id":"'$id'","transcript_path":"/tmp/t.jsonl","cwd":"/Users/me/My \"quoted\" app","hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"/x","content":"SECRET"},"tool_response":{"ok":true}}'
file="$sessions/$id/PostToolUse.json"
[[ "$(field "$file" tool_name)" == Write ]] || fail "tool_name not recorded"
[[ "$(field "$file" cwd)" == '/Users/me/My "quoted" app' ]] || fail "tool event cwd not preserved"
grep -q SECRET "$file" && fail "tool input should be stripped"

run '{"session_id":"'$id'","cwd":"/a","hook_event_name":"Notification","message":"Claude needs your permission to use Bash","notification_type":"permission_prompt"}'
[[ "$(field "$sessions/$id/Notification.json" notification_type)" == permission_prompt ]] || fail "notification not recorded"

python3 -c 'import json,sys; [json.load(open(p)) for p in sys.argv[1:]]' "$sessions/$id"/*.json || fail "invalid JSON written"
[[ -z "$(ls -A "$sessions/$id" | grep '^\.' || true)" ]] || fail "temp files left behind"

run '{"session_id":"../../etc","hook_event_name":"Stop"}'
[[ ! -e "$ATTENTION_STATE_DIR/etc" ]] || fail "path traversal not rejected"
run 'not json at all'

output=$(run '{"session_id":"'$id'","hook_event_name":"SessionEnd","reason":"exit"}')
[[ -z "$output" ]] || fail "hook printed output"
[[ ! -e "$sessions/$id" ]] || fail "SessionEnd did not remove the session"

if (( failures )); then echo "$failures failure(s)"; exit 1; fi
echo "All hook tests passed"
