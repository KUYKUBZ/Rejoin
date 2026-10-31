
#!/data/data/com.termux/files/usr/bin/bash

AUTO="/storage/emulated/0/Delta/Autoexecute"
CONFIG="$HOME/.rejoin_link"
STATUS_DIR="$HOME/game_status"

mkdir -p "$STATUS_DIR"

CYAN='\033[1;36m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
RESET='\033[0m'

get_packages() {
    pm list packages |
        grep -Ei 'roblox|delt' |
        sed 's/package://'
}

status_file() {
    echo "$STATUS_DIR/$1.txt"
}

check_game() {
    local file
    file=$(status_file "$1")

    if [ ! -f "$file" ]; then
        echo "NOT_IN_GAME"
        return
    fi

    local status timestamp now
    status=$(head -n 1 "$file")
    timestamp=$(tail -n 1 "$file")
    now=$(date +%s)

    if [[ "$status" == "IN_GAME" ]] &&
       [[ "$timestamp" =~ ^[0-9]+$ ]] &&
       (( now - timestamp >= 0 && now - timestamp <= 10 )); then
        echo "IN_GAME"
    else
        echo "NOT_IN_GAME"
    fi
}

open_app() {
    local package="$1"
    local url="$2"

    echo "Opening $package"

    if [ -n "$url" ]; then
        am start -a android.intent.action.VIEW \
            -d "$url" -p "$package"
    else
        am start -a android.intent.action.MAIN \
            -c android.intent.category.LAUNCHER \
            -p "$package"
    fi
}

create_api() {
    mkdir -p "$AUTO"

    cat > "$AUTO/api.lua" <<'LUA'
local Players = game:GetService("Players")
local player = Players.LocalPlayer

while true do
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")

    local status = "NOT_IN_GAME"

    if humanoid and root and humanoid.Health > 0 then
        status = "IN_GAME"
    end

    writefile("status.txt", status .. "\n" .. os.time())
    task.wait(3)
end
LUA

    echo "Created: $AUTO/api.lua"
}

while true; do
    clear
    echo -e "${CYAN}===== ARIWAA =====${RESET}"
    echo "[1] Open Roblox apps"
    echo "[2] Set Game Link"
    echo "[3] Setup Executor"
    echo "[4] Check each app"
    echo "[5] Monitor each app"
    echo "[6] Exit"

    read -r -p "Select: " choice

    case "$choice" in
        1)
            packages=$(get_packages)
            url=""
            [ -f "$CONFIG" ] && url=$(cat "$CONFIG")

            if [ -z "$packages" ]; then
                echo "No apps found."
            else
                for package in $packages; do
                    open_app "$package" "$url"
                    sleep 20
                done
            fi
            read -r -p "Press Enter..."
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
            echo "Link saved."
            read -r -p "Press Enter..."
            ;;

        3)
            create_api
            read -r -p "Press Enter..."
            ;;

        4)
            packages=$(get_packages)
            clear
            echo "===== EACH APP STATUS ====="

            for package in $packages; do
                echo
                echo "$package"
                check_game "$package"
            done

            read -r -p "Press Enter..."
            ;;

        5)
            packages=$(get_packages)
            url=""
            [ -f "$CONFIG" ] && url=$(cat "$CONFIG")

            declare -A failures
            for package in $packages; do
                failures["$package"]=0
            done

            while true; do
                clear
                echo "===== MONITOR EACH APP ====="

                for package in $packages; do
                    status=$(check_game "$package")
                    echo
                    echo "$package : $status"

                    if [ "$status" = "IN_GAME" ]; then
                        failures["$package"]=0
                    else
                        failures["$package"]=$((failures["$package"] + 1))
                        echo "Checking ${failures[$package]}/10"

                        if [ "${failures[$package]}" -ge 10 ]; then
                            echo "Opening $package again..."
                            open_app "$package" "$url"
                            failures["$package"]=0
                        fi
                    fi
                done

                echo
                echo "Press CTRL+C to stop"
                sleep 3
            done
            ;;

        6)
            exit 0
            ;;

        *)
            echo "Invalid option."
            sleep 1
            ;;
    esac
done
