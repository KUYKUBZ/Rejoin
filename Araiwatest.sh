
#!/data/data/com.termux/files/usr/bin/bash

CONFIG="$HOME/.rejoin_link"
ERROR_LOG="$HOME/ariwaa_errors.log"
LOCK="$HOME/.ariwaa_recovery_lock"

CYAN='\033[1;36m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
GREEN='\033[1;32m'
RESET='\033[0m'

# -----------------------------
# Find Roblox packages
# -----------------------------

get_packages() {
    pm list packages |
        grep -Ei 'roblox|delt' |
        sed 's/package://'
}

# -----------------------------
# Get foreground package
# -----------------------------

get_foreground_package() {
    local activity

    activity=$(
        /system/bin/dumpsys activity activities 2>/dev/null |
        grep -E 'mResumedActivity|topResumedActivity' |
        tail -n 1
    )

    if [ -z "$activity" ]; then
        activity=$(
            /system/bin/dumpsys window windows 2>/dev/null |
            grep 'mCurrentFocus' |
            head -n 1
        )
    fi

    printf '%s\n' "$activity" |
        grep -oE '[A-Za-z0-9_]+(\.[A-Za-z0-9_]+){1,}/' |
        head -n 1 |
        tr -d '/'
}

# -----------------------------
# Check target package
# -----------------------------

is_target_package() {
    local target="$1"

    printf '%s\n' "$PACKAGES" |
        grep -Fxq "$target"
}

# -----------------------------
# Open Roblox
# -----------------------------

open_rbx() {
    local package="$1"

    echo -e "${GREEN}[OPEN] $package${RESET}"

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

# -----------------------------
# Detect Error Code
# -----------------------------

is_error() {
    local line="$1"

    echo "$line" |
        grep -Eiq \
        'Error[ _-]*Code[^0-9]*[0-9]+|Disconnected from|Connection Lost|Connection Failed|Connection Timed Out|Same account launched|WIN DEATH|has died|am_crash|ANR in|am_anr'
}

# -----------------------------
# Errors requiring manual attention
# -----------------------------

is_blocked_error() {
    local line="$1"

    echo "$line" |
        grep -Eiq \
        'AccountLocked|ChallengeActivity|TwoStepVerification|arkoselabs|Funcaptcha|Captcha'
}

# -----------------------------
# Error Recovery
# -----------------------------

recover_package() {
    local package="$1"
    local error="$2"

    # Prevent repeated recovery
    if ! mkdir "$LOCK" 2>/dev/null; then
        return
    fi

    {
        echo "[$(date '+%F %T')] Package: $package"
        echo "Error: $error"
        echo "-----------------------------"
    } >> "$ERROR_LOG"

    echo
    echo -e "${RED}[ERROR DETECTED]${RESET}"
    echo "$error"

    if is_blocked_error "$error"; then
        echo -e "${YELLOW}[MANUAL CHECK REQUIRED]${RESET}"
        echo "Verification or account restriction detected."
        rmdir "$LOCK"
        return
    fi

    echo -e "${YELLOW}[REJOIN] $package${RESET}"

    open_rbx "$package"

    echo "Waiting 15 seconds..."

    sleep 15

    rmdir "$LOCK" 2>/dev/null

    echo -e "${GREEN}[RECOVERY FINISHED]${RESET}"
}

# -----------------------------
# Monitor Android Logcat
# -----------------------------

monitor_errors() {
    echo "[LOGCAT] Starting monitor..."

    /system/bin/logcat -v brief 2>&1 |
    while IFS= read -r line; do

        if is_error "$line"; then

            package=$(get_foreground_package)

            if [ -z "$package" ]; then
                continue
            fi

            if ! is_target_package "$package"; then
                continue
            fi

            recover_package "$package" "$line"

        fi

    done
}

# -----------------------------
# Main Menu
# -----------------------------

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
    line "       A r i w a a"
    line ""
    border
    line ""
    line " [1] Open Roblox"
    line " [2] Set Game Link"
    line " [3] View Error Log"
    line " [4] Exit"
    line ""
    border

    printf "\n${YELLOW}Select: ${WHITE}"
    read -r choice

    case "$choice" in

        1)

            PACKAGES=$(get_packages)

            if [ -z "$PACKAGES" ]; then
                echo "No Roblox apps found."
                read -r -p "Press Enter..."
                continue
            fi

            url=""
            [ -f "$CONFIG" ] && url=$(cat "$CONFIG")

            echo "$PACKAGES" | while IFS= read -r package; do
                [ -z "$package" ] && continue

                open_rbx "$package"
                sleep 20
            done

            # Start error monitor
            monitor_errors &
            MONITOR_PID=$!

            trap 'kill "$MONITOR_PID" 2>/dev/null; rmdir "$LOCK" 2>/dev/null; exit 0' INT TERM

            echo
            echo -e "${GREEN}Ariwaa Monitor Started${RESET}"
            echo "Press CTRL+C to stop."

            while true; do

                CURRENT=$(get_foreground_package)

                if [ -n "$CURRENT" ] && is_target_package "$CURRENT"; then

                    echo -ne "\r${GREEN}[FOREGROUND]${RESET} $CURRENT                    "

                else

                    echo -ne "\r${YELLOW}[NOT IN FOREGROUND]${RESET} $CURRENT                    "

                fi

                sleep 3

            done

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

            echo "$url" > "$CONFIG"

            echo "Link saved successfully!"
            read -r -p "Press Enter..."

            ;;

        3)

            if [ -f "$ERROR_LOG" ]; then
                cat "$ERROR_LOG"
            else
                echo "No Error Log."
            fi

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
