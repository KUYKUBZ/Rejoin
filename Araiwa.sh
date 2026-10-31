#!/data/data/com.termux/files/usr/bin/bash

clear

CONFIG="$HOME/.rejoin_link"

CYAN='\033[1;36m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
GREEN='\033[1;32m'
RESET='\033[0m'

# Find Roblox packages
get_packages() {
    pm list packages | grep -Ei 'roblox|delt' | sed 's/package://'
}

# Check if package has a Task
has_task() {
    /system/bin/dumpsys activity recents |
        grep -F "A=$1 " >/dev/null
}

# Force stop package
force_stop() {
    package="$1"

    echo -e "${YELLOW}[FORCE STOP]${RESET} $package"

    if su -c "am force-stop '$package'"; then
        echo -e "${GREEN}[STOP OK]${RESET} $package"
        return 0
    else
        echo -e "${RED}[STOP ERROR]${RESET} $package"
        return 1
    fi
}

# Open package
open_package() {
    package="$1"
    url="$2"

    force_stop "$package"

    sleep 2

    echo "[OPENING] $package"

    if [ -n "$url" ]; then
        am start -a android.intent.action.VIEW \
            -d "$url" -p "$package"
    else
        am start -a android.intent.action.MAIN \
            -c android.intent.category.LAUNCHER \
            -p "$package"
    fi

    sleep 10
}

while true; do

    clear

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

    border
    line ""
    line "       A r i w a a"
    line ""
    border
    line ""
    line " [1] Open Roblox"
    line " [2] Set Game Link"
    line " [3] Exit"
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

            echo ""
            echo "Found packages:"
            echo "$packages"
            echo ""

            # Open all packages
            for package in $packages; do
                open_package "$package" "$url"
            done

            echo ""
            echo "[MONITOR STARTED]"
            echo ""

            # Auto rejoin
            while true; do

                for package in $packages; do

                    if has_task "$package"; then
                        :
                    else
                        echo "[TASK NOT FOUND] $package"

                        open_package "$package" "$url"
                    fi

                done

                sleep 5

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
        
        4)
            exit 0
            ;;

        *)
            echo "Invalid option."
            sleep 1
            ;;

    esac

done
