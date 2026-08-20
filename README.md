# ChatGPT Docker

Run the official ChatGPT Linux desktop application inside Docker and access its graphical interface from a modern web browser through noVNC.

> [!IMPORTANT]
> This is an independent community project. It is not affiliated with, endorsed by, or maintained by OpenAI. ChatGPT and OpenAI are trademarks of OpenAI.

## Features

- Browser-based access to the ChatGPT desktop interface
- Multi-platform images for `linux/amd64` and `linux/arm64`
- Official architecture-specific ChatGPT Debian packages
- Lightweight Xvfb, Openbox, x11vnc, and noVNC desktop stack
- Runtime `gpt` user with a configurable host-matching UID and GID
- Persistent home directory and host Codex configuration
- Automatic current-workspace mounting with the helper script
- Optional VNC password protection
- Build-time and runtime proxy support
- Automated multi-platform publishing to GitHub Container Registry

## Requirements

- Docker Engine 24 or newer is recommended
- Docker Compose v2 is optional
- At least 2 GB of free memory is recommended
- Several GB of free disk space are required for the image and persistent data

## Quick Start

The helper script automatically:

- Runs ChatGPT as the container user `gpt`
- Sets `gpt` to the current host user's UID and GID
- Mounts the `gpt-home` volume at `/home/gpt`
- Mounts `~/.codex` at `/home/gpt/.codex`
- Mounts the current directory at `/work/<current-directory-name>`
- Binds noVNC to `127.0.0.1:6080`

Start the container from the directory you want ChatGPT to access:

```bash
VNC_PASSWORD='change-this-password' /path/to/chatgpt-docker/run.sh
```

When running from this repository itself:

```bash
VNC_PASSWORD='change-this-password' ./run.sh
```

Open <http://127.0.0.1:6080> and enter the VNC password. The noVNC client connects automatically and displays the ChatGPT application.

Stop and remove the container without deleting persistent data:

```bash
docker rm -f chatgpt
```

### Run Without the Helper Script

```bash
mkdir -p "${HOME}/.codex"

WORKSPACE_NAME="$(basename "${PWD}")"
docker run -d \
  --name chatgpt \
  --restart unless-stopped \
  --init \
  --shm-size=1g \
  -p 127.0.0.1:6080:6080 \
  -e PUID="$(id -u)" \
  -e PGID="$(id -g)" \
  -e VNC_PASSWORD='change-this-password' \
  -v gpt-home:/home/gpt \
  -v "${HOME}/.codex:/home/gpt/.codex" \
  -v "${PWD}:/work/${WORKSPACE_NAME}" \
  -w "/work/${WORKSPACE_NAME}" \
  ghcr.io/mark0725/chatgpt-docker:latest
```

## Remote Access

The default commands bind noVNC only to localhost. For a remote Docker host, use an SSH tunnel:

```bash
ssh -L 6080:127.0.0.1:6080 user@docker-host
```

Then open <http://127.0.0.1:6080> on your local computer.

To publish the service directly, change the port binding to `0.0.0.0:6080:6080` only after configuring `VNC_PASSWORD` and an HTTPS reverse proxy.

## Docker Compose

Prepare the runtime environment from the directory containing `compose.yaml`:

```bash
mkdir -p "${HOME}/.codex"
export PUID="$(id -u)"
export PGID="$(id -g)"
export WORKSPACE_PATH="${PWD}"
export WORKSPACE_NAME="$(basename "${PWD}")"
export VNC_PASSWORD='change-this-password'
```

Start the service:

```bash
docker compose up -d
```

View logs or stop the service:

```bash
docker compose logs -f
docker compose down
```

Application state is stored in the `gpt-home` named volume and is preserved when the container is recreated. The host's `~/.codex` directory is mounted separately over `/home/gpt/.codex`.

## Build Locally

Build for the current machine:

```bash
docker build -t chatgpt-docker:local .
```

Build a specific architecture with Buildx:

```bash
docker buildx build \
  --platform linux/amd64 \
  --load \
  -t chatgpt-docker:amd64 .
```

