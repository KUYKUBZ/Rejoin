
#!/data/data/com.termux/files/usr/bin/bash

CONFIG="$HOME/.rejoin_link"
ERROR_LOG="$HOME/ariwaa_errors.log"
LOCK_DIR="$HOME/.ariwaa_locks"
XML="/sdcard/ariwaa_window.xml"

mkdir -p "$LOCK_DIR"
touch "$ERROR_LOG"

CYAN='\033[1;36m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
RESET='\033[0m'

# -----------------------------
# Packages
# -----------------------------

get_packages() {
    pm list packages |
        grep -Ei 'roblox|delt' |
        sed 's/package://'
}

# -----------------------------
# Foreground package
# -----------------------------

get_foreground() {
    su -c 'dumpsys activity activities' 2>/dev/null |
        grep -E 'mResumedActivity|topResumedActivity' |
        tail -n 1 |
        grep -oE '[A-Za-z0-9_.]+/[A-Za-z0-9_.$]+' |
        head -n 1 |
        cut -d/ -f1
}

# -----------------------------
# Check package
# -----------------------------

is_target() {
    printf '%s\n' "$PACKAGES" |
        grep -Fxq "$1"
}

# -----------------------------
# Read foreground UI
# -----------------------------

read_screen() {
    su -c "uiautomator dump $XML >/dev/null 2>&1 && cat $XML && rm -f $XML" 2>/dev/null
}

# -----------------------------
# Detect visible errors
# -----------------------------

detect_error() {
    local screen="$1"

    printf '%s\n' "$screen" |
        grep -Eio \
        'Error[ _-]*Code[^"]*[0-9]+|DISCONNECTED|Connection Lost|Connection Failed|Connection Timed Out|Same account launched' |
        head -n 1
}

# -----------------------------
# Manual verification errors
# -----------------------------

is_blocked() {
    printf '%s\n' "$1" |
        grep -Eiq \
        'AccountLocked|TwoStepVerification|Captcha|Verification|ChallengeActivity|Funcaptcha'
}

# -----------------------------
# Open Roblox
# -----------------------------

open_rbx() {
    local package="$1"

    echo -e "${YELLOW}[STOP] $package${RESET}"

    su -c "am force-stop $package"

    sleep 2

    echo -e "${GREEN}[OPEN] $package${RESET}"

    if [ -n "$url" ]; then
        am start \
            -a android.intent.action.VIEW \
            -d "$url" \
            -p "$package"
    else
        monkey -p "$package" 1
    fi
}

# -----------------------------
# Recovery
# -----------------------------

recover() {
    local package="$1"
    local error="$2"

    local lock="$LOCK_DIR/$package"

    if ! mkdir "$lock" 2>/dev/null; then
        return
    fi

    echo
    echo -e "${RED}[ERROR DETECTED]${RESET}"
    echo "Package: $package"
    echo "Error: $error"

    echo "[$(date '+%F %T')] $package : $error" \
        >> "$ERROR_LOG"

    if is_blocked "$error"; then
        echo -e "${YELLOW}[MANUAL CHECK REQUIRED]${RESET}"
        rmdir "$lock"
        return
    fi

    open_rbx "$package"

    echo "[WAIT] 15 seconds..."
    sleep 15

    rmdir "$lock" 2>/dev/null

    echo -e "${GREEN}[RECOVERY FINISHED]${RESET}"
}

# -----------------------------
# Menu
# -----------------------------

while true; do

    clear

    echo -e "${CYAN}+------------------------------+${RESET}"
    echo -e "${CYAN}|          A R I W A A         |${RESET}"
    echo -e "${CYAN}+------------------------------+${RESET}"
    echo
    echo "[1] Open Roblox + Monitor"
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

            while IFS= read -r package; do
                [ -z "$package" ] && continue

                open_rbx "$package"
                sleep 20

            done <<< "$PACKAGES"

            echo
            echo -e "${GREEN}[MONITOR STARTED]${RESET}"

            # Monitor foreground application
            while true; do

                CURRENT=$(get_foreground)

                if [ -n "$CURRENT" ] && is_target "$CURRENT"; then

                    echo -e "${GREEN}[APP FOREGROUND]${RESET} $CURRENT"

                    SCREEN=$(read_screen)

                    ERROR=$(detect_error "$SCREEN")

                    if [ -n "$ERROR" ]; then

                        recover "$CURRENT" "$ERROR"

                    else

                        echo -e "${CYAN}[NO VISIBLE ERROR]${RESET} $CURRENT"

                    fi

                else

                    echo -e "${YELLOW}[WAITING FOR ROBLOX]${RESET}"

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
