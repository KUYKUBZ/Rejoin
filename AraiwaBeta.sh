#!/data/data/com.termux/files/usr/bin/bash

PLACE_ID="132929771812494"
NOKA_DIR="$HOME/Noka"
HEARTBEAT_DIR="$NOKA_DIR/heartbeats"

REFRESH=2
REJOIN_TIME=420 # configurado no menu; valor em segundos
DISCONNECT_CONFIRM=2

mkdir -p "$HEARTBEAT_DIR"

RESET='\033[0m'
BOLD='\033[1m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
ORANGE='\033[38;5;208m'
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'

banner() {
    clear
    echo -e "${RED}${BOLD}"
    echo " ██████╗ ██╗   ██╗███████╗████████╗"
    echo "██╔════╝ ██║   ██║██╔════╝╚══██╔══╝"
    echo "██║  ███╗██║   ██║███████╗   ██║   "
    echo "██║   ██║██║   ██║╚════██║   ██║   "
    echo "╚██████╔╝╚██████╔╝███████║   ██║   "
    echo " ╚═════╝  ╚═════╝ ╚══════╝   ╚═╝   "
    echo -e "${RESET}"
    echo -e "${BOLD}${YELLOW}              GUST REJOIN${RESET}"
    echo -e "${GRAY}============================================================${RESET}"
}
get_packages() {
    {
        command -v pm >/dev/null 2>&1 && pm list packages -3 2>/dev/null | sed 's/^package://'
        /system/bin/pm list packages -3 2>/dev/null | sed 's/^package://'
        printf '%s\\n' free.nokaA free.nokaB free.nokaC
    } | sort -fu | while IFS= read -r package; do
        [ -n "$package" ] || continue
        if pm list packages "$package" 2>/dev/null | grep -Fxq "package:$package" ||
           /system/bin/pm list packages "$package" 2>/dev/null | grep -Fxq "package:$package"; then
            printf '%s\\n' "$package"
        fi
    done
}

running() {
    pidof "$1" >/dev/null 2>&1
}

json_value() {
    local file="$1"
    local key="$2"

    [ -f "$file" ] || return

    sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$file" |
        head -n 1
}

json_number() {
    local file="$1"
    local key="$2"

    [ -f "$file" ] || return

    sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p" "$file" |
        head -n 1
}

heartbeat_file() {
    echo "$HEARTBEAT_DIR/$1.json"
}

open_game() {
    local package="$1"
    local result

    echo
    echo -e "${YELLOW}[OPEN]${RESET} $package — tentando entrar no Place ID $PLACE_ID"

    # Tentativa 1: deep link Roblox.
    result="$(am start -W -a android.intent.action.VIEW \\
        -d "roblox://placeId=$PLACE_ID" -p "$package" 2>&1)"
    echo "$result"
    sleep 5

    # Tentativa 2: link HTTPS do jogo, direcionado ao clone.
    result="$(am start -W -a android.intent.action.VIEW \\
        -d "https://www.roblox.com/games/$PLACE_ID" -p "$package" 2>&1)"
    echo "$result"
    sleep 5

    # Se os links não encaminharem ao jogo, tenta abrir a tela inicial.
    # Isso não garante que o clone entre na experiência automaticamente.
    result="$(am start -W -a android.intent.action.MAIN \\
        -c android.intent.category.LAUNCHER -p "$package" 2>&1)"
    echo "$result"
    sleep 8
}

recover() {
    local package="$1"

    echo
    echo -e "${RED}[RECOVERY]${RESET} $package"

    am force-stop "$package" >/dev/null 2>&1
    sleep 2

    open_game "$package"
}

format_time() {
    local s="$1"

    printf "%02d:%02d" "$((s / 60))" "$((s % 60))"
}

configure_settings() {
    local value
    echo
    echo -e "${BOLD}${YELLOW}CONFIGURAÇÃO${RESET}"
    read -r -p "Place ID do Roblox [$PLACE_ID]: " value
    if [ -n "$value" ]; then
        if [[ "$value" =~ ^[0-9]+$ ]]; then
            PLACE_ID="$value"
        else
            echo -e "${RED}Place ID inválido; mantendo $PLACE_ID.${RESET}"
        fi
    fi

    while true; do
        read -r -p "Intervalo de REJOIN em minutos [7]: " value
        value="${value:-7}"
        if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge 1 ] && [ "$value" -le 1440 ]; then
            REJOIN_TIME=$((value * 60))
            break
        fi
        echo -e "${RED}Digite um número entre 1 e 1440 minutos.${RESET}"
    done

    echo -e "${GREEN}Place ID:${RESET} $PLACE_ID"
    echo -e "${GREEN}Intervalo:${RESET} $((REJOIN_TIME / 60)) minuto(s)"
}

