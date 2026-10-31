
#!/data/data/com.termux/files/usr/bin/bash

clear

AUTO="/storage/emulated/0/Delta/Autoexecute"
API="$AUTO/api.lua"
HEARTBEAT="$AUTO/heartbeat.txt"
CONFIG="$HOME/.rejoin_link"

TIMEOUT=120
CHECK_INTERVAL=5
MAX_AGE=30

CYAN='\033[1;36m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
RESET='\033[0m'

# =================================
# Find Roblox packages
# =================================

get_packages() {
    pm list packages |
        grep -Ei 'roblox|delt' |
        sed 's/package://' |
        sort -u
}

# =================================
# Create Lua API
# =================================

create_api() {

    mkdir -p "$AUTO" || return 1

    cat > "$API" <<'LUA'
-- =================================
-- ARIWAA GAME WATCHDOG API
-- Delta Auto Execute
-- =================================

local HEARTBEAT =
    "/storage/emulated/0/Delta/Autoexecute/heartbeat.txt"

local HttpService = game:GetService("HttpService")

local function log(message)
    print("[ARIWAA API] " .. tostring(message))
end

log("API STARTING")

-- Wait for game loading
if not game:IsLoaded() then
    log("WAITING FOR GAME")

    game.Loaded:Wait()
end

log("GAME LOADED")

-- Wait for player
local Players = game:GetService("Players")
local player = Players.LocalPlayer

while not player do
    task.wait(1)
    player = Players.LocalPlayer
end

log("PLAYER DETECTED")

-- Heartbeat
local function sendHeartbeat()

    local success, err = pcall(function()

        writefile(HEARTBEAT, tostring(os.time()))

    end)

    if not success then
        warn("[ARIWAA API] WRITE ERROR: " .. tostring(err))
    end

    return success
end

-- Initial heartbeat
if not sendHeartbeat() then
    log("HEARTBEAT FAILED")
else
    log("HEARTBEAT STARTED")
end

-- Continuous heartbeat
while true do

    task.wait(5)

    if not sendHeartbeat() then
        warn("[ARIWAA API] HEARTBEAT FAILED")
    end

end
LUA

    if [ -s "$API" ]; then
        echo -e "${GREEN}[SUCCESS] API CREATED${RESET}"
        echo "$API"
        return 0
    fi

    echo -e "${RED}[ERROR] API CREATION FAILED${RESET}"
    return 1
}

# =================================
# Check heartbeat
# =================================

check_heartbeat() {

    [ -f "$HEARTBEAT" ] || return 1

    local beat
    local now
    local age

    beat=$(cat "$HEARTBEAT" 2>/dev/null)

    [[ "$beat" =~ ^[0-9]+$ ]] || return 1

    now=$(date +%s)
    age=$((now - beat))

    (( age >= 0 && age <= MAX_AGE ))
}

# =================================
# Open Roblox
# =================================

open_package() {

    local package="$1"
    local url="$2"

    echo -e "${CYAN}[OPEN] $package${RESET}"

    if [ -n "$url" ]; then

        am start \
            -a android.intent.action.VIEW \
            -d "$url" \
            -p "$package"

    else

        monkey -p "$package" 1

    fi
}

# =================================
# Force Stop
# =================================

stop_package() {

    local package="$1"

    echo -e "${RED}[FORCE STOP] $package${RESET}"

    su -c "am force-stop '$package'"

    sleep 3
}

# =================================
# Wait for API
# =================================

wait_for_api() {

    local elapsed=0

    echo -e "${YELLOW}[WAIT] Waiting for Lua API...${RESET}"

    while [ "$elapsed" -lt "$TIMEOUT" ]; do

        if check_heartbeat; then

            echo
            echo -e "${GREEN}[API RUNNING] Heartbeat detected${RESET}"

            return 0
        fi

        printf "\r${YELLOW}[WAIT] %s/%s seconds${RESET}" \
            "$elapsed" "$TIMEOUT"

        sleep "$CHECK_INTERVAL"

        elapsed=$((elapsed + CHECK_INTERVAL))

    done

    echo
    echo -e "${RED}[TIMEOUT] API NOT DETECTED${RESET}"

    return 1
}

