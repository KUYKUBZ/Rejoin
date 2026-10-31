
#!/data/data/com.termux/files/usr/bin/bash

clear

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
    local package="$1"

    pidof "$package" >/dev/null 2>&1
}

# Open Roblox
open_package() {
    local package="$1"
    local url="$2"

    echo -e "${CYAN}[OPEN] $package${RESET}"

    if [ -n "$url" ]; then

        am start -a android.intent.action.VIEW \
            -d "$url" \
            -p "$package"

    else

        monkey -p "$package" 1

    fi
}

# Force stop
stop_package() {
    local package="$1"

    echo -e "${RED}[FORCE STOP] $package${RESET}"

    if su -c "am force-stop '$package'"; then
        echo -e "${GREEN}[STOPPED] $package${RESET}"
        sleep 3
        return 0
    else
        echo -e "${RED}[ERROR] Cannot force stop $package${RESET}"
        return 1
    fi
}

# Wait for Roblox process
wait_for_game() {
    local package="$1"
    local timeout=120
    local elapsed=0

    echo -e "${YELLOW}[WAIT] Checking Roblox process...${RESET}"

    while [ "$elapsed" -lt "$timeout" ]; do

        if is_running "$package"; then

            echo -e "${GREEN}[APP RUNNING] $package${RESET}"

            return 0
        fi

        sleep 2
        elapsed=$((elapsed + 2))

        printf "\r${YELLOW}[WAIT] %s / %s seconds${RESET}" \
            "$elapsed" "$timeout"

    done

    echo
    echo -e "${RED}[TIMEOUT] Process not found${RESET}"

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
        echo -e "${CYAN}================================${RESET}"
        echo -e "${WHITE}[ATTEMPT $attempt]${RESET}"
        echo -e "${WHITE}[PACKAGE] $package${RESET}"
        echo -e "${CYAN}================================${RESET}"

        # Open Roblox
        open_package "$package" "$url"

        # Check process
        if wait_for_game "$package"; then

            echo
            echo -e "${GREEN}[PROCESS DETECTED]${RESET}"
            echo "Roblox process is running."
            echo "Game server connection is NOT verified."

            return 0

        fi

        # Process not found
        echo
        echo -e "${RED}[PROCESS NOT FOUND]${RESET}"
        echo "[RESTART] Restarting Roblox..."

        # Force stop
        if ! stop_package "$package"; then
            echo "[ERROR] Root permission required."
            return 1
        fi

        sleep 2

    done
}

# Main menu
while true; do

    clear

    echo -e "${CYAN}+------------------------------+${RESET}"
    echo -e "${CYAN}|${WHITE}          A R I W A A         ${CYAN}|${RESET}"
    echo -e "${CYAN}|                              |${RESET}"
    echo -e "${CYAN}|${WHITE} [1] Open Roblox              ${CYAN}|${RESET}"
    echo -e "${CYAN}|${WHITE} [2] Set Game Link            ${CYAN}|${RESET}"
    echo -e "${CYAN}|${WHITE} [3] Exit                     ${CYAN}|${RESET}"
    echo -e "${CYAN}+------------------------------+${RESET}"

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
            echo -e "${GREEN}Found packages:${RESET}"
            echo "$packages"

            for package in $packages; do

                auto_rejoin "$package" "$url"

            done

            echo
            echo "Finished."
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

            echo -e "${GREEN}Game Link saved successfully!${RESET}"

            read -r -p "Press Enter..."

            ;;

        3)

            echo "Exiting..."
            exit 0

            ;;

        *)

            echo -e "${RED}Invalid option.${RESET}"
            sleep 1

            ;;

    esac

done
