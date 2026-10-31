
#!/data/data/com.termux/files/usr/bin/bash

CONFIG="$HOME/.rejoin_link"
ERROR_LOG="$HOME/ariwaa_errors.log"
LOCK_DIR="$HOME/.ariwaa_locks"
STATE_DIR="$HOME/.ariwaa_state"
EVENT_LOG="$STATE_DIR/events.log"

mkdir -p "$LOCK_DIR" "$STATE_DIR"
touch "$ERROR_LOG" "$EVENT_LOG"

CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
WHITE='\033[1;37m'
RESET='\033[0m'

LOGCAT_PID=""
PROCESS_PID=""
PACKAGES=""
url=""
RUNNING=0

# -----------------------------
# Find packages
# -----------------------------

get_packages() {
    pm list packages |
        grep -Ei 'roblox|delt' |
        sed 's/package://' |
        sort -u
}

is_target() {
    local target="$1"
    grep -Fxq "$target" <<< "$PACKAGES"
}

# -----------------------------
# Package process check
# -----------------------------

package_running() {
    local package="$1"

    is_target "$package" || return 1

    su -c "pidof '$package'" 2>/dev/null |
        grep -q '[0-9]'
}

# -----------------------------
# Event output
# -----------------------------

event() {
    printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >> "$EVENT_LOG"
}

# -----------------------------
# PID to package
# -----------------------------

find_package_by_pid() {
    local pid="$1"
    local process
    local package

    [[ "$pid" =~ ^[0-9]+$ ]] || return 1

    process=$(
        su -c "ps -A -o PID,NAME" 2>/dev/null |
        awk -v p="$pid" '$1 == p {print $2; exit}'
    )

    for package in $PACKAGES; do
        case "$process" in
            "$package"|"$package":*)
                printf '%s\n' "$package"
                return 0
                ;;
        esac
    done

    return 1
}

identify_package() {
    local line="$1"
    local pid="$2"
    local package

    for package in $PACKAGES; do
        if [[ "$line" == *"$package"* ]]; then
            printf '%s\n' "$package"
            return 0
        fi
    done

    find_package_by_pid "$pid"
}

# -----------------------------
# Error detection
# -----------------------------

is_error() {
    printf '%s\n' "$1" |
        grep -Eiq \
        'Error[ _-]*Code[^0-9]*[0-9]+|Disconnected from|DISCONNECTED|Connection Lost|Connection Failed|Connection Timed Out|FATAL EXCEPTION|am_crash|ANR in|am_anr|has died'
}

