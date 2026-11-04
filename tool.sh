#!/data/data/com.termux/files/usr/bin/bash

clear


get_packages() {
    pm list packages |
        grep -Ei 'roblox|delt' |
        sed 's/package://'
}

auto_resize() {
    local WIDTH="$1"
    local HEIGHT="$2"
    local pkg
    local TASK_ID
    local X=0 Y=0

    command -v su >/dev/null 2>&1 || {
        echo "[ERROR] Root not available"
        return 1
    }

    [[ "$WIDTH" =~ ^[0-9]+$ && "$HEIGHT" =~ ^[0-9]+$ ]] || {
        echo "[ERROR] Invalid size"
        return 1
    }

    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue

        echo "[FOUND] $pkg"

        TASK_ID=$(
            su -c 'dumpsys activity recents' 2>/dev/null |
            awk -v pkg="$pkg" '
                index($0, pkg) {
                    if (match($0, /#[0-9]+/)) {
                        print substr($0, RSTART+1, RLENGTH-1)
                        exit
                    }
                }
            '
        )

        if [[ ! "$TASK_ID" =~ ^[0-9]+$ ]]; then
            echo "[SKIP] Task not found: $pkg"
            continue
        fi

        local RIGHT=$((X + WIDTH))
        local BOTTOM=$((Y + HEIGHT))

        echo "[RESIZE] $pkg Task=$TASK_ID"

        su -c "am task resize $TASK_ID $X $Y $RIGHT $BOTTOM"

    done < <(get_packages)
}

emulated="/storage/emulated/0/"
mkdir -p "$emulated/DownloadConfig"

data="/storage/emulated/0/Android/data/"
delta="/storage/emulated/0/Delta"

echo
echo " [1] Setup in $data"
echo " [2] Setup in $delta"
echo " [3] load config by pastebin link to download"
echo " [4] Auto Resize"
echo " [5] Install REJOIN [~/run] or [~/run --auto]"
echo " [6] Exit"
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

            Realfile="${data}${pkg}/files/gloop/external/Autoexecute"

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
        read -rp "Pastebin link: " link
        read -rp "File name: " name
        
        mkdir -p "${emulated}DownloadConfig"
        
        [[ -z "$link" || -z "$name" ]] && {
            echo "[ERROR] Invalid input"
            return 1
        }
        
        curl -fL --retry 3 --connect-timeout 15 \
            -A "Mozilla/5.0" \
            "$link" \
            -o "${emulated}DownloadConfig/$name" || {
                echo "[ERROR] Download failed"
                rm -f "${emulated}DownloadConfig/$name"
                return 1
            }
        
        echo "[SUCCESS] Download complete"
        sleep 1
        clear
        bash tool.sh
        ;;

    4)
    read -rp "Width: " WIDTH
    read -rp "Height: " HEIGHT

    auto_resize "$WIDTH" "$HEIGHT"
    ;;
    
    5)
        echo "Install REJOIN"
        sleep 2
        curl -sL https://raw.githubusercontent.com/KUYKUBZ/nefrejoin/refs/heads/main/rejoin.sh | bash
        ;;
    6)
        exit 0
        ;;
    *)
        echo "Invalid option."
        sleep 1
        ;;
esac
