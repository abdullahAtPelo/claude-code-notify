# claude-code-notify

Native macOS notifications for Claude Code. Get notified when Claude finishes a response — click the notification to jump straight to the terminal.

## Features

- **Smart focus detection** — only notifies when you're not looking at the Claude session, works across terminals and IDEs
- **Click to focus** — clicking the notification brings you to the exact terminal Claude is running in
- **Works with any terminal** — Ghostty, iTerm2, Terminal.app, Warp, JetBrains IDEs, and more
- **Smart messages** — notifications show a summary of Claude's last response or permission request details
- **Multi-session friendly** — each Claude session is tracked independently, so notifications from one session don't get suppressed when you're looking at another
- **Sound alert** — plays a configurable system sound

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
       ]
     }
   }
   ```

## Configuration

After installing, a config file is created at `~/.claude/notify-config.json`:

```json
{
  "sound": "Glass",
  "focused": {
    "notification": false,
    "sound": false
  },
  "unfocused": {
    "notification": true,
    "sound": true
  }
}
```

| Option | Default | Description |
|--------|---------|-------------|
| `sound` | `"Glass"` | macOS system sound to play (see list below) |
| `focused.notification` | `false` | Show notifications when you're looking at this Claude session |
| `focused.sound` | `false` | Play sound when you're looking at this Claude session |
| `unfocused.notification` | `true` | Show notifications when you're not looking at this Claude session |
| `unfocused.sound` | `true` | Play sound when you're not looking at this Claude session |

**Available sounds:** Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink

Changes take effect immediately — no restart needed.

## How it works

Two hooks are registered:
- **Stop** — fires instantly when Claude finishes a response
- **PermissionRequest** — fires instantly when Claude needs you to approve a tool call

The script:

1. Reads the hook payload (JSON via stdin) to get the last message, working directory, and session ID
2. Checks if you're looking at this specific Claude session using macOS accessibility APIs — reads the focused UI element's text content to detect if "Claude Code" and the project directory are visible on screen
3. If you're already looking at this session, skips the notification
4. Otherwise, sends a notification via `terminal-notifier` with click-to-activate pointing at your terminal and plays a sound via `afplay`

This focus detection works universally across standalone terminals (Ghostty, iTerm2, Terminal.app) and IDE-embedded terminals (JetBrains GoLand, IntelliJ, etc.) without any terminal-specific code.

## Requirements

- macOS
- [Homebrew](https://brew.sh)
- [Claude Code](https://claude.ai/claude-code)
