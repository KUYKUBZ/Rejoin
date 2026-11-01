
#!/data/data/com.termux/files/usr/bin/bash

# ==========================================
#           ARAIWAA V2
#       ROBLOX CLONE MONITOR
# ==========================================

VERSION="2.0"

BASE="$HOME/.araiwaa"
CONFIG="$BASE/config"
LOG="$BASE/system.log"
ERROR_LOG="$BASE/errors.log"
PROCESS_LOG="$BASE/process.log"
STATE="$BASE/state"
UI_FILE="/sdcard/ariwaa_ui.xml"

mkdir -p "$BASE" "$STATE"

touch "$LOG" "$ERROR_LOG" "$PROCESS_LOG"

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RESET='\033[0m'

# ==========================================
# ROOT CHECK
# ==========================================

check_root() {
    su -c id 2>/dev/null | grep -q 'uid=0'
}

# ==========================================
# PACKAGE DETECTION
# ==========================================

get_packages() {
    pm list packages 2>/dev/null |
        sed 's/package://' |
        grep -Ei 'roblox|delta' |
        sort -u
}

# ==========================================
# LOG SYSTEM
# ==========================================

log() {
    echo "[$(date '+%F %T')] $1" >> "$LOG"
}

error_log() {
    echo "[$(date '+%F %T')] $1" >> "$ERROR_LOG"
}

process_log() {
    echo "[$(date '+%F %T')] $1" >> "$PROCESS_LOG"
}

# ==========================================
# PID DETECTION
# ==========================================

get_pids() {
    local package="$1"

    su -c 'ps -A -o PID,NAME' 2>/dev/null |
        awk -v p="$package" '
        $2 == p || index($2,p":") == 1 {
            print $1
        }'
}

check_pid() {
    local pid="$1"

    [ -d "/proc/$pid" ] || return 1

    local state
    state=$(su -c "cat /proc/$pid/stat" 2>/dev/null |
        awk '{print $3}')

    [ -n "$state" ] && [ "$state" != "Z" ]
}

get_memory() {
    local pid="$1"

    su -c "cat /proc/$pid/status" 2>/dev/null |
        awk '/VmRSS:/ {
            printf "%.1f MB", $2/1024
        }'
}

# ==========================================
# TASK DETECTION
# ==========================================

has_task() {
    local package="$1"

    su -c 'dumpsys activity recents' 2>/dev/null |
        grep -F "$package" >/dev/null
}

# ==========================================
# FOREGROUND ACTIVITY
# ==========================================

get_foreground() {
    su -c 'dumpsys activity activities' 2>/dev/null |
        grep -m 1 -E 'mResumedActivity:|topResumedActivity:' |
        sed -nE 's/.* u[0-9]+ ([^/ ]+)\/.*/\1/p'
}

# ==========================================
# ERROR CODE DETECTION
# ==========================================

check_error_code() {

    local package="$1"
    local foreground

    foreground=$(get_foreground)

    # UI dump can only inspect the visible screen.
    [ "$foreground" = "$package" ] || return 0

    local xml

    xml=$(su -c \
        'uiautomator dump --compressed /sdcard/ariwaa_ui.xml >/dev/null 2>&1; cat /sdcard/ariwaa_ui.xml' \
        2>/dev/null)

    [ -n "$xml" ] || return 0

    local found

    found=$(printf '%s\n' "$xml" |
        grep -Eio 'error[[:space:]_-]*code[^0-9]{0,20}[0-9]{2,4}|error[^0-9]{0,10}[0-9]{2,4}' |
        head -n 1)

    if [ -n "$found" ]; then
        error_log "$package ERROR: $found"

        echo -e "${RED}[ERROR DETECTED]${RESET}"
        echo "Package: $package"
        echo "Message: $found"

        return 1
    fi

    return 0
}

# ==========================================
# OPEN ROBLOX
# ==========================================

open_package() {

    local package="$1"
    local url=""

    [ -f "$CONFIG" ] && url=$(cat "$CONFIG")

    echo -e "${YELLOW}[OPENING]${RESET} $package"

    if [ -n "$url" ]; then

        am start \
            -a android.intent.action.VIEW \
            -d "$url" \
            -p "$package"

    else

        am start \
            -a android.intent.action.MAIN \
            -c android.intent.category.LAUNCHER \
            -p "$package"

    fi

    log "OPEN $package"
}

# ==========================================
# RESTART CONTROL
# ==========================================

restart_package() {

    local package="$1"
    local stamp="$STATE/${package}.restart"
    local now
    local last

    now=$(date +%s)
    last=0

    [ -f "$stamp" ] && last=$(cat "$stamp")

    # 30-second cooldown
    if (( now - last < 30 )); then
        return
    fi

    echo "$now" > "$stamp"

    echo -e "${YELLOW}[REOPEN]${RESET} $package"

    log "REOPEN $package"

    open_package "$package"

}

