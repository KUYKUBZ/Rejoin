#!/data/data/com.termux/files/usr/bin/bash

#test

if [ "$(id -u)" -ne 0 ]; then
    if [ -f "$0" ] && [ "$0" != "bash" ] && [ "$0" != "sh" ] && ! echo "$0" | grep -qE "(/bin/bash|/bin/sh)$"; then
        exec su -c "/data/data/com.termux/files/usr/bin/bash \"$(realpath "$0")\" $@"
    else
        exec su -c "bash -c '$(curl -sL https://tinyurl.com/2bspyv74 | tr -d '\r')'"
    fi
fi

DOWNLOAD_DIR="/sdcard/Download"
CONF_DIR="$DOWNLOAD_DIR"
CONF_FILE="$CONF_DIR/packages.conf"
EXPORT_FILE="$CONF_DIR/roblox_sessions_export.txt"
COOKIE_INPUT_FILE="$DOWNLOAD_DIR/cookie.txt"

mkdir -p "$DOWNLOAD_DIR"
[ ! -f "$CONF_FILE" ] && touch "$CONF_FILE"
[ ! -f "$COOKIE_INPUT_FILE" ] && touch "$COOKIE_INPUT_FILE"

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_CYAN="\033[1;36m"
C_GREEN="\033[1;32m"
C_RED="\033[1;31m"
C_YELLOW="\033[1;33m"
C_BLUE="\033[1;34m"
C_MAGENTA="\033[1;35m"
C_WHITE="\033[1;37m"
C_GRAY="\033[0;90m"

cleanup() {
    tput cnorm 2>/dev/null || printf "\033[?25h"
    printf "${C_RESET}\n"
    clear
    exit 0
}
trap cleanup INT TERM

parse_server_intent() {
    local link="$1"
    if echo "$link" | grep -qE "^[0-9]+$"; then
        echo "roblox://placeId=$link"
    elif echo "$link" | grep -iq "linkCode="; then
        local code
        code=$(echo "$link" | grep -oE "linkCode=[a-zA-Z0-9_-]+" | cut -d'=' -f2)
        local pid
        pid=$(echo "$link" | grep -oE "games/[0-9]+" | cut -d'/' -f2)
        if [ -n "$pid" ] && [ -n "$code" ]; then
            echo "roblox://placeId=$pid&linkCode=$code"
        else
            echo "$link"
        fi
    elif echo "$link" | grep -iq "roblox://"; then
        echo "$link"
    else
        echo "roblox://placeId=$link"
    fi
}

get_all_installed_roblox() {
    local pkgs
    pkgs=$(pm list packages -3 2>/dev/null | sed 's/package://g' | grep -vE "^com.termux$" | tr -d '\r')
    if [ -z "$pkgs" ]; then
        pkgs=$(pm list packages --user all -3 2>/dev/null | sed 's/package://g' | grep -vE "^com.termux$" | tr -d '\r')
    fi
    if ! echo "$pkgs" | grep -q "com.roblox.client"; then
        pkgs=$(printf "com.roblox.client\n%s" "$pkgs")
    fi
    echo "$pkgs" | grep -vE "^$" | sort -u
}

list_selected_packages() {
    clear
    printf "${C_CYAN}┌── [ PACKAGES ĐÃ CẤU HÌNH ] ────────┐${C_RESET}\n"
    if [ ! -s "$CONF_FILE" ]; then
        printf " ${C_RED}[!] Chưa có package nào.${C_RESET}\n"
    else
        local idx=1
        while IFS='=' read -r pkg link || [ -n "$pkg" ]; do
            [ -z "$pkg" ] && continue
            printf " ${C_YELLOW}%d.${C_RESET} %s\n" "$idx" "$pkg"
            printf "    ${C_GRAY}Link: ${C_GREEN}%s${C_RESET}\n" "${link:0:30}"
            idx=$((idx + 1))
        done < "$CONF_FILE"
    fi
    printf "${C_CYAN}└────────────────────────────────────┘${C_RESET}\n"
    printf " ${C_GRAY}File cấu hình: %s${C_RESET}\n" "$CONF_FILE"
    printf "\n${C_WHITE}Bấm Enter để quay lại...${C_RESET}"
    read -r _
}

select_packages_assign_link() {
    clear
    local installed
    installed=$(get_all_installed_roblox)

    local i=1
    declare -A pkg_map
    for p in $installed; do
        printf "${C_MAGENTA}[%d]${C_RESET} ${C_CYAN}%s${C_RESET}\n" "$i" "$p"
        pkg_map[$i]="$p"
        i=$((i + 1))
    done
    printf "\n"

    while true; do
        printf "${C_GREEN}Select package name(0 - stop): ${C_RESET}"
        read -r sel
        [ "$sel" = "0" ] && break
        [ -z "$sel" ] && continue

        local chosen_pkg="${pkg_map[$sel]}"
        if [ -z "$chosen_pkg" ]; then
            chosen_pkg="$sel"
        fi

        printf "${C_WHITE}Nhập Place ID/Link cho ${C_YELLOW}%s${C_WHITE}: ${C_RESET}" "$chosen_pkg"
        read -r s_link
        if [ -n "$s_link" ]; then
            sed -i "/^$chosen_pkg=/d" "$CONF_FILE" 2>/dev/null
            echo "$chosen_pkg=$s_link" >> "$CONF_FILE"
            printf " ${C_GREEN}[✓] Đã lưu %s${C_RESET}\n\n" "$chosen_pkg"
        fi
    done

    printf "\n${C_WHITE}Hoàn tất cấu hình. Bấm Enter để tiếp tục...${C_RESET}"
    read -r _
}

auto_select_all_one_link() {
    clear
    printf "${C_CYAN}┌── [ GÁN TẤT CẢ CHUNG 1 LINK ] ──────┐${C_RESET}\n"
    local installed
    installed=$(get_all_installed_roblox)
    for p in $installed; do
        printf " ${C_GRAY}•${C_RESET} %s\n" "$p"
    done
    printf "${C_CYAN}└────────────────────────────────────┘${C_RESET}\n"

    printf "\n${C_WHITE}Nhập Place ID hoặc Link dùng chung: ${C_RESET}"
    read -r link
    [ -z "$link" ] && return

    > "$CONF_FILE"
    for p in $installed; do
        echo "$p=$link" >> "$CONF_FILE"
    done
    printf " ${C_GREEN}[✓] Đã gán tất cả package thành công!${C_RESET}\n"
    sleep 2
}

