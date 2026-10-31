
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
        sed 's/package://'
}

# Get foreground activity
get_foreground() {
    dumpsys activity activities 2>/dev/null |
        grep -m 1 'mResumedActivity'
}

# Check foreground package
is_foreground() {
    local package="$1"
    local activity

    activity=$(get_foreground)

    echo "$activity" | grep -F "$package" >/dev/null
}

# Open Roblox
open_package() {
    local package="$1"
    local url="$2"

    echo -e "${CYAN}[OPEN] $package${RESET}"

    if [ -n "$url" ]; then
        am start -a android.intent.action.VIEW \
            -d "$url" -p "$package"
    else
        monkey -p "$package" 1
    fi
}

# Force stop Roblox
stop_package() {
    local package="$1"

    echo -e "${RED}[FORCE STOP] $package${RESET}"

    su -c "am force-stop $package"

    sleep 3
}

# Wait for app foreground
wait_for_foreground() {
    local package="$1"
    local timeout=120
    local elapsed=0

    echo -e "${YELLOW}[WAIT] Checking app...${RESET}"

    while [ "$elapsed" -lt "$timeout" ]; do

        if is_foreground "$package"; then
            echo -e "${GREEN}[APP OPEN] $package${RESET}"
            return 0
        fi

        sleep 2
        elapsed=$((elapsed + 2))

    done

    echo -e "${RED}[TIMEOUT] App not detected${RESET}"

    return 1
}

# Auto retry
auto_rejoin() {
    local package="$1"
    local url="$2"
    local attempt=0

    while true; do

        attempt=$((attempt + 1))

        echo
        echo -e "${CYAN}==============================${RESET}"
        echo "[ATTEMPT $attempt]"
        echo "[PACKAGE] $package"
        echo -e "${CYAN}==============================${RESET}"

        open_package "$package" "$url"

        if wait_for_foreground "$package"; then

            echo
            echo -e "${GREEN}[APP DETECTED]${RESET}"
            echo "Roblox is foreground."
            echo "Server connection is not verified."

            return 0

        fi

        echo -e "${RED}[NOT DETECTED] Restarting...${RESET}"

        stop_package "$package"

        sleep 2

    done
}

# Main menu
while true; do

    clear

    echo -e "${CYAN}+------------------------------+${RESET}"
    echo "|          A R I W A A         |"
    echo "|                              |"
    echo "| [1] Open Roblox              |"
    echo "| [2] Set Game Link            |"
    echo "| [3] Exit                     |"
    echo -e "${CYAN}+------------------------------+${RESET}"

    echo
    read -r -p "Select: " choice

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
            echo "Found packages:"
            echo "$packages"

            for package in $packages; do
                auto_rejoin "$package" "$url"
            done

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

            exit 0

            ;;

        *)

            echo -e "${RED}Invalid option.${RESET}"
            sleep 1

            ;;

    esac

done
