# claude-code-notify

macOS notification plugin for Claude Code.

## Structure

- `notify.sh` — Main notification script (called by Stop and PermissionRequest hooks)
- `notify-clear.sh` — Clears notifications on prompt submit
- `setup.sh` / `uninstall.sh` — Install/remove scripts and hooks
- `skills/notify-config/` — `/notify-config` skill for in-chat configuration
- `jetbrains-plugin/` — JetBrains IDE plugin for terminal tab focus (pre-built zip in `dist/`)
- Config lives at `~/.claude/notify-config.json`

## Testing

Run `make install` after changes to reinstall scripts to `~/.claude/`. Restart Claude Code to pick up hook changes.

Requires macOS, Homebrew, and `terminal-notifier` (installed by setup.sh).