open_all_tabs() {
    clear
    printf "${C_CYAN}Mở tất cả tabs Roblox...${C_RESET}\n\n"
    if [ ! -s "$CONF_FILE" ]; then
        printf "${C_RED}[!] Danh sách trống. Hãy cấu hình mục 2 hoặc 4 trước!${C_RESET}\n"
        sleep 2
        return
    fi

    while IFS='=' read -r pkg link || [ -n "$pkg" ]; do
        [ -z "$pkg" ] && continue
        local intent_url
        intent_url=$(parse_server_intent "$link")
        printf " ${C_YELLOW}→ Mở %s...${C_RESET}\n" "$pkg"
        am start -p "$pkg" -a android.intent.action.VIEW -d "$intent_url" >/dev/null 2>&1
        sleep 8
    done
    printf "\n${C_GREEN}[✓] Đã mở toàn bộ tabs!${C_RESET}\n"
    sleep 2
}

apply_cookie_to_pkg() {
    local target_pkg="$1"
    local cookie_val="$2"

    am force-stop "$target_pkg" >/dev/null 2>&1
    local db_dir="/data/data/$target_pkg/app_webview/Default"
    mkdir -p "$db_dir"
    local db_path="$db_dir/Cookies"

    sqlite3 "$db_path" "CREATE TABLE IF NOT EXISTS cookies(creation_utc INTEGER NOT NULL, host_key TEXT NOT NULL, name TEXT NOT NULL, value TEXT NOT NULL, path TEXT NOT NULL, expires_utc INTEGER NOT NULL, is_secure INTEGER NOT NULL, is_httponly INTEGER NOT NULL, last_access_utc INTEGER NOT NULL, has_expires INTEGER NOT NULL, is_persistent INTEGER NOT NULL, priority INTEGER NOT NULL, encrypted_value BLOB DEFAULT '', samesite INTEGER NOT NULL, source_scheme INTEGER NOT NULL, source_port INTEGER NOT NULL, is_same_party INTEGER NOT NULL, PRIMARY KEY(host_key, name, path));" 2>/dev/null

    local now_epoch
    now_epoch=$(date +%s)
    local webkit_time=$(( (now_epoch + 11644473600) * 1000000 ))
    local expire_time=$(( webkit_time + 315360000000000 ))

    sqlite3 "$db_path" "DELETE FROM cookies WHERE name='.ROBLOSECURITY';" 2>/dev/null
    sqlite3 "$db_path" "INSERT OR REPLACE INTO cookies (creation_utc, host_key, name, value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent, priority, samesite, source_scheme, source_port, is_same_party) VALUES ($webkit_time, '.roblox.com', '.ROBLOSECURITY', '$cookie_val', '/', $expire_time, 1, 1, $webkit_time, 1, 1, 1, -1, 2, 443, 0);" 2>/dev/null

    local app_uid
    app_uid=$(stat -c "%u" "/data/data/$target_pkg" 2>/dev/null)
    if [ -n "$app_uid" ]; then
        chown -R "$app_uid:$app_uid" "/data/data/$target_pkg/app_webview" 2>/dev/null
        chmod 660 "$db_path" 2>/dev/null
    fi
}

login_via_cookie() {
    clear
    printf "${C_CYAN}┌── [ LOGIN VIA COOKIE ] ────────────┐${C_RESET}\n"
    printf " ${C_YELLOW} 1.${C_RESET} Nạp tự động từ file cookie.txt\n"
    printf " ${C_YELLOW} 2.${C_RESET} Chọn package và nhập cookie\n"
    printf "${C_CYAN}└────────────────────────────────────┘${C_RESET}\n"
    printf " ${C_GRAY}Vị trí: %s${C_RESET}\n" "$COOKIE_INPUT_FILE"
    printf "\n${C_WHITE}Chọn phương thức: ${C_RESET}"
    read -r method

    if [ "$method" = "1" ]; then
        if [ ! -s "$COOKIE_INPUT_FILE" ]; then
            printf " ${C_RED}[!] File %s trống hoặc chưa có dữ liệu!${C_RESET}\n" "$COOKIE_INPUT_FILE"
            sleep 2
            return
        fi

        local installed
        installed=$(get_all_installed_roblox)
        local count=0

        while IFS= read -r line || [ -n "$line" ]; do
            local clean_line
            clean_line=$(echo "$line" | tr -d '\r' | xargs)
            [ -z "$clean_line" ] && continue

            count=$((count + 1))
            local target_pkg
            target_pkg=$(echo "$installed" | sed -n "${count}p")
            if [ -n "$target_pkg" ]; then
                apply_cookie_to_pkg "$target_pkg" "$clean_line"
                printf " ${C_GREEN}[✓] Dòng %d -> Gán vào %s${C_RESET}\n" "$count" "$target_pkg"
            fi
        done < "$COOKIE_INPUT_FILE"

        printf "\n${C_GREEN}[✓] Hoàn tất nạp danh sách cookies!${C_RESET}\n"
        sleep 2
    else
        local installed
        installed=$(get_all_installed_roblox)
        local i=1
        declare -A pkg_map
        for p in $installed; do
            printf "${C_MAGENTA}[%d]${C_RESET} ${C_CYAN}%s${C_RESET}\n" "$i" "$p"
            pkg_map[$i]="$p"
            i=$((i + 1))
        done
        printf "\n"

        while true; do
            printf "${C_GREEN}Select package name(0 - stop): ${C_RESET}"
            read -r sel
            [ "$sel" = "0" ] && break
            [ -z "$sel" ] && continue

            local chosen_pkg="${pkg_map[$sel]}"
            if [ -z "$chosen_pkg" ]; then
                chosen_pkg="$sel"
            fi

            printf "${C_WHITE}Dán chuỗi Cookie cho ${C_YELLOW}%s${C_WHITE}: ${C_RESET}" "$chosen_pkg"
            read -r cookie_input
            if [ -n "$cookie_input" ]; then
                apply_cookie_to_pkg "$chosen_pkg" "$cookie_input"
                printf " ${C_GREEN}[✓] Đã login cookie vào %s!${C_RESET}\n\n" "$chosen_pkg"
            fi
        done
    fi
}

