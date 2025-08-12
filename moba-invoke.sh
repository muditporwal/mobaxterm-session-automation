#!/usr/bin/env bash

# mobaxterm-external-ini.sh: Launch MobaXterm with a symlinked, timestamped INI file
# Usage: ./mobaxterm-external-ini.sh

# Require CSV file as first argument (relative to current directory)
if [[ -z "$1" ]]; then
    echo "Usage: $0 <path/to/sessions.csv>"
    echo "  Example: $0 my_sessions.csv"
    exit 1
fi
CSV_FILE="$1"

# Global Configuration
MOBAXTERM_EXE="C:/Program Files (x86)/Mobatek/MobaXterm/MobaXterm.exe"
MOBAXTERM_INI="C:/Users/U004700/AppData/Local/mobaxterm/MobaXterm.ini"
TEMPLATE_INI="$(dirname "$0")/config/template.ini"
GLOBAL_SSH_KEY="_ProfileDir_\\.ssh\\id_ed25519"

# Create timestamped INI
NOW=$(date +%Y%m%d_%H%M%S)
SESSIONS_DIR="$(pwd)/sessions"
mkdir -p "$SESSIONS_DIR"
NEW_INI="$SESSIONS_DIR/MobaXterm_$NOW.ini"

echo "[INFO] Generating MobaXterm INI: $NEW_INI"

# Validate required files
[[ -f "$TEMPLATE_INI" ]] || { echo "[ERROR] Template file not found: $TEMPLATE_INI"; exit 1; }
[[ -f "$CSV_FILE" ]] || { echo "[ERROR] CSV file not found: $CSV_FILE"; exit 1; }
[[ -f "$MOBAXTERM_EXE" ]] || { echo "[ERROR] MobaXterm executable not found: $MOBAXTERM_EXE"; exit 1; }

# Extract session template
SESSION_TEMPLATE=$(grep -m1 "{name}=#" "$TEMPLATE_INI" | tr -d '\r\n')
[[ -n "$SESSION_TEMPLATE" ]] || { echo "[ERROR] Session template not found in $TEMPLATE_INI"; exit 1; }

# Generate sessions from CSV
SESSION_LINES=""
SESSION_COUNT=0

while IFS=',' read -r name ip user port _; do
    [[ "$name" == "" || "$name" == "Name" ]] && continue

    # Strip double quotes from each field
    name=${name//\"/}
    ip=${ip//\"/}
    user=${user//\"/}
    port=${port//\"/}

    # Replace placeholders and apply transformations
    session_line="$SESSION_TEMPLATE"
    session_line="${session_line//\{name\}/$name}"
    session_line="${session_line//\{ip\}/$ip}"
    session_line="${session_line//\{username\}/$user}"
    session_line="${session_line//\{port\}/$port}"
    session_line="${session_line//\{ssh_pkey\}/$GLOBAL_SSH_KEY}"
    session_line=$(echo "$session_line" | sed -E 's#[Cc]:/#_currentdir_/#g')
    
    SESSION_LINES+="$session_line"$'\r\n'
    ((SESSION_COUNT++))
done < <(tail -n +2 "$CSV_FILE")

[[ "$SESSION_COUNT" -gt 0 ]] || { echo "[ERROR] No sessions generated from CSV"; exit 1; }
echo "[INFO] Generated $SESSION_COUNT sessions"


# Create INI file with sessions
{
    sed -n '1,/^\[Bookmarks\]/p' "$TEMPLATE_INI"
    echo -ne "$SESSION_LINES"
    sed -n '/^\[Bookmarks\]/,${/^{name}=/d; p}' "$TEMPLATE_INI" | tail -n +2
} > "$NEW_INI"

# Ensure Windows line endings
command -v unix2dos >/dev/null 2>&1 && unix2dos "$NEW_INI" 2>/dev/null || sed -i 's/$/\r/' "$NEW_INI" 2>/dev/null || true

# Create symlink and launch MobaXterm
[[ -e "$MOBAXTERM_INI" ]] && rm -f "$MOBAXTERM_INI"
if command -v cygpath >/dev/null 2>&1; then
    ln -sf "$(cygpath -w "$NEW_INI")" "$MOBAXTERM_INI"
else
    ln -sf "$NEW_INI" "$MOBAXTERM_INI"
fi

echo "[INFO] Created INI: $NEW_INI"
echo "[INFO] Launching MobaXterm..."
"$MOBAXTERM_EXE" &
echo "[SUCCESS] MobaXterm launched with generated INI file."

# Clean up: remove symlink and generated INI after launch
sleep 30  # Give MobaXterm a moment to read the INI
if [[ -e "$MOBAXTERM_INI" ]]; then
    rm -f "$MOBAXTERM_INI"
    echo "[INFO] Removed symlink: $MOBAXTERM_INI"
fi
if [[ -f "$NEW_INI" ]]; then
    rm -f "$NEW_INI"
    echo "[INFO] Removed generated INI: $NEW_INI"
fi
