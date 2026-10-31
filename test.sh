
#!/data/data/com.termux/files/usr/bin/bash

echo "-----------------"
echo "|    Rejoin     |"
echo "| [1] open      |"
echo "| [2] placeid   |"
echo "-----------------"

read -p "select: " choice

case "$choice" in
  1)
    echo "กำลังค้นหาเกม..."

    packages=$(pm list packages | grep -Ei 'roblox|zam\.delt')

    if [ -z "$packages" ]; then
      echo "ไม่พบแอปที่ต้องการ"
    else
      count=$(echo "$packages" | wc -l)

      if [ "$count" -gt 1 ]; then
        echo "พบหลายแอป:"
        echo "$packages"
        echo "กรุณาเลือก Package ที่ต้องการ"
      else
        package=${packages#package:}
        echo "กำลังเปิด $package"
        am start -a android.intent.action.MAIN \
          -c android.intent.category.LAUNCHER \
          -p "$package"
      fi
    fi
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

    am start -a android.intent.action.VIEW -d "$url"
    ;;

  *)
    echo "ไม่มีคำสั่งนี้"
    ;;
esac
