
#!/data/data/com.termux/files/usr/bin/bash

CONFIG="$HOME/.rejoin_link"

# Find Roblox packages
get_packages() {
  pm list packages | grep -i 'roblox' | sed 's/package://'
}

# Check if package has a Task
has_task() {
  /system/bin/dumpsys activity recents |
    grep -F "A=$1 " >/dev/null
}

while true; do
  clear
  echo "-----------------"
  echo "|    Rejoin     |"
  echo "| [1] Open      |"
  echo "| [2] Set Link  |"
  echo "| [3] Exit      |"
  echo "-----------------"

  read -r -p "Select: " choice

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
