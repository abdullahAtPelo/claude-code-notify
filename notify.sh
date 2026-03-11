#!/bin/bash
input=$(cat)

# Load config (defaults if missing)
CONFIG_FILE="$HOME/.claude/notify-config.json"
sound="Glass"
focused_notification=false
focused_sound=false
unfocused_notification=true
unfocused_sound=true
if [ -f "$CONFIG_FILE" ]; then
  eval "$(/usr/bin/python3 -c "
import json
with open('$CONFIG_FILE') as f: c=json.load(f)
f=c.get('focused',{})
u=c.get('unfocused',{})
print(f'sound={c.get(\"sound\",\"Glass\")}')
print(f'focused_notification={str(f.get(\"notification\",False)).lower()}')
print(f'focused_sound={str(f.get(\"sound\",False)).lower()}')
print(f'unfocused_notification={str(u.get(\"notification\",True)).lower()}')
print(f'unfocused_sound={str(u.get(\"sound\",True)).lower()}')
" 2>/dev/null)"
fi

# Extract message, cwd, and session from the hook payload
message=""
cwd=""
session=""
if [ -n "$input" ]; then
  message=$(echo "$input" | /usr/bin/python3 -c "
import sys,json
d=json.load(sys.stdin)
tool=d.get('tool_name','')
if tool:
    desc=d.get('tool_input',{}).get('description','') or d.get('tool_input',{}).get('command','')
    if desc:
        msg=f'Requesting permission to {tool}: {desc}'
    else:
        msg=f'Requesting permission to use {tool}'
else:
    msg=d.get('last_assistant_message','')
if not msg:sys.exit(1)
if len(msg)<=100:print(msg)
else:
 t=msg[:100];i=t.rfind(' ')
 print((t[:i] if i>0 else t)+'...')
" 2>/dev/null) || exit 0
  cwd=$(echo "$input" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd','').split('/')[-1])" 2>/dev/null)
  session=$(echo "$input" | /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id','default'))" 2>/dev/null)
fi
[ -z "$message" ] && exit 0

# Focus detection: check if the user is looking at THIS Claude session
# Reads the focused UI element's text content — works across all terminals and IDEs
is_focused=false
ax_value=$(osascript -e '
tell application "System Events"
    try
        set focusedEl to value of attribute "AXFocusedUIElement" of (first application process whose frontmost is true)
        set elVal to value of attribute "AXValue" of focusedEl
        if length of elVal > 500 then
            set elVal to text 1 thru 500 of elVal
        end if
        return elVal
    on error
        return ""
    end try
end tell' 2>/dev/null)
if echo "$ax_value" | grep -q "Claude Code"; then
  if [ -n "$cwd" ] && echo "$ax_value" | grep -q "$cwd"; then
    is_focused=true
  fi
fi

# Apply focused/unfocused config
if [ "$is_focused" = "true" ]; then
  [ "$focused_notification" = "false" ] && exit 0
  notify_sound="$focused_sound"
else
  [ "$unfocused_notification" = "false" ] && exit 0
  notify_sound="$unfocused_sound"
fi

title="Claude Code${cwd:+ — $cwd}"

bundle=""

# Fast path: __CFBundleIdentifier is set by macOS for GUI app subprocesses (instant)
if [ -n "$__CFBundleIdentifier" ]; then
  bundle="$__CFBundleIdentifier"
# Try TERM_PROGRAM to resolve bundle ID via System Events
elif [ -n "$TERM_PROGRAM" ]; then
  bundle=$(osascript -e "tell application \"System Events\" to get bundle identifier of application process \"$TERM_PROGRAM\"" 2>/dev/null)
fi

# Fallback: walk the process tree to find the parent GUI app
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

sound_flag=""
[ "$notify_sound" = "true" ] && sound_flag="-sound $sound"
# Resolve terminal app icon for content image
content_image=""
if [ -n "$bundle" ]; then
  app_path=$(mdfind "kMDItemCFBundleIdentifier == '$bundle'" 2>/dev/null | head -1)
  if [ -n "$app_path" ]; then
    icon_name=$(defaults read "$app_path/Contents/Info.plist" CFBundleIconFile 2>/dev/null)
    if [ -n "$icon_name" ]; then
      [[ "$icon_name" != *.icns ]] && icon_name="$icon_name.icns"
      app_icon="$app_path/Contents/Resources/$icon_name"
      [ -f "$app_icon" ] && content_image="$app_icon"
    fi
  fi
fi
# Fall back to Claude icon if terminal icon not found
[ -z "$content_image" ] && [ -f "$HOME/.claude/notify-icon.png" ] && content_image="$HOME/.claude/notify-icon.png"
# Build click action: use -execute to raise the correct window by project name
activate_flag=""
if [ -n "$bundle" ] && [ -n "$cwd" ]; then
  safe_cwd=$(echo "$cwd" | sed 's/"/\\"/g')
  activate_script=$(mktemp /tmp/notify-activate.XXXXXX)
  cat > "$activate_script" <<SCRIPT
#!/bin/bash
osascript -e 'tell application id "$bundle" to activate' \\
  -e 'delay 0.1' \\
  -e 'tell application "System Events"' \\
  -e '  tell (first application process whose bundle identifier is "$bundle")' \\
  -e '    try' \\
  -e '      set targetWindow to first window whose name contains "$safe_cwd"' \\
  -e '      perform action "AXRaise" of targetWindow' \\
  -e '    end try' \\
  -e '  end tell' \\
  -e 'end tell'
rm -f "\$0"
SCRIPT
  chmod +x "$activate_script"
  activate_flag="-execute $activate_script"
elif [ -n "$bundle" ]; then
  activate_flag="-activate $bundle"
fi
terminal-notifier -title "$title" -message "$message" $sound_flag ${content_image:+-contentImage "$content_image"} -group "${session:-default}" $activate_flag
if [ "$notify_sound" = "true" ]; then
  sound_file="/System/Library/Sounds/${sound}.aiff"
  [ -f "$sound_file" ] && afplay "$sound_file" &
fi
