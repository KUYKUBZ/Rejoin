#!/bin/bash
# ============================================================
#  Roblox Auto-Rejoin Script for Termux (Rooted Android)
#  Detection: Process + Logcat + Activity + CPU + Background
#  Extras: Notifications | Cooldown | Server Lock
#          Scheduled Restart | Color Logs | Landscape Support
# ============================================================

# ── CONFIGURATION ────────────────────────────────────────────

PLACE_ID="132929771812494"

SERVER_INSTANCE_ID=""

REJOIN_DELAY=5
CHECK_INTERVAL=20
LAUNCH_GRACE_PERIOD=40
MAX_LAUNCH_RETRIES=5

COOLDOWN_MAX_REJOINS=4
COOLDOWN_WINDOW_SECONDS=300
COOLDOWN_PAUSE_SECONDS=120

SCHEDULED_RESTART_INTERVAL=10800

TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
DISCORD_WEBHOOK_URL=""

LOG_FILE="$HOME/roblox_rejoin.log"
MAX_LOG_SIZE=5242880

# PID tracking
PID_FILE="$HOME/.roblox_rejoin.pid"
CHILD_PID_FILE="$HOME/.roblox_children.pid"

# How many consecutive bad checks before rejoining
# Prevents false positives from brief idle/loading moments
CONFIRM_THRESHOLD=2

# CPU freeze detection — samples taken, interval between them
CPU_SAMPLE_COUNT=3
CPU_SAMPLE_INTERVAL=2
CPU_MIN_TICK_DELTA=2

ACCOUNTS=(
  "com.roblox.clienv|Account1|$PLACE_ID"
  "com.roblox.clienw|Account2|$PLACE_ID"
  "com.roblox.clienx|Account3|$PLACE_ID"
)

ERROR_PATTERNS=(
  # --- Error Codes (Joining & In-Game) ---
  "Error Code: 0" "Error Code: 103" "Error Code: 110" 
  "Error Code: 256" "Error Code: 260" "Error Code: 261" 
  "Error Code: 262" "Error Code: 264" "Error Code: 266" 
  "Error Code: 267" "Error Code: 268" "Error Code: 271" 
  "Error Code: 272" "Error Code: 273" "Error Code: 274" 
  "Error Code: 275" "Error Code: 276" "Error Code: 277" 
  "Error Code: 278" "Error Code: 279" "Error Code: 280" 
  "Error Code: 282" "Error Code: 284" "Error Code: 285" 
  "Error Code: 286" "Error Code: 288" "Error Code: 290" 
  "Error Code: 291" "Error Code: 292"

  # --- Error Codes (Service & Platform) ---
  "Error Code: 400" "Error Code: 403" "Error Code: 429" 
  "Error Code: 517" "Error Code: 524" "Error Code: 525" 
  "Error Code: 528" "Error Code: 529" "Error Code: 533" 
  "Error Code: 769" "Error Code: 901" "Error Code: 1001"

  # --- Connection & Network Messages ---
  "Connection timed out" "Unable to connect" "Lost connection"
  "disconnected" "Network error" "socket error"
  "You have been disconnected" "Connection attempt failed"
  "HTTP error" "HttpError"

  # --- Game State & Kicks ---
  "kicked from" "teleport failed" "game has shut"
  "You have been kicked" "Player has been removed"
  "server has shut down" "shut down for maintenance"
)

# ── COLORS ───────────────────────────────────────────────────

setup_colors() {
  if [[ -t 1 ]]; then
    C_RESET="\033[0m";    C_BOLD="\033[1m"
    C_INFO="\033[0;36m";  C_OK="\033[0;32m"
    C_WARN="\033[0;33m";  C_ERROR="\033[0;31m"
    C_TIME="\033[2;37m";  C_LABEL="\033[1;34m"
    C_PKG="\033[0;34m";   C_VAL="\033[1;37m"
    C_DIM="\033[2;37m";   C_BANNER="\033[1;35m"
    C_NOTIF="\033[1;33m"
  else
    C_RESET="" C_BOLD="" C_INFO="" C_OK="" C_WARN="" C_ERROR=""
    C_TIME="" C_LABEL="" C_PKG="" C_VAL="" C_DIM="" C_BANNER=""
    C_NOTIF=""
  fi
}

