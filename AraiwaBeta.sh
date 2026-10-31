
#!/data/data/com.termux/files/usr/bin/bash

clear

AUTO="/storage/emulated/0/Delta/Autoexecute"
CONFIG="$HOME/.rejoin_link"

CYAN='\033[1;36m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
RESET='\033[0m'

# Find Roblox packages
get_packages() {
    pm list packages |
        grep -Ei 'roblox|delt' |
        sed 's/package://' |
        sort -u
}

# Check process
is_running() {
    pidof "$1" >/dev/null 2>&1
}

# Open Roblox
open_package() {
    local package="$1"
    local url="$2"

    echo -e "${CYAN}[OPEN] $package${RESET}"

    if [ -n "$url" ]; then
        am start -a android.intent.action.VIEW \
            -d "$url" -p "$package"
    else
        monkey -p "$package" 1
    fi
}

# Force stop
stop_package() {
    local package="$1"

    echo -e "${RED}[STOP] $package${RESET}"

    su -c "am force-stop '$package'"

    sleep 3
}

# Wait for process
wait_for_game() {
    local package="$1"
    local timeout=120
    local elapsed=0

    echo -e "${YELLOW}[WAIT] Checking process...${RESET}"

    while [ "$elapsed" -lt "$timeout" ]; do

        if is_running "$package"; then
            echo -e "${GREEN}[PROCESS DETECTED]${RESET}"
            return 0
        fi

        sleep 2
        elapsed=$((elapsed + 2))

        printf "\r[WAIT] %s/%s seconds" "$elapsed" "$timeout"
    done

    echo
    return 1
}

# Auto Rejoin
auto_rejoin() {
    local package="$1"
    local url="$2"
    local attempt=0

    while true; do
        attempt=$((attempt + 1))

        echo
        echo "[ATTEMPT $attempt]"
        echo "[PACKAGE] $package"

        open_package "$package" "$url"

        if wait_for_game "$package"; then
            echo -e "${GREEN}[APP RUNNING]${RESET}"
            echo "Lua checker will verify character readiness."
            return 0
        fi

        echo -e "${RED}[NOT RUNNING] Restarting...${RESET}"

        stop_package "$package"
        sleep 2
    done
}

# Create API file
create_api() {

    echo -e "${YELLOW}[CREATE] GameChecker API${RESET}"

    mkdir -p "$AUTO"

    if [ ! -d "$AUTO" ]; then
        echo -e "${RED}[ERROR] Cannot create Autoexecute folder${RESET}"
        return 1
    fi

    cat > "$AUTO/api.lua" <<'LUA'
-- =================================
-- Roblox Game Checker API
-- Delta Auto Execute
-- =================================

local Players = game:GetService("Players")

local function log(message)
    print("[GAME API] " .. tostring(message))
end

log("Starting API...")

-- Wait for game loading
if not game:IsLoaded() then
    log("Waiting for game loading...")
    game.Loaded:Wait()
end

log("Game loaded")

-- Wait for player
local player = Players.LocalPlayer

while not player do
    task.wait(1)
    player = Players.LocalPlayer
end

log("Player detected: " .. player.Name)

-- Wait for character
local character = player.Character

if not character then
    log("Waiting for character...")
    character = player.CharacterAdded:Wait()
end

-- Check character readiness
local function checkCharacter(char)

    log("Checking character...")

    local humanoid = char:WaitForChild("Humanoid", 120)
    local root = char:WaitForChild("HumanoidRootPart", 120)

    if humanoid and root then
        log("================================")
        log("IN GAME")
        log("Player: " .. player.Name)
        log("Place ID: " .. game.PlaceId)
        log("Job ID: " .. game.JobId)
        log("Character Ready")
        log("================================")
        return true
    end

    log("CHARACTER NOT READY")
    return false
end

checkCharacter(character)

-- Detect respawn
player.CharacterAdded:Connect(function(newCharacter)
    log("Character respawned")
    checkCharacter(newCharacter)
end)

log("Game Checker API running")
LUA

    if [ -s "$AUTO/api.lua" ]; then
        echo
        echo -e "${GREEN}[SUCCESS] API created!${RESET}"
        echo "File: $AUTO/api.lua"
    else
        echo -e "${RED}[ERROR] File creation failed${RESET}"
        return 1
    fi

    read -r -p "Press Enter to return..."
}

# Main menu
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
    printf "${YELLOW}Select: ${WHITE}"
    read -r choice

    case "$choice" in

        1)
            packages=$(get_packages)

            if [ -z "$packages" ]; then
                echo -e "${RED}No Roblox apps found.${RESET}"
                read -r -p "Press Enter..."
                continue
            fi

            url=""

            if [ -f "$CONFIG" ]; then
                url=$(cat "$CONFIG")
            fi

            echo
            echo "Found packages:"
            echo "$packages"

            for package in $packages; do
                auto_rejoin "$package" "$url"
            done

            read -r -p "Press Enter to return..."
            ;;

        2)
            read -r -p "Enter Game ID or Link: " game

            if [[ "$game" =~ ^[0-9]+$ ]]; then
                url="roblox://experiences/start?placeId=$game"

            elif [[ "$game" == http://* ||
                    "$game" == https://* ]]; then
                url="$game"

            else
                echo -e "${RED}Invalid Game ID or Link.${RESET}"
                read -r -p "Press Enter..."
                continue
            fi

            echo "$url" > "$CONFIG"

            echo -e "${GREEN}Game Link saved!${RESET}"
            read -r -p "Press Enter..."
            ;;

        3)
            exit 0
            ;;

        4)
            create_api
            ;;

        *)
            echo -e "${RED}Invalid option.${RESET}"
            sleep 1
            ;;

    esac

done
