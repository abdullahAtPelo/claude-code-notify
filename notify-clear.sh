#!/bin/bash
# Clear notification for this session when the user submits a prompt
input=$(cat)
session=$(echo "$input" | /usr/bin/python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id','default'))" 2>/dev/null)
terminal-notifier -remove "${session:-default}" 2>/dev/null
