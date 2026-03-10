# claude-code-notify

Native macOS notifications for Claude Code. Get notified when Claude finishes a response — click the notification to jump straight to the terminal.

## Features

- **Click to focus** — clicking the notification brings you to the exact terminal Claude is running in
- **Works with any terminal** — Ghostty, iTerm2, Terminal.app, Warp, JetBrains IDEs, and more
- **Smart messages** — notifications show a summary of Claude's last response
- **Multi-agent friendly** — each Claude session replaces its own notification, so they don't pile up
- **Sound alert** — plays a Glass sound so you know Claude is done

## Install

```bash
git clone https://github.com/abdullahAtPelo/claude-code-notify.git
cd claude-code-notify
bash setup.sh
```

Then:
1. Open **System Settings → Notifications → terminal-notifier**
2. Enable notifications and set the style to **Alerts** (if you want them to persist until clicked)
3. Restart Claude Code

## Uninstall

```bash
cd claude-code-notify
bash uninstall.sh
```

## Manual setup

If you prefer to set it up manually:

1. Install terminal-notifier:
   ```bash
   brew install terminal-notifier
   ```

2. Copy `notify.sh` to `~/.claude/notify.sh` and make it executable:
   ```bash
   cp notify.sh ~/.claude/notify.sh
   chmod +x ~/.claude/notify.sh
   ```

3. Add the hooks to `~/.claude/settings.json`:
   ```json
   {
     "hooks": {
       "Stop": [
         {
           "matcher": "",
           "hooks": [
             {
               "type": "command",
               "command": "bash ~/.claude/notify.sh"
             }
           ]
         }
       ],
       "PermissionRequest": [
         {
           "matcher": "",
           "hooks": [
             {
               "type": "command",
               "command": "bash ~/.claude/notify.sh"
             }
           ]
         }
       ],
       "Notification": [
         {
           "matcher": "",
           "hooks": [
             {
               "type": "command",
               "command": "bash ~/.claude/notify.sh"
             }
           ]
         }
       ]
     }
   }
   ```

## Configuration

After installing, a config file is created at `~/.claude/notify-config.json`:

```json
{
  "sound": "Glass",
  "sound_enabled": true,
  "only_when_unfocused": false
}
```

| Option | Default | Description |
|--------|---------|-------------|
| `sound` | `"Glass"` | macOS system sound name (e.g. `"Ping"`, `"Purr"`, `"Hero"`, `"Submarine"`) |
| `sound_enabled` | `true` | Set to `false` to disable sound entirely |
| `only_when_unfocused` | `false` | Set to `true` to only notify when the terminal is not in the foreground |

Changes take effect immediately — no restart needed.

## How it works

Three hooks are registered:
- **Stop** — fires every time Claude finishes a response (works whether terminal is focused or not)
- **PermissionRequest** — fires when Claude needs you to approve a tool call (focused or not)
- **Notification** — fires when Claude is waiting for input and the terminal is unfocused

The script:

1. Reads the hook payload (JSON via stdin) to get the last message, working directory, and session ID
2. Detects which terminal app you're using via `$TERM_PROGRAM`, or by walking the process tree for terminals that don't set it (like JetBrains)
3. Sends a notification via `terminal-notifier` with click-to-activate pointing at your terminal
4. Plays a Glass sound via `afplay`

## Requirements

- macOS
- [Homebrew](https://brew.sh)
- [Claude Code](https://claude.ai/claude-code)
