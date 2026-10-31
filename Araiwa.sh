clear
#!/data/data/com.termux/files/usr/bin/bash

CONFIG="$HOME/.rejoin_link"

# Find Roblox packages
get_packages() {
  pm list packages | grep -Ei 'roblox|delt' | sed 's/package://'
}

# Check if package has a Task
has_task() {
  /system/bin/dumpsys activity recents |
    grep -F "A=$1 " >/dev/null
}

while true; do

clear

CYAN='\033[1;36m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# Detect screen width
WIDTH=$(tput cols 2>/dev/null)
[[ "$WIDTH" =~ ^[0-9]+$ ]] || WIDTH=30
[ "$WIDTH" -lt 10 ] && WIDTH=10
[ "$WIDTH" -gt 50 ] && WIDTH=50

INNER=$((WIDTH - 2))

# Draw border
border() {
    printf "${CYAN}+"
    printf '%*s' "$INNER" '' | tr ' ' '-'
    printf "+${RESET}\n"
}

# Draw text without overflowing
line() {
    printf "${CYAN}|${RESET}"
    printf "%-*.*s" "$INNER" "$INNER" "$1"
    printf "${CYAN}|${RESET}\n"
}

clear
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

      for package in $packages; do
        echo "Opening $package"

        if [ -n "$url" ]; then
          am start -a android.intent.action.VIEW \
            -d "$url" -p "$package"
        else
          am start -a android.intent.action.MAIN \
            -c android.intent.category.LAUNCHER \
            -p "$package"
        fi

        sleep 10
      done

      echo "Starting Task monitor..."

      while true; do
        for package in $packages; do
          if has_task "$package"; then
            echo "[Running] $package"
          else
            echo "[Task Not Found] Reopening $package"

            if [ -n "$url" ]; then
              am start -a android.intent.action.VIEW \
                -d "$url" -p "$package"
            else
              am start -a android.intent.action.MAIN \
                -c android.intent.category.LAUNCHER \
                -p "$package"
            fi

            sleep 10
          fi
        done

        sleep 5
      done
      ;;

    2)
      read -r -p "Enter Game ID or Link: " game

      if [[ "$game" =~ ^[0-9]+$ ]]; then
        url="https://www.roblox.com/games/$game"
      elif [[ "$game" == http://* || "$game" == https://* ]]; then
        url="$game"
      else
        echo "Invalid Game Link."
        read -r -p "Press Enter..."
        continue
      fi

      echo "$url" > "$CONFIG"
      echo "Link saved successfully!"
      read -r -p "Press Enter to return to menu..."
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
