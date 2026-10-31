
#!/data/data/com.termux/files/usr/bin/bash

AUTO="/storage/emulated/0/Delta/Autoexecute"
CONFIG="$HOME/.rejoin_link"
STATUS_DIR="$HOME/rejoin_status"

CYAN='\033[1;36m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
GREEN='\033[1;32m'
RESET='\033[0m'

mkdir -p "$STATUS_DIR"

# ตรวจสอบ Root
check_root() {
    if ! su -c id 2>/dev/null | grep -q 'uid=0'; then
        echo -e "${RED}Root permission unavailable!${RESET}"
        return 1
    fi
    return 0
}

# ค้นหา Package ID
get_packages() {
    pm list packages |
        grep -Ei 'roblox|delt' |
        sed 's/package://' |
        sort -u
}

# ตรวจสอบสถานะแยกตาม Package
check_game() {
    local package="$1"
    local file="$STATUS_DIR/$package.txt"

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

# แสดงสถานะทั้งหมด
show_status() {
    local packages="$1"

    echo "========== PACKAGE STATUS =========="

    while IFS= read -r package; do
        [ -z "$package" ] && continue

        status=$(check_game "$package")

        if [ "$status" = "IN_GAME" ]; then
            echo -e "$package : ${GREEN}$status${RESET}"
        else
            echo -e "$package : ${RED}$status${RESET}"
        fi
    done <<< "$packages"

    echo "===================================="
}

# เปิดแอปทีละตัว
open_one() {
    local package="$1"
    local url="$2"

    echo
    echo "Package: $package"

    echo "Stopping app..."

    su -c "am force-stop $package"

    sleep 2

    echo "Opening app..."

    if [[ "$package" == *roblox* ]] && [ -n "$url" ]; then
        su -c "am start -a android.intent.action.VIEW -d '$url' -p '$package'"
    else
        su -c "monkey -p $package 1"
    fi

    sleep 20
}

# ตรวจสอบทีละ Package
monitor_packages() {
    local packages="$1"
    local url="$2"

    while IFS= read -r package; do
        [ -z "$package" ] && continue

        clear
        echo "===== CURRENT PACKAGE ====="
        echo "$package"

        open_one "$package" "$url"

        local failures=0

        while true; do
            clear
            echo "===== PACKAGE MONITOR ====="
            echo "Package: $package"

            status=$(check_game "$package")
            echo "Status: $status"

            if [ "$status" = "IN_GAME" ]; then
                failures=0
            else
                failures=$((failures + 1))
                echo "Checking: $failures/10"
            fi

            show_status "$packages"

            if [ "$failures" -ge 10 ]; then
                echo
                echo "Status timeout."
                echo "This package needs attention."
                echo "Stopping automatic retry for safety."
                break
            fi

            echo
            echo "Press CTRL+C to stop"
            sleep 3
        done

    done <<< "$packages"
}

# สร้าง API ตัวอย่าง
create_api() {
    mkdir -p "$AUTO"

    cat > "$AUTO/api.lua" <<'LUA'
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- ต้องกำหนดไฟล์ให้ตรงกับ Package ID
-- ห้ามใช้ไฟล์สถานะร่วมกันระหว่างหลายแอป

local STATUS_FILE = "status.txt"

while true do
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")

    local status = "NOT_IN_GAME"

    if humanoid and root and humanoid.Health > 0 then
        status = "IN_GAME"
    end

    writefile(
        STATUS_FILE,
        status .. "\n" .. os.time()
    )

    task.wait(3)
end
LUA

    echo "Created: $AUTO/api.lua"
    echo "Configure separate STATUS_FILE paths for each executor."
}

# เมนูหลัก
while true; do
    clear

    echo -e "${CYAN}"
    echo "================================"
    echo "          A R I W A A"
    echo "================================"
    echo -e "${RESET}"

    echo "[1] Open Roblox Sequential"
    echo "[2] Set Game Link"
    echo "[3] Setup Executor"
    echo "[4] Check All Status"
    echo "[5] Exit"

    echo
    read -r -p "Select: " choice

    case "$choice" in
        1)
            if ! check_root; then
                read -r -p "Press Enter..."
                continue
            fi

            packages=$(get_packages)

            if [ -z "$packages" ]; then
                echo "No packages found."
                read -r -p "Press Enter..."
                continue
            fi

            url=""
            [ -f "$CONFIG" ] && url=$(cat "$CONFIG")

            monitor_packages "$packages" "$url"
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
            echo "Game Link saved."
            read -r -p "Press Enter..."
            ;;

        3)
            create_api
            read -r -p "Press Enter..."
            ;;

        4)
            packages=$(get_packages)
            show_status "$packages"
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
