
#!/data/data/com.termux/files/usr/bin/bash

AUTO="/storage/emulated/0/Delta/Autoexecute"
CONFIG="$HOME/.rejoin_link"
LOG_DIR="$HOME/rejoin_logs"
RESULT_DIR="$HOME/rejoin_results"

mkdir -p "$LOG_DIR" "$RESULT_DIR"

CYAN='\033[1;36m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
RESET='\033[0m'

# ตรวจสอบ Root
check_root() {
    if ! su -c id 2>/dev/null | grep -q 'uid=0'; then
        echo -e "${RED}ROOT NOT AVAILABLE${RESET}"
        return 1
    fi
    return 0
}

# ตรวจหา Package
get_packages() {
    pm list packages |
        grep -Ei 'roblox|delt' |
        sed 's/package://' |
        sort -u
}

# ตรวจสอบชื่อ Package ให้ปลอดภัย
valid_package() {
    [[ "$1" =~ ^[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)+$ ]]
}

# บันทึก Log
save_log() {
    local package="$1"
    shift

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" \
        >> "$LOG_DIR/$package.log"
}

# แสดงผลคำสั่ง
show_result() {
    local name="$1"
    local output="$2"
    local code="$3"

    echo
    echo "$name"

    if [ "$code" -eq 0 ]; then
        echo -e "${GREEN}RESULT: SUCCESS${RESET}"
    else
        echo -e "${RED}RESULT: ERROR${RESET}"
    fi

    echo "EXIT CODE: $code"

    if [ -n "$output" ]; then
        echo "OUTPUT:"
        printf '%s\n' "$output"
    fi
}

# ปิดและเปิดแอป พร้อมตรวจสอบผลแยกกัน
restart_package() {
    local package="$1"
    local url="$2"
    local output
    local code
    local log="$LOG_DIR/$package.log"

    if ! valid_package "$package"; then
        echo "Invalid Package ID: $package"
        return 1
    fi

    clear

    echo "================================"
    echo "       CURRENT PACKAGE"
    echo "================================"
    echo "APP: $package"
    echo "================================"

    : > "$log"

    # ขั้นตอนปิด
    echo
    echo " [1] STOPPING APP"

    output=$(su -c "am force-stop $package" 2>&1)
    code=$?

    show_result "STOP APP" "$output" "$code"
    save_log "$package" "STOP exit=$code output=$output"

    if [ "$code" -ne 0 ]; then
        echo -e "${RED}Cannot continue: STOP FAILED${RESET}"
        save_log "$package" "RESTART ABORTED"
        return 1
    fi

    sleep 3

    # ขั้นตอนเปิด
    echo
    echo " [2] STARTING APP"

    if [[ "$package" == *roblox* ]] && [ -n "$url" ]; then
        output=$(su -c "am start -a android.intent.action.VIEW -d '$url' -p '$package'" 2>&1)
    else
        output=$(su -c "monkey -p '$package' 1" 2>&1)
    fi

    code=$?

    show_result "START APP" "$output" "$code"
    save_log "$package" "START exit=$code output=$output"

    sleep 5

    # ตรวจสอบ Process
    echo
    echo " [3] PROCESS CHECK"

    output=$(su -c "pidof $package" 2>&1)
    code=$?

    if [ -n "$output" ] && [ "$code" -eq 0 ]; then
        echo -e "${GREEN}PROCESS: RUNNING${RESET}"
        save_log "$package" "PROCESS RUNNING: $output"
    else
        echo -e "${RED}PROCESS: NOT DETECTED${RESET}"
        save_log "$package" "PROCESS NOT DETECTED"
    fi

    # บันทึกผลล่าสุด
    {
        echo "PACKAGE=$package"
        echo "STOP_EXIT_CODE=$code"
        echo "PROCESS_OUTPUT=$output"
        echo "TIME=$(date '+%Y-%m-%d %H:%M:%S')"
    } > "$RESULT_DIR/$package.txt"

    echo
    echo "================================"
    echo "PACKAGE FINISHED"
    echo "================================"

    sleep 3
}

# ทำงานทีละ Package
run_all() {
    local packages="$1"
    local url="$2"

    local total=0
    local success=0
    local errors=0

    while IFS= read -r package; do
        [ -z "$package" ] && continue

        total=$((total + 1))

        if restart_package "$package" "$url"; then
            success=$((success + 1))
        else
            errors=$((errors + 1))
        fi

    done <<< "$packages"

    clear

    echo "================================"
    echo "          FINAL REPORT"
    echo "================================"
    echo "TOTAL:   $total"
    echo -e "SUCCESS: ${GREEN}$success${RESET}"
    echo -e "ERROR:   ${RED}$errors${RESET}"
    echo "================================"

    echo
    echo "PACKAGE ERROR REPORT"

    while IFS= read -r package; do
        [ -z "$package" ] && continue

        echo
        echo "PACKAGE: $package"

        if [ -f "$LOG_DIR/$package.log" ]; then
            tail -n 5 "$LOG_DIR/$package.log"
        else
            echo "NO LOG"
        fi

    done <<< "$packages"

    echo
    read -r -p "Press Enter..."
}

# ตั้งค่า Game Link
set_link() {
    read -r -p "Enter Game ID or Link: " game

    if [[ "$game" =~ ^[0-9]+$ ]]; then
        url="roblox://experiences/start?placeId=$game"

    elif [[ "$game" == http://* || "$game" == https://* ]]; then
        url="$game"

    else
        echo "Invalid Game ID or Link"
        read -r -p "Press Enter..."
        return
    fi

    printf '%s\n' "$url" > "$CONFIG"

    echo "Game Link saved!"
    read -r -p "Press Enter..."
}

# ดู Log
view_logs() {
    clear
    echo "========== PACKAGE LOGS =========="

    if [ ! -d "$LOG_DIR" ]; then
        echo "No logs found."
    else
        for file in "$LOG_DIR"/*.log; do
            [ -f "$file" ] || continue

            echo
            echo "FILE: $(basename "$file")"
            tail -n 15 "$file"
        done
    fi

    echo
    read -r -p "Press Enter..."
}

# เมนูหลัก
while true; do
    clear

    echo -e "${CYAN}"
    echo "================================"
    echo "          A R I W A A"
    echo "================================"
    echo -e "${RESET}"

    echo "[1] Open / Restart All Packages"
    echo "[2] Set Game Link"
    echo "[3] View Package Logs"
    echo "[4] Exit"

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

            echo
            echo "FOUND PACKAGES:"
            echo "$packages"

            echo
            read -r -p "Start sequentially? (y/n): " confirm

            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                continue
            fi

            url=""
            [ -f "$CONFIG" ] && url=$(cat "$CONFIG")

            run_all "$packages" "$url"
            ;;

        2)
            set_link
            ;;

        3)
            view_logs
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
