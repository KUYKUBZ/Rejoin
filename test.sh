#!/data/data/com.termux/files/usr/bin/bash

echo "-----------------"
echo "|     Rejoin    |"
echo "| [1] open      |"
echo "| [2] placeid   |"
echo "-----------------"

read -p "select: " choice

case "$choice" in
  1)
    echo "opening roblox"
    am start -a android.intent.action.VIEW \
      -d "https://www.roblox.com/share?code=ba26a95be5923142940ecd4d134123fe&type=Server" \
      -p zam.deltb
    ;;

  2)
    echo "ยังไม่ได้ใส่คำสั่ง Place ID"
    ;;

  *)
    echo "ไม่มีคำสั่งนี้"
    ;;
esac
