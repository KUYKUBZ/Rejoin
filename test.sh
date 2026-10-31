
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
            -d "$url" -p "$package"
        else
          am start -a android.intent.action.MAIN \
            -c android.intent.category.LAUNCHER \
            -p "$package"
        fi

        sleep 10
        clear
      done

      echo "เริ่มตรวจสอบ Roblox..."
      echo "ตรวจสอบทุก 5 วินาที"
      echo "กด CTRL+C เพื่อหยุด"

      while true; do
        echo "-----------------"
        echo "กำลังตรวจสอบ Task..."

        tasks=$(/system/bin/dumpsys activity recents |
          grep -E 'Recent #[0-9]+: TaskRecord.*com\.roblox')

        if [ -z "$tasks" ]; then
          echo "ไม่พบ Roblox ใน Recent Tasks"
        else
          echo "$tasks"
        fi

        echo "-----------------"
        sleep 5
        clear
      done
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
