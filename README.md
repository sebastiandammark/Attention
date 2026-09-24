# Attention

A macOS desktop widget and menu bar app that shows your active Claude Code
sessions, with the ones waiting on you first.

| Status | Meaning |
| --- | --- |
| **Needs you** (orange) | Claude is blocked on you: a permission prompt, a question, or a plan to approve |
| **Your turn** (blue) | Claude finished (or you interrupted it) and is waiting for your next prompt |
| **Working** (green) | Claude is working on a prompt |
| **Idle** (grey) | The session is open but hasn't been given a prompt yet |

The widget comes in small (a count of sessions waiting on you), medium (the top 3)
and large (the top 7) sizes. The menu bar icon shows the same count.

## How it works

```
Claude Code ──hook──▶ ~/.claude/attention/sessions/<id>/<Event>.json
                                   │  (polled every 2 s)
                                   ▼
                     Attention.app (menu bar) ──▶ App Group snapshot.json ──▶ Widget
```

1. `hooks/attention-hook.sh` is a Claude Code
   [hook](https://code.claude.com/docs/en/hooks). On `SessionStart`,
   `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`, `Stop` and
   `SessionEnd` it saves the latest event of each kind per session. It only needs
   bash, grep and sed, and it always exits 0 without printing anything, so it
   never gets in Claude's way.
2. The menu bar app works out each session's status from those files and writes a
   snapshot into the shared App Group container. It reloads the widget only when a
   status changes, not on every tool call.
3. The widget is sandboxed, so it reads only that snapshot.

Sessions drop off when Claude Code ends them, or after 12 hours with no activity
(for example, a terminal closed mid-session). Right-click a session in the menu
bar window to dismiss it, show its folder, or copy a `claude --resume` command.

Click a session's name in the menu bar window to go to it. In Terminal and iTerm
this selects the tab it runs in (macOS asks once for permission to control
them). In VS Code, Cursor and Windsurf it brings up the window for the project,
and in any other app it brings the app to the front. The hook notes where each
session runs the first time it fires for that session, so after updating the
app, click **Reinstall Hooks**. Sessions that were already open become links on
their next event.

## Setup

You need macOS 14 or later, Xcode 15 or later, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

1. `brew install xcodegen`
2. In `project.yml`, set `DEVELOPMENT_TEAM` to your Apple Developer Team ID. A free
   Personal Team works. Widgets won't load from an unsigned build.
3. `xcodegen generate && open Attention.xcodeproj`
4. Build and run the **Attention** scheme. Then move `Attention.app` into
   `/Applications` so the widget stays registered.
5. Click the sparkles icon in the menu bar and choose **Install Hooks**. This copies
   the hook to `~/.claude/attention/hook.sh` and adds it to
   `~/.claude/settings.json`. It saves a backup of that file as
   `settings.json.attention-backup` and doesn't change your existing hooks.
6. Right-click the desktop, choose **Edit Widgets**, and add **Claude Sessions**.
7. Restart any Claude Code sessions that are already running so they pick up the
   hooks.

### Installing the hooks by hand

If you'd rather not let the app edit your settings, copy the script and add this
to `~/.claude/settings.json` (or to a project's `.claude/settings.json`):

```sh
mkdir -p ~/.claude/attention && cp hooks/attention-hook.sh ~/.claude/attention/hook.sh
```

```json
{
  "hooks": {
    "SessionStart":     [{ "hooks": [{ "type": "command", "command": "~/.claude/attention/hook.sh" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "~/.claude/attention/hook.sh" }] }],
    "PreToolUse":       [{ "hooks": [{ "type": "command", "command": "~/.claude/attention/hook.sh" }] }],
    "PostToolUse":      [{ "hooks": [{ "type": "command", "command": "~/.claude/attention/hook.sh" }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "~/.claude/attention/hook.sh" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "~/.claude/attention/hook.sh" }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "~/.claude/attention/hook.sh" }] }]
  }
}
```

## Scope and privacy

- It covers Claude Code running on this Mac: the CLI, and the IDE extensions and
  apps that use your `~/.claude` settings. It can't see Claude Code sessions
  running in the cloud (claude.ai/code) or claude.ai chats, because hooks for
  those run on Anthropic's machines.
- Everything stays on your Mac. The hook stores your latest prompt and Claude's
  latest notification per session. For tool events it keeps only the tool name,
  not its input or output.

## Development

`tests/hook_test.sh` runs the hook against sample payloads (it needs `python3` to
check the JSON the hook writes).
