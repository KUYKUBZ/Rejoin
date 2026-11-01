
#!/data/data/com.termux/files/usr/bin/bash

CONFIG="$HOME/.rejoin_link"
MAP="$HOME/.ariwaa_map"
AUTOEXE="/storage/emulated/0/Delta/Autoexecute"
WORKSPACE="/storage/emulated/0/Delta/Workspace/Ariwaa"
LOG="$HOME/ariwaa_errors.log"
COOLDOWN="$HOME/.ariwaa_cooldown"

mkdir -p "$AUTOEXE" "$WORKSPACE"
touch "$LOG" "$COOLDOWN"

CYAN='\033[1;36m'
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

get_packages() {
    pm list packages |
        sed 's/package://' |
        grep -i 'roblox' |
        sort -u
}

valid_package() {
    [[ "$1" =~ ^[a-zA-Z0-9._]+$ ]]
}

open_package() {
    local package="$1"
    local url=""

    [ -f "$CONFIG" ] && url=$(cat "$CONFIG")

    if [ -n "$url" ]; then
        am start -a android.intent.action.VIEW \
            -d "$url" -p "$package"
    else
        monkey -p "$package" 1
    fi
}

restart_package() {
    local package="$1"

    valid_package "$package" || return 1

    echo -e "${YELLOW}[RESTART] $package${RESET}"

    if ! su -c "am force-stop $package"; then
        echo "$(date) FORCE STOP FAILED: $package" >> "$LOG"
        return 1
    fi

    sleep 3
    open_package "$package"
}

get_last_restart() {
    awk -F'|' -v p="$1" '$1==p {v=$2} END {print v+0}' "$COOLDOWN"
}

set_last_restart() {
    local package="$1"
    local now="$2"

    grep -v "^${package}|" "$COOLDOWN" > "$COOLDOWN.tmp" 2>/dev/null
    echo "$package|$now" >> "$COOLDOWN.tmp"
    mv "$COOLDOWN.tmp" "$COOLDOWN"
}

setup_mapping() {
    local packages
    packages=$(get_packages)

    if [ -z "$packages" ]; then
        echo "ไม่พบ Roblox Package"
        return 1
    fi

    echo "=== Roblox Packages ==="
    echo "$packages"
    echo
    echo "จับคู่ Package กับ User ID ที่ล็อกอินอยู่จริง"
    echo

    : > "$MAP"

    while IFS= read -r package; do
        [ -z "$package" ] && continue

        read -r -p "User ID ของ $package: " uid

        if [[ ! "$uid" =~ ^[0-9]+$ ]]; then
            echo "User ID ไม่ถูกต้อง"
            rm -f "$MAP"
            return 1
        fi

        echo "$package|$uid" >> "$MAP"
    done <<< "$packages"

    echo "บันทึกการจับคู่แล้ว"
}

create_api() {
    cat > "$AUTOEXE/api.txt" <<'LUA'
local Players = game:GetService("Players")

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local player = Players.LocalPlayer

while not player do
    task.wait(1)
    player = Players.LocalPlayer
end

local folder = "Ariwaa"

local ok, err = pcall(function()
    if not isfolder(folder) then
        makefolder(folder)
    end
end)

local file = folder .. "/" .. tostring(player.UserId) .. "_Status.txt"

print("[ARIWAA] STARTED: " .. player.UserId)

while true do
    local content =
        "IN GAME\n" ..
        tostring(player.UserId) .. "\n" ..
        tostring(os.time())

    local success, writeErr = pcall(function()
        writefile(file, content)
    end)

    if not success then
        warn("[ARIWAA] WRITE ERROR: " .. tostring(writeErr))
    end

    task.wait(5)
end
LUA

    echo "สร้าง API : $AUTOEXE/api.txt"
}

check_api() {
    local package="$1"
    local uid="$2"
    local file="$WORKSPACE/${uid}_Status.txt"

    if [ ! -f "$file" ]; then
        echo "MISSING"
        return 1
    fi

    local status file_uid timestamp now diff

    status=$(sed -n '1p' "$file" | tr -d '\r')
    file_uid=$(sed -n '2p' "$file" | tr -d '\r')
    timestamp=$(sed -n '3p' "$file" | tr -d '\r')

    if [[ "$file_uid" != "$uid" ||
          ! "$timestamp" =~ ^[0-9]+$ ]]; then
        echo "ERROR"
        return 1
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

monitor() {
    local start_time
    start_time=$(date +%s)

    echo "ARIWAA AUTO MONITOR STARTED"

    while true; do
        clear
        echo "========== ARIWAA AUTO =========="
        echo "เวลา: $(date)"
        echo

        while IFS='|' read -r package uid; do
            [ -z "$package" ] && continue
            [ -z "$uid" ] && continue

            result=$(check_api "$package" "$uid")
            now=$(date +%s)
            elapsed=$((now - start_time))
            last=$(get_last_restart "$package")
            cooldown=$((now - last))

            if [ "$result" = "ONLINE" ]; then
                echo -e "${GREEN}[API ONLINE]${RESET} $package / $uid"
                continue
            fi

            echo -e "${RED}[API $result]${RESET} $package / $uid"

            # ให้เวลา Autoexecute ทำงานหลังเปิดเกมครั้งแรก
            if (( elapsed < 90 )); then
                echo "รอ API เริ่มทำงาน..."
                continue
            fi

            # ป้องกันการรีซ้ำภายใน 60 วินาที
            if (( cooldown >= 60 )); then
                set_last_restart "$package" "$now"
                restart_package "$package"
            else
                echo "รอ Cooldown: $((60-cooldown)) วินาที"
            fi

        done < "$MAP"

        echo
        echo "ตรวจอีกครั้งใน 5 วินาที"
        sleep 5
    done
}

auto_start() {
    if [ ! -s "$MAP" ]; then
        echo "ตั้งค่าการจับคู่ครั้งแรก"
        setup_mapping || return 1
    fi

    local packages
    packages=$(get_packages)

    echo "กำลังเปิด Roblox ทุก Package..."

    while IFS= read -r package; do
        [ -z "$package" ] && continue
        open_package "$package"
        sleep 10
    done <<< "$packages"

    echo
    echo "เริ่มตรวจ API..."
    sleep 5
    monitor
}

while true; do
    clear
    echo -e "${CYAN}========== ARIWAA ==========${RESET}"
    echo
    echo "[1] AUTO START"
    echo "[2] SET GAME LINK"
    echo "[3] CREATE API"
    echo "[4] SETUP PACKAGE MAPPING"
    echo "[5] EXIT"
    echo

    read -r -p "Select: " choice

    case "$choice" in
        1)
            auto_start
            read -r -p "กด Enter เพื่อกลับ..."
            ;;
        2)
            read -r -p "ใส่ Private Server Link: " url
            if [[ "$url" == https://* ]]; then
                echo "$url" > "$CONFIG"
                echo "บันทึกลิงก์แล้ว"
            else
                echo "ลิงก์ไม่ถูกต้อง"
            fi
            read -r -p "กด Enter..."
            ;;
        3)
            create_api
            read -r -p "กด Enter..."
            ;;
        4)
            setup_mapping
            read -r -p "กด Enter..."
            ;;
        5)
            exit 0
            ;;
        *)
            echo "ตัวเลือกไม่ถูกต้อง"
            sleep 1
            ;;
    esac
done