# ==========================================
# PID HISTORY
# ==========================================

check_pid_change() {

    local package="$1"
    local pid="$2"

    local file="$STATE/${package}.pid"
    local old=""

    [ -f "$file" ] && old=$(cat "$file")

    if [ "$old" != "$pid" ]; then

        process_log "$package PID CHANGE: $old -> $pid"

        echo -e "${CYAN}[PID CHANGE]${RESET} $package"
        echo "Old PID: ${old:-NONE}"
        echo "New PID: $pid"

        echo "$pid" > "$file"
    fi
}

# ==========================================
# MONITOR SYSTEM
# ==========================================

monitor_all() {

    local packages
    packages=$(get_packages)

    if [ -z "$packages" ]; then
        echo "No Roblox packages found."
        read -r -p "Press Enter..."
        return
    fi

    echo
    echo "Launching Roblox Clones..."

    while IFS= read -r package; do
        [ -n "$package" ] || continue

        open_package "$package"
        sleep 20

    done <<< "$packages"

    echo "Starting Monitor..."

    while true; do

        clear

        echo -e "${CYAN}====================================${RESET}"
        echo -e "${CYAN}       ARAIWAA V2 MONITOR${RESET}"
        echo -e "${CYAN}====================================${RESET}"
        echo

        while IFS= read -r package; do

            [ -n "$package" ] || continue

            pids=$(get_pids "$package")

            echo -e "${WHITE}PACKAGE: $package${RESET}"

            if [ -z "$pids" ]; then

                echo -e "${RED}[PROCESS OFFLINE]${RESET}"

                process_log "$package PROCESS OFFLINE"

                restart_package "$package"

                echo
                continue
            fi

            for pid in $pids; do

                if check_pid "$pid"; then

                    memory=$(get_memory "$pid")

                    echo -e "${GREEN}[RUNNING]${RESET}"
                    echo "PID: $pid"
                    echo "RAM: ${memory:-Unknown}"

                    check_pid_change "$package" "$pid"

                else

                    echo -e "${RED}[PROCESS DEAD]${RESET}"

                    process_log "$package PID $pid DEAD"

                    restart_package "$package"

                fi

            done

            if has_task "$package"; then
                echo -e "${GREEN}[TASK FOUND]${RESET}"
            else
                echo -e "${YELLOW}[TASK NOT FOUND]${RESET}"
            fi

            if ! check_error_code "$package"; then
                restart_package "$package"
            fi

            echo

        done <<< "$packages"

        echo "------------------------------------"
        echo "Refresh: 5 seconds"
        echo "Press CTRL+C to stop monitor"

        sleep 5

    done
}

# ==========================================
# SET GAME LINK
# ==========================================

set_game_link() {

    echo
    read -r -p "Enter Game ID or Link: " game

    if [[ "$game" =~ ^[0-9]+$ ]]; then

        url="roblox://experiences/start?placeId=$game"

    elif [[ "$game" == http://* || "$game" == https://* ]]; then

        url="$game"

    else

        echo "Invalid Game ID or Link."
        sleep 2
        return

    fi

    echo "$url" > "$CONFIG"

    echo "Game Link Saved!"
    log "GAME LINK UPDATED"

    read -r -p "Press Enter..."

}

# ==========================================
# SHOW PACKAGES
# ==========================================

show_packages() {

    echo
    echo "Detected Roblox Packages:"
    echo

    get_packages

    echo
    read -r -p "Press Enter..."

}

# ==========================================
# SHOW LOGS
# ==========================================

show_logs() {

    echo
    echo "1. System Log"
    echo "2. Error Log"
    echo "3. Process Log"

    read -r -p "Select: " option

    case "$option" in
        1) tail -n 40 "$LOG" ;;
        2) tail -n 40 "$ERROR_LOG" ;;
        3) tail -n 40 "$PROCESS_LOG" ;;
    esac

    echo
    read -r -p "Press Enter..."

}

# ==========================================
# MAIN MENU
# ==========================================

if ! check_root; then
    echo "Root permission required!"
    exit 1
fi

while true; do

    clear

    echo -e "${CYAN}================================${RESET}"
    echo -e "${CYAN}          A R I W A A${RESET}"
    echo -e "${CYAN}           VERSION $VERSION${RESET}"
    echo -e "${CYAN}================================${RESET}"
    echo
    echo " [1] Open Roblox + Auto Monitor"
    echo " [2] Set Game Link"
    echo " [3] Show Packages"
    echo " [4] View Logs"
    echo " [5] Exit"
    echo

    read -r -p "Select: " choice

    case "$choice" in

        1)
            monitor_all
            ;;

        2)
            set_game_link
            ;;

        3)
            show_packages
            ;;

        4)
            show_logs
            ;;

        5)
            exit 0
            ;;

        *)
            echo "Invalid option."
            sleep 1
            ;;

    esac

done