```bash
docker buildx build \
  --platform linux/arm64 \
  --load \
  -t chatgpt-docker:arm64 .
```

Create and push a multi-platform image:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --push \
  -t your-registry/chatgpt-docker:latest .
```

The Dockerfile automatically selects the official package matching Docker's target platform:

- `https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb`
- `https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_arm64.deb`

### Build Through a Proxy

Docker's standard proxy build arguments are supported by both APT and the package downloader:

```bash
docker build \
  --build-arg HTTP_PROXY=http://proxy.example.com:3128 \
  --build-arg HTTPS_PROXY=http://proxy.example.com:3128 \
  --build-arg NO_PROXY=localhost,127.0.0.1 \
  -t chatgpt-docker:local .
```

Use a proxy address reachable from the Docker builder. `127.0.0.1` refers to the build environment and not necessarily to the Docker host.

To proxy only the large ChatGPT package download, use `CHATGPT_DOWNLOAD_PROXY`:

```bash
docker build \
  --build-arg CHATGPT_DOWNLOAD_PROXY=http://proxy.example.com:3128 \
  -t chatgpt-docker:local .
```

The initial Debian mirrors can also be overridden without changing the Dockerfile. Use HTTP URLs because the slim base image installs CA certificates from this mirror:

```bash
docker build \
  --build-arg DEBIAN_MIRROR=http://your-mirror.example.com/debian \
  --build-arg DEBIAN_SECURITY_MIRROR=http://your-mirror.example.com/debian-security \
  -t chatgpt-docker:local .
```

The `CHATGPT_DOWNLOAD_CACHE_BUST` build argument can force a fresh download of the `latest` package when using a cached builder:

```bash
docker build \
  --build-arg CHATGPT_DOWNLOAD_CACHE_BUST="$(date +%s)" \
  -t chatgpt-docker:local .
```

## Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `PUID` | `1000` | Numeric UID assigned to the `gpt` user at startup. |
| `PGID` | `1000` | Numeric primary GID assigned to the `gpt` user at startup. |
| `VNC_PASSWORD` | Empty | Password required by the noVNC session. Set it whenever access is not strictly local. |
| `NOVNC_PORT` | `6080` | HTTP/WebSocket port served by noVNC inside the container. |
| `VNC_PORT` | `5900` | Internal VNC port, bound only to the container loopback interface. |
| `DISPLAY_WIDTH` | `1440` | Virtual desktop width in pixels. |
| `DISPLAY_HEIGHT` | `900` | Virtual desktop height in pixels. |
| `DISPLAY_DEPTH` | `24` | Virtual display color depth. |
| `DISPLAY_DPI` | `96` | Virtual display DPI. |
| `CHATGPT_PROXY_SERVER` | Empty | Chromium/Electron proxy server, such as `http://proxy.example.com:3128`. |
| `CHATGPT_EXTRA_ARGS` | Empty | Additional space-separated Electron command-line arguments. |
| `CHATGPT_BINARY` | `chatgpt` | Override the ChatGPT executable path for debugging. |

The `run.sh` helper also supports these variables:

| Variable | Default | Description |
| --- | --- | --- |
| `IMAGE` | `ghcr.io/mark0725/chatgpt-docker:latest` | Image to run. |
| `CONTAINER_NAME` | `chatgpt` | Docker container name. |
| `HOST_PORT` | `6080` | Host loopback port mapped to noVNC. |
| `HOME_VOLUME` | `gpt-home` | Named volume mounted at `/home/gpt`. |
| `CODEX_HOME` | `${HOME}/.codex` | Host Codex configuration directory. |
| `WORKSPACE_PATH` | Current directory | Host directory exposed to ChatGPT. |
| `WORKSPACE_NAME` | Workspace basename | Directory name created below `/work`. |

You can append Electron arguments directly to `run.sh` or `docker run`:

```bash
./run.sh --force-device-scale-factor=1.25
```

### Runtime Proxy

Set standard proxy variables and the explicit Electron proxy option when required by your network:

```bash
HTTP_PROXY=http://proxy.example.com:3128 \
HTTPS_PROXY=http://proxy.example.com:3128 \
CHATGPT_PROXY_SERVER=http://proxy.example.com:3128 \
VNC_PASSWORD='change-this-password' \
./run.sh
```