get_error_code() {
    local line="$1"

    if [[ "$line" =~ [Ee]rror[[:space:]_-]*[Cc]ode[^0-9]*([0-9]+) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    else
        printf 'UNKNOWN\n'
    fi
}

# -----------------------------
# Manual attention
# -----------------------------

requires_manual() {
    local line="$1"

    printf '%s\n' "$line" |
        grep -Eiq \
        'AccountLocked|TwoStepVerification|Captcha|Verification|ChallengeActivity|Funcaptcha|Error[ _-]*Code[^0-9]*267'
}

# -----------------------------
# Open package
# -----------------------------

open_rbx() {
    local package="$1"

    is_target "$package" || {
        event "[REJECTED] Unknown package: $package"
        return 1
    }

    event "[OPEN] $package"

    if [ -n "$url" ]; then
        am start \
            -a android.intent.action.VIEW \
            -d "$url" \
            -p "$package" >/dev/null 2>&1
    else
        monkey -p "$package" 1 >/dev/null 2>&1
    fi
}

# -----------------------------
# Recovery
# -----------------------------

recover_package() {
    local package="$1"
    local line="$2"
    local code
    local lock="$LOCK_DIR/$package"
    local last_file="$STATE_DIR/$package.status"
    local now
    local last=0

    is_target "$package" || return 1

    code=$(get_error_code "$line")

    if requires_manual "$line"; then
        event "[MANUAL CHECK] $package | CODE: $code"
        return
    fi

    if ! mkdir "$lock" 2>/dev/null; then
        return
    fi

    now=$(date +%s)

    [ -f "$last_file" ] &&
        read -r last < "$last_file"

    if [[ "$last" =~ ^[0-9]+$ ]] &&
       (( now - last < 45 )); then
        event "[COOLDOWN] $package"
        rmdir "$lock"
        return
    fi

    printf '%s\n' "$now" > "$last_file"

    {
        echo "[$(date '+%F %T')]"
        echo "PACKAGE: $package"
        echo "ERROR CODE: $code"
        echo "LOG: $line"
        echo "-------------------------"
    } >> "$ERROR_LOG"

    event "[ERROR] $package | CODE: $code"

    # Restart only the selected package.
    su -c "am force-stop '$package'" >/dev/null 2>&1

    sleep 2

    open_rbx "$package"

    event "[WAIT] $package"

    sleep 20

    if package_running "$package"; then
        event "[PROCESS RUNNING] $package"
    else
        event "[PROCESS NOT FOUND] $package"
    fi

    rmdir "$lock"
}

# -----------------------------
# Logcat monitor
# -----------------------------

monitor_logcat() {
    event "[LOGCAT STARTED]"

    su -c 'logcat -v threadtime' 2>/dev/null |
    while IFS= read -r raw; do

        # threadtime format:
        # date time PID TID priority tag: message

        read -r date time pid tid priority rest <<< "$raw"

        [[ "$pid" =~ ^[0-9]+$ ]] || continue

        is_error "$raw" || continue

        package=$(identify_package "$raw" "$pid")

        [ -n "$package" ] || continue

        event "[LOG ERROR] $package"

        recover_package "$package" "$raw" &

    done
}

# -----------------------------
# Process monitor
# -----------------------------

monitor_processes() {
    local package
    local count
    local -A missing

    for package in $PACKAGES; do
        missing["$package"]=0
    done

    event "[PROCESS MONITOR STARTED]"

    while true; do

        for package in $PACKAGES; do

            if package_running "$package"; then

                missing["$package"]=0

                event "[PROCESS RUNNING] $package"

            else

                count=${missing["$package"]}
                count=$((count + 1))

                missing["$package"]=$count

                event "[PROCESS MISSING] $package ($count/3)"

                if (( count >= 3 )); then

                    event "[PROCESS LOST] $package"

                    recover_package \
                        "$package" \
                        "Process missing / application stopped" &

                    missing["$package"]=0

                fi

            fi

        done

        sleep 5
    done
}

# -----------------------------
# Dashboard
# -----------------------------

dashboard() {
    local line
    local last_line=0

    while true; do

        clear

        printf "${CYAN}+--------------------------------------+\n"
        printf "|              ARIWAA MONITOR          |\n"
        printf "+--------------------------------------+\n${RESET}"

        printf "\n${WHITE}Packages:${RESET}\n"

        while IFS= read -r package; do
            [ -z "$package" ] && continue

            if package_running "$package"; then
                printf "${GREEN}[RUNNING]${RESET} %s\n" "$package"
            else
                printf "${YELLOW}[MISSING]${RESET} %s\n" "$package"
            fi

        done <<< "$PACKAGES"

        printf "\n${CYAN}Recent Events:${RESET}\n"

        tail -n 15 "$EVENT_LOG"

        printf "\n${YELLOW}Press CTRL+C to stop monitoring.${RESET}\n"

        sleep 3
    done
}

# -----------------------------
# Stop monitors
# -----------------------------

stop_monitors() {
    [ "$RUNNING" = 1 ] || return
    RUNNING=0

    trap '' INT TERM

    event "[STOPPING MONITORS]"

    [ -n "$LOGCAT_PID" ] &&
        kill "$LOGCAT_PID" 2>/dev/null

    [ -n "$PROCESS_PID" ] &&
        kill "$PROCESS_PID" 2>/dev/null

    jobs -pr | xargs -r kill 2>/dev/null

    wait 2>/dev/null

    rm -rf "$LOCK_DIR"/*

    printf "\n${YELLOW}Monitor stopped.${RESET}\n"
}

# -----------------------------
# Main menu
# -----------------------------

while true; do

    clear

    printf "${CYAN}+------------------------------+\n"
    printf "|          A R I W A A         |\n"
    printf "+------------------------------+${RESET}\n\n"

    echo "[1] Open Roblox + Multi Monitor"
    echo "[2] Set Game Link"
    echo "[3] View Error Log"
    echo "[4] Exit"
    echo

    read -r -p "Select: " choice

    case "$choice" in

        1)

            PACKAGES=$(get_packages)

            if [ -z "$PACKAGES" ]; then
                echo "No Roblox packages found."
                read -r -p "Press Enter..."
                continue
            fi

            url=""
            [ -f "$CONFIG" ] && url=$(cat "$CONFIG")

            : > "$EVENT_LOG"

            echo
            echo "Packages detected:"

            while IFS= read -r package; do

                [ -z "$package" ] && continue

                echo " - $package"

                open_rbx "$package"

                sleep 10

            done <<< "$PACKAGES"

            echo
            echo "Starting monitors..."

            RUNNING=1

            monitor_logcat &
            LOGCAT_PID=$!

            monitor_processes &
            PROCESS_PID=$!

            trap 'stop_monitors; exit 0' INT TERM

            dashboard

            stop_monitors
            ;;

        2)

            read -r -p "Enter Game ID or Link: " game

            if [[ "$game" =~ ^[0-9]+$ ]]; then
                url="roblox://experiences/start?placeId=$game"

            elif [[ "$game" == http://* || "$game" == https://* ]]; then
                url="$game"

            else
                echo "Invalid Game ID or Link."
                read -r -p "Press Enter..."
                continue
            fi

            printf '%s\n' "$url" > "$CONFIG"

            echo "Link saved!"
            read -r -p "Press Enter..."

            ;;

        3)

            cat "$ERROR_LOG"
            read -r -p "Press Enter..."

            ;;

        4)

            exit 0
            ;;

        *)

            echo "Invalid option."
            sleep 1
            ;;

    esac

done
