
#!/data/data/com.termux/files/usr/bin/bash

CONFIG="$HOME/.rejoin_link"

echo "-----------------"
echo "|    Rejoin     |"
echo "| [1] open      |"
echo "| [2] set link  |"
echo "-----------------"

read -p "select: " choice

case "$choice" in

  1)
    echo "กำลังค้นหา Roblox..."

    packages=$(pm list packages | grep -i 'roblox' | sed 's/package://')

    if [ -z "$packages" ]; then
      echo "ไม่พบแอป Roblox"
      exit 1
    fi

    for package in $packages; do
      echo "กำลังเปิด $package"

      if [ -f "$CONFIG" ]; then
        url=$(cat "$CONFIG")

        am start -a android.intent.action.VIEW \
          -d "$url" \
          -p "$package"
      else
        am start -a android.intent.action.MAIN \
          -c android.intent.category.LAUNCHER \
          -p "$package"
      fi

      sleep 3
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
      exit 1
    fi

    echo "$url" > "$CONFIG"
    echo "บันทึกลิงก์เรียบร้อยแล้ว"
    ;;

  *)
    echo "ไม่มีคำสั่งนี้"
    ;;
esac
