
#!/data/data/com.termux/files/usr/bin/bash

CONFIG="$HOME/.rejoin_link"
AUTOEXE="/storage/emulated/0/Delta/Autoexecute"
WORKSPACE="/storage/emulated/0/Delta/Workspace"

mkdir -p "$AUTOEXE" "$WORKSPACE"

CYAN='\033[1;36m'
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
RESET='\033[0m'

get_packages() {
    pm list packages |
        grep -Ei 'roblox|delt' |
        sed 's/package://'
}

has_task() {
    /system/bin/dumpsys activity recents |
        grep -F "A=$1 " >/dev/null
}

check_api() {
    local package="$1"
    local file="$WORKSPACE/$package.txt"
    local timestamp
    local now
    local diff

    if [ ! -f "$file" ]; then
        echo "WAITING"
        return 2
    fi

    timestamp=$(cat "$file" 2>/dev/null)

    if [[ ! "$timestamp" =~ ^[0-9]+$ ]]; then
        echo "ERROR"
        return 3
    fi

    now=$(date +%s)
    diff=$((now - timestamp))

    if (( diff >= 0 && diff <= 15 )); then
        echo "ONLINE"
        return 0
    fi

    echo "OFFLINE"
    return 1
}

open_roblox() {
    local package="$1"
    local url="$2"

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
    cat > "$AUTOEXE/api.txt" <<'LUA'
-- API heartbeat template
-- ต้องมีตัวกลางที่เชื่อถือได้สำหรับระบุ Package
-- ก่อนนำ Heartbeat ไปจับคู่กับ Android Package

local Players = game:GetService("Players")

local player = Players.LocalPlayer

while not player do
    task.wait(1)
    player = Players.LocalPlayer
end

print("[ARIWAA] Player detected: " .. player.Name)
print("[ARIWAA] API initialized")
LUA

    echo "API CREATED"
}

monitor() {
    local packages="$1"
    local package
    local status

    while true; do
        clear

        echo "========== ARIWAA MONITOR =========="
        echo ""

        for package in $packages; do
            echo "PACKAGE: $package"

            if has_task "$package"; then
                echo -e "${GREEN}TASK: FOUND${RESET}"
            else
                echo -e "${RED}TASK: NOT FOUND${RESET}"
            fi

            status=$(check_api "$package")

            case "$status" in
                ONLINE)
                    echo -e "${GREEN}API: ONLINE${RESET}"
                    ;;
                OFFLINE)
                    echo -e "${RED}API: OFFLINE${RESET}"
                    ;;
                WAITING)
                    echo -e "${YELLOW}API: WAITING${RESET}"
                    ;;
                *)
                    echo -e "${RED}API: ERROR${RESET}"
                    ;;
            esac

            echo ""
        done

        echo "Next check: 5 seconds"
        sleep 5
    done
}

while true; do
    clear

    echo "========== ARIWAA =========="
    echo ""
    echo "[1] Open Roblox"
    echo "[2] Set Game Link"
    echo "[3] Setup API"
    echo "[4] Monitor"
    echo "[5] Exit"
    echo ""

    read -r -p "Select: " choice

    case "$choice" in
        1)
            packages=$(get_packages)

            if [ -z "$packages" ]; then
                echo "No Roblox packages found."
                read -r -p "Enter..."
                continue
            fi

            url=""
            [ -f "$CONFIG" ] && url=$(cat "$CONFIG")

            for package in $packages; do
                echo "Opening $package"
                open_roblox "$package" "$url"
                sleep 20
            done

            read -r -p "Press Enter..."
            ;;

        2)
            read -r -p "Enter Game ID or Link: " game

            if [[ "$game" =~ ^[0-9]+$ ]]; then
                url="roblox://experiences/start?placeId=$game"
            elif [[ "$game" == http://* || "$game" == https://* ]]; then
                url="$game"
            else
                echo "Invalid Link"
                sleep 2
                continue
            fi

            echo "$url" > "$CONFIG"
            echo "Link saved"
            sleep 2
            ;;

        3)
            create_api
            read -r -p "Press Enter..."
            ;;

        4)
            packages=$(get_packages)
            monitor "$packages"
            ;;

        5)
            exit 0
            ;;

        *)
            echo "Invalid option"
            sleep 1
            ;;
    esac
done
