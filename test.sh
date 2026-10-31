
#!/data/data/com.termux/files/usr/bin/bash

CONFIG="$HOME/.rejoin_link"

while true; do
  echo "-----------------"
  echo "|    Rejoin     |"
  echo "| [1] open      |"
  echo "| [2] set link  |"
  echo "| [3] exit      |"
  echo "-----------------"

  read -p "select: " choice

  case "$choice" in

    1)
      echo "กำลังค้นหา Roblox..."

      packages=$(pm list packages | grep -i 'roblox' | sed 's/package://')

      if [ -z "$packages" ]; then
        echo "ไม่พบแอป Roblox"
        read -p "กด Enter เพื่อกลับเมนู..."
        continue
      fi

      url=""
      if [ -f "$CONFIG" ]; then
        url=$(cat "$CONFIG")
      fi

      for package in $packages; do
        echo "กำลังเปิด $package"

        if [ -n "$url" ]; then
          am start -a android.intent.action.VIEW \
            -d "$url" \
            -p "$package"
        else
          am start -a android.intent.action.MAIN \
            -c android.intent.category.LAUNCHER \
            -p "$package"
        fi

        clear
        sleep 10
      done

      echo "เริ่มตรวจสอบ Roblox..."
      echo "กด CTRL+C เพื่อหยุดตรวจสอบ"

      while true; do
        running=0

        for package in $packages; do
          if pidof "$package" >/dev/null 2>&1; then
            running=1
            break
          fi
        done

        if [ "$running" -eq 0 ]; then
          echo "Roblox ปิดหรือหยุดทำงานแล้ว!"
          break
        fi

        sleep 5
      done

      read -p "กด Enter เพื่อกลับเมนู..."
      ;;

    2)
      read -p "ใส่ Game ID หรือ Link: " game

      if [[ "$game" =~ ^[0-9]+$ ]]; then
        url="https://www.roblox.com/games/$game"
      elif [[ "$game" == http://* || "$game" == https://* ]]; then
        url="$game"
      else
        echo "Game ID หรือ Link ไม่ถูกต้อง"
        sleep 2
        clear
        continue
      fi

      echo "$url" > "$CONFIG"
      echo "บันทึกลิงก์เรียบร้อยแล้ว!"

      sleep 2
      clear
      ;;

    3)
      echo "ออกจากโปรแกรม"
      exit 0
      ;;

    *)
      echo "ไม่มีคำสั่งนี้"
      sleep 2
      clear
      ;;
  esac
done
