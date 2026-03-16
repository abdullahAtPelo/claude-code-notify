#!/bin/bash
# Clean up stale activate scripts (only deleted on click, not dismiss)
find /tmp -name 'notify-activate.*' -mmin +60 -delete 2>/dev/null

input=$(cat)

# Load config (defaults if missing)
CONFIG_FILE="$HOME/.claude/notify-config.json"
sound="Glass"
focused_notification=true
focused_sound=true
unfocused_notification=true
unfocused_sound=true
if [ -f "$CONFIG_FILE" ]; then
  {
    IFS= read -r sound
    IFS= read -r focused_notification
    IFS= read -r focused_sound
    IFS= read -r unfocused_notification
    IFS= read -r unfocused_sound
  } < <(/usr/bin/python3 -c "
import json
with open('$CONFIG_FILE') as f: c=json.load(f)
fc=c.get('focused',{})
u=c.get('unfocused',{})
print(c.get('sound','Glass'))
print(str(fc.get('notification',True)).lower())
print(str(fc.get('sound',True)).lower())
print(str(u.get('notification',True)).lower())
print(str(u.get('sound',True)).lower())
" 2>/dev/null)
fi

# Extract message, cwd, and session from the hook payload
message=""
cwd=""
session=""
if [ -n "$input" ]; then
  {
    IFS= read -r message
    IFS= read -r cwd
    IFS= read -r session
  } < <(echo "$input" | /usr/bin/python3 -c "
import sys, json
d = json.load(sys.stdin)
tool = d.get('tool_name', '')
if tool:
    desc = d.get('tool_input', {}).get('description', '') or d.get('tool_input', {}).get('command', '')
    msg = f'Requesting permission to {tool}: {desc}' if desc else f'Requesting permission to use {tool}'
else:
    msg = d.get('last_assistant_message', '')
if not msg:
    sys.exit(1)
if len(msg) > 100:
    t = msg[:100]
    i = t.rfind(' ')
    msg = (t[:i] if i > 0 else t) + '...'
print(msg)
print(d.get('cwd', '').split('/')[-1])
print(d.get('session_id', 'default'))
" 2>/dev/null)
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
  if [ -n "$cwd" ] && echo "$ax_value" | grep -qF "$cwd"; then
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
# For JetBrains IDEs, detect which terminal tab is active (likely the one running Claude)
jb_tab=""
case "$bundle" in
  com.jetbrains.*|com.google.android.studio)
    for jb_port in $(seq 63342 63351); do
      jb_tabs=$(curl -sf --connect-timeout 0.5 "http://127.0.0.1:$jb_port/api/claude/terminal/tabs" 2>/dev/null) && break
      jb_port=""
    done
    if [ -n "$jb_tabs" ]; then
      # Identify our terminal tab by walking the process tree.
      # Our shell is the ancestor of this script whose parent has no TTY (the IDE process).
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

      if [ -n "$_shell_pid" ] && [ -n "$_ide_pid" ]; then
        # Find all IDE child shells with TTYs (sorted by PID = creation order)
        _all_ide_shells=$(ps -eo pid,ppid,tty 2>/dev/null | awk -v ide="$_ide_pid" '$2 == ide && $3 != "??" { print $1 }' | sort -n)

        # Filter to shells whose CWD basename matches our project, find our index
        _index=0
        _found=false
        for _spid in $_all_ide_shells; do
          _scwd=$(lsof -a -d cwd -p "$_spid" -Fn 2>/dev/null | awk '/^n/{sub(/^n/,""); print; exit}')
          _scwd_name=$(basename "$_scwd" 2>/dev/null)
          if [ "$_scwd_name" = "$cwd" ]; then
            if [ "$_spid" = "$_shell_pid" ]; then
              _found=true
              break
            fi
            _index=$((_index + 1))
          fi
        done

        if [ "$_found" = "true" ]; then
          jb_tab=$(echo "$jb_tabs" | /usr/bin/python3 -c "
import sys, json
cwd = sys.argv[1]
index = int(sys.argv[2])
tabs = [t for t in json.load(sys.stdin) if t['project'] == cwd]
if index < len(tabs):
    print(tabs[index]['tab'])
" "$cwd" "$_index" 2>/dev/null)
        fi
      fi

      # Fallback: selected tab
      if [ -z "$jb_tab" ]; then
        jb_tab=$(echo "$jb_tabs" | /usr/bin/python3 -c "
import sys, json
cwd = sys.argv[1]
for t in json.load(sys.stdin):
    if t['project'] == cwd and t.get('selected'):
        print(t['tab'])
        break
" "$cwd" 2>/dev/null)
      fi
    fi
    ;;
esac
# Build terminal-notifier command as an array to avoid word-splitting issues
cmd=(terminal-notifier -title "$title" -message "$message" -group "${session:-default}")
[ -n "$content_image" ] && cmd+=(-contentImage "$content_image")
# Click action: raise the correct window and terminal tab
if [ -n "$jb_tab" ]; then
  # JetBrains: plugin handles window activation + tab focus sequentially
  jb_url_project=$(echo "$cwd" | /usr/bin/python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))" 2>/dev/null)
  jb_url_tab=$(echo "$jb_tab" | /usr/bin/python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))" 2>/dev/null)
  activate_script=$(mktemp /tmp/notify-activate.XXXXXX)
  cat > "$activate_script" <<SCRIPT
#!/bin/bash
for p in \$(seq 63342 63351); do
  curl -sf "http://127.0.0.1:\$p/api/claude/terminal/focus?project=$jb_url_project&tab=$jb_url_tab" >/dev/null 2>&1 && break
done
rm -f "\$0"
SCRIPT
  chmod +x "$activate_script"
  cmd+=(-execute "$activate_script")
elif [ -n "$bundle" ] && [ -n "$cwd" ]; then
  # Other terminals: AppleScript to raise the correct window
  safe_cwd=$(echo "$cwd" | sed 's/"/\\"/g')
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
