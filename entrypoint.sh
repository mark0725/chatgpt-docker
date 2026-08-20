#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[chatgpt-docker] %s\n' "$*"
}

if [[ "$(id -u)" == "0" ]]; then
  PUID="${PUID:-1000}"
  PGID="${PGID:-1000}"

  if [[ ! "${PUID}" =~ ^[0-9]+$ ]] || ((PUID == 0)); then
    log "PUID must be a positive numeric user ID."
    exit 1
  fi

  if [[ ! "${PGID}" =~ ^[0-9]+$ ]] || ((PGID == 0)); then
    log "PGID must be a positive numeric group ID."
    exit 1
  fi

  existing_group="$(getent group "${PGID}" | cut -d: -f1 || true)"
  if [[ -n "${existing_group}" && "${existing_group}" != "gpt" ]]; then
    usermod --gid "${existing_group}" gpt
  else
    if [[ "$(id -g gpt)" != "${PGID}" ]]; then
      groupmod --gid "${PGID}" gpt
    fi
    usermod --gid "${PGID}" gpt
  fi

  if [[ "$(id -u gpt)" != "${PUID}" ]]; then
    usermod --non-unique --uid "${PUID}" gpt
  fi

  install -d -m 1777 /tmp/.X11-unix
  install -d -m 700 -o "${PUID}" -g "${PGID}" /tmp/runtime-gpt
  mkdir -p /home/gpt/.cache /home/gpt/.codex /home/gpt/.config /home/gpt/.local/share
  chown -R "${PUID}:${PGID}" /home/gpt

  export HOME=/home/gpt
  export XDG_CONFIG_HOME=/home/gpt/.config
  export XDG_CACHE_HOME=/home/gpt/.cache
  export XDG_DATA_HOME=/home/gpt/.local/share
  export XDG_RUNTIME_DIR=/tmp/runtime-gpt

  log "Starting as gpt (${PUID}:${PGID})."
  exec gosu gpt "$0" "$@"
fi

DISPLAY="${DISPLAY:-:99}"
DISPLAY_WIDTH="${DISPLAY_WIDTH:-1440}"
DISPLAY_HEIGHT="${DISPLAY_HEIGHT:-900}"
DISPLAY_DEPTH="${DISPLAY_DEPTH:-24}"
DISPLAY_DPI="${DISPLAY_DPI:-96}"
VNC_PORT="${VNC_PORT:-5900}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
VNC_PASSWORD="${VNC_PASSWORD:-}"
CHATGPT_BINARY="${CHATGPT_BINARY:-chatgpt}"
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-gpt}"

export DISPLAY XDG_RUNTIME_DIR
export ELECTRON_OZONE_PLATFORM_HINT="${ELECTRON_OZONE_PLATFORM_HINT:-x11}"
export NO_AT_BRIDGE="${NO_AT_BRIDGE:-1}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"

mkdir -p \
  "${HOME}/.cache" \
  "${HOME}/.codex" \
  "${HOME}/.config" \
  "${HOME}/.local/share" \
  "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"
find "${XDG_CONFIG_HOME}" -maxdepth 2 -name 'Singleton*' -delete 2>/dev/null || true

declare -a process_ids=()

start_process() {
  "$@" &
  local process_id=$!
  process_ids+=("${process_id}")
  log "Started PID ${process_id}: $*"
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM

  if ((${#process_ids[@]})); then
    kill "${process_ids[@]}" 2>/dev/null || true
    wait "${process_ids[@]}" 2>/dev/null || true
  fi

  if [[ -n "${DBUS_SESSION_BUS_PID:-}" ]]; then
    kill "${DBUS_SESSION_BUS_PID}" 2>/dev/null || true
  fi

  exit "${status}"
}
trap cleanup EXIT INT TERM

eval "$(dbus-launch --sh-syntax)"
export DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID

start_process Xvfb "${DISPLAY}" \
  -screen 0 "${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}x${DISPLAY_DEPTH}" \
  -dpi "${DISPLAY_DPI}" \
  -nolisten tcp \
  -ac \
  -noreset

for _ in {1..50}; do
  if xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

if ! xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1; then
  log "Xvfb did not become ready."
  exit 1
fi

xsetroot -display "${DISPLAY}" -solid '#202123'
start_process openbox

vnc_args=(
  -display "${DISPLAY}"
  -rfbport "${VNC_PORT}"
  -forever
  -shared
  -localhost
  -noxdamage
  -repeat
)

if [[ -n "${VNC_PASSWORD}" ]]; then
  mkdir -p "${HOME}/.vnc"
  x11vnc -storepasswd "${VNC_PASSWORD}" "${HOME}/.vnc/passwd" >/dev/null
  chmod 600 "${HOME}/.vnc/passwd"
  vnc_args+=(-rfbauth "${HOME}/.vnc/passwd")
else
  vnc_args+=(-nopw)
  log "Warning: VNC_PASSWORD is empty; do not expose port ${NOVNC_PORT} to an untrusted network."
fi

start_process x11vnc "${vnc_args[@]}"
start_process websockify \
  --web=/usr/share/novnc/ \
  --heartbeat=30 \
  "${NOVNC_PORT}" \
  "127.0.0.1:${VNC_PORT}"

if ! command -v "${CHATGPT_BINARY}" >/dev/null 2>&1; then
  if [[ -x /usr/lib/chatgpt/ChatGPT ]]; then
    CHATGPT_BINARY=/usr/lib/chatgpt/ChatGPT
  else
    log "ChatGPT executable not found: ${CHATGPT_BINARY}"
    exit 1
  fi
fi

chatgpt_args=(
  --no-sandbox
  --disable-dev-shm-usage
  --ozone-platform=x11
  --password-store=basic
)

if [[ -n "${CHATGPT_PROXY_SERVER:-}" ]]; then
  chatgpt_args+=("--proxy-server=${CHATGPT_PROXY_SERVER}")
fi

if [[ -n "${CHATGPT_EXTRA_ARGS:-}" ]]; then
  read -r -a extra_args <<<"${CHATGPT_EXTRA_ARGS}"
  chatgpt_args+=("${extra_args[@]}")
fi

chatgpt_args+=("$@")
start_process "${CHATGPT_BINARY}" "${chatgpt_args[@]}"

log "Open http://localhost:${NOVNC_PORT} in your browser."

set +e
wait -n "${process_ids[@]}"
status=$?
set -e
log "A required process exited with status ${status}; shutting down."
exit "${status}"
