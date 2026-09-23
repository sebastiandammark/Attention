#!/bin/bash
# Claude Code hook for the Attention widget.
#
# Claude Code runs this on session events with a JSON payload on stdin. It keeps
# the latest event of each kind in ~/.claude/attention/sessions/<session id>/,
# which the Attention app reads to work out which sessions are waiting on you.
# It never prints anything and always exits 0, so it can't get in Claude's way.

state_dir="${ATTENTION_STATE_DIR:-$HOME/.claude/attention}/sessions"
payload=$(cat)

# Prints the first `"key": "string"` pair in the payload, still JSON-encoded
# (e.g. `"cwd":"/Users/me/app"`). Claude Code puts the common fields first, and
# this avoids depending on jq for the few flat fields we need.
json_field() {
  printf '%s' "$payload" \
    | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"(\\\\.|[^\"\\\\])*\"" \
    | head -n 1
}

json_value() {
  json_field "$1" | sed -E 's/^"[^"]*"[[:space:]]*:[[:space:]]*"(.*)"$/\1/'
}

session_id=$(json_value session_id)
event=$(json_value hook_event_name)

# Session ids are UUIDs; ignore anything that could escape the state dir.
[[ "$session_id" =~ ^[A-Za-z0-9_-]+$ && "$event" =~ ^[A-Za-z]+$ ]] || exit 0

session_dir="$state_dir/$session_id"

if [[ "$event" == "SessionEnd" ]]; then
  rm -rf "$session_dir"
  exit 0
fi

case "$event" in
  PreToolUse|PostToolUse)
    # Tool payloads can carry whole files; keep only what the app needs.
    record="{$(for key in session_id hook_event_name cwd transcript_path tool_name; do
      json_field "$key"
    done | paste -sd, -)}"
    ;;
  *)
    record=$payload
    ;;
esac

mkdir -p "$session_dir" || exit 0
now=$(perl -MTime::HiRes=time -e 'printf "%.3f", time' 2>/dev/null || date +%s)
tmp=$(mktemp "$session_dir/.$event.XXXXXX") || exit 0
printf '{"received_at":%s,"event":%s}\n' "$now" "$record" > "$tmp" \
  && mv -f "$tmp" "$session_dir/$event.json"
exit 0
