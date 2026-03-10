# claude-code-notify

macOS notification plugin for Claude Code.

## Structure

- `hooks/hooks.json` — Hook definitions (Stop, PermissionRequest, UserPromptSubmit)
- `notify.sh` — Main notification script (called by Stop and PermissionRequest hooks)
- `notify-clear.sh` — Clears notifications on prompt submit
- `skills/notify-config/` — `/notify-config` skill for in-chat configuration
- `setup.sh` / `uninstall.sh` — Install/remove scripts
- Config lives at `~/.claude/notify-config.json`

## Testing

Run `bash setup.sh` after changes to reinstall scripts to `~/.claude/`. Restart Claude Code to pick up hook changes.

Requires macOS, Homebrew, and `terminal-notifier` (installed by setup.sh).
