
#!/data/data/com.termux/files/usr/bin/bash

clear

AUTO="/storage/emulated/0/Delta/Autoexecute"
CONFIG="$HOME/.rejoin_link"
STATUS_DIR="$HOME/Ariwaa/status"

MAX_FAIL=10
CHECK_INTERVAL=5

mkdir -p "$STATUS_DIR"

CYAN='\033[1;36m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
GREEN='\033[1;32m'
RESET='\033[0m'

# ==========================================
# PACKAGE DETECTION
# ==========================================

get_packages() {
    pm list packages |
        grep -Ei 'roblox|delt' |
        sed 's/package://'
}

# ==========================================
# TASK DETECTION
# ==========================================

has_task() {
    local package="$1"

    /system/bin/dumpsys activity recents 2>/dev/null |
        grep -F "A=$package " >/dev/null
}

# ==========================================
# RESTART PACKAGE
# ==========================================

restart_package() {
    local package="$1"

    echo -e "${RED}[RESTART] $package${RESET}"

    if su -c "am force-stop '$package'"; then
        sleep 2
    else
        echo "Force-stop failed: $package"
        return 1
    fi

    if [ -n "$url" ]; then
        am start -a android.intent.action.VIEW \
            -d "$url" -p "$package"
    else
        monkey -p "$package" 1
    fi
}

# ==========================================
# GAME STATUS CHECK
# ==========================================

check_game() {
    local player="$1"
    local STATUS="$STATUS_DIR/${player}_status.txt"

    [ -f "$STATUS" ] || return 1

    local status timestamp now

    status=$(head -n 1 "$STATUS")
    timestamp=$(tail -n 1 "$STATUS")
    now=$(date +%s)

    if [[ "$status" == "IN_GAME" ]] &&
       [[ "$timestamp" =~ ^[0-9]+$ ]] &&
       (( now - timestamp >= 0 && now - timestamp <= 10 )); then
        return 0
    fi

    return 1
}

# ==========================================
# CREATE LUA API
# ==========================================

create_api() {
    mkdir -p "$AUTO"

    cat > "$AUTO/api.lua" <<'LUA'
local Players = game:GetService("Players")
local Player = Players.LocalPlayer

local folder = "Ariwaa"

if not isfolder(folder) then
    makefolder(folder)
end

local filename = folder .. "/" ..
    tostring(Player.UserId) .. "_status.txt"

while true do
    local Character = Player.Character
    local Humanoid = Character and
        Character:FindFirstChild("Humanoid")

    local HRP = Character and
        Character:FindFirstChild("HumanoidRootPart")

    local status = "NOT_IN_GAME"

    if Humanoid and HRP and Humanoid.Health > 0 then
        status = "IN_GAME"
    end

    writefile(
        filename,
        status .. "\n" ..
        tostring(Player.UserId) .. "\n" ..
        os.time()
    )

    task.wait(3)
end
LUA

    echo "Created: $AUTO/api.lua"
}

# ==========================================
# WATCHDOG
# ==========================================

start_watchdog() {

    local packages
    packages=$(get_packages)

    if [ -z "$packages" ]; then
        echo "No Roblox apps found."
        read -r -p "Press Enter..."
        return
    fi

    local url=""
    [ -f "$CONFIG" ] && url=$(cat "$CONFIG")

    declare -A FAIL_COUNT

    for package in $packages; do
        FAIL_COUNT["$package"]=0
    done

    echo ""
    echo "Watchdog Started"
    echo "Max failures: $MAX_FAIL"
    echo "Interval: ${CHECK_INTERVAL}s"
    echo "Press CTRL+C to stop."
    echo ""

    while true; do

        for package in $packages; do

            if has_task "$package"; then

                FAIL_COUNT["$package"]=0

                echo -e "${GREEN}[ONLINE]${RESET} $package"

            else

                FAIL_COUNT["$package"]=$(
                    (${FAIL_COUNT["$package"]:-0} + 1)
                )

                echo -e "${YELLOW}[FAILED]${RESET} $package : ${FAIL_COUNT["$package"]}/$MAX_FAIL"

                if (( FAIL_COUNT["$package"] >= MAX_FAIL )); then

                    restart_package "$package"

                    FAIL_COUNT["$package"]=0

                    sleep 10
                fi

            fi

        done

        sleep "$CHECK_INTERVAL"

    done
}

# ==========================================
# MENU
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
    line "       A r i w a a"
    line ""
    border
    line ""
    line " [1] Open Roblox + Watchdog"
    line " [2] Set Game Link"
    line " [3] Setup Executor"
    line " [4] Check Account Status"
    line " [5] Exit"
    line ""
    border

    printf "\n${YELLOW}Select: ${WHITE}"
    read -r choice

    case "$choice" in

        1)
            start_watchdog
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
            create_api
            read -r -p "Press Enter..."
            ;;

        4)
            echo ""

            for file in "$STATUS_DIR"/*_status.txt; do
                [ -f "$file" ] || continue

                player=$(basename "$file" _status.txt)

                if check_game "$player"; then
                    echo "[$player] IN GAME"
                else
                    echo "[$player] NOT IN GAME"
                fi
            done

            read -r -p "Press Enter..."
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
