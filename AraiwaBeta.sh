
#!/data/data/com.termux/files/usr/bin/bash

AUTO="/storage/emulated/0/Delta/Autoexecute"
CONFIG="$HOME/.rejoin_link"
STATUS="$HOME/status.txt"

get_packages() {
    pm list packages | grep -Ei 'roblox|delt' | sed 's/package://'
}

has_task() {
    /system/bin/dumpsys activity recents |
        grep -F "A=$1 " >/dev/null
}

check_game() {
    if [ ! -f "$STATUS" ]; then
        echo "NOT_IN_GAME"
        return
    fi

    local status timestamp now

    status=$(head -n 1 "$STATUS")
    timestamp=$(tail -n 1 "$STATUS")
    now=$(date +%s)

    if [[ "$status" == "IN_GAME" ]] &&
       [[ "$timestamp" =~ ^[0-9]+$ ]] &&
       (( now - timestamp >= 0 && now - timestamp <= 10 )); then
        echo "IN_GAME"
    else
        echo "NOT_IN_GAME"
    fi
}

create_api() {
    mkdir -p "$AUTO"

    cat > "$AUTO/api.lua" <<'LUA'
local Players = game:GetService("Players")
local Player = Players.LocalPlayer

local RunService = game:GetService("RunService")

RunService.Heartbeat:Connect(function()
    local Character = Player.Character
    local Humanoid = Character and Character:FindFirstChild("Humanoid")
    local hrp = Character and Character:FindFirstChild("HumanoidRootPart")

    local status = "NOT_IN_GAME"

    if Humanoid and hrp and Humanoid.Health > 0 then
        status = "IN_GAME"
    end

    writefile(Player.Name .."_status.txt", status .. "\n" .. Player.Name .. "\n" .. os.time())

    task.wait(3)
end)
LUA

    echo "Created: $AUTO/api.lua"
}

# Force stop package
force_stop() {
    package="$1"

    echo -e "${YELLOW}[FORCE STOP]${RESET} $package"

    if su -c "am force-stop '$package'"; then
        echo -e "${GREEN}[STOP OK]${RESET} $package"
        return 0
    else
        echo -e "${RED}[STOP ERROR]${RESET} $package"
        return 1
    fi
}

# Open package
open_package() {
    package="$1"
    url="$2"

    force_stop "$package"

    sleep 2

    echo "[OPENING] $package"

    if [ -n "$url" ]; then
        am start -a android.intent.action.VIEW \
            -d "$url" -p "$package"
    else
        am start -a android.intent.action.MAIN \
            -c android.intent.category.LAUNCHER \
            -p "$package"
    fi

    sleep 10
}

while true; do
    clear

    CYAN='\033[1;36m'
    WHITE='\033[1;37m'
    YELLOW='\033[1;33m'
    RESET='\033[0m'

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
    line "       A r i w a a"
    border
    line ""
    line " [1] Open Roblox"
    line " [2] Set Game Link"
    line " [3] Setup Executor"
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
            [ -f "$CONFIG" ] && url=$(cat "$CONFIG")

            for package in $packages; do
                if [ -n "$url" ]; then
                    open_package "$url" "$package"
                fi
                sleep 20
            done

            while true; do
                clear
                check_game
                sleep 3
            done
            ;;

        2)
            read -r -p "Enter Game ID or Link: " game

            if [[ "$game" =~ ^[0-9]+$ ]]; then
                url="roblox://experiences/start?placeId=$game"
            elif [[ "$game" == * ]]; then
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
            exit 0
            ;;

        *)
            echo "Invalid option."
            sleep 1
            ;;
    esac
done
