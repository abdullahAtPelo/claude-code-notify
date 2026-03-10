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

# Copy notify script
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

echo ""
echo "Done! Next steps:"
echo "  1. Enable the plugin in Claude Code:"
echo "     /plugin install $SCRIPT_DIR"
echo "  2. Enable notifications for terminal-notifier in:"
echo "     System Settings → Notifications → terminal-notifier"
echo "  3. Set the alert style to 'Alerts' if you want notifications to persist"
echo "  4. Restart Claude Code"
