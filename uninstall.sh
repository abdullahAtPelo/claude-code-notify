#!/bin/bash
set -e

NOTIFY_SCRIPT="$HOME/.claude/notify.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"
HOOK_COMMAND="bash $NOTIFY_SCRIPT"

echo "==> Uninstalling claude-code-notify"

# Remove hook from settings.json
if [ -f "$SETTINGS_FILE" ]; then
  /usr/bin/python3 -c "
import json

with open('$SETTINGS_FILE', 'r') as f:
    settings = json.load(f)

hooks = settings.get('hooks', {})
stop_hooks = hooks.get('Stop', [])

stop_hooks = [
    entry for entry in stop_hooks
    if not any(h.get('command') == '$HOOK_COMMAND' for h in entry.get('hooks', []))
]

if stop_hooks:
    hooks['Stop'] = stop_hooks
else:
    hooks.pop('Stop', None)

if not hooks:
    settings.pop('hooks', None)

with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
" && echo "==> Removed hook from $SETTINGS_FILE"
fi

# Remove notify script
if [ -f "$NOTIFY_SCRIPT" ]; then
  rm "$NOTIFY_SCRIPT"
  echo "==> Removed $NOTIFY_SCRIPT"
fi

echo "==> Done. Restart Claude Code for changes to take effect."
