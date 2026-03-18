#!/bin/bash
# Clean up stale activate scripts (only deleted on click, not dismiss)
find /tmp -name 'notify-activate.*' -mmin +60 -delete 2>/dev/null

input=$(cat)

# Parse config and input payload in a single Python call
sound="Glass"
focused_notification=true
focused_sound=true
unfocused_notification=true
unfocused_sound=true
message=""
cwd=""
session=""
{
  IFS= read -r sound
  IFS= read -r focused_notification
  IFS= read -r focused_sound
  IFS= read -r unfocused_notification
  IFS= read -r unfocused_sound
  IFS= read -r message
  IFS= read -r cwd
  IFS= read -r session
} < <(echo "$input" | /usr/bin/python3 -c "
import sys, json, os
config_path = os.path.expanduser('~/.claude/notify-config.json')
sound, fn, fs, un, us = 'Glass', 'true', 'true', 'true', 'true'
try:
    with open(config_path) as f:
        c = json.load(f)
    fc = c.get('focused', {})
    uf = c.get('unfocused', {})
    sound = c.get('sound', 'Glass')
    fn = str(fc.get('notification', True)).lower()
    fs = str(fc.get('sound', True)).lower()
    un = str(uf.get('notification', True)).lower()
    us = str(uf.get('sound', True)).lower()
except Exception:
    pass
print(sound); print(fn); print(fs); print(un); print(us)
try:
    d = json.load(sys.stdin)
    tool = d.get('tool_name', '')
    if tool:
        desc = d.get('tool_input', {}).get('description', '') or d.get('tool_input', {}).get('command', '')
        msg = f'Requesting permission to {tool}: {desc}' if desc else f'Requesting permission to use {tool}'
    else:
        msg = d.get('last_assistant_message', '')
    if not msg:
        raise ValueError
    if len(msg) > 100:
        t = msg[:100]
        i = t.rfind(' ')
        msg = (t[:i] if i > 0 else t) + '...'
    print(msg)
    print(d.get('cwd', '').split('/')[-1])
    print(d.get('session_id', 'default'))
except Exception:
    pass
" 2>/dev/null)
[ -z "$message" ] && exit 0

# Resolve parent app bundle ID
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

# Walk the process tree to find our shell PID and TTY (used for focus detection everywhere)
_pid=$$
_shell_pid=""
_ide_pid=""
while true; do
  _ppid=$(ps -o ppid= -p "$_pid" 2>/dev/null | tr -d ' ')
  [ -z "$_ppid" ] || [ "$_ppid" = "0" ] || [ "$_ppid" = "1" ] && break
  _ptty=$(ps -o tty= -p "$_ppid" 2>/dev/null | tr -d ' ')
  if [ "$_ptty" = "??" ]; then
    _shell_pid=$_pid
    _ide_pid=$_ppid
    break
  fi
  _pid=$_ppid
done
_shell_tty=""
[ -n "$_shell_pid" ] && _shell_tty=$(ps -o tty= -p "$_shell_pid" 2>/dev/null | tr -d ' ')

# For JetBrains IDEs, resolve terminal tab via PID
jb_tab=""
jb_url_project=""
jb_url_tab=""
jb_tabs=""
jb_port=""
case "$bundle" in
  com.jetbrains.*|com.google.android.studio)
    # Find which built-in server port belongs to our IDE process
    if [ -n "$_ide_pid" ]; then
      jb_port=$(lsof -anP -iTCP -sTCP:LISTEN -p "$_ide_pid" 2>/dev/null | awk '/127\.0\.0\.1:6334[2-9]|127\.0\.0\.1:6335[01]/ {sub(/.*:/,"",$9); print $9; exit}')
      if [ -n "$jb_port" ]; then
        jb_tabs=$(curl -sf --connect-timeout 0.5 "http://127.0.0.1:$jb_port/api/claude/terminal/tabs" 2>/dev/null)
      fi
    fi

    if [ -n "$jb_tabs" ] && [ -n "$_shell_pid" ]; then
      # Resolve tab by matching shell PID, with fallback to selected tab
      {
        IFS= read -r jb_tab
        IFS= read -r jb_url_project
        IFS= read -r jb_url_tab
      } < <(echo "$jb_tabs" | /usr/bin/python3 -c "
import sys, json, urllib.parse
shell_pid, cwd = int(sys.argv[1]), sys.argv[2]
tabs = json.load(sys.stdin)
tab = ''
# Primary: exact PID match
for t in tabs:
    if t.get('pid') == shell_pid:
        tab = t['tab']
        cwd = t['project']
        break
# Fallback: selected tab in matching project
if not tab:
    for t in tabs:
        if t['project'] == cwd and t.get('selected'):
            tab = t['tab']
            break
if tab:
    print(tab)
    print(urllib.parse.quote(cwd))
    print(urllib.parse.quote(tab))
" "$_shell_pid" "$cwd" 2>/dev/null)
    fi
    ;;
esac

# Focus detection: check if the user is looking at THIS Claude session
is_focused=false
frontmost=$(osascript -e 'tell application "System Events" to get bundle identifier of first application process whose frontmost is true' 2>/dev/null)
if [ "$frontmost" = "$bundle" ]; then
  if [ -n "$jb_tabs" ] && [ -n "$_shell_pid" ]; then
    # JetBrains: PID-based — check if our tab is selected
    echo "$jb_tabs" | /usr/bin/python3 -c "
import sys, json
pid = int(sys.argv[1])
for t in json.load(sys.stdin):
    if t.get('pid') == pid and t.get('selected'):
        sys.exit(0)
sys.exit(1)
" "$_shell_pid" 2>/dev/null && is_focused=true
  elif [ -n "$_shell_tty" ]; then
    # TTY-based: compare our shell TTY with the focused terminal tab's TTY
    focused_tty=""
    case "$bundle" in
      com.googlecode.iterm2)
        focused_tty=$(osascript -e 'tell application "iTerm2" to get tty of current session of current tab of current window' 2>/dev/null)
        ;;
      com.apple.Terminal)
        focused_tty=$(osascript -e 'tell application "Terminal" to get tty of selected tab of front window' 2>/dev/null)
        ;;
    esac
    if [ -n "$focused_tty" ]; then
      # Strip /dev/ prefix for comparison (ps returns "ttys006", AppleScript returns "/dev/ttys006")
      focused_tty="${focused_tty#/dev/}"
      [ "$focused_tty" = "$_shell_tty" ] && is_focused=true
    else
      # Unsupported terminal: fall back to reading focused UI element text
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
        if [ -n "$cwd" ] && echo "$ax_value" | grep -qF "$cwd"; then
          is_focused=true
        fi
      fi
    fi
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
# Build terminal-notifier command as an array to avoid word-splitting issues
cmd=(terminal-notifier -title "$title" -message "$message" -group "${session:-default}")
[ -n "$content_image" ] && cmd+=(-contentImage "$content_image")
# Click action: raise the correct window and terminal tab
if [ -n "$jb_tab" ]; then
  # JetBrains: plugin handles window activation + tab focus sequentially
  activate_script=$(mktemp /tmp/notify-activate.XXXXXX)
  cat > "$activate_script" <<SCRIPT
#!/bin/bash
curl -sf "http://127.0.0.1:$jb_port/api/claude/terminal/focus?project=$jb_url_project&tab=$jb_url_tab" >/dev/null 2>&1
rm -f "\$0"
SCRIPT
  chmod +x "$activate_script"
  cmd+=(-execute "$activate_script")
elif [ -n "$bundle" ] && [ -n "$cwd" ]; then
  # Other terminals: AppleScript to raise the correct window
  safe_cwd=$(echo "$cwd" | sed 's/\\/\\\\/g; s/"/\\"/g')
  activate_script=$(mktemp /tmp/notify-activate.XXXXXX)
  cat > "$activate_script" <<SCRIPT
#!/bin/bash
osascript -e 'tell application id "$bundle" to activate' \\
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
  cmd+=(-execute "$activate_script")
elif [ -n "$bundle" ]; then
  cmd+=(-activate "$bundle")
fi
"${cmd[@]}"
if [ "$notify_sound" = "true" ]; then
  sound_file="/System/Library/Sounds/${sound}.aiff"
  [ -f "$sound_file" ] && afplay "$sound_file" &
fi
