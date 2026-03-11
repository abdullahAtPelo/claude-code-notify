---
name: notify-config
description: Configure claude-code-notify notification settings. Use when the user wants to change notification sounds, toggle focused/unfocused notifications, or view current notification settings.
disable-model-invocation: true
allowed-tools: Read, Edit, Write
---

# Configure claude-code-notify

The notification config file is at `~/.claude/notify-config.json`.

## Step 1: Read the current config

Read `~/.claude/notify-config.json` and show the user their current settings in a friendly format:

- **Sound**: the current sound name
- **Focused** (you're looking at the Claude session): notification on/off, sound on/off
- **Unfocused** (you're NOT looking at the Claude session): notification on/off, sound on/off

## Step 2: Ask what to change

If the user passed arguments (e.g. `/notify-config sound Ping`), apply those changes directly.

Otherwise, ask the user what they'd like to change. Present these options:

1. **Change sound** — available sounds: Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink
2. **Toggle focused notification** — on/off
3. **Toggle focused sound** — on/off
4. **Toggle unfocused notification** — on/off
5. **Toggle unfocused sound** — on/off

## Step 3: Update the config

Write the updated JSON to `~/.claude/notify-config.json`. The schema is:

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

After saving, confirm the changes. Changes take effect immediately — no restart needed.