choose_clients() {
    local packages=()
    while IFS= read -r package; do
        [ -n "$package" ] && packages+=("$package")
    done < <(get_packages)

    if [ "${#packages[@]}" -eq 0 ]; then
        echo -e "${RED}Nenhum pacote com 'roblox' no nome foi encontrado.${RESET}"
        echo "Verifique se os clones estão instalados e se o Termux tem acesso ao comando pm."
        exit 1
    fi

    echo
    echo -e "${BOLD}${WHITE}CLONES ROBLOX DETECTADOS${RESET}"
    local i=1
    for package in "${packages[@]}"; do
        echo -e "${YELLOW}$i${RESET} - $package"
        ((i++))
    done
    echo
    echo "Digite os números dos clones que deseja manter ativos, separados por espaço."
    echo "Exemplo: 1 3 4  |  Digite 'todos' para selecionar todos."

    local choice
    while true; do
        read -r -p "Clones selecionados: " choice
        SELECTED=()
        if [ "$choice" = "todos" ] || [ "$choice" = "TODOS" ]; then
            SELECTED=("${packages[@]}")
            break
        fi
        local valid=1
        local -A seen=()
        for index in $choice; do
            if [[ ! "$index" =~ ^[0-9]+$ ]] || [ "$index" -lt 1 ] || [ "$index" -gt "${#packages[@]}" ]; then
                valid=0
                break
            fi
            if [ -z "${seen[$index]+x}" ]; then
                SELECTED+=("${packages[$((index - 1))]}")
                seen[$index]=1
            fi
        done
        if [ "$valid" -eq 1 ] && [ "${#SELECTED[@]}" -gt 0 ]; then
            break
        fi
        echo -e "${RED}Seleção inválida. Informe um ou mais números da lista.${RESET}"
    done

    echo
    echo -e "${GREEN}Clientes selecionados:${RESET}"
    printf ' • %s\n' "${SELECTED[@]}"
}
start_clients() {

    echo
    echo -e "${CYAN}${BOLD}Abrindo Roblox no Place ID $PLACE_ID...${RESET}"

    for package in "${SELECTED[@]}"; do
        echo -e "${GREEN}→${RESET} $package"
        open_game "$package"
        sleep 2
    done

    sleep 3
}

show_client() {

    local number="$1"
    local package="$2"
    local file
    local state
    local timestamp
    local sequence
    local player

    file="$(heartbeat_file "$package")"

    state="$(json_value "$file" "state")"
    timestamp="$(json_number "$file" "timestamp")"
    sequence="$(json_number "$file" "sequence")"
    player="$(json_value "$file" "player")"

    local age="-"

    if [[ "$timestamp" =~ ^[0-9]+$ ]]; then
        local now
        now="$(date +%s)"
        age=$((now - timestamp))

        [ "$age" -lt 0 ] && age=0
    fi

    local status="${RED}OFFLINE${RESET}"

    if running "$package"; then
        status="${GREEN}ONLINE${RESET}"
    fi

    case "$state" in
        active)
            state_text="${GREEN}ACTIVE${RESET}"
            ;;
        loading)
            state_text="${YELLOW}LOADING${RESET}"
            ;;
        teleporting)
            state_text="${CYAN}TELEPORTING${RESET}"
            ;;
        disconnected)
            state_text="${RED}DISCONNECTED${RESET}"
            ;;
        *)
            state_text="${GRAY}${state:-UNKNOWN}${RESET}"
            ;;
    esac

    echo
    echo -e "${WHITE}┌─ CLIENTE $number ────────────────────────────────────────┐${RESET}"
    echo -e "│ Package:   $package"
    echo -e "│ Status:    $status"
    echo -e "│ Estado:    $state_text"
    echo -e "│ Heartbeat: ${age}s atrás"
    echo -e "│ Sequence:  ${sequence:-0}"
    echo -e "│ Player:    ${player:-unknown}"
    echo -e "${WHITE}└───────────────────────────────────────────────────────────┘${RESET}"
}

main() {
    local countdown=$REJOIN_TIME

    declare -A disconnect_count

    while true; do

        banner

        echo -e "${BOLD}${YELLOW}GUST REJOIN${RESET}"
        echo -e "${GRAY}Place ID: $PLACE_ID${RESET}"

        local number=1

        for package in "${SELECTED[@]}"; do

            show_client "$number" "$package"

            file="$(heartbeat_file "$package")"
            state="$(json_value "$file" "state")"

            if [ "$state" = "disconnected" ]; then

                disconnect_count["$package"]=$(( ${disconnect_count[$package]:-0} + 1 ))

                if [ "${disconnect_count[$package]}" -ge "$DISCONNECT_CONFIRM" ]; then
                    recover "$package"
                    disconnect_count["$package"]=0
                fi

            else
                disconnect_count["$package"]=0
            fi

            ((number++))
        done

        echo
        echo -e "${GRAY}============================================================${RESET}"
        echo -e "${BOLD}${CYAN}PRÓXIMO REJOIN:${RESET} ${WHITE}$(format_time "$countdown")${RESET}"
        echo -e "${GRAY}No ciclo normal, todos os selecionados são fechados antes de reabrir.${RESET}"
        echo -e "${GRAY}Recovery utiliza force-stop somente em DISCONNECTED.${RESET}"
        echo -e "${GRAY}============================================================${RESET}"

        sleep "$REFRESH"

        countdown=$((countdown - REFRESH))

        if [ "$countdown" -le 0 ]; then

            echo
            echo -e "${RED}${BOLD}REJOIN: FECHANDO TODOS OS SELECIONADOS${RESET}"

            # Fecha todos os clones selecionados antes de reabrir qualquer um.
            for package in "${SELECTED[@]}"; do
                echo -e "${RED}Fechando:${RESET} $package"
                am force-stop "$package" >/dev/null 2>&1
            done

            # Aguarda o Android concluir o encerramento dos aplicativos.
            sleep 3

            # Reabre os clientes um por vez, respeitando a pausa.
            for package in "${SELECTED[@]}"; do
                echo -e "${YELLOW}Abrindo:${RESET} $package"
                open_game "$package"
                sleep 3
            done

            countdown=$REJOIN_TIME
            sleep 2
        fi
    done
}

banner
echo -e "${YELLOW}Iniciando GUST REJOIN...${RESET}"
sleep 1
configure_settings
choose_clients
start_clients
main
