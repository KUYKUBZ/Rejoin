#!/data/data/com.termux/files/usr/bin/bash

clear

# ==== Paths ====
Auto="/storage/emulated/0/Delta/Autoexecute"
CONFIG="$HOME/.rejoin_link"
WORKSPACE_FILE="$HOME/.executor_workspace"
LOG="$HOME/rejoin.log"

# โหลด workspace ที่เคยตั้งไว้ (default = Delta)
if [ -f "$WORKSPACE_FILE" ]; then
    WORKSPACE=$(cat "$WORKSPACE_FILE")
else
    WORKSPACE="/storage/emulated/0/Delta/Workspace"
fi

# ==== Colors ====
CYAN='\033[1;36m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
GREEN='\033[1;32m'
RESET='\033[0m'

# ==== ตัวแปรกัน restart รัว ====
RESTART_COUNT=0
LAST_RESTART=0

# ==== Logger ====
log() {
    echo -e "$*" | tee -a "$LOG"
}

# ==== เช็ค root ครั้งเดียวตอนเริ่ม ====
check_root() {
    if ! su -c "true" >/dev/null 2>&1; then
        echo -e "${RED}[ERROR]${RESET} ไม่มีสิทธิ์ root — สคริปต์ต้องการ su"
        exit 1
    fi
}

# ==== หา package ที่เป็น Roblox ====
get_packages() {
    pm list packages 2>/dev/null | grep -Ei 'roblox|delt' | sed 's/package://'
}

# ==== ตรวจว่ามี task ใน recents ====
has_task() {
    /system/bin/dumpsys activity recents 2>/dev/null |
        grep -F "A=$1 " >/dev/null
}

# ==== ตรวจว่า process ยังอยู่ ====
is_process_alive() {
    su -c "pidof '$1'" >/dev/null 2>&1
}

# ==== สร้าง api.luau (writefile ธรรมดา ลง workspace) ====
CreateApi() {
    mkdir -p "$Auto"
    cat > "$Auto/api.luau" << 'LUA'
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

    -- เขียนลง workspace ของ executor เอง (ไม่ระบุ path)
    pcall(function()
        writefile(Player.Name .. "_status.txt",
            status .. "\n" .. Player.Name .. "\n" .. os.time())
    end)

    task.wait(3)
end)
LUA
    echo -e "${GREEN}Created:${RESET} $Auto/api.luau"
    echo -e "${YELLOW}อย่าลืม:${RESET} ตั้ง Delta → Auto Execute → เลือก api.luau"
}