# =================================
# Monitor API
# =================================

monitor_api() {

    while true; do

        sleep "$CHECK_INTERVAL"

        if check_heartbeat; then

            echo -e "${GREEN}[RUNNING] Lua API OK${RESET}"

        else

            echo
            echo -e "${RED}[API STOPPED] Heartbeat lost${RESET}"

            return 1

        fi

    done
}

# =================================
# Auto Rejoin
# =================================

auto_rejoin() {

    local package="$1"
    local url="$2"
    local attempt=0

    while true; do

        attempt=$((attempt + 1))

        echo
        echo -e "${CYAN}==============================${RESET}"
        echo "[ATTEMPT $attempt]"
        echo "[PACKAGE] $package"
        echo -e "${CYAN}==============================${RESET}"

        # Remove old heartbeat
        rm -f "$HEARTBEAT"

        # Open Roblox
        open_package "$package" "$url"

        # Wait for Lua API
        if wait_for_api; then

            echo -e "${GREEN}[API CONNECTED]${RESET}"

            # Monitor heartbeat
            if monitor_api; then
                continue
            fi

        fi

        # API missing or stopped
        echo
        echo -e "${RED}[RESTART] Restarting Roblox${RESET}"

        stop_package "$package"

        sleep 2

    done
}

# =================================
# Main Menu
# =================================

while true; do

    clear

    echo -e "${CYAN}+--------------------------------+${RESET}"
    echo -e "${CYAN}|${WHITE}          A R I W A A           ${CYAN}|${RESET}"
    echo -e "${CYAN}|                                |${RESET}"
    echo -e "${CYAN}|${WHITE} [1] Open Roblox                ${CYAN}|${RESET}"
    echo -e "${CYAN}|${WHITE} [2] Set Game Link              ${CYAN}|${RESET}"
    echo -e "${CYAN}|${WHITE} [3] Exit                       ${CYAN}|${RESET}"
    echo -e "${CYAN}|${GREEN} [4] Create GameChecker API     ${CYAN}|${RESET}"
    echo -e "${CYAN}+--------------------------------+${RESET}"

    echo
    read -r -p "Select: " choice

    case "$choice" in

        1)

            if [ ! -f "$API" ]; then

                echo "[API] Creating API..."
                create_api || {
                    read -r -p "Press Enter..."
                    continue
                }

            fi

            packages=$(get_packages)

            if [ -z "$packages" ]; then

                echo -e "${RED}No Roblox packages found${RESET}"
                read -r -p "Press Enter..."
                continue

            fi

            package_list=()

            while IFS= read -r package; do
                [ -n "$package" ] && package_list+=("$package")
            done <<< "$packages"

            echo
            echo "Available packages:"

            for i in "${!package_list[@]}"; do
                echo "[$((i + 1))] ${package_list[$i]}"
            done

            echo
            read -r -p "Select package number: " number

            if ! [[ "$number" =~ ^[0-9]+$ ]] ||
                [ "$number" -lt 1 ] ||
                [ "$number" -gt "${#package_list[@]}" ]; then

                echo -e "${RED}Invalid package${RESET}"
                sleep 2
                continue

            fi

            selected="${package_list[$((number - 1))]}"

            url=""

            if [ -f "$CONFIG" ]; then
                url=$(cat "$CONFIG")
            fi

            auto_rejoin "$selected" "$url"

            ;;

        2)

            read -r -p "Enter Game ID or Link: " game

            if [[ "$game" =~ ^[0-9]+$ ]]; then

                url="roblox://experiences/start?placeId=$game"

            elif [[ "$game" == http://* ||
                    "$game" == https://* ]]; then

                url="$game"

            else

                echo -e "${RED}Invalid Game ID or Link${RESET}"
                read -r -p "Press Enter..."
                continue

            fi

            echo "$url" > "$CONFIG"

            echo -e "${GREEN}[SAVED] Game Link saved${RESET}"

            read -r -p "Press Enter..."

            ;;

        3)

            exit 0

            ;;

        4)

            create_api

            read -r -p "Press Enter to return..."

            ;;

        *)

            echo "Invalid option"
            sleep 1

            ;;

    esac

done
