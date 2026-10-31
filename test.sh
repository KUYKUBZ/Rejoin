
#!/data/data/com.termux/files/usr/bin/bash

CONFIG="$HOME/.rejoin_link"

# ตรวจสอบแพ็กเกจ Roblox
get_packages() {
  pm list packages | grep -i 'roblox' | sed 's/package://'
}

# ตรวจสอบว่าแพ็กเกจมี Task หรือไม่
has_task() {
  /system/bin/dumpsys activity recents |
    grep -F "A=$1 " >/dev/null
}

while true; do
  clear
  echo "-----------------"
  echo "|    Rejoin     |"
  echo "| [1] open      |"
  echo "| [2] set link  |"
  echo "| [3] exit      |"
  echo "-----------------"

  read -r -p "select: " choice

  case "$choice" in
    1)
      packages=$(get_packages)

      if [ -z "$packages" ]; then
        echo "ไม่พบแอป Roblox"
        read -r -p "กด Enter..."
        continue
      fi

      url=""
      [ -f "$CONFIG" ] && url=$(cat "$CONFIG")

      for package in $packages; do
        echo "กำลังเปิด $package"

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

      echo "เริ่มตรวจสอบ Task..."
      while true; do
        for package in $packages; do
          if has_task "$package"; then
            echo "[เปิดอยู่] $package"
          else
            echo "[ไม่พบ Task] กำลังเปิด $package"

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
      read -r -p "ใส่ Game ID หรือ Link: " game

      if [[ "$game" =~ ^[0-9]+$ ]]; then
        url="https://www.roblox.com/games/$game"
      elif [[ "$game" == http://* || "$game" == https://* ]]; then
        url="$game"
      else
        echo "Game ID หรือ Link ไม่ถูกต้อง"
        read -r -p "กด Enter..."
        continue
      fi

      echo "$url" > "$CONFIG"
      echo "บันทึกลิงก์เรียบร้อยแล้ว!"
      read -r -p "กด Enter เพื่อกลับเมนู..."
      ;;

    3)
      exit 0
      ;;

    *)
      echo "เลือกเมนูไม่ถูกต้อง"
      sleep 1
      ;;
  esac
done