# ── TERMINAL / LANDSCAPE ─────────────────────────────────────

get_term_width() { tput cols 2>/dev/null || echo 80; }

draw_separator() {
  local width char="${1:--}" color="${2:-$C_DIM}"
  width=$(get_term_width)
  printf "${color}"; printf '%*s' "$width" '' | tr ' ' "$char"
  printf "${C_RESET}\n"
}

draw_banner() {
  local width title sub pad
  width=$(get_term_width)
  title="  Roblox Auto-Rejoin Monitor  "
  sub="  Logcat + CPU + Activity + Background Detection  "
  draw_separator "═" "$C_BANNER"
  pad=$(( (width - ${#title}) / 2 ))
  printf "${C_BANNER}${C_BOLD}%*s%s${C_RESET}\n" "$pad" "" "$title"
  pad=$(( (width - ${#sub}) / 2 ))
  printf "${C_DIM}%*s%s${C_RESET}\n" "$pad" "" "$sub"
  draw_separator "═" "$C_BANNER"
}

# ── LOGGING ──────────────────────────────────────────────────

log() {
  local level="$1" raw_msg="$2" color="$3" label_str="${4:-}"
  local timestamp; timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local label_part=""
  [[ -n "$label_str" ]] && label_part="${C_LABEL}[${label_str}]${C_RESET} "
  printf "${C_TIME}[%s]${C_RESET} ${color}${C_BOLD}[%-5s]${C_RESET} %s%s\n" \
    "$timestamp" "$level" "$label_part" "${color}${raw_msg}${C_RESET}"
  echo "[$timestamp] [$level] ${label_str:+[$label_str] }$raw_msg" >> "$LOG_FILE"
}

info()  { log "INFO"  "$1" "$C_INFO"  "${2:-}"; }
ok()    { log "OK"    "$1" "$C_OK"    "${2:-}"; }
warn()  { log "WARN"  "$1" "$C_WARN"  "${2:-}"; }
error() { log "ERROR" "$1" "$C_ERROR" "${2:-}"; }

rotate_log() {
  [[ ! -f "$LOG_FILE" ]] && return
  local size; size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
  if (( size > MAX_LOG_SIZE )); then
    mv "$LOG_FILE" "${LOG_FILE}.old"
    info "Log rotated."
  fi
}

# ── NOTIFICATIONS ────────────────────────────────────────────

send_notification() {
  local msg="$1"
  if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TELEGRAM_CHAT_ID}" \
      -d "text=${msg}" \
      -d "parse_mode=Markdown" &>/dev/null &
  fi
  if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
    curl -s -X POST "$DISCORD_WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "{\"content\": \"${msg}\"}" &>/dev/null &
  fi
}

notify() {
  local label="$1" event="$2" details="${3:-}"
  local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
  printf "${C_NOTIF}  ↳ Notification: %s — %s${C_RESET}\n" "$label" "$event"
  send_notification "🎮 *Roblox Rejoin Monitor*
Account: \`${label}\`
Event: ${event}
${details:+Details: ${details}
}Time: ${ts}"
}

# ── ROOT & DEPS ───────────────────────────────────────────────

check_root() {
  if ! su -c "id" &>/dev/null; then
    error "Root access required. Grant Termux superuser permissions."; exit 1
  fi
  ok "Root access confirmed."
}

check_deps() {
  local missing=0
  for cmd in am pidof logcat ping; do
    if ! su -c "command -v $cmd" &>/dev/null; then
      error "Required tool '$cmd' not found."; missing=1
    fi
  done
  command -v curl &>/dev/null || warn "curl not found — notifications disabled. Install: pkg install curl"
  [[ $missing -eq 1 ]] && exit 1
  ok "All required tools found."
}

# ── PROCESS ──────────────────────────────────────────────────

is_running() {
  local pid; pid=$(su -c "pidof $1 2>/dev/null")
  [[ -n "$pid" ]]
}

get_pid() { su -c "pidof $1 2>/dev/null" | awk '{print $1}'; }
force_stop() { su -c "am force-stop $1" &>/dev/null; }

# ── INTERNET ─────────────────────────────────────────────────

has_internet() { ping -c 1 -W 3 8.8.8.8 &>/dev/null; }

wait_for_internet() {
  local label="${1:-System}" attempts=0
  while ! has_internet; do
    attempts=$((attempts + 1))
    warn "No internet (attempt $attempts) — retrying in 10s..." "$label"
    sleep 10
    if [[ $attempts -ge 36 ]]; then
      error "No internet after 6 minutes." "$label"
      notify "$label" "⚠️ No Internet" "Cannot reconnect after 6 minutes."
      return 1
    fi
  done
  ok "Internet connection restored." "$label"
}

# ── LAUNCH ───────────────────────────────────────────────────

build_url() {
  local url="roblox://experiences/start?placeId=$1"
  [[ -n "$SERVER_INSTANCE_ID" ]] && url="${url}&gameInstanceId=${SERVER_INSTANCE_ID}"
  echo "$url"
}

launch_game() {
  local pkg="$1" label="$2" place_id="$3"
  local url; url=$(build_url "$place_id")
  local retries=0

  while [[ $retries -lt $MAX_LAUNCH_RETRIES ]]; do
    info "Launching (attempt $((retries+1))/$MAX_LAUNCH_RETRIES)..." "$label"
    force_stop "$pkg"
    sleep 2

    su -c "am start \
      -a android.intent.action.VIEW \
      -d '$url' \
      --activity-clear-task \
      -p '$pkg'" &>/dev/null

    info "Waiting ${LAUNCH_GRACE_PERIOD}s for game to load..." "$label"
    sleep "$LAUNCH_GRACE_PERIOD"

    if is_running "$pkg"; then
      ok "Running (PID: $(get_pid "$pkg"))." "$label"
      return 0
    fi

    warn "Not running after launch — retrying..." "$label"
    retries=$((retries + 1))
    sleep 3
  done

  error "Failed to launch after $MAX_LAUNCH_RETRIES attempts." "$label"
  notify "$label" "❌ Launch Failed" "Could not start after $MAX_LAUNCH_RETRIES attempts."
  return 1
}

# ── DETECTION LAYER 1: LOGCAT ────────────────────────────────

detect_error_logcat() {
  local pkg="$1" label="$2" loglines
  loglines=$(su -c "
    pid=\$(pidof $pkg 2>/dev/null | awk '{print \$1}')
    [ -n \"\$pid\" ] && logcat -d -t 100 --pid=\$pid 2>/dev/null
  " 2>/dev/null)
  [[ -z "$loglines" ]] && return 1
  for pattern in "${ERROR_PATTERNS[@]}"; do
    if echo "$loglines" | grep -qi "$pattern"; then
      warn "Logcat matched: '$pattern'" "$label"; return 0
    fi
  done
  return 1
}

# ── DETECTION LAYER 2: ACTIVITY FOCUS ────────────────────────

detect_error_activity() {
  local pkg="$1" label="$2" focused
  focused=$(su -c "dumpsys window windows 2>/dev/null \
    | grep -i 'mCurrentFocus' \
    | grep -oP '(?<=\{)[^/]+' \
    | tr -d ' '" 2>/dev/null)
  if is_running "$pkg" && [[ -n "$focused" ]] && [[ "$focused" != "$pkg" ]]; then
    case "$focused" in
      com.android.systemui|android|com.google.android.*) return 1 ;;
      *) warn "Focus stolen by: $focused" "$label"; return 0 ;;
    esac
  fi
  return 1
}

# ── DETECTION LAYER 3: FROZEN CPU ────────────────────────────
# Takes multiple samples — ALL must show no movement to trigger.
# One active sample anywhere = process is alive, no rejoin.

detect_frozen_process() {
  local pkg="$1" label="$2"
  local pid; pid=$(su -c "pidof $pkg 2>/dev/null | awk '{print \$1}'")
  [[ -z "$pid" ]] && return 1

  local prev curr delta i frozen_count=0
  prev=$(su -c "awk '{print \$14+\$15}' /proc/$pid/stat 2>/dev/null")
  [[ -z "$prev" ]] && return 1

  for (( i=1; i<=CPU_SAMPLE_COUNT; i++ )); do
    sleep "$CPU_SAMPLE_INTERVAL"
    curr=$(su -c "awk '{print \$14+\$15}' /proc/$pid/stat 2>/dev/null")
    [[ -z "$curr" ]] && return 1   # Process died mid-check — let other layers catch it
    delta=$(( curr - prev ))
    if (( delta <= CPU_MIN_TICK_DELTA )); then
      frozen_count=$(( frozen_count + 1 ))
    else
      return 1   # Activity detected — definitely not frozen
    fi
    prev=$curr
  done

  if (( frozen_count >= CPU_SAMPLE_COUNT )); then
    warn "Process frozen — no CPU movement across $CPU_SAMPLE_COUNT samples." "$label"
    return 0
  fi
  return 1
}

# ── DETECTION LAYER 4: BACKGROUND SUSPENDED ──────────────────

detect_background_suspended() {
  local pkg="$1" label="$2" state proc_num
  state=$(su -c "dumpsys activity processes 2>/dev/null \
    | grep -A2 '$pkg' \
    | grep -i 'procState'" 2>/dev/null)
  proc_num=$(echo "$state" | grep -oP 'procState=\K[0-9]+' | head -1)
  if [[ -n "$proc_num" ]] && (( proc_num >= 14 )); then
    warn "App background-suspended (procState=$proc_num)." "$label"; return 0
  fi
  return 1
}

# ── DETECTION LAYER 5: WRONG FOREGROUND ACTIVITY ─────────────

detect_wrong_activity() {
  local pkg="$1" label="$2" top
  top=$(su -c "dumpsys activity top 2>/dev/null | grep 'ACTIVITY' | tail -1" 2>/dev/null)
  if is_running "$pkg" && [[ -n "$top" ]] && ! echo "$top" | grep -q "$pkg"; then
    warn "Roblox not in foreground activity stack." "$label"; return 0
  fi
  return 1
}

# ── CONFIRM THRESHOLD ────────────────────────────────────────
# Each account tracks its own bad-check streak in a temp file.
# Must fail CONFIRM_THRESHOLD times in a row to trigger rejoin.

err_count_file() { echo "/tmp/rbx_err_${1// /_}"; }
get_err_count()  { local f; f=$(err_count_file "$1"); [[ -f "$f" ]] && cat "$f" || echo 0; }
inc_err_count()  { echo $(( $(get_err_count "$1") + 1 )) > "$(err_count_file "$1")"; }
reset_err_count(){ echo 0 > "$(err_count_file "$1")"; }

# ── COMBINED DETECTION ───────────────────────────────────────

detect_problem() {
  local pkg="$1" label="$2"

  # Dead process — immediate, no threshold
  if ! is_running "$pkg"; then
    warn "Process is not running." "$label"
    reset_err_count "$label"
    return 0
  fi

  # Internet gone — immediate
  if ! has_internet; then
    warn "Internet lost." "$label"
    notify "$label" "🌐 Internet Lost" "Waiting for reconnection..."
    wait_for_internet "$label" || return 0
    # Rejoin after reconnect to ensure clean state
    return 0
  fi

  # Soft detection layers (all must fail before confirm threshold increments)
  local found=0
  if detect_error_logcat          "$pkg" "$label"; then found=1
  elif detect_error_activity      "$pkg" "$label"; then found=1
  elif detect_frozen_process      "$pkg" "$label"; then found=1
  elif detect_background_suspended "$pkg" "$label"; then found=1
  elif detect_wrong_activity      "$pkg" "$label"; then found=1
  fi

  if [[ $found -eq 1 ]]; then
    inc_err_count "$label"
    local count; count=$(get_err_count "$label")
    if (( count >= CONFIRM_THRESHOLD )); then
      warn "Problem confirmed ($count/$CONFIRM_THRESHOLD). Triggering rejoin." "$label"
      reset_err_count "$label"
      return 0
    else
      warn "Possible issue ($count/$CONFIRM_THRESHOLD) — waiting to confirm..." "$label"
      return 1   # Not rejoining yet
    fi
  fi

  reset_err_count "$label"
  return 1
}

# ── COOLDOWN ─────────────────────────────────────────────────

cd_file()      { echo "/tmp/rbx_cd_${1// /_}"; }
record_rejoin(){ echo "$(date +%s)" >> "$(cd_file "$1")"; }

is_in_cooldown() {
  local label="$1" f now ws count=0
  f=$(cd_file "$label"); now=$(date +%s); ws=$((now - COOLDOWN_WINDOW_SECONDS))
  [[ ! -f "$f" ]] && return 1
  local recent=()
  while IFS= read -r ts; do
    (( ts >= ws )) && count=$((count+1)) && recent+=("$ts")
  done < "$f"
  printf '%s\n' "${recent[@]}" > "$f"
  if (( count >= COOLDOWN_MAX_REJOINS )); then
    warn "Cooldown: $count rejoins/${COOLDOWN_WINDOW_SECONDS}s. Pausing ${COOLDOWN_PAUSE_SECONDS}s..." "$label"
    notify "$label" "🛑 Cooldown" "$count rejoins in ${COOLDOWN_WINDOW_SECONDS}s."
    sleep "$COOLDOWN_PAUSE_SECONDS"
    > "$f"; return 0
  fi
  return 1
}

# ── SCHEDULED RESTART ────────────────────────────────────────

sr_file() { echo "/tmp/rbx_sr_${1// /_}"; }

should_scheduled_restart() {
  local label="$1" f now last elapsed
  f=$(sr_file "$label"); now=$(date +%s)
  [[ "$SCHEDULED_RESTART_INTERVAL" -eq 0 ]] && return 1
  if [[ ! -f "$f" ]]; then echo "$now" > "$f"; return 1; fi
  last=$(cat "$f"); elapsed=$((now - last))
  if (( elapsed >= SCHEDULED_RESTART_INTERVAL )); then
    info "Scheduled restart due (${elapsed}s elapsed)." "$label"
    echo "$now" > "$f"; return 0
  fi
  return 1
}

# ── PER-ACCOUNT MONITOR ──────────────────────────────────────

monitor_account() {
  local pkg="$1" label="$2" place_id="$3"
  local total_rejoins=0

  draw_separator "-" "$C_INFO"
  info "Monitor started — ${C_PKG}$pkg${C_RESET}" "$label"
  notify "$label" "✅ Monitor Started" "Watching $pkg | Place: $place_id"

  launch_game "$pkg" "$label" "$place_id"

  while true; do
    sleep "$CHECK_INTERVAL"
    rotate_log

    if should_scheduled_restart "$label"; then
      info "Performing scheduled restart..." "$label"
      notify "$label" "🔄 Scheduled Restart" "Proactive restart to prevent memory leaks."
      reset_err_count "$label"
      launch_game "$pkg" "$label" "$place_id"
      continue
    fi

    if detect_problem "$pkg" "$label"; then
      total_rejoins=$((total_rejoins + 1))
      is_in_cooldown "$label"
      record_rejoin "$label"
      warn "Rejoining in ${REJOIN_DELAY}s... (total: ${C_VAL}$total_rejoins${C_RESET})" "$label"
      notify "$label" "🔁 Rejoining" "Total rejoins: $total_rejoins"
      sleep "$REJOIN_DELAY"
      ! has_internet && wait_for_internet "$label"
      launch_game "$pkg" "$label" "$place_id"
    else
      ok "Healthy. Total rejoins: ${C_VAL}$total_rejoins${C_RESET}" "$label"
    fi
  done
}

# ── CHILD PID TRACKING ───────────────────────────────────────
# Instead of process groups (which break background jobs in Termux),
# we track each child PID in a file and kill them explicitly on exit.

register_child() {
  echo "$1" >> "$CHILD_PID_FILE"
}

kill_all_children() {
  [[ ! -f "$CHILD_PID_FILE" ]] && return
  while IFS= read -r cpid; do
    kill "$cpid" 2>/dev/null
  done < "$CHILD_PID_FILE"
  rm -f "$CHILD_PID_FILE"
}

# ── STOP SCRIPT ──────────────────────────────────────────────

write_stop_script() {
  cat > "$HOME/stop_roblox.sh" << EOF
#!/bin/bash
# Stop the Roblox rejoin monitor

CHILD_PID_FILE="$CHILD_PID_FILE"
PID_FILE="$PID_FILE"

if [[ -f "\$PID_FILE" ]]; then
  MAIN_PID=\$(cat "\$PID_FILE")
  echo "Stopping main process (\$MAIN_PID)..."
  kill "\$MAIN_PID" 2>/dev/null
fi

if [[ -f "\$CHILD_PID_FILE" ]]; then
  echo "Stopping monitor children..."
  while IFS= read -r cpid; do
    kill "\$cpid" 2>/dev/null
  done < "\$CHILD_PID_FILE"
fi

rm -f "\$PID_FILE" "\$CHILD_PID_FILE"
rm -f /tmp/rbx_err_* /tmp/rbx_cd_* /tmp/rbx_sr_* 2>/dev/null
echo "Done. All monitors stopped."
EOF
  chmod +x "$HOME/stop_roblox.sh"
}

# ── CLEANUP ──────────────────────────────────────────────────

cleanup() {
  echo ""
  draw_separator "═" "$C_BANNER"
  info "Shutting down — stopping all monitors..."
  notify "System" "🛑 Script Stopped" "Monitor shut down."
  kill_all_children
  rm -f "$PID_FILE" "$CHILD_PID_FILE"
  rm -f /tmp/rbx_err_* /tmp/rbx_cd_* /tmp/rbx_sr_* 2>/dev/null
  exit 0
}

# SIGHUP fires when Termux session closes
trap cleanup SIGINT SIGTERM SIGHUP

# ── MAIN ─────────────────────────────────────────────────────

main() {
  setup_colors
  clear
  draw_banner

  # Write PID and stop script before anything else
  echo $$ > "$PID_FILE"
  > "$CHILD_PID_FILE"   # Clear any stale child PIDs
  write_stop_script

  info "Main PID: ${C_VAL}$$"
  info "To stop: ${C_VAL}bash ~/stop_roblox.sh${C_RESET}  or  ${C_VAL}Ctrl+C"
  info "Terminal width: ${C_VAL}$(get_term_width) columns"

  check_root
  check_deps
  wait_for_internet "Startup"

  if [[ ${#ACCOUNTS[@]} -eq 0 ]]; then
    error "No accounts configured in ACCOUNTS array."; exit 1
  fi

  draw_separator "-" "$C_DIM"
  [[ -n "$SERVER_INSTANCE_ID" ]]            && info "Server lock:        ${C_VAL}$SERVER_INSTANCE_ID"
  [[ "$SCHEDULED_RESTART_INTERVAL" -gt 0 ]] && info "Scheduled restart:  ${C_VAL}every ${SCHEDULED_RESTART_INTERVAL}s"
  [[ -n "$TELEGRAM_BOT_TOKEN" ]]            && info "Telegram:           ${C_OK}enabled"
  [[ -n "$DISCORD_WEBHOOK_URL" ]]           && info "Discord:            ${C_OK}enabled"
  info "Accounts:           ${C_VAL}${#ACCOUNTS[@]}"
  info "Check interval:     ${C_VAL}${CHECK_INTERVAL}s"
  info "Confirm threshold:  ${C_VAL}${CONFIRM_THRESHOLD} bad checks before rejoin"
  info "CPU samples:        ${C_VAL}${CPU_SAMPLE_COUNT} × ${CPU_SAMPLE_INTERVAL}s"
  info "Rejoin delay:       ${C_VAL}${REJOIN_DELAY}s"
  info "Cooldown:           ${C_VAL}${COOLDOWN_MAX_REJOINS} rejoins / ${COOLDOWN_WINDOW_SECONDS}s"
  draw_separator "═" "$C_BANNER"
  echo ""

  # Launch each account monitor as a background job,
  # record its PID so cleanup can kill it precisely
  for entry in "${ACCOUNTS[@]}"; do
    IFS='|' read -r pkg label place_id <<< "$entry"
    monitor_account "$pkg" "$label" "$place_id" &
    register_child $!
    sleep 2
  done

  # Wait for all children — this keeps the main process alive
  wait
}

main
