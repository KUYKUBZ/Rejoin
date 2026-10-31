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

# Get terminal width
WIDTH=$(tput cols 2>/dev/null || echo 40)

# Keep the box within the screen
[ "$WIDTH" -gt 50 ] && WIDTH=50
[ "$WIDTH" -lt 24 ] && WIDTH=24

INNER=$((WIDTH - 2))

# Print centered text inside the box
print_line() {
    text="$1"
    printf "%b" "$CYAN"
    printf "|"
    printf "%-*s" "$INNER" "$text"
    printf "|\n"
}

# Print top and bottom border
print_border() {
    printf "%b+" "$CYAN"
    printf '%*s' "$INNER" '' | tr ' ' '-'
    printf "+\n"
}

clear
print_border
print_line ""
print_line "A r i w a a"
print_line ""
print_border
print_line ""
print_line "[1] Open Roblox"
print_line "[2] Set Game Link"
print_line "[3] Exit"
print_line ""
print_border
printf "%b" "$RESET"

printf "${YELLOW}Select an option ${WHITE}> ${RESET}"
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
        echo "Invalid Game ID or Link."
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
