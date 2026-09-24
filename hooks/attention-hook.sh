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

# Once per session, note the app and terminal tab it runs in, so the Attention
# app can bring it to the front. Hooks have no terminal of their own, so look
# for the nearest parent process that does.
host_file="$session_dir/host.json"
if [[ ! -e "$host_file" ]]; then
  pid=$$ tty=""
  for _ in 1 2 3 4 5 6; do
    tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
    [[ "$tty" =~ ^tty[A-Za-z0-9]+$ ]] && break
    tty=""
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 ]] || break
  done
  # macOS sets __CFBundleIdentifier for everything an app launches, shells included.
  bundle_id=${__CFBundleIdentifier:-}
  [[ "$bundle_id" =~ ^[A-Za-z0-9._-]+$ ]] || bundle_id=""
  tmp=$(mktemp "$session_dir/.host.XXXXXX") \
    && printf '{"tty":"%s","bundle_id":"%s"}\n' "${tty:+/dev/$tty}" "$bundle_id" > "$tmp" \
    && mv -f "$tmp" "$host_file"
fi

now=$(perl -MTime::HiRes=time -e 'printf "%.3f", time' 2>/dev/null || date +%s)
tmp=$(mktemp "$session_dir/.$event.XXXXXX") || exit 0
printf '{"received_at":%s,"event":%s}\n' "$now" "$record" > "$tmp" \
  && mv -f "$tmp" "$session_dir/$event.json"
exit 0
