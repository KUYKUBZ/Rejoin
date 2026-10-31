
#!/data/data/com.termux/files/usr/bin/bash

CONFIG="$HOME/.rejoin_link"
ERROR_LOG="$HOME/ariwaa_errors.log"
LOCK_DIR="$HOME/.ariwaa_locks"
STATE_DIR="$HOME/.ariwaa_state"

mkdir -p "$LOCK_DIR" "$STATE_DIR"
touch "$ERROR_LOG"

CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
WHITE='\033[1;37m'
RESET='\033[0m'

MONITOR_PID=""
PACKAGES=""
url=""

# -----------------------------
# Find packages
# -----------------------------

get_packages() {
    pm list packages |
        grep -Ei 'roblox|delt' |
        sed 's/package://' |
        sort -u
}

# -----------------------------
# Check package process
# -----------------------------

package_running() {
    local package="$1"

    su -c "pidof $package" 2>/dev/null |
        grep -q '[0-9]'
}

# -----------------------------
# Map Logcat PID to package
# -----------------------------

find_package_by_pid() {
    local pid="$1"
    local process

    [ -z "$pid" ] && return 1

    process=$(
        su -c "ps -A -o PID,NAME" 2>/dev/null |
        awk -v p="$pid" '$1 == p {print $2; exit}'
    )

    for package in $PACKAGES; do
        case "$process" in
            "$package"|"$package":*)
                echo "$package"
                return 0
                ;;
        esac
    done

    return 1
}

# -----------------------------
# Identify package from log
# -----------------------------

identify_package() {
    local line="$1"
    local pid="$2"

    # Package name directly in log
    for package in $PACKAGES; do
        if [[ "$line" == *"$package"* ]]; then
            echo "$package"
            return 0
        fi
    done

    # Otherwise map PID
    find_package_by_pid "$pid"
}

# -----------------------------
# Error detection
# -----------------------------

is_error() {
    printf '%s\n' "$1" |
        grep -Eiq \
        'Error[ _-]*Code[^0-9]*[0-9]+|Disconnected from|DISCONNECTED|Connection Lost|Connection Failed|Connection Timed Out|Same account launched|FATAL EXCEPTION|am_crash|ANR in|am_anr|has died'
}

# -----------------------------
# Error code extraction
# -----------------------------

get_error_code() {
    local line="$1"

    if [[ "$line" =~ [Ee]rror[[:space:]_-]*[Cc]ode[^0-9]*([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "UNKNOWN"
    fi
}

# -----------------------------
# Manual attention errors
# -----------------------------

requires_manual() {
    local line="$1"
    local code="$2"

    # Moderation and verification should not
    # be repeatedly rejoined automatically.
    [ "$code" = "267" ] && return 0

    printf '%s\n' "$line" |
        grep -Eiq \
        'AccountLocked|TwoStepVerification|Captcha|Verification|ChallengeActivity|Funcaptcha'
}

# -----------------------------
# Open package
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

recover_package() {
    local package="$1"
    local line="$2"
    local code
    local lock="$LOCK_DIR/$package"
    local last_file="$STATE_DIR/$package"
    local now
    local last

    code=$(get_error_code "$line")

    # Prevent simultaneous recovery
    if ! mkdir "$lock" 2>/dev/null; then
        return
    fi

    # Cooldown per package
    now=$(date +%s)
    last=0

    [ -f "$last_file" ] && read -r last < "$last_file"

    if [[ "$last" =~ ^[0-9]+$ ]] &&
       (( now - last < 45 )); then
        echo "[COOLDOWN] $package"
        rmdir "$lock"
        return
    fi

    echo "$now" > "$last_file"

    {
        echo "[$(date '+%F %T')]"
        echo "PACKAGE: $package"
        echo "ERROR CODE: $code"
        echo "LOG: $line"
        echo "-------------------------"
    } >> "$ERROR_LOG"

    echo
    echo -e "${RED}[ERROR DETECTED]${RESET}"
    echo "Package: $package"
    echo "Code: $code"

    if requires_manual "$line" "$code"; then
        echo -e "${YELLOW}[MANUAL CHECK REQUIRED]${RESET}"
        rmdir "$lock"
        return
    fi

    open_rbx "$package"

    echo "[WAIT] 20 seconds"
    sleep 20

    if package_running "$package"; then
        echo -e "${GREEN}[PROCESS RUNNING] $package${RESET}"
    else
        echo -e "${RED}[PROCESS NOT FOUND] $package${RESET}"
    fi

    rmdir "$lock"
}

# -----------------------------
# Monitor all Logcat processes
# -----------------------------

monitor_logcat() {
    echo "[LOGCAT MONITOR STARTED]"

    su -c 'logcat -v threadtime' 2>/dev/null |
    while IFS= read -r raw; do

        read -r date time pid tid priority tag message <<< "$raw"

        line="$raw"

        if ! is_error "$line"; then
            continue
        fi

        package=$(identify_package "$line" "$pid")

        [ -z "$package" ] && continue

        echo -e "${RED}[LOG ERROR]${RESET} $package"

        recover_package "$package" "$line" &

    done
}

# -----------------------------
# Monitor all package processes
# -----------------------------

monitor_processes() {
    local missing=()
    local package
    local count

    for package in $PACKAGES; do
        missing+=("$package:0")
    done

    while true; do

        local updated=()

        for item in "${missing[@]}"; do

            package="${item%:*}"
            count="${item##*:}"

            if package_running "$package"; then

                updated+=("$package:0")

                echo -e "${GREEN}[PROCESS RUNNING]${RESET} $package"

            else

                count=$((count + 1))

                echo -e "${YELLOW}[PROCESS MISSING]${RESET} $package ($count/3)"

                if (( count >= 3 )); then

                    echo "[PROCESS LOST] $package"

                    recover_package \
                        "$package" \
                        "Process missing / application stopped" &

                    count=0

                fi

                updated+=("$package:$count")

            fi

        done

        missing=("${updated[@]}")

        sleep 5

    done
}

# -----------------------------
# Stop monitors
# -----------------------------

stop_monitors() {
    echo
    echo "[STOPPING MONITORS]"

    [ -n "$MONITOR_PID" ] &&
        kill "$MONITOR_PID" 2>/dev/null

    jobs -pr | xargs -r kill 2>/dev/null

    rm -rf "$LOCK_DIR"/*

    echo "Monitor stopped."
}

# -----------------------------
# Main menu
# -----------------------------

while true; do

    clear

    echo -e "${CYAN}+------------------------------+${RESET}"
    echo -e "${CYAN}|          A R I W A A         |${RESET}"
    echo -e "${CYAN}+------------------------------+${RESET}"
    echo
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

            echo
            echo "Packages detected:"

            while IFS= read -r package; do
                [ -z "$package" ] && continue

                echo " - $package"
                open_rbx "$package"
                sleep 10

            done <<< "$PACKAGES"

            echo
            echo -e "${GREEN}[MULTI MONITOR STARTED]${RESET}"

            # Start Logcat monitor
            monitor_logcat &
            LOGCAT_PID=$!

            # Start process monitor
            monitor_processes &
            PROCESS_PID=$!

            MONITOR_PID="$LOGCAT_PID $PROCESS_PID"

            trap 'stop_monitors; exit 0' INT TERM

            echo "Monitoring all packages."
            echo "Press CTRL+C to stop."

            wait

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