logout_roblox() {
    clear
    local installed
    installed=$(get_all_installed_roblox)
    local i=1
    declare -A pkg_map
    for p in $installed; do
        printf "${C_MAGENTA}[%d]${C_RESET} ${C_CYAN}%s${C_RESET}\n" "$i" "$p"
        pkg_map[$i]="$p"
        i=$((i + 1))
    done
    printf " ${C_MAGENTA}[A]${C_RESET} ${C_YELLOW}Logout TẤT CẢ${C_RESET}\n\n"

    while true; do
        printf "${C_GREEN}Select package name to logout(0 - stop): ${C_RESET}"
        read -r choice
        [ "$choice" = "0" ] && break
        [ -z "$choice" ] && continue

        if [ "$choice" = "A" ] || [ "$choice" = "a" ]; then
            for p in $installed; do
                am force-stop "$p" >/dev/null 2>&1
                rm -rf "/data/data/$p/app_webview" "/data/data/$p/shared_prefs" 2>/dev/null
            done
            printf " ${C_GREEN}[✓] Đã logout toàn bộ!${C_RESET}\n"
            break
        else
            local chosen_pkg="${pkg_map[$choice]}"
            if [ -z "$chosen_pkg" ]; then
                chosen_pkg="$choice"
            fi
            am force-stop "$chosen_pkg" >/dev/null 2>&1
            rm -rf "/data/data/$chosen_pkg/app_webview" "/data/data/$chosen_pkg/shared_prefs" 2>/dev/null
            printf " ${C_GREEN}[✓] Đã logout %s!${C_RESET}\n\n" "$chosen_pkg"
        fi
    done
    sleep 1
}

export_cookies() {
    clear
    printf "${C_CYAN}┌── [ EXPORT COOKIES ] ──────────────┐${C_RESET}\n"
    local installed
    installed=$(get_all_installed_roblox)
    > "$EXPORT_FILE"
    local count=0

    for p in $installed; do
        local db_path="/data/data/$p/app_webview/Default/Cookies"
        [ ! -f "$db_path" ] && db_path="/data/data/$p/app_webview/Cookies"

        local c_val=""
        if [ -f "$db_path" ]; then
            c_val=$(sqlite3 "$db_path" "SELECT value FROM cookies WHERE name='.ROBLOSECURITY' LIMIT 1;" 2>/dev/null)
        fi

        if [ -n "$c_val" ]; then
            echo "[$p]: $c_val" >> "$EXPORT_FILE"
            printf " ${C_GREEN}[✓]${C_WHITE} %s${C_RESET}\n" "$p"
            count=$((count + 1))
        else
            printf " ${C_GRAY}[-] %s (Trống)${C_RESET}\n" "$p"
        fi
    done
    printf "${C_CYAN}└────────────────────────────────────┘${C_RESET}\n"
    printf " ${C_GREEN}[✓] Đã lưu %d cookies vào: %s${C_RESET}\n" "$count" "$EXPORT_FILE"
    printf "\n${C_WHITE}Bấm Enter để tiếp tục...${C_RESET}"
    read -r _
}

