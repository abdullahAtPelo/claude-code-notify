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

# Add hook to settings.json
HOOK_COMMAND="bash $NOTIFY_SCRIPT"
if [ -f "$SETTINGS_FILE" ]; then
  # Merge hook into existing settings
  /usr/bin/python3 -c "
import json, sys

with open('$SETTINGS_FILE', 'r') as f:
    settings = json.load(f)

hook_entry = {
    'matcher': '',
    'hooks': [{'type': 'command', 'command': '$HOOK_COMMAND'}]
}

hooks = settings.setdefault('hooks', {})
stop_hooks = hooks.setdefault('Stop', [])

# Check if hook already exists
already_exists = any(
    any(h.get('command') == '$HOOK_COMMAND' for h in entry.get('hooks', []))
    for entry in stop_hooks
)

if not already_exists:
    stop_hooks.append(hook_entry)
    with open('$SETTINGS_FILE', 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
    print('==> Added Stop hook to $SETTINGS_FILE')
else:
    print('==> Hook already configured in $SETTINGS_FILE')
" || {
  echo "ERROR: Failed to update settings.json. You may need to add the hook manually."
  echo "See README.md for manual setup instructions."
  exit 1
}
else
  # Create new settings file with just the hook
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
    ]
  }
}
EOF
  echo "==> Created $SETTINGS_FILE with Stop hook"
fi

echo ""
echo "Done! A few things to note:"
echo "  1. Enable notifications for terminal-notifier in:"
echo "     System Settings → Notifications → terminal-notifier"
echo "  2. Set the alert style to 'Alerts' if you want notifications to persist"
echo "  3. Restart Claude Code for the hook to take effect"
