#!/bin/bash
set -e

NOTIFY_SCRIPT="$HOME/.claude/notify.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "==> Installing claude-code-notify"

# Install terminal-notifier if not present
if ! command -v terminal-notifier &>/dev/null; then
  echo "==> Installing terminal-notifier via Homebrew..."
  brew install terminal-notifier
else
  echo "==> terminal-notifier already installed"
fi

# Ensure .claude directory exists
mkdir -p "$HOME/.claude"

# Copy notify script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/notify.sh" "$NOTIFY_SCRIPT"
chmod +x "$NOTIFY_SCRIPT"
echo "==> Installed notify script to $NOTIFY_SCRIPT"

# Create default config if it doesn't exist
CONFIG_FILE="$HOME/.claude/notify-config.json"
if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" <<'CONF'
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
CONF
  echo "==> Created default config at $CONFIG_FILE"
else
  echo "==> Config already exists at $CONFIG_FILE"
fi

# Add hooks to settings.json
HOOK_COMMAND="bash $NOTIFY_SCRIPT"
if [ -f "$SETTINGS_FILE" ]; then
  # Merge hooks into existing settings, cleaning up old hook formats
  /usr/bin/python3 -c "
import json, sys

with open('$SETTINGS_FILE', 'r') as f:
    settings = json.load(f)

hooks = settings.setdefault('hooks', {})
changed = False

# Clean up old Notification hooks and old-style commands with event arguments
old_commands = [
    '$HOOK_COMMAND',
    '$HOOK_COMMAND Stop',
    '$HOOK_COMMAND PermissionRequest',
    '$HOOK_COMMAND Notification',
]

# Remove Notification hook entirely
if 'Notification' in hooks:
    for entry in hooks['Notification']:
        entry['hooks'] = [h for h in entry.get('hooks', []) if h.get('command') not in old_commands]
    hooks['Notification'] = [e for e in hooks['Notification'] if e.get('hooks')]
    if not hooks['Notification']:
        del hooks['Notification']
        changed = True
        print('==> Removed Notification hook from $SETTINGS_FILE')

for event in ['Stop', 'PermissionRequest']:
    event_hooks = hooks.setdefault(event, [])

    # Remove old-style hooks
    for entry in event_hooks:
        entry['hooks'] = [h for h in entry.get('hooks', []) if h.get('command') not in old_commands]
    event_hooks[:] = [e for e in event_hooks if e.get('hooks')]

    already_exists = any(
        any(h.get('command') == '$HOOK_COMMAND' for h in entry.get('hooks', []))
        for entry in event_hooks
    )
    if not already_exists:
        event_hooks.append({
            'matcher': '',
            'hooks': [{'type': 'command', 'command': '$HOOK_COMMAND'}]
        })
        changed = True
        print(f'==> Added {event} hook to $SETTINGS_FILE')
    else:
        print(f'==> {event} hook already configured in $SETTINGS_FILE')

if changed:
    with open('$SETTINGS_FILE', 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
" || {
  echo "ERROR: Failed to update settings.json. You may need to add the hook manually."
  echo "See README.md for manual setup instructions."
  exit 1
}
else
  # Create new settings file with hooks
  cat > "$SETTINGS_FILE" <<EOF
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_COMMAND"
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
            "command": "$HOOK_COMMAND"
          }
        ]
      }
    ]
  }
}
EOF
  echo "==> Created $SETTINGS_FILE with hooks"
fi

echo ""
echo "Done! A few things to note:"
echo "  1. Enable notifications for terminal-notifier in:"
echo "     System Settings → Notifications → terminal-notifier"
echo "  2. Set the alert style to 'Alerts' if you want notifications to persist"
echo "  3. Restart Claude Code for the hook to take effect"