check_in_game_status() {
    local target_pkg="$1"
    local pid="$2"

    if [ -z "$pid" ]; then
        echo "CRASHED"
        return
    fi

    # 1. Kiểm tra màn hình điện thoại (Launcher / Trang chủ hệ thống)
    local focus
    focus=$(dumpsys window 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp")
    if echo "$focus" | grep -iqE "(launcher|home|recents)"; then
        echo "DISCONNECTED"
        return
    fi

    # 2. Kiểm tra logfile của Roblox: xem sự kiện cuối cùng là vào game hay ra game
    local log_dir="/data/data/$target_pkg/files/logs"
    [ ! -d "$log_dir" ] && log_dir="/sdcard/Android/data/$target_pkg/files/logs"
    if [ -d "$log_dir" ]; then
        local latest_log
        latest_log=$(ls -t "$log_dir"/*.txt 2>/dev/null | head -n 1)
        if [ -f "$latest_log" ]; then
            local last_status
            last_status=$(grep -iE "(Game ended|Disconnecting from server|Connection lost|Game joined|Game loaded)" "$latest_log" 2>/dev/null | tail -n 1)
            if [ -n "$last_status" ]; then
                if echo "$last_status" | grep -iqE "(Game ended|Disconnecting from server|Connection lost)"; then
                    echo "DISCONNECTED"
                    return
                fi
            fi
        fi
    fi

    # 3. Kiểm tra logcat tổng quát
    local logcat_last
    logcat_last=$(logcat -d 2>/dev/null | grep -iE "(Game ended|User requested leave|leaveGame|OnDisconnection|Lost connection|Disconnected from|ErrorPrompt)" | tail -n 1)
    if [ -n "$logcat_last" ]; then
        echo "DISCONNECTED"
        return
    fi

    echo "INGAME"
}

start_auto_rejoin() {
    clear
    if [ ! -s "$CONF_FILE" ]; then
        printf "${C_RED}[!] Danh sách package trống! Hãy cấu hình mục 2 hoặc 4 trước.${C_RESET}\n"
        sleep 2
        return
    fi

    printf "${C_WHITE}Thời gian tự động reset (phút) [30]: ${C_RESET}"
    read -r interval_input
    local reset_min="${interval_input:-30}"
    local max_runtime=$((reset_min * 60))

    tput civis 2>/dev/null || printf "\033[?25l"
    clear

    declare -A start_times
    declare -A crash_counts

    logcat -c 2>/dev/null

    while IFS='=' read -r pkg link || [ -n "$pkg" ]; do
        [ -z "$pkg" ] && continue
        start_times[$pkg]=$(date +%s)
        crash_counts[$pkg]=0
        local intent_url
        intent_url=$(parse_server_intent "$link")
        am force-stop "$pkg" >/dev/null 2>&1
        input keyevent 4 >/dev/null 2>&1
        sleep 1
        am start -p "$pkg" -a android.intent.action.VIEW -d "$intent_url" >/dev/null 2>&1
    done < "$CONF_FILE"

    local warmup_time=20
    for ((w=warmup_time; w>0; w--)); do
        printf "\033[H"
        printf "${C_CYAN}┌── [ ROBLOX AUTO-REJOIN ] ──────────┐${C_RESET}\033[K\n"
        printf "│ ${C_YELLOW}Đang khởi động & vào game (${w}s)...${C_RESET} │\033[K\n"
        printf "${C_CYAN}└────────────────────────────────────┘${C_RESET}\033[K\n"
        sleep 1
    done
    logcat -c 2>/dev/null

    while true; do
        printf "\033[H"
        printf "${C_CYAN}┌── [ ROBLOX IN-GAME MONITOR ] ──────┐${C_RESET}\033[K\n"
        local now
        now=$(date +%s)

        while IFS='=' read -r pkg link || [ -n "$pkg" ]; do
            [ -z "$pkg" ] && continue
            local pid
            pid=$(pidof "$pkg" | awk '{print $1}')
            local p_start="${start_times[$pkg]:-$now}"
            local elapsed=$((now - p_start))
            local remain=$((max_runtime - elapsed))
            [ "$remain" -lt 0 ] && remain=0

            local status_text
            local intent_url
            intent_url=$(parse_server_intent "$link")

            local state
            state=$(check_in_game_status "$pkg" "$pid")

            if [ "$state" = "CRASHED" ]; then
                status_text="${C_RED}VĂNG APP -> REJOIN${C_RESET}"
                crash_counts[$pkg]=$(( ${crash_counts[$pkg]:-0} + 1 ))
                am force-stop "$pkg" >/dev/null 2>&1
                input keyevent 4 >/dev/null 2>&1
                sleep 1
                am start -p "$pkg" -a android.intent.action.VIEW -d "$intent_url" >/dev/null 2>&1
                start_times[$pkg]=$now
                logcat -c 2>/dev/null
            elif [ "$state" = "DISCONNECTED" ]; then
                status_text="${C_RED}ĐÃ THOÁT/MẤT KẾT NỐI -> REJOIN${C_RESET}"
                crash_counts[$pkg]=$(( ${crash_counts[$pkg]:-0} + 1 ))
                am force-stop "$pkg" >/dev/null 2>&1
                input keyevent 4 >/dev/null 2>&1
                sleep 1
                am start -p "$pkg" -a android.intent.action.VIEW -d "$intent_url" >/dev/null 2>&1
                start_times[$pkg]=$now
                logcat -c 2>/dev/null
            elif [ "$max_runtime" -gt 0 ] && [ "$elapsed" -ge "$max_runtime" ]; then
                status_text="${C_YELLOW}HẾT CHU KỲ -> RESET${C_RESET}"
                am force-stop "$pkg" >/dev/null 2>&1
                input keyevent 4 >/dev/null 2>&1
                sleep 1
                am start -p "$pkg" -a android.intent.action.VIEW -d "$intent_url" >/dev/null 2>&1
                start_times[$pkg]=$now
                logcat -c 2>/dev/null
            else
                status_text="${C_GREEN}ĐANG TRONG GAME (PID: $pid)${C_RESET}"
            fi

            printf "│ ${C_YELLOW}%-18s${C_RESET} Rejoin: ${C_RED}%-2d${C_RESET}│\033[K\n" "${pkg:0:18}" "${crash_counts[$pkg]:-0}"
            printf "│ TT: %-33b │\033[K\n" "$status_text"
            printf "│ Reset sau: %02d:%02d                   │\033[K\n" $((remain/60)) $((remain%60))
            printf "├────────────────────────────────────┤\033[K\n"
        done < "$CONF_FILE"

        printf "${C_CYAN}└────────────────────────────────────┘${C_RESET}\033[K\n"
        printf " ${C_GRAY}[Ctrl + C] Quay lại Menu${C_RESET}\033[K\n"
        sleep 2
    done
}

while true; do
    clear
    printf "${C_CYAN}⚡ Shouko Menu${C_RESET}\n"
    printf "${C_CYAN}┌── Auto Rejoin ─────────────────────┐${C_RESET}\n"
    printf "│ ${C_YELLOW} 1${C_RESET}  Start auto rejoin              │\n"
    printf "${C_CYAN}├── Server Setup ────────────────────┤${C_RESET}\n"
    printf "│ ${C_YELLOW} 2${C_RESET}  Select package & assign link   │\n"
    printf "│ ${C_YELLOW} 3${C_RESET}  List selected packages         │\n"
    printf "│ ${C_YELLOW} 4${C_RESET}  Auto-select all with one link  │\n"
    printf "${C_CYAN}├── Tabs ────────────────────────────┤${C_RESET}\n"
    printf "│ ${C_YELLOW} 5${C_RESET}  Open all Roblox tabs           │\n"
    printf "${C_CYAN}├── Account / Cookie ────────────────┤${C_RESET}\n"
    printf "│ ${C_YELLOW} 6${C_RESET}  Login via cookie               │\n"
    printf "│ ${C_YELLOW} 7${C_RESET}  Logout Roblox                  │\n"
    printf "│ ${C_YELLOW} 8${C_RESET}  Export cookies from packages   │\n"
    printf "${C_CYAN}├── System ──────────────────────────┤${C_RESET}\n"
    printf "│ ${C_YELLOW} 9${C_RESET}  Xem toàn bộ package quét được  │\n"
    printf "│ ${C_RED}10${C_RESET}  Exit                           │\n"
    printf "${C_CYAN}└────────────────────────────────────┘${C_RESET}\n\n"

    printf "${C_MAGENTA}Enter choice: ${C_RESET}"
    read -r choice

    case "$choice" in
        1) start_auto_rejoin ;;
        2) select_packages_assign_link ;;
        3) list_selected_packages ;;
        4) auto_select_all_one_link ;;
        5) open_all_tabs ;;
        6) login_via_cookie ;;
        7) logout_roblox ;;
        8) export_cookies ;;
        9) 
            clear
            printf "${C_CYAN}Toàn bộ packages quét được:${C_RESET}\n\n"
            get_all_installed_roblox | while read -r p; do
                printf "  ${C_GREEN}•${C_RESET} %s\n" "$p"
            done
            printf "\n${C_WHITE}Bấm Enter để tiếp tục...${C_RESET}"
            read -r _
            ;;
        10) cleanup ;;
        *) sleep 1 ;;
    esac
done
#!/data/data/com.termux/files/usr/bin/bash

if [ "$(id -u)" -ne 0 ]; then
    if [ -f "$0" ] && [ "$0" != "bash" ] && [ "$0" != "sh" ] && ! echo "$0" | grep -qE "(/bin/bash|/bin/sh)$"; then
        exec su -c "/data/data/com.termux/files/usr/bin/bash \"$(realpath "$0")\" $@"
    else
        exec su -c "bash -c '$(curl -sL https://tinyurl.com/29no9trz | tr -d '\r')'"
    fi
fi

DOWNLOAD_DIR="/sdcard/Download"
CONF_DIR="$DOWNLOAD_DIR"
CONF_FILE="$CONF_DIR/packages.conf"
EXPORT_FILE="$CONF_DIR/roblox_sessions_export.txt"
COOKIE_INPUT_FILE="$DOWNLOAD_DIR/cookie.txt"

mkdir -p "$DOWNLOAD_DIR"
[ ! -f "$CONF_FILE" ] && touch "$CONF_FILE"
[ ! -f "$COOKIE_INPUT_FILE" ] && touch "$COOKIE_INPUT_FILE"

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_CYAN="\033[1;36m"
C_GREEN="\033[1;32m"
C_RED="\033[1;31m"
C_YELLOW="\033[1;33m"
C_BLUE="\033[1;34m"
C_MAGENTA="\033[1;35m"
C_WHITE="\033[1;37m"
C_GRAY="\033[0;90m"

cleanup() {
    tput cnorm 2>/dev/null || printf "\033[?25h"
    printf "${C_RESET}\n"
    clear
    exit 0
}
trap cleanup INT TERM

parse_server_intent() {
    local link="$1"
    if echo "$link" | grep -qE "^[0-9]+$"; then
        echo "roblox://placeId=$link"
    elif echo "$link" | grep -iq "linkCode="; then
        local code
        code=$(echo "$link" | grep -oE "linkCode=[a-zA-Z0-9_-]+" | cut -d'=' -f2)
        local pid
        pid=$(echo "$link" | grep -oE "games/[0-9]+" | cut -d'/' -f2)
        if [ -n "$pid" ] && [ -n "$code" ]; then
            echo "roblox://placeId=$pid&linkCode=$code"
        else
            echo "$link"
        fi
    elif echo "$link" | grep -iq "roblox://"; then
        echo "$link"
    else
        echo "roblox://placeId=$link"
    fi
}

get_all_installed_roblox() {
    local pkgs
    pkgs=$(pm list packages -3 2>/dev/null | sed 's/package://g' | grep -vE "^com.termux$" | tr -d '\r')
    if [ -z "$pkgs" ]; then
        pkgs=$(pm list packages --user all -3 2>/dev/null | sed 's/package://g' | grep -vE "^com.termux$" | tr -d '\r')
    fi
    if ! echo "$pkgs" | grep -q "com.roblox.client"; then
        pkgs=$(printf "com.roblox.client\n%s" "$pkgs")
    fi
    echo "$pkgs" | grep -vE "^$" | sort -u
}

list_selected_packages() {
    clear
    printf "${C_CYAN}┌── [ PACKAGES ĐÃ CẤU HÌNH ] ────────┐${C_RESET}\n"
    if [ ! -s "$CONF_FILE" ]; then
        printf " ${C_RED}[!] Chưa có package nào.${C_RESET}\n"
    else
        local idx=1
        while IFS='=' read -r pkg link || [ -n "$pkg" ]; do
            [ -z "$pkg" ] && continue
            printf " ${C_YELLOW}%d.${C_RESET} %s\n" "$idx" "$pkg"
            printf "    ${C_GRAY}Link: ${C_GREEN}%s${C_RESET}\n" "${link:0:30}"
            idx=$((idx + 1))
        done < "$CONF_FILE"
    fi
    printf "${C_CYAN}└────────────────────────────────────┘${C_RESET}\n"
    printf " ${C_GRAY}File cấu hình: %s${C_RESET}\n" "$CONF_FILE"
    printf "\n${C_WHITE}Bấm Enter để quay lại...${C_RESET}"
    read -r _
}

select_packages_assign_link() {
    clear
    local installed
    installed=$(get_all_installed_roblox)

    local i=1
    declare -A pkg_map
    for p in $installed; do
        printf "${C_MAGENTA}[%d]${C_RESET} ${C_CYAN}%s${C_RESET}\n" "$i" "$p"
        pkg_map[$i]="$p"
        i=$((i + 1))
    done
    printf "\n"

    while true; do
        printf "${C_GREEN}Select package name(0 - stop): ${C_RESET}"
        read -r sel
        [ "$sel" = "0" ] && break
        [ -z "$sel" ] && continue

        local chosen_pkg="${pkg_map[$sel]}"
        if [ -z "$chosen_pkg" ]; then
            chosen_pkg="$sel"
        fi

        printf "${C_WHITE}Nhập Place ID/Link cho ${C_YELLOW}%s${C_WHITE}: ${C_RESET}" "$chosen_pkg"
        read -r s_link
        if [ -n "$s_link" ]; then
            sed -i "/^$chosen_pkg=/d" "$CONF_FILE" 2>/dev/null
            echo "$chosen_pkg=$s_link" >> "$CONF_FILE"
            printf " ${C_GREEN}[✓] Đã lưu %s${C_RESET}\n\n" "$chosen_pkg"
        fi
    done

    printf "\n${C_WHITE}Hoàn tất cấu hình. Bấm Enter để tiếp tục...${C_RESET}"
    read -r _
}

auto_select_all_one_link() {
    clear
    printf "${C_CYAN}┌── [ GÁN TẤT CẢ CHUNG 1 LINK ] ──────┐${C_RESET}\n"
    local installed
    installed=$(get_all_installed_roblox)
    for p in $installed; do
        printf " ${C_GRAY}•${C_RESET} %s\n" "$p"
    done
    printf "${C_CYAN}└────────────────────────────────────┘${C_RESET}\n"

    printf "\n${C_WHITE}Nhập Place ID hoặc Link dùng chung: ${C_RESET}"
    read -r link
    [ -z "$link" ] && return

    > "$CONF_FILE"
    for p in $installed; do
        echo "$p=$link" >> "$CONF_FILE"
    done
    printf " ${C_GREEN}[✓] Đã gán tất cả package thành công!${C_RESET}\n"
    sleep 2
}

open_all_tabs() {
    clear
    printf "${C_CYAN}Mở tất cả tabs Roblox...${C_RESET}\n\n"
    if [ ! -s "$CONF_FILE" ]; then
        printf "${C_RED}[!] Danh sách trống. Hãy cấu hình mục 2 hoặc 4 trước!${C_RESET}\n"
        sleep 2
        return
    fi

    while IFS='=' read -r pkg link || [ -n "$pkg" ]; do
        [ -z "$pkg" ] && continue
        local intent_url
        intent_url=$(parse_server_intent "$link")
        printf " ${C_YELLOW}→ Mở %s...${C_RESET}\n" "$pkg"
        am start -p "$pkg" -a android.intent.action.VIEW -d "$intent_url" >/dev/null 2>&1
        sleep 8
    done
    printf "\n${C_GREEN}[✓] Đã mở toàn bộ tabs!${C_RESET}\n"
    sleep 2
}

apply_cookie_to_pkg() {
    local target_pkg="$1"
    local cookie_val="$2"

    am force-stop "$target_pkg" >/dev/null 2>&1
    local db_dir="/data/data/$target_pkg/app_webview/Default"
    mkdir -p "$db_dir"
    local db_path="$db_dir/Cookies"

    sqlite3 "$db_path" "CREATE TABLE IF NOT EXISTS cookies(creation_utc INTEGER NOT NULL, host_key TEXT NOT NULL, name TEXT NOT NULL, value TEXT NOT NULL, path TEXT NOT NULL, expires_utc INTEGER NOT NULL, is_secure INTEGER NOT NULL, is_httponly INTEGER NOT NULL, last_access_utc INTEGER NOT NULL, has_expires INTEGER NOT NULL, is_persistent INTEGER NOT NULL, priority INTEGER NOT NULL, encrypted_value BLOB DEFAULT '', samesite INTEGER NOT NULL, source_scheme INTEGER NOT NULL, source_port INTEGER NOT NULL, is_same_party INTEGER NOT NULL, PRIMARY KEY(host_key, name, path));" 2>/dev/null

    local now_epoch
    now_epoch=$(date +%s)
    local webkit_time=$(( (now_epoch + 11644473600) * 1000000 ))
    local expire_time=$(( webkit_time + 315360000000000 ))

    sqlite3 "$db_path" "DELETE FROM cookies WHERE name='.ROBLOSECURITY';" 2>/dev/null
    sqlite3 "$db_path" "INSERT OR REPLACE INTO cookies (creation_utc, host_key, name, value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent, priority, samesite, source_scheme, source_port, is_same_party) VALUES ($webkit_time, '.roblox.com', '.ROBLOSECURITY', '$cookie_val', '/', $expire_time, 1, 1, $webkit_time, 1, 1, 1, -1, 2, 443, 0);" 2>/dev/null

    local app_uid
    app_uid=$(stat -c "%u" "/data/data/$target_pkg" 2>/dev/null)
    if [ -n "$app_uid" ]; then
        chown -R "$app_uid:$app_uid" "/data/data/$target_pkg/app_webview" 2>/dev/null
        chmod 660 "$db_path" 2>/dev/null
    fi
}

login_via_cookie() {
    clear
    printf "${C_CYAN}┌── [ LOGIN VIA COOKIE ] ────────────┐${C_RESET}\n"
    printf " ${C_YELLOW} 1.${C_RESET} Nạp tự động từ file cookie.txt\n"
    printf " ${C_YELLOW} 2.${C_RESET} Chọn package và nhập cookie\n"
    printf "${C_CYAN}└────────────────────────────────────┘${C_RESET}\n"
    printf " ${C_GRAY}Vị trí: %s${C_RESET}\n" "$COOKIE_INPUT_FILE"
    printf "\n${C_WHITE}Chọn phương thức: ${C_RESET}"
    read -r method

    if [ "$method" = "1" ]; then
        if [ ! -s "$COOKIE_INPUT_FILE" ]; then
            printf " ${C_RED}[!] File %s trống hoặc chưa có dữ liệu!${C_RESET}\n" "$COOKIE_INPUT_FILE"
            sleep 2
            return
        fi

        local installed
        installed=$(get_all_installed_roblox)
        local count=0

        while IFS= read -r line || [ -n "$line" ]; do
            local clean_line
            clean_line=$(echo "$line" | tr -d '\r' | xargs)
            [ -z "$clean_line" ] && continue

            count=$((count + 1))
            local target_pkg
            target_pkg=$(echo "$installed" | sed -n "${count}p")
            if [ -n "$target_pkg" ]; then
                apply_cookie_to_pkg "$target_pkg" "$clean_line"
                printf " ${C_GREEN}[✓] Dòng %d -> Gán vào %s${C_RESET}\n" "$count" "$target_pkg"
            fi
        done < "$COOKIE_INPUT_FILE"

        printf "\n${C_GREEN}[✓] Hoàn tất nạp danh sách cookies!${C_RESET}\n"
        sleep 2
    else
        local installed
        installed=$(get_all_installed_roblox)
        local i=1
        declare -A pkg_map
        for p in $installed; do
            printf "${C_MAGENTA}[%d]${C_RESET} ${C_CYAN}%s${C_RESET}\n" "$i" "$p"
            pkg_map[$i]="$p"
            i=$((i + 1))
        done
        printf "\n"

        while true; do
            printf "${C_GREEN}Select package name(0 - stop): ${C_RESET}"
            read -r sel
            [ "$sel" = "0" ] && break
            [ -z "$sel" ] && continue

            local chosen_pkg="${pkg_map[$sel]}"
            if [ -z "$chosen_pkg" ]; then
                chosen_pkg="$sel"
            fi

            printf "${C_WHITE}Dán chuỗi Cookie cho ${C_YELLOW}%s${C_WHITE}: ${C_RESET}" "$chosen_pkg"
            read -r cookie_input
            if [ -n "$cookie_input" ]; then
                apply_cookie_to_pkg "$chosen_pkg" "$cookie_input"
                printf " ${C_GREEN}[✓] Đã login cookie vào %s!${C_RESET}\n\n" "$chosen_pkg"
            fi
        done
    fi
}

logout_roblox() {
    clear
    local installed
    installed=$(get_all_installed_roblox)
    local i=1
    declare -A pkg_map
    for p in $installed; do
        printf "${C_MAGENTA}[%d]${C_RESET} ${C_CYAN}%s${C_RESET}\n" "$i" "$p"
        pkg_map[$i]="$p"
        i=$((i + 1))
    done
    printf " ${C_MAGENTA}[A]${C_RESET} ${C_YELLOW}Logout TẤT CẢ${C_RESET}\n\n"

    while true; do
        printf "${C_GREEN}Select package name to logout(0 - stop): ${C_RESET}"
        read -r choice
        [ "$choice" = "0" ] && break
        [ -z "$choice" ] && continue

        if [ "$choice" = "A" ] || [ "$choice" = "a" ]; then
            for p in $installed; do
                am force-stop "$p" >/dev/null 2>&1
                rm -rf "/data/data/$p/app_webview" "/data/data/$p/shared_prefs" 2>/dev/null
            done
            printf " ${C_GREEN}[✓] Đã logout toàn bộ!${C_RESET}\n"
            break
        else
            local chosen_pkg="${pkg_map[$choice]}"
            if [ -z "$chosen_pkg" ]; then
                chosen_pkg="$choice"
            fi
            am force-stop "$chosen_pkg" >/dev/null 2>&1
            rm -rf "/data/data/$chosen_pkg/app_webview" "/data/data/$chosen_pkg/shared_prefs" 2>/dev/null
            printf " ${C_GREEN}[✓] Đã logout %s!${C_RESET}\n\n" "$chosen_pkg"
        fi
    done
    sleep 1
}

export_cookies() {
    clear
    printf "${C_CYAN}┌── [ EXPORT COOKIES ] ──────────────┐${C_RESET}\n"
    local installed
    installed=$(get_all_installed_roblox)
    > "$EXPORT_FILE"
    local count=0

    for p in $installed; do
        local db_path="/data/data/$p/app_webview/Default/Cookies"
        [ ! -f "$db_path" ] && db_path="/data/data/$p/app_webview/Cookies"

        local c_val=""
        if [ -f "$db_path" ]; then
            c_val=$(sqlite3 "$db_path" "SELECT value FROM cookies WHERE name='.ROBLOSECURITY' LIMIT 1;" 2>/dev/null)
        fi

        if [ -n "$c_val" ]; then
            echo "[$p]: $c_val" >> "$EXPORT_FILE"
            printf " ${C_GREEN}[✓]${C_WHITE} %s${C_RESET}\n" "$p"
            count=$((count + 1))
        else
            printf " ${C_GRAY}[-] %s (Trống)${C_RESET}\n" "$p"
        fi
    done
    printf "${C_CYAN}└────────────────────────────────────┘${C_RESET}\n"
    printf " ${C_GREEN}[✓] Đã lưu %d cookies vào: %s${C_RESET}\n" "$count" "$EXPORT_FILE"
    printf "\n${C_WHITE}Bấm Enter để tiếp tục...${C_RESET}"
    read -r _
}

check_in_game_status() {
    local target_pkg="$1"
    local pid="$2"

    if [ -z "$pid" ]; then
        echo "CRASHED"
        return
    fi

    local focus
    focus=$(dumpsys window 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp")
    if echo "$focus" | grep -iqE "(launcher|home|recents)"; then
        echo "DISCONNECTED"
        return
    fi

    local log_dir="/data/data/$target_pkg/files/logs"
    [ ! -d "$log_dir" ] && log_dir="/sdcard/Android/data/$target_pkg/files/logs"
    if [ -d "$log_dir" ]; then
        local latest_log
        latest_log=$(ls -t "$log_dir"/*.txt 2>/dev/null | head -n 1)
        if [ -f "$latest_log" ]; then
            local last_status
            last_status=$(grep -iE "(Game ended|Disconnecting from server|Connection lost|Game joined|Game loaded)" "$latest_log" 2>/dev/null | tail -n 1)
            if [ -n "$last_status" ]; then
                if echo "$last_status" | grep -iqE "(Game ended|Disconnecting from server|Connection lost)"; then
                    echo "DISCONNECTED"
                    return
                fi
            fi
        fi
    fi

    local logcat_last
    logcat_last=$(logcat -d 2>/dev/null | grep -iE "(Game ended|User requested leave|leaveGame|OnDisconnection|Lost connection|Disconnected from|ErrorPrompt)" | tail -n 1)
    if [ -n "$logcat_last" ]; then
        echo "DISCONNECTED"
        return
    fi

    echo "INGAME"
}

rejoin_countdown() {
    local reason="$1"
    local delay=25
    for ((cd=delay; cd>0; cd--)); do
        printf "\033[H"
        printf "${C_CYAN}┌── [ PHÁT HIỆN THOÁT GAME ] ────────┐${C_RESET}\033[K\n"
        printf "│ ${C_RED}%-34s${C_RESET} │\033[K\n" "$reason"
        printf "│ ${C_YELLOW}Tự động Rejoin sau: %2ds...          ${C_RESET}│\033[K\n" "$cd"
        printf "│ ${C_WHITE}[Ctrl + C] ngay để DỪNG tool        ${C_RESET}│\033[K\n"
        printf "${C_CYAN}└────────────────────────────────────┘${C_RESET}\033[K\n"
        sleep 1
    done
}

start_auto_rejoin() {
    clear
    if [ ! -s "$CONF_FILE" ]; then
        printf "${C_RED}[!] Danh sách package trống! Hãy cấu hình mục 2 hoặc 4 trước.${C_RESET}\n"
        sleep 2
        return
    fi

    printf "${C_WHITE}Thời gian tự động reset (phút) [30]: ${C_RESET}"
    read -r interval_input
    local reset_min="${interval_input:-30}"
    local max_runtime=$((reset_min * 60))

    tput civis 2>/dev/null || printf "\033[?25l"
    clear

    declare -A start_times
    declare -A crash_counts

    logcat -c 2>/dev/null

    while IFS='=' read -r pkg link || [ -n "$pkg" ]; do
        [ -z "$pkg" ] && continue
        start_times[$pkg]=$(date +%s)
        crash_counts[$pkg]=0
        local intent_url
        intent_url=$(parse_server_intent "$link")
        am force-stop "$pkg" >/dev/null 2>&1
        input keyevent 4 >/dev/null 2>&1
        sleep 1
        am start -p "$pkg" -a android.intent.action.VIEW -d "$intent_url" >/dev/null 2>&1
    done < "$CONF_FILE"

    local warmup_time=20
    for ((w=warmup_time; w>0; w--)); do
        printf "\033[H"
        printf "${C_CYAN}┌── [ ROBLOX AUTO-REJOIN ] ──────────┐${C_RESET}\033[K\n"
        printf "│ ${C_YELLOW}Đang khởi động & vào game (${w}s)...${C_RESET} │\033[K\n"
        printf "${C_CYAN}└────────────────────────────────────┘${C_RESET}\033[K\n"
        sleep 1
    done
    logcat -c 2>/dev/null

    while true; do
        printf "\033[H"
        printf "${C_CYAN}┌── [ ROBLOX IN-GAME MONITOR ] ──────┐${C_RESET}\033[K\n"
        local now
        now=$(date +%s)

        while IFS='=' read -r pkg link || [ -n "$pkg" ]; do
            [ -z "$pkg" ] && continue
            local pid
            pid=$(pidof "$pkg" | awk '{print $1}')
            local p_start="${start_times[$pkg]:-$now}"
            local elapsed=$((now - p_start))
            local remain=$((max_runtime - elapsed))
            [ "$remain" -lt 0 ] && remain=0

            local status_text
            local intent_url
            intent_url=$(parse_server_intent "$link")

            local state
            state=$(check_in_game_status "$pkg" "$pid")

            if [ "$state" = "CRASHED" ]; then
                status_text="${C_RED}VĂNG APP -> ĐỢI REJOIN${C_RESET}"
                crash_counts[$pkg]=$(( ${crash_counts[$pkg]:-0} + 1 ))
                rejoin_countdown "App bị văng: ${pkg:0:18}"
                am force-stop "$pkg" >/dev/null 2>&1
                input keyevent 4 >/dev/null 2>&1
                sleep 1
                am start -p "$pkg" -a android.intent.action.VIEW -d "$intent_url" >/dev/null 2>&1
                start_times[$pkg]=$now
                logcat -c 2>/dev/null
            elif [ "$state" = "DISCONNECTED" ]; then
                status_text="${C_RED}THOÁT GAME -> ĐỢI REJOIN${C_RESET}"
                crash_counts[$pkg]=$(( ${crash_counts[$pkg]:-0} + 1 ))
                rejoin_countdown "Thoát game/Lobby: ${pkg:0:15}"
                am force-stop "$pkg" >/dev/null 2>&1
                input keyevent 4 >/dev/null 2>&1
                sleep 1
                am start -p "$pkg" -a android.intent.action.VIEW -d "$intent_url" >/dev/null 2>&1
                start_times[$pkg]=$now
                logcat -c 2>/dev/null
            elif [ "$max_runtime" -gt 0 ] && [ "$elapsed" -ge "$max_runtime" ]; then
                status_text="${C_YELLOW}HẾT CHU KỲ -> RESET${C_RESET}"
                am force-stop "$pkg" >/dev/null 2>&1
                input keyevent 4 >/dev/null 2>&1
                sleep 1
                am start -p "$pkg" -a android.intent.action.VIEW -d "$intent_url" >/dev/null 2>&1
                start_times[$pkg]=$now
                logcat -c 2>/dev/null
            else
                status_text="${C_GREEN}ĐANG TRONG GAME (PID: $pid)${C_RESET}"
            fi

            printf "│ ${C_YELLOW}%-18s${C_RESET} Rejoin: ${C_RED}%-2d${C_RESET}│\033[K\n" "${pkg:0:18}" "${crash_counts[$pkg]:-0}"
            printf "│ TT: %-33b │\033[K\n" "$status_text"
            printf "│ Reset sau: %02d:%02d                   │\033[K\n" $((remain/60)) $((remain%60))
            printf "├────────────────────────────────────┤\033[K\n"
        done < "$CONF_FILE"

        printf "${C_CYAN}└────────────────────────────────────┘${C_RESET}\033[K\n"
        printf " ${C_GRAY}[Ctrl + C] Quay lại Menu${C_RESET}\033[K\n"
        sleep 2
    done
}

while true; do
    clear
    printf "${C_CYAN}⚡ Shouko Menu${C_RESET}\n"
    printf "${C_CYAN}┌── Auto Rejoin ─────────────────────┐${C_RESET}\n"
    printf "│ ${C_YELLOW} 1${C_RESET}  Start auto rejoin              │\n"
    printf "${C_CYAN}├── Server Setup ────────────────────┤${C_RESET}\n"
    printf "│ ${C_YELLOW} 2${C_RESET}  Select package & assign link   │\n"
    printf "│ ${C_YELLOW} 3${C_RESET}  List selected packages         │\n"
    printf "│ ${C_YELLOW} 4${C_RESET}  Auto-select all with one link  │\n"
    printf "${C_CYAN}├── Tabs ────────────────────────────┤${C_RESET}\n"
    printf "│ ${C_YELLOW} 5${C_RESET}  Open all Roblox tabs           │\n"
    printf "${C_CYAN}├── Account / Cookie ────────────────┤${C_RESET}\n"
    printf "│ ${C_YELLOW} 6${C_RESET}  Login via cookie               │\n"
    printf "│ ${C_YELLOW} 7${C_RESET}  Logout Roblox                  │\n"
    printf "│ ${C_YELLOW} 8${C_RESET}  Export cookies from packages   │\n"
    printf "${C_CYAN}├── System ──────────────────────────┤${C_RESET}\n"
    printf "│ ${C_YELLOW} 9${C_RESET}  Xem toàn bộ package quét được  │\n"
    printf "│ ${C_RED}10${C_RESET}  Exit                           │\n"
    printf "${C_CYAN}└────────────────────────────────────┘${C_RESET}\n\n"

    printf "${C_MAGENTA}Enter choice: ${C_RESET}"
    read -r choice

    case "$choice" in
        1) start_auto_rejoin ;;
        2) select_packages_assign_link ;;
        3) list_selected_packages ;;
        4) auto_select_all_one_link ;;
        5) open_all_tabs ;;
        6) login_via_cookie ;;
        7) logout_roblox ;;
        8) export_cookies ;;
        9) 
            clear
            printf "${C_CYAN}Toàn bộ packages quét được:${C_RESET}\n\n"
            get_all_installed_roblox | while read -r p; do
                printf "  ${C_GREEN}•${C_RESET} %s\n" "$p"
            done
            printf "\n${C_WHITE}Bấm Enter để tiếp tục...${C_RESET}"
            read -r _
            ;;
        10) cleanup ;;
        *) sleep 1 ;;
    esac
done
