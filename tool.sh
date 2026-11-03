#!/data/data/com.termux/files/usr/bin/bash

clear

get_packages() {
    pm list packages | grep -Ei 'roblox|delt' | sed 's/package://'
}

create_file() {
    local filepath="$1"
    local filename="$2"
    local src="$3"

    mkdir -p "$filepath" || return 1

    printf '%s\n' "$src" > "${filepath%/}/$filename" || return 1

    echo "[SUCCESS] Created: ${filepath%/}/$filename"
}

data="/storage/emulated/0/Android/data/"
delta="/storage/emulated/0/Delta"

echo
echo " [1] Setup in $data"
echo " [2] Setup in $delta"
echo " [3] Install REJOIN [~/run] or [~/run --auto]"
echo

read -rp "Select method: " choice

case "$choice" in
    1)
        clear

        echo "Put your name file:"
        read -r name

        echo "Put your script:"
        read -r script

        # ค้นหาแพ็กเกจ Roblox
        while IFS= read -r pkg; do
            [ -z "$pkg" ] && continue

            Realfile="${data}${pkg}/files/gloop/Autoexecute"

            create_file "$Realfile" "$name" "$script"

        done < <(get_packages)
        sleep 1
        clear
        bash tool.sh
        ;;

    2)
        clear

        echo "Put your name file:"
        read -r name

        echo "Put your script:"
        read -r script

        create_file "$delta/Autoexecute" "$name" "$script"
        clear
        bash tool.sh
        ;;

    3)
        echo "Install REJOIN"
        sleep 2
        curl -sL https://raw.githubusercontent.com/KUYKUBZ/nefrejoin/refs/heads/main/rejoin.sh | bash
        ;;

    *)
        echo "Invalid option."
        sleep 1
        ;;
esac
