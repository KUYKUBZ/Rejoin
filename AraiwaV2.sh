
#!/data/data/com.termux/files/usr/bin/bash

CONFIG="$HOME/.rejoin_link"
MAP="$HOME/.ariwaa_map"
AUTOEXE="/storage/emulated/0/Delta/Autoexecute"
WORKSPACE="/storage/emulated/0/Delta/Workspace"
STATUS_DIR="$WORKSPACE/Ariwaa"
LOG="$HOME/ariwaa_errors.log"
COOLDOWN="$HOME/.ariwaa_cooldown"

mkdir -p "$AUTOEXE" "$STATUS_DIR"
touch "$LOG" "$COOLDOWN"

CYAN='\033[1;36m'
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
RESET='\033[0m'

get_packages() {
    pm list packages |
        sed 's/package://' |
        grep -Ei 'roblox|delt' |
        sort -u
}

valid_package() {
    [[ "$1" =~ ^[a-zA-Z0-9._]+$ ]]
}

get_url() {
    if [ -f "$CONFIG" ]; then
        cat "$CONFIG"
    fi
}

open_package() {
    local package="$1"
    local url
    url=$(get_url)

    valid_package "$package" || return 1

    echo "Opening $package"

    if [ -n "$url" ]; then
        am start -a android.intent.action.VIEW \
            -d "$url" -p "$package"
    else
        monkey -p "$package" 1
    fi
}

force_restart() {
    local package="$1"

    valid_package "$package" || return 1

    echo -e "${YELLOW}RESTART: $package${RESET}"

    if ! su -c "am force-stop $package"; then
        echo "FORCE STOP FAILED: $package" >> "$LOG"
        return 1
    fi

    sleep 3
    open_package "$package"
}

create_api() {
    cat > "$AUTOEXE/api.txt" <<'LUA'
local Players = game:GetService("Players")

local function log(msg)
    print("[ARIWAA] " .. tostring(msg))
end

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local player = Players.LocalPlayer

while not player do
    task.wait(1)
    player = Players.LocalPlayer
end

local folder = "Ariwaa"

local function prepareFolder()
    pcall(function()
        if not isfolder(folder) then
            makefolder(folder)
        end
    end)
end

prepareFolder()

local file = folder .. "/" .. tostring(player.UserId) .. "_Status.txt"

local function heartbeat()
    local state = "IN GAME"

    if not player or not player.Parent then
        state = "OFFLINE"
    end

    local content =
        state .. "\n" ..
        tostring(player.UserId) .. "\n" ..
        tostring(os.time())

    local success, err = pcall(function()
        writefile(file, content)
    end)

    if not success then
        warn("[ARIWAA] WRITE ERROR: " .. tostring(err))
    end

    return success
end

log("HEARTBEAT STARTED: " .. tostring(player.UserId))

while true do
    heartbeat()
    task.wait(5)
end
LUA

    echo "API created: $AUTOEXE/api.txt"
    echo "Make sure Delta executes this file."
}

setup_map() {
    echo
    echo "=== PACKAGE LIST ==="

    local packages
    packages=$(get_packages)

    if [ -z "$packages" ]; then
        echo "No packages found"
        return
    fi

    echo "$packages"
    echo

    touch "$MAP"

    while true; do
        read -r -p "Package (Enter to finish): " package
        [ -z "$package" ] && break

        if ! valid_package "$package"; then
            echo "Invalid package"
            continue
        fi

        read -r -p "Roblox User ID: " uid

        if [[ ! "$uid" =~ ^[0-9]+$ ]]; then
            echo "Invalid User ID"
            continue
        fi

        grep -v "^${package}|" "$MAP" > "$MAP.tmp"
        mv "$MAP.tmp" "$MAP"

        echo "$package|$uid" >> "$MAP"
        echo "Saved: $package -> $uid"
    done
}

get_last_restart() {
    local package="$1"
    local value

    value=$(awk -F'|' -v p="$package" '$1==p {v=$2} END {print v}' "$COOLDOWN")
    echo "${value:-0}"
}