# ==== อ่าน status file จาก workspace ====
# return 0 = IN_GAME ปกติ
# return 1 = หลุด / stale / ไม่มีไฟล์
check_status() {
    local file
    file=$(ls "$WORKSPACE"/*_status.txt 2>/dev/null | head -n1)

    if [ -z "$file" ]; then
        echo -e "${YELLOW}[STATUS]${RESET} ไม่พบไฟล์ใน $WORKSPACE"
        return 1
    fi

    local s name t age now
    s=$(head -n1 "$file" 2>/dev/null)
    name=$(sed -n '2p' "$file" 2>/dev/null)
    t=$(sed -n '3p' "$file" 2>/dev/null)
    now=$(date +%s)

    if ! [[ "$t" =~ ^[0-9]+$ ]]; then
        echo -e "${YELLOW}[STATUS]${RESET} $name : timestamp เสีย"
        return 1
    fi

    age=$(( now - t ))

    if [ "$age" -gt 10 ]; then
        echo -e "${RED}[STATUS]${RESET} $name : STALE (${age}s) → หลุด"
        return 1
    fi

    if [ "$s" != "IN_GAME" ]; then
        echo -e "${YELLOW}[STATUS]${RESET} $name : $s → หลุด"
        return 1
    fi

    echo -e "${GREEN}[STATUS]${RESET} $name : IN_GAME (${age}s ago)"
    return 0
}

# ==== Force stop ====
force_stop() {
    local package="$1"
    echo -e "${YELLOW}[FORCE STOP]${RESET} $package"
    if su -c "am force-stop '$package'" >/dev/null 2>&1; then
        echo -e "${GREEN}[STOP OK]${RESET} $package"
        return 0
    else
        echo -e "${RED}[STOP ERROR]${RESET} $package"
        return 1
    fi
}

# ==== เปิด package ====
open_package() {
    local package="$1"
    local url="$2"

    force_stop "$package"
    sleep 2

    log "[OPENING] $package"

    # ลบ status เก่าใน workspace กันอ่านค่าเก่า
    rm -f "$WORKSPACE"/*_status.txt 2>/dev/null

    if [ -n "$url" ]; then
        su -c "am start -a android.intent.action.VIEW -d '$url' -p '$package'" >/dev/null 2>&1
    else
        su -c "am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p '$package'" >/dev/null 2>&1
    fi

    sleep 10
}

# ==== ตรวจว่าหลุดไหม ====
is_disconnected() {
    local pkg="$1"

    # 1) process ตาย
    if ! is_process_alive "$pkg"; then
        echo -e "${RED}[DETECT]${RESET} process ตาย"
        return 0
    fi

    # 2) ไม่มี task
    if ! has_task "$pkg"; then
        echo -e "${RED}[DETECT]${RESET} ไม่มี task"
        return 0
    fi

    # 3) status ผิดปกติ
    if ! check_status >/dev/null 2>&1; then
        echo -e "${RED}[DETECT]${RESET} status ผิดปกติ"
        return 0
    fi

    return 1
}

# ==== Restart พร้อม throttle ====
restart_package() {
    local pkg="$1"
    local url="$2"

    local now
    now=$(date +%s)

    # reset counter ถ้าผ่านไปเกิน 60 วิ
    if [ $(( now - LAST_RESTART )) -gt 60 ]; then
        RESTART_COUNT=0
    fi

    RESTART_COUNT=$(( RESTART_COUNT + 1 ))
    LAST_RESTART=$now

    if [ "$RESTART_COUNT" -gt 5 ]; then
        log "${RED}[THROTTLE]${RESET} restart เกิน 5 ครั้ง/นาที — รอ 60 วิ"
        sleep 60
        RESTART_COUNT=0
    fi

    log "${RED}[RESTART]${RESET} $pkg (ครั้งที่ $RESTART_COUNT)"
    open_package "$pkg" "$url"
    log "${GREEN}[RESTART OK]${RESET} $pkg"
}

# ==== UI helpers ====
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

# ==== MAIN ====
check_root

while true; do
    clear

    border
    line ""
    line "       A r i w a a"
    line ""
    border
    line ""
    line " [1] Open Roblox"
    line " [2] Set Game Link"
    line " [3] Setup executor"
    line " [4] Set Workspace Path"
    line " [5] Exit"
    line ""
    border
    line ""
    line " WS: ${WORKSPACE:0:$((INNER-5))}"
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

            # ตรวจ workspace ก่อนเริ่ม
            if [ ! -d "$WORKSPACE" ]; then
                echo -e "${RED}ไม่พบ workspace:${RESET} $WORKSPACE"
                echo "ไปที่ [4] เพื่อตั้งค่า workspace ก่อน"
                read -r -p "Press Enter..."
                continue
            fi

            echo ""
            echo "Found packages:"
            echo "$packages"
            echo ""

            # เปิดทั้งหมดครั้งแรก
            for package in $packages; do
                open_package "$package" "$url"
            done

            echo ""
            echo "[MONITOR STARTED]"
            echo ""

            RESTART_COUNT=0
            LAST_RESTART=$(date +%s)

            # ==== Monitoring Loop ====
            while true; do
                for package in $packages; do

                    if is_disconnected "$package"; then
                        log "${YELLOW}[DISCONNECTED]${RESET} $package"
                        restart_package "$package" "$url"
                    else
                        check_status
                    fi

                done

                sleep 15
            done
            ;;

        2)
            read -r -p "Enter Game ID or Link: " game

            if [[ "$game" =~ ^[0-9]+$ ]]; then
                url="roblox://experiences/start?placeId=$game"
            elif [[ "$game" == http://* || "$game" == https://* ]]; then
                url="$game"
            else
                echo "Invalid Game Id or Link."
                read -r -p "Press Enter..."
                continue
            fi

            echo "$url" > "$CONFIG"
            echo "Link saved successfully!"
            read -r -p "Press Enter to return to menu..."
            ;;

        3)
            CreateApi
            read -r -p "Press Enter..."
            ;;

        4)
            echo ""
            echo "ที่อยู่ workspace ของ executor"
            echo "ตัวอย่าง:"
            echo "  Delta     : /storage/emulated/0/Delta/Workspace"
            echo "  Codex     : /storage/emulated/0/Codex/Workspace"
            echo "  Fluxus    : /storage/emulated/0/Fluxus/Workspace"
            echo "  Hydrogen  : /storage/emulated/0/Hydrogen/Workspace"
            echo ""
            echo "ปัจจุบัน: $WORKSPACE"
            echo ""
            read -r -p "Workspace Path (เว้นว่าง = ไม่เปลี่ยน): " ws

            # ถ้าเว้นว่าง = ไม่เปลี่ยน
            if [ -z "$ws" ]; then
                echo "ไม่เปลี่ยน"
                read -r -p "Press Enter..."
                continue
            fi

            # ตัด / ปิดท้าย
            ws="${ws%/}"

            if [ -d "$ws" ]; then
                echo "$ws" > "$WORKSPACE_FILE"
                WORKSPACE="$ws"
                echo -e "${GREEN}บันทึกแล้ว:${RESET} $WORKSPACE"
            else
                echo -e "${RED}ไม่พบโฟลเดอร์:${RESET} $ws"
                echo "สร้างโฟลเดอร์ก่อน หรือตรวจ path อีกครั้ง"
            fi

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
