#!/bin/bash
input=$(cat)

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
    msg=d.get('last_assistant_message','Done')
if len(msg)<=100:print(msg)
else:
 t=msg[:100];i=t.rfind(' ')
 print((t[:i] if i>0 else t)+'...')
" 2>/dev/null || echo "Done")
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

terminal-notifier -title "$title" -message "$message" -sound Glass -group "${session:-default}" ${bundle:+-activate "$bundle"}
afplay /System/Library/Sounds/Glass.aiff &