set_last_restart() {
    local package="$1"
    local now="$2"

    grep -v "^${package}|" "$COOLDOWN" > "$COOLDOWN.tmp"
    echo "$package|$now" >> "$COOLDOWN.tmp"
    mv "$COOLDOWN.tmp" "$COOLDOWN"
}

check_one() {
    local package="$1"
    local uid="$2"
    local file="$STATUS_DIR/${uid}_Status.txt"
    local now timestamp diff status file_uid
    now=$(date +%s)

    if [ ! -f "$file" ]; then
        echo -e "${RED}API MISSING${RESET} | $package | $uid"
        return 1
    fi

    status=$(sed -n '1p' "$file" | tr -d '\r')
    file_uid=$(sed -n '2p' "$file" | tr -d '\r')
    timestamp=$(sed -n '3p' "$file" | tr -cd '0-9')

    if [[ "$file_uid" != "$uid" || ! "$timestamp" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}API ERROR${RESET} | $package | $uid"
        return 1
    fi

    diff=$((now - timestamp))

    if (( diff >= 0 && diff <= 15 )); then
        echo -e "${GREEN}API ONLINE${RESET} | $package | $uid | $status"
        return 0
    fi

    echo -e "${RED}API OFFLINE${RESET} | $package | $uid | ${diff}s"
    return 1
}

monitor() {
    if [ ! -s "$MAP" ]; then
        echo "Please setup Package mapping first"
        return
    fi

    echo "ARIWAA MONITOR STARTED"
    echo "Press CTRL+C to stop"

    while true; do
        clear
        echo "========== ARIWAA MONITOR =========="
        echo "Time: $(date)"
        echo

        while IFS='|' read -r package uid; do
            [ -z "$package" ] && continue
            [ -z "$uid" ] && continue

            if ! check_one "$package" "$uid"; then
                now=$(date +%s)
                last=$(get_last_restart "$package")
                elapsed=$((now - last))

                if (( elapsed >= 60 )); then
                    set_last_restart "$package" "$now"
                    force_restart "$package"
                else
                    echo "Restart cooldown: $package (${elapsed}s)"
                fi
            fi

        done < "$MAP"

        echo
        echo "Next check: 5 seconds"
        sleep 5
    done
}

while true; do
    clear

    echo -e "${CYAN}================================${RESET}"
    echo -e "${WHITE}          ARIWAA${RESET}"
    echo -e "${CYAN}================================${RESET}"
    echo
    echo "[1] Open Roblox"
    echo "[2] Set Game Link"
    echo "[3] Setup API"
    echo "[4] Setup Package Mapping"
    echo "[5] Monitor API / Auto Rejoin"
    echo "[6] Exit"
    echo

    read -r -p "Select: " choice

    case "$choice" in
        1)
            packages=$(get_packages)

            if [ -z "$packages" ]; then
                echo "No Roblox packages found"
            else
                while IFS= read -r package; do
                    [ -z "$package" ] && continue
                    open_package "$package"
                    sleep 20
                done <<< "$packages"
            fi

            read -r -p "Press Enter..."
            ;;

        2)
            read -r -p "Enter Game ID or Link: " game

            if [[ "$game" =~ ^[0-9]+$ ]]; then
                echo "roblox://experiences/start?placeId=$game" > "$CONFIG"
            elif [[ "$game" == http://* || "$game" == https://* || "$game" == roblox://* ]]; then
                echo "$game" > "$CONFIG"
            else
                echo "Invalid link"
            fi

            read -r -p "Press Enter..."
            ;;

        3)
            create_api
            read -r -p "Press Enter..."
            ;;

        4)
            setup_map
            read -r -p "Press Enter..."
            ;;

        5)
            monitor
            ;;

        6)
            exit 0
            ;;

        *)
            echo "Invalid option"
            sleep 1
            ;;
    esac
done