## Data and Workspace Mounts

The default layout is:

| Host source | Container path | Purpose |
| --- | --- | --- |
| Docker volume `gpt-home` | `/home/gpt` | Application settings, caches, login state, and other home data |
| `${HOME}/.codex` | `/home/gpt/.codex` | Existing host Codex configuration and credentials |
| Current directory | `/work/<current-directory-name>` | Project files ChatGPT can inspect and modify |

Matching `PUID` and `PGID` ensure files created in the mounted workspace are owned by the host user. The entrypoint starts as root only long enough to update the `gpt` account and home ownership, then runs the desktop session as `gpt`.

To reset the persistent container home:

```bash
docker rm -f chatgpt
docker volume rm gpt-home
```

This permanently deletes application data stored in the named volume. It does not delete the host workspace or `~/.codex`.

## Security Notes

- Bind port `6080` to `127.0.0.1` unless remote access is intentionally required.
- Always set `VNC_PASSWORD` before exposing noVNC beyond the local machine.
- Use an HTTPS reverse proxy or SSH tunnel over untrusted networks. VNC authentication alone does not provide HTTPS transport security.
- The Electron sandbox is disabled for compatibility with the containerized desktop environment. Do not grant the container unnecessary privileges.
- The mounted workspace is writable by ChatGPT. Run the container only from a directory whose contents you intend to expose.
- Anyone with access to `gpt-home` or the mounted `~/.codex` directory may be able to access saved application data or credentials.
- `PUID=0` is rejected; the application must not run as root.

## GitHub Actions

`.github/workflows/docker-publish.yml`:

- Builds `linux/amd64` and `linux/arm64` images on pushes to `main`, version tags, manual runs, and the weekly schedule
- Builds `linux/amd64` without publishing for pull requests
- Publishes images to `ghcr.io/<owner>/<repository>`
- Tags images with the branch, Git tag, commit SHA, and `latest` on the default branch
- Refreshes the official `latest` ChatGPT package on each workflow run
- Publishes build provenance and an SBOM

The workflow uses the repository's built-in `GITHUB_TOKEN`. Make the package public in the repository package settings if anonymous pulls are desired.

## Troubleshooting

### The browser cannot connect

Check that the container is running and healthy:

```bash
docker ps
docker logs chatgpt
```

Verify that the host port mapping matches `NOVNC_PORT`.

### Permission errors in the workspace

Confirm that `PUID` and `PGID` match the owner of the mounted host directory:

```bash
id -u
id -g
```

The `run.sh` helper sets both values automatically for non-root users.

### Login state disappears

Make sure `/home/gpt` is mounted to the same named volume whenever the container is recreated. Also keep the same `~/.codex` bind mount.

### The ChatGPT window is blank or too small

Recreate the container with a different resolution:

```bash
DISPLAY_WIDTH=1920 DISPLAY_HEIGHT=1080 ./run.sh
```

The image forces Mesa software rendering for compatibility with virtual displays.

### ARM image builds are slow

Cross-building `linux/arm64` on an AMD64 runner uses QEMU emulation. Native ARM64 builders are faster.

### Audio and microphone

The noVNC transport provides video, keyboard, mouse, and clipboard access. It does not forward host audio or microphone devices, so voice features are not expected to work through the browser session.

## How It Works

1. The build downloads the official ChatGPT Debian package matching Docker's target architecture.
2. The root entrypoint maps the `gpt` account to the requested host UID and GID.
3. The entrypoint drops privileges and starts a virtual X11 display with Xvfb and Openbox.
4. x11vnc exports the virtual display only to the container's loopback interface.
5. websockify and noVNC expose the session as a browser-compatible HTTP/WebSocket interface.
6. The ChatGPT desktop application runs as `gpt` with access to the persistent home, Codex configuration, and mounted workspace.

## License

The project source code is licensed under the [Apache License 2.0](LICENSE). The downloaded ChatGPT application is distributed by OpenAI and is subject to OpenAI's own terms and licenses.
