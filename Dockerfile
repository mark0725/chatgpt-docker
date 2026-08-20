FROM debian:bookworm-slim

ARG TARGETARCH
ARG CHATGPT_DEB_BASE_URL=https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest
ARG CHATGPT_DOWNLOAD_CACHE_BUST=1
ARG CHATGPT_DOWNLOAD_PROXY
ARG DEBIAN_MIRROR=http://deb.debian.org/debian
ARG DEBIAN_SECURITY_MIRROR=http://deb.debian.org/debian-security
ARG USER_UID=1000
ARG USER_GID=1000

LABEL org.opencontainers.image.title="ChatGPT Docker" \
      org.opencontainers.image.description="Run the ChatGPT Linux desktop app in a browser through noVNC" \
      org.opencontainers.image.source="https://github.com/mark0725/chatgpt-docker" \
      org.opencontainers.image.licenses="Apache-2.0"

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:99 \
    HOME=/home/gpt \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    XDG_CONFIG_HOME=/home/gpt/.config \
    XDG_CACHE_HOME=/home/gpt/.cache \
    XDG_DATA_HOME=/home/gpt/.local/share

RUN set -eux; \
    target_arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "${target_arch}" in \
      amd64|arm64) chatgpt_arch="${target_arch}" ;; \
      *) echo "Unsupported target architecture: ${target_arch}" >&2; exit 1 ;; \
    esac; \
    echo "ChatGPT download cache key: ${CHATGPT_DOWNLOAD_CACHE_BUST}"; \
    sed -i \
      -e "s|http://deb.debian.org/debian-security|${DEBIAN_SECURITY_MIRROR}|g" \
      -e "s|http://deb.debian.org/debian|${DEBIAN_MIRROR}|g" \
      /etc/apt/sources.list.d/debian.sources; \
    apt-get update; \
    apt-get install -y --no-install-recommends aria2 ca-certificates curl; \
    download_proxy="${CHATGPT_DOWNLOAD_PROXY:-${HTTPS_PROXY:-${HTTP_PROXY:-}}}"; \
    if [ -n "${download_proxy}" ]; then \
      aria2c \
        --all-proxy="${download_proxy}" \
        --allow-overwrite=true \
        --auto-file-renaming=false \
        --console-log-level=notice \
        --dir=/tmp \
        --file-allocation=none \
        --max-connection-per-server=8 \
        --max-tries=5 \
        --min-split-size=4M \
        --out=chatgpt.deb \
        --retry-wait=2 \
        --split=8 \
        "${CHATGPT_DEB_BASE_URL}/chatgpt_${chatgpt_arch}.deb"; \
    else \
      aria2c \
        --allow-overwrite=true \
        --auto-file-renaming=false \
        --console-log-level=notice \
        --dir=/tmp \
        --file-allocation=none \
        --max-connection-per-server=8 \
        --max-tries=5 \
        --min-split-size=4M \
        --out=chatgpt.deb \
        --retry-wait=2 \
        --split=8 \
        "${CHATGPT_DEB_BASE_URL}/chatgpt_${chatgpt_arch}.deb"; \
    fi; \
    apt-get purge -y --auto-remove aria2; \
    apt-get install -y --no-install-recommends \
      /tmp/chatgpt.deb \
      bash \
      dbus-x11 \
      fonts-liberation \
      fonts-noto-cjk \
      fonts-noto-color-emoji \
      git \
      gnome-keyring \
      gosu \
      novnc \
      openbox \
      procps \
      websockify \
      x11-utils \
      x11-xserver-utils \
      x11vnc \
      xauth \
      xvfb; \
    rm -f \
      /tmp/chatgpt.deb \
      /etc/apt/sources.list.d/chatgpt.sources \
      /usr/share/keyrings/chatgpt-archive-keyring.gpg; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    groupadd --gid "${USER_GID}" gpt; \
    useradd --uid "${USER_UID}" --gid "${USER_GID}" --create-home --shell /bin/bash gpt; \
    install -d -o gpt -g gpt \
      /home/gpt/.cache \
      /home/gpt/.codex \
      /home/gpt/.config \
      /home/gpt/.local/share \
      /work

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY novnc-index.html /usr/share/novnc/index.html

USER root
WORKDIR /home/gpt

EXPOSE 6080

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl --noproxy '*' --fail --silent --show-error http://127.0.0.1:${NOVNC_PORT:-6080}/ >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
