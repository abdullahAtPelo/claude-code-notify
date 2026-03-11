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

for event in ['Stop', 'PermissionRequest', 'UserPromptSubmit']:
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

# Remove scripts and config
rm -f "$HOME/.claude/notify.sh" "$HOME/.claude/notify-clear.sh" "$HOME/.claude/notify-config.json" "$HOME/.claude/notify-icon.png"
echo "==> Removed notify scripts and config"

echo "==> Done. Restart Claude Code for changes to take effect."
