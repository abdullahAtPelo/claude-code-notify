#!/bin/bash
set -e

echo "==> Installing claude-code-notify"

# Suggest make update if already installed
if [ -f "$HOME/.claude/notify.sh" ] && [ "${UPDATING:-}" != "1" ]; then
  echo ""
  echo "It looks like claude-code-notify is already installed."
  echo "To pull the latest changes and reinstall, run: make update"
  echo ""
  read -r -p "Continue with install anyway? [y/n] " answer
  if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    exit 0
  fi
fi

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
cp "$SCRIPT_DIR/assets/icon.png" "$HOME/.claude/notify-icon.png"
chmod +x "$HOME/.claude/notify.sh" "$HOME/.claude/notify-clear.sh"
echo "==> Installed notify scripts to ~/.claude/"

# Install /notify-config skill
mkdir -p "$HOME/.claude/skills/notify-config"
cp "$SCRIPT_DIR/skills/notify-config/SKILL.md" "$HOME/.claude/skills/notify-config/SKILL.md"
echo "==> Installed /notify-config skill"

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

# Clean up old plugin/marketplace entries (migrating from plugin-based install)
for key in list(settings.get('enabledPlugins', {}).keys()):
    if 'claude-code-notify' in key:
        del settings['enabledPlugins'][key]
if not settings.get('enabledPlugins'):
    settings.pop('enabledPlugins', None)
for key in list(settings.get('extraKnownMarketplaces', {}).keys()):
    if 'claude-code-notify' in key:
        del settings['extraKnownMarketplaces'][key]
if not settings.get('extraKnownMarketplaces'):
    settings.pop('extraKnownMarketplaces', None)

notify_cmd = 'bash ~/.claude/notify.sh'
clear_cmd = 'bash ~/.claude/notify-clear.sh'

hook_defs = {
    'Stop': notify_cmd,
    'PermissionRequest': notify_cmd,
    'PreToolUse': clear_cmd,
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

# Clean up old plugin cache (migrating from plugin-based install)
if [ -f "$HOME/.claude/plugins/known_marketplaces.json" ]; then
  /usr/bin/python3 -c "
import json, os, shutil
path = os.path.expanduser('~/.claude/plugins/known_marketplaces.json')
with open(path) as f:
    data = json.load(f)
changed = False
for key in list(data.keys()):
    if 'claude-code-notify' in key:
        loc = data[key].get('installLocation', '')
        if loc and os.path.isdir(loc):
            shutil.rmtree(loc)
        del data[key]
        changed = True
if changed:
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
" 2>/dev/null
fi
rm -rf "$HOME/.claude/plugins/cache/" 2>/dev/null

# Install JetBrains terminal focus plugin if any JetBrains IDEs are detected
JB_PLUGIN_ZIP="$SCRIPT_DIR/jetbrains-plugin/dist/claude-code-terminal-focus-1.0.0.zip"
if [ -f "$JB_PLUGIN_ZIP" ]; then
  jb_installed=false
  # Find the latest version directory for each IDE
  /usr/bin/python3 -c "
import os, re, sys
jb_base = os.path.expanduser('~/Library/Application Support/JetBrains')
ide_pattern = re.compile(r'^(GoLand|IntelliJIdea|PyCharm|WebStorm|Rider|PhpStorm|CLion|RubyMine|DataGrip|AndroidStudio)(.+)$')
latest = {}
for name in sorted(os.listdir(jb_base)):
    m = ide_pattern.match(name)
    if not m:
        continue
    path = os.path.join(jb_base, name, 'plugins')
    if not os.path.isdir(path):
        continue
    ide, ver = m.group(1), m.group(2)
    latest[ide] = name
for name in latest.values():
    print(name)
" 2>/dev/null | while IFS= read -r jb_name; do
    jb_dir="$HOME/Library/Application Support/JetBrains/$jb_name"
    rm -rf "$jb_dir/plugins/claude-code-terminal-focus"
    unzip -qo "$JB_PLUGIN_ZIP" -d "$jb_dir/plugins/"
    jb_installed=true
    echo "==> Installed terminal focus plugin to $jb_name"
  done
  # Check if any were installed (pipe runs in subshell so we re-check)
  for jb_dir in "$HOME/Library/Application Support/JetBrains"/*/plugins/claude-code-terminal-focus; do
    [ -d "$jb_dir" ] && jb_installed=true && break
  done
  if [ "$jb_installed" = "false" ]; then
    echo "==> No JetBrains IDEs detected, skipping terminal focus plugin"
  fi
fi

echo ""
echo "Done! Next steps:"
echo "  1. Enable notifications for terminal-notifier in:"
echo "     System Settings → Notifications → terminal-notifier"
echo "  2. Set the alert style to 'Alerts' if you want notifications to persist"
if [ "$jb_installed" = "true" ]; then
  echo "  3. Restart any open JetBrains IDEs to load the terminal focus plugin"
fi
echo ""
echo "To update later: cd $(basename "$SCRIPT_DIR") && git checkout main && make update"
