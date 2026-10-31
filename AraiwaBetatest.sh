
#!/data/data/com.termux/files/usr/bin/bash

# ==========================================
# ARIWAA BETA
# ==========================================

clear

AUTO="/storage/emulated/0/Delta/Autoexecute"
CONFIG="$HOME/.rejoin_link"

MAX_FAIL=10
CHECK_INTERVAL=5

CYAN='\033[1;36m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
GREEN='\033[1;32m'
RESET='\033[0m'

GAME_URL=""

# ==========================================
# LOAD CONFIG
# ==========================================

load_config() {
    GAME_URL=""

    if [ -f "$CONFIG" ]; then
        GAME_URL=$(cat "$CONFIG")
    fi
}

# ==========================================
# PACKAGE DETECTION
# ==========================================

get_packages() {
    pm list packages |
        sed 's/package://' |
        grep -Ei 'roblox|delt'
}

# ==========================================
# PROCESS DETECTION
# ==========================================

is_running() {
    local package="$1"

    /system/bin/pidof "$package" >/dev/null 2>&1
}

# ==========================================
# OPEN PACKAGE
# ==========================================

open_package() {
    local package="$1"

    echo -e "${GREEN}[OPEN] $package${RESET}"

    if [ -n "$GAME_URL" ]; then
        am start \
            -a android.intent.action.VIEW \
            -d "$GAME_URL" \
            -p "$package"
    else
        monkey -p "$package" 1 >/dev/null 2>&1
    fi
}

# ==========================================
# RESTART PACKAGE
# ==========================================

restart_package() {
    local package="$1"

    echo -e "${RED}[RESTART] $package${RESET}"

    if ! su -c "am force-stop '$package'"; then
        echo -e "${RED}[ERROR] Force-stop failed${RESET}"
        return 1
    fi

    sleep 2

    open_package "$package"

    return 0
}

# ==========================================
# WATCHDOG
# ==========================================

start_watchdog() {

    local packages
    packages=$(get_packages)

    if [ -z "$packages" ]; then
        echo "No Roblox / Delta packages found."
        read -r -p "Press Enter..."
        return
    fi

    load_config

    declare -A FAIL_COUNT

    echo ""
    echo "Starting applications..."

    for package in $packages; do
        FAIL_COUNT["$package"]=0
        open_package "$package"
        sleep 15
    done

    echo ""
    echo "================================"
    echo "       ARIWAA WATCHDOG"
    echo "================================"
    echo "Max failures : $MAX_FAIL"
    echo "Interval     : $CHECK_INTERVAL sec"
    echo "================================"
    echo "Press CTRL+C to stop."
    echo ""

    while true; do

        for package in $packages; do

            if is_running "$package"; then

                FAIL_COUNT["$package"]=0

                echo -e "${GREEN}[ONLINE]${RESET} $package"

            else

                # FIX: Correct counter calculation
                local count="${FAIL_COUNT[$package]:-0}"

                count=$((count + 1))

                FAIL_COUNT["$package"]="$count"

                echo -e "${YELLOW}[FAILED]${RESET} $package : $count/$MAX_FAIL"

                if (( count >= MAX_FAIL )); then

                    echo -e "${RED}[LIMIT REACHED] $package${RESET}"

                    if restart_package "$package"; then
                        FAIL_COUNT["$package"]=0
                    fi

                    sleep 10

                fi

            fi

        done

        sleep "$CHECK_INTERVAL"

    done
}

# ==========================================
# SET GAME LINK
# ==========================================

set_game_link() {

    local game
    local url

    read -r -p "Enter Game ID or Link: " game

    if [[ "$game" =~ ^[0-9]+$ ]]; then

        url="roblox://experiences/start?placeId=$game"

    elif [[ "$game" == http://* || "$game" == https://* ]]; then

        url="$game"

    else

        echo -e "${RED}Invalid Game ID or Link.${RESET}"
        read -r -p "Press Enter..."
        return
    fi

    echo "$url" > "$CONFIG"

    echo -e "${GREEN}Game Link Saved!${RESET}"

    read -r -p "Press Enter..."
}

# ==========================================
# CREATE LUA API
# ==========================================

create_api() {

    if ! mkdir -p "$AUTO"; then
        echo "Cannot access Autoexecute directory."
        read -r -p "Press Enter..."
        return
    fi

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

    echo -e "${GREEN}Created: $AUTO/api.lua${RESET}"

    read -r -p "Press Enter..."
}

# ==========================================
# CHECK PACKAGE STATUS
# ==========================================

check_packages() {

    local packages
    packages=$(get_packages)

    echo ""
    echo "PACKAGE STATUS"
    echo "----------------------------"

    for package in $packages; do

        if is_running "$package"; then
            echo -e "${GREEN}[ONLINE]${RESET} $package"
        else
            echo -e "${RED}[OFFLINE]${RESET} $package"
        fi

    done

    echo ""
    read -r -p "Press Enter..."
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
    line "       A r i w a a"
    line ""
    border
    line ""
    line " [1] Open Roblox + Watchdog"
    line " [2] Set Game Link"
    line " [3] Setup Executor"
    line " [4] Check Package Status"
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
            set_game_link
            ;;

        3)
            create_api
            ;;

        4)
            check_packages
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
