#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${IMAGE:-ghcr.io/mark0725/chatgpt-docker:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-chatgpt}"
HOST_PORT="${HOST_PORT:-6080}"
HOME_VOLUME="${HOME_VOLUME:-gpt-home}"
CODEX_HOME="${CODEX_HOME:-${HOME}/.codex}"
WORKSPACE_PATH="${WORKSPACE_PATH:-${PWD}}"
WORKSPACE_NAME="${WORKSPACE_NAME:-$(basename "${WORKSPACE_PATH}")}"
HOST_UID="${PUID:-${SUDO_UID:-$(id -u)}}"
HOST_GID="${PGID:-${SUDO_GID:-$(id -g)}}"

if [[ "${HOST_UID}" == "0" ]]; then
  HOST_UID=1000
  HOST_GID=1000
  printf '%s\n' 'Running as root without SUDO_UID; using PUID=1000 and PGID=1000.' >&2
fi

mkdir -p "${CODEX_HOME}"

run_args=(
  --detach
  --name "${CONTAINER_NAME}"
  --restart unless-stopped
  --init
  --shm-size 1g
  --publish "127.0.0.1:${HOST_PORT}:6080"
  --env "PUID=${HOST_UID}"
  --env "PGID=${HOST_GID}"
  --env "VNC_PASSWORD=${VNC_PASSWORD:-}"
  --volume "${HOME_VOLUME}:/home/gpt"
  --volume "${CODEX_HOME}:/home/gpt/.codex"
  --volume "${WORKSPACE_PATH}:/work/${WORKSPACE_NAME}"
  --workdir "/work/${WORKSPACE_NAME}"
)

for variable in HTTP_PROXY HTTPS_PROXY NO_PROXY ALL_PROXY CHATGPT_PROXY_SERVER DISPLAY_WIDTH DISPLAY_HEIGHT DISPLAY_DEPTH DISPLAY_DPI CHATGPT_EXTRA_ARGS CHATGPT_BINARY; do
  if [[ -n "${!variable:-}" ]]; then
    run_args+=(--env "${variable}=${!variable}")
  fi
done

docker run "${run_args[@]}" "${IMAGE}" "$@"
printf 'ChatGPT is starting at http://127.0.0.1:%s\n' "${HOST_PORT}"
