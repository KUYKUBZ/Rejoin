#!/data/data/com.termux/files/usr/bin/bash

clear

CONFIG="$HOME/.rejoin_link"
INTERVAL=1200

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

# Check Task
has_task() {
    /system/bin/dumpsys activity recents 2>/dev/null |
        grep -F "A=$1 " >/dev/null
}

# Root force stop
force_stop() {
    su -c "am force-stop '$1'"
}

# Open application
open_app() {
    local package="$1"
    local url="$2"

    if [ -n "$url" ]; then
        am start -a android.intent.action.VIEW \
            -d "$url" -p "$package" >/dev/null 2>&1
    else
        am start -a android.intent.action.MAIN \
            -c android.intent.category.LAUNCHER \
            -p "$package" >/dev/null 2>&1
    fi
}

# Restart all screens
restart_all() {

    echo -e "\n${YELLOW}[RESTART] Restarting all screens...${RESET}"

    for package in $packages; do

        echo -e "${RED}[STOP]${WHITE} $package"

        force_stop "$package"

        sleep 3

        echo -e "${GREEN}[OPEN]${WHITE} $package"

        open_app "$package" "$url"

        sleep 10

    done

    echo -e "${GREEN}[SUCCESS] All screens restarted.${RESET}"

}

# Detect screen width
get_width() {
    WIDTH=$(tput cols 2>/dev/null)
    [[ "$WIDTH" =~ ^[0-9]+$ ]] || WIDTH=30
    [ "$WIDTH" -lt 10 ] && WIDTH=10
    [ "$WIDTH" -gt 50 ] && WIDTH=50
}

# Main menu
while true; do

    clear
    get_width

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
    line "       A r a i w a "
    line ""
    border
    line ""
    line " [1] Start Auto Rejoin"
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

            echo -e "${GREEN}[START] Opening all screens${RESET}"

            # Initial open
            for package in $packages; do

                echo "[OPEN] $package"

                open_app "$package" "$url"

                sleep 20

            done

            # Start 20-minute timer
            next_restart=$((SECONDS + INTERVAL))

            # Monitoring loop
            while true; do

                # Restart all screens every 20 minutes
                if [ "$SECONDS" -ge "$next_restart" ]; then

                    restart_all

                    next_restart=$((SECONDS + INTERVAL))

                fi

                # Check each package
                for package in $packages; do

                    if has_task "$package"; then

                        echo -e "${GREEN}[ONLINE]${WHITE} $package"

                    else

                        echo -e "${RED}[TASK NOT FOUND]${WHITE} $package"

                        echo "[REOPEN] $package"

                        open_app "$package" "$url"

                        sleep 10

                    fi

                done

                # Countdown
                remaining=$((next_restart - SECONDS))

                if [ "$remaining" -lt 0 ]; then
                    remaining=0
                fi
                
                printf "\r${CYAN}[NEXT RESTART] %02d:%02d${RESET}\n" \
                $((remaining / 60)) \
                $((remaining % 60))

                sleep 60

            done
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

            echo "Link saved successfully!"

            read -r -p "Press Enter..."

            ;;

        3)
            exit 0
            ;;

        *)
            echo "Invalid option."
            sleep 1
            ;;

    esac

done
