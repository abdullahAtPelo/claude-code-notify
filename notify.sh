#!/bin/bash
input=$(cat)

# Load config (defaults if missing)
CONFIG_FILE="$HOME/.claude/notify-config.json"
sound="Glass"
sound_enabled=true
only_when_unfocused=false
if [ -f "$CONFIG_FILE" ]; then
  eval "$(/usr/bin/python3 -c "
import json
with open('$CONFIG_FILE') as f: c=json.load(f)
print(f'sound={c.get(\"sound\",\"Glass\")}')
print(f'sound_enabled={str(c.get(\"sound_enabled\",True)).lower()}')
print(f'only_when_unfocused={str(c.get(\"only_when_unfocused\",False)).lower()}')
" 2>/dev/null)"
fi

# Extract message and working directory from the hook payload
message="Done"
cwd=""
if [ -n "$input" ]; then
  message=$(echo "$input" | /usr/bin/python3 -c "
import sys,json
d=json.load(sys.stdin)
# PermissionRequest hook has tool_name field
tool=d.get('tool_name','')
if tool:
    desc=d.get('tool_input',{}).get('description','') or d.get('tool_input',{}).get('command','')
    if desc:
        msg=f'Requesting permission to {tool}: {desc}'
    else:
        msg=f'Requesting permission to use {tool}'
else:
    msg=d.get('last_assistant_message','')
if not msg:print('__SKIP__')
elif len(msg)<=100:print(msg)
else:
 t=msg[:100];i=t.rfind(' ')
 print((t[:i] if i>0 else t)+'...')
" 2>/dev/null || echo "Done")
  [ "$message" = "__SKIP__" ] && exit 0
  cwd=$(echo "$input" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd','').split('/')[-1])" 2>/dev/null)
  session=$(echo "$input" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id','default'))" 2>/dev/null)
fi
title="Claude Code${cwd:+ — $cwd}"

bundle=""

# Fast path: use TERM_PROGRAM if available (works for most terminals)
if [ -n "$TERM_PROGRAM" ]; then
  bundle=$(osascript -e "tell application \"System Events\" to get bundle identifier of application process \"$TERM_PROGRAM\"" 2>/dev/null)
fi

# Fallback: walk the process tree to find the parent GUI app (e.g. JetBrains)
if [ -z "$bundle" ]; then
  pid=$$
  while [ "$pid" != "1" ] && [ -n "$pid" ]; do
    bundle=$(osascript -e "tell application \"System Events\" to get bundle identifier of first application process whose unix id is $pid" 2>/dev/null)
    if [ -n "$bundle" ]; then
      break
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  done
fi

# Skip if only_when_unfocused is set and terminal is focused
if [ "$only_when_unfocused" = "true" ] && [ -n "$bundle" ]; then
  frontmost=$(osascript -e "tell application \"System Events\" to get bundle identifier of first application process whose frontmost is true" 2>/dev/null)
  [ "$frontmost" = "$bundle" ] && exit 0
fi

sound_flag=""
[ "$sound_enabled" = "true" ] && sound_flag="-sound $sound"
terminal-notifier -title "$title" -message "$message" $sound_flag -group "${session:-default}" ${bundle:+-activate "$bundle"}
if [ "$sound_enabled" = "true" ]; then
  sound_file="/System/Library/Sounds/${sound}.aiff"
  [ -f "$sound_file" ] && afplay "$sound_file" &
fi
