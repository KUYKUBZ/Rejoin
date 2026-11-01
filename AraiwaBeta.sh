#!/data/data/com.termux/files/usr/bin/bash

# ==========================================
#             A R A I W A
#       ROBLOX AUTO REOPEN SYSTEM
# ==========================================

CONFIG="$HOME/.rejoin_link"
BASE="$HOME/.araiwaa"
LOG="$BASE/system.log"
PIDFILE="$BASE/ram_monitor.pid"

mkdir -p "$BASE"
touch "$LOG"

CYAN='\033[1;36m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
RESET='\033[0m'

RAM_LIMIT=85
CLEAN_INTERVAL=60
RAM_MONITOR_PID=""

# ==========================================
# FIND ROBLOX PACKAGES
# ==========================================

get_packages() {
    pm list packages |
        grep -Ei 'roblox|delt' |
        sed 's/package://'
}

# ==========================================
# CHECK APP TASK
# ==========================================

has_task() {
    /system/bin/dumpsys activity recents 2>/dev/null |
        grep -F "A=$1 " >/dev/null
}

# ==========================================
# RAM MONITOR
# ==========================================

get_ram_usage() {
    awk '
    /MemTotal:/ {total=$2}
    /MemAvailable:/ {available=$2}
    END {
        if (total > 0)
            printf "%d", ((total-available)*100)/total
        else
            print 0
    }' /proc/meminfo
}

ram_monitor() {
    while true; do

        RAM=$(get_ram_usage)

        if [ "$RAM" -ge "$RAM_LIMIT" ]; then

            echo "[$(date)] RAM HIGH: ${RAM}%" >> "$LOG"

            # Request memory trim for Termux
            am send-trim-memory \
                com.termux RUNNING_LOW \
                >/dev/null 2>&1

        fi

        sleep "$CLEAN_INTERVAL"
    done
}

start_ram_monitor() {

    if [ -n "$RAM_MONITOR_PID" ] &&
       kill -0 "$RAM_MONITOR_PID" 2>/dev/null; then
        return
    fi

    ram_monitor &
    RAM_MONITOR_PID=$!

    echo "$RAM_MONITOR_PID" > "$PIDFILE"
}

stop_ram_monitor() {

    if [ -n "$RAM_MONITOR_PID" ]; then
        kill "$RAM_MONITOR_PID" 2>/dev/null
        wait "$RAM_MONITOR_PID" 2>/dev/null
    fi

    rm -f "$PIDFILE"
}

# ==========================================
# OPEN ROBLOX
# ==========================================

open_package() {

    package="$1"
    url="$2"

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
}

# ==========================================
# MAIN MENU
# ==========================================

while true; do

    clear

    WIDTH=$(tput cols 2>/dev/null)
    [[ "$WIDTH" =~ ^[0-9]+$ ]] || WIDTH=30

    [ "$WIDTH" -lt 10 ] && WIDTH=10
    [ "$WIDTH" -gt 50 ] && WIDTH=50

    INNER=$((WIDTH - 2))

    border() {
        printf "${CYAN}+"
        printf '%*s' "$INNER" '' | tr ' ' '-'
        printf "+${RESET}\n"
    }

    line() {
        printf "${CYAN}|${RESET}"
        printf "%-*.*s" "$INNER" "$INNER" "$1"
        printf "${CYAN}|${RESET}\n"
    }

    border
    line ""
    line "       A r a i w a"
    line "      SMART REJOIN"
    line ""
    border
    line ""
    line " [1] Open Roblox"
    line " [2] Set Game Link"
    line " [3] RAM Information"
    line " [4] Exit"
    line ""
    border

    printf "\n${YELLOW}Select: ${WHITE}"
    read -r choice

    case "$choice" in

        1)

            packages=$(get_packages)

            if [ -z "$packages" ]; then
                echo "No Roblox apps found."
                read -r -p "Press Enter..."
                continue
            fi

            url=""

            [ -f "$CONFIG" ] &&
                url=$(cat "$CONFIG")

            start_ram_monitor

            echo ""
            echo "Starting Roblox packages..."

            for package in $packages; do

                echo "Opening: $package"

                open_package "$package" "$url"

                sleep 20

            done

            echo ""
            echo "Auto Reopen Started."
            echo "Press CTRL+C to stop."

            trap 'stop_ram_monitor; trap - INT; break' INT

            while true; do

                for package in $packages; do

                    if ! has_task "$package"; then

                        echo "[Task Not Found] $package"

                        open_package "$package" "$url"

                        sleep 20

                    fi

                done

                sleep 5

            done

            trap - INT

            ;;

        2)

            read -r -p "Enter Game ID or Link: " game

            if [[ "$game" =~ ^[0-9]+$ ]]; then

                url="roblox://experiences/start?placeId=$game"

            elif [[ "$game" == http://* ||
                    "$game" == https://* ]]; then

                url="$game"

            else

                echo "Invalid Game ID or Link."
                read -r -p "Press Enter..."
                continue

            fi

            echo "$url" > "$CONFIG"

            echo "Link saved successfully!"

            read -r -p "Press Enter..."

            ;;

        3)

            RAM=$(get_ram_usage)

            echo ""
            echo "========== RAM INFORMATION =========="
            echo "RAM Usage: ${RAM}%"
            echo "RAM Threshold: ${RAM_LIMIT}%"
            echo "Monitor Interval: ${CLEAN_INTERVAL}s"
            echo "======================================"

            read -r -p "Press Enter..."

            ;;

        4)

            stop_ram_monitor
            exit 0

            ;;

        *)

            echo "Invalid option."
            sleep 1

            ;;

    esac

done
