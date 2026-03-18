#!/bin/bash
set -e

echo "==> Uninstalling claude-code-notify"

SETTINGS_FILE="$HOME/.claude/settings.json"

# Remove hooks from settings.json
if [ -f "$SETTINGS_FILE" ]; then
  /usr/bin/python3 -c "
import json

with open('$SETTINGS_FILE') as f:
    settings = json.load(f)

hooks = settings.get('hooks', {})
cmds_to_remove = {'bash ~/.claude/notify.sh', 'bash ~/.claude/notify-clear.sh'}

for event in ['Stop', 'PermissionRequest', 'PreToolUse', 'UserPromptSubmit']:
    entries = hooks.get(event, [])
    entries = [
        entry for entry in entries
        if not any(h.get('command') in cmds_to_remove for h in entry.get('hooks', []))
    ]
    if entries:
        hooks[event] = entries
    else:
        hooks.pop(event, None)

if not hooks:
    settings.pop('hooks', None)

with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
" && echo "==> Removed hooks from $SETTINGS_FILE"
fi

# Remove scripts, config, and skill
rm -f "$HOME/.claude/notify.sh" "$HOME/.claude/notify-clear.sh" "$HOME/.claude/notify-config.json" "$HOME/.claude/notify-icon.png"
rm -rf "$HOME/.claude/skills/notify-config"
echo "==> Removed notify scripts, config, and skill"

# Remove JetBrains terminal focus plugin
for jb_dir in "$HOME/Library/Application Support/JetBrains"/*/plugins/claude-code-terminal-focus; do
  if [ -d "$jb_dir" ]; then
    rm -rf "$jb_dir"
    echo "==> Removed terminal focus plugin from $(basename "$(dirname "$(dirname "$jb_dir")")")"
  fi
done

echo ""
echo "==> Done. Restart Claude Code for changes to take effect."
