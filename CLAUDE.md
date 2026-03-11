# claude-code-notify

macOS notification plugin for Claude Code.

## First-time setup

On the user's first message, check if `~/.claude/notify.sh` exists. If it doesn't, tell the user:

> It looks like claude-code-notify isn't installed yet. Want me to set it up? I'll run `make install` which installs `terminal-notifier` and adds notification hooks to your Claude Code config.

If they agree, run `make install`. After it completes, tell them:

1. Open **System Settings → Notifications → terminal-notifier**, enable notifications, and optionally set the style to **Alerts**
2. Restart Claude Code

Then offer to install the optional plugin for the `/notify-config` command — explain it's not required but lets them change settings from chat. If they want it, tell them to run these commands after restarting:

```
/plugin marketplace add abdullahAtPelo/claude-code-notify
/plugin install claude-code-notify@abdullahAtPelo/claude-code-notify
```

## Structure

- `notify.sh` — Main notification script (called by Stop and PermissionRequest hooks)
- `notify-clear.sh` — Clears notifications on prompt submit
- `setup.sh` / `uninstall.sh` — Install/remove scripts and hooks
- `skills/notify-config/` — `/notify-config` skill for in-chat configuration
- Config lives at `~/.claude/notify-config.json`

## Testing

Run `make install` after changes to reinstall scripts to `~/.claude/`. Restart Claude Code to pick up hook changes.

Requires macOS, Homebrew, and `terminal-notifier` (installed by setup.sh).
