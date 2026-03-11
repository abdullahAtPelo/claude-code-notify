# claude-code-notify

Native macOS notifications for Claude Code. Get notified when Claude finishes a response — click the notification to jump straight to the terminal.

## Features

- **Smart focus detection** — only notifies when you're not looking at the Claude session, works across terminals and IDEs
- **Click to focus** — clicking the notification brings you to the exact terminal Claude is running in
- **Works with any terminal** — Ghostty, iTerm2, Terminal.app, Warp, JetBrains IDEs, and more
- **Smart messages** — notifications show a summary of Claude's last response or permission request details
- **Multi-session friendly** — each Claude session is tracked independently, so notifications from one session don't get suppressed when you're looking at another
- **Sound alert** — plays a configurable system sound
- **`/notify-config` command** — configure notification settings directly in Claude Code

## Install

Clone the repo, open Claude Code in it, and ask Claude to help you set it up:

```bash
git clone https://github.com/abdullahAtPelo/claude-code-notify.git
cd claude-code-notify
claude
```

Then tell Claude: **"help me set up notifications"** — it'll run the installer and walk you through the rest.

Or install manually:

```bash
git clone https://github.com/abdullahAtPelo/claude-code-notify.git
cd claude-code-notify
make install
```

Then:
1. Open **System Settings → Notifications → terminal-notifier**, enable notifications, and set the style to **Alerts** (if you want them to persist until clicked)
2. Restart Claude Code

### Optional: install the plugin

The plugin is **not required** — notifications work fully without it. It just adds the `/notify-config` command, which lets you change settings from inside Claude Code instead of editing the JSON file manually.

Run these inside Claude Code:

```
/plugin marketplace add abdullahAtPelo/claude-code-notify
/plugin install claude-code-notify@abdullahAtPelo/claude-code-notify
```

When prompted, select **"Install for you (user scope)"**.

## Uninstall

```bash
cd claude-code-notify
make uninstall
```

## Configuration

A config file is created at `~/.claude/notify-config.json`:

```json
{
  "sound": "Glass",
  "focused": {
    "notification": true,
    "sound": true
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
| `focused.notification` | `true` | Show notifications when you're looking at this Claude session |
| `focused.sound` | `true` | Play sound when you're looking at this Claude session |
| `unfocused.notification` | `true` | Show notifications when you're not looking at this Claude session |
| `unfocused.sound` | `true` | Play sound when you're not looking at this Claude session |

**Available sounds:** Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink

Changes take effect immediately — no restart needed.

### Using `/notify-config`

You can also configure notifications by typing `/claude-code-notify:notify-config` in Claude Code. Claude will show your current settings and walk you through changing them.

## How it works

The installer registers three hooks in `~/.claude/settings.json`:
- **Stop** — fires when Claude finishes a response
- **PermissionRequest** — fires when Claude needs you to approve a tool call
- **UserPromptSubmit** — clears stale notifications when you send a new prompt

The script:

1. Reads the hook payload (JSON via stdin) to get the last message, working directory, and session ID
2. Checks if you're looking at this specific Claude session using macOS accessibility APIs — reads the focused UI element's text content to detect if "Claude Code" and the project directory are visible on screen
3. If you're already looking at this session, applies the `focused` config. Otherwise, applies the `unfocused` config
4. Sends a notification via `terminal-notifier` with click-to-activate pointing at your terminal and optionally plays a sound via `afplay`

This focus detection works universally across standalone terminals (Ghostty, iTerm2, Terminal.app) and IDE-embedded terminals (JetBrains GoLand, IntelliJ, etc.) without any terminal-specific code.

## Requirements

- macOS
- [Homebrew](https://brew.sh)
- [Claude Code](https://claude.ai/claude-code)
