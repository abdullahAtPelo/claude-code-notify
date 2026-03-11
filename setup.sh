#!/bin/bash
set -e

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

# Copy notify scripts
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/notify.sh" "$HOME/.claude/notify.sh"
cp "$SCRIPT_DIR/notify-clear.sh" "$HOME/.claude/notify-clear.sh"
chmod +x "$HOME/.claude/notify.sh" "$HOME/.claude/notify-clear.sh"
echo "==> Installed notify scripts to ~/.claude/"

# Create default config if it doesn't exist
CONFIG_FILE="$HOME/.claude/notify-config.json"
if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" <<'CONF'
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
CONF
  echo "==> Created default config at $CONFIG_FILE"
else
  echo "==> Config already exists at $CONFIG_FILE"
fi

# Add hooks to ~/.claude/settings.json
SETTINGS_FILE="$HOME/.claude/settings.json"
/usr/bin/python3 -c "
import json, os

path = '$SETTINGS_FILE'
settings = {}
if os.path.exists(path):
    with open(path) as f:
        settings = json.load(f)

hooks = settings.setdefault('hooks', {})

notify_cmd = 'bash ~/.claude/notify.sh'
clear_cmd = 'bash ~/.claude/notify-clear.sh'

hook_defs = {
    'Stop': notify_cmd,
    'PermissionRequest': notify_cmd,
    'UserPromptSubmit': clear_cmd,
}

for event, cmd in hook_defs.items():
    entries = hooks.get(event, [])
    already = any(
        any(h.get('command') == cmd for h in entry.get('hooks', []))
        for entry in entries
    )
    if not already:
        entries.append({
            'matcher': '',
            'hooks': [{'type': 'command', 'command': cmd}]
        })
        hooks[event] = entries

with open(path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
" && echo "==> Added hooks to $SETTINGS_FILE"

echo ""
echo "Done! Next steps:"
echo "  1. Enable notifications for terminal-notifier in:"
echo "     System Settings → Notifications → terminal-notifier"
echo "  2. Set the alert style to 'Alerts' if you want notifications to persist"
echo "  3. Restart Claude Code"
echo ""
echo "Optional: install the plugin for the /notify-config command:"
echo "  /plugin marketplace add abdullahAtPelo/claude-code-notify"
echo "  /plugin install claude-code-notify@abdullahAtPelo/claude-code-notify"
