#!/usr/bin/env bash
set -euo pipefail

FIREFOX_URL="https://ftp.mozilla.org/pub/firefox/releases/52.9.0esr/linux-x86_64/en-US/firefox-52.9.0esr.tar.bz2"
FLASH_URL="https://web.archive.org/web/20200530062840if_/https://fpdownload.adobe.com/get/flashplayer/pdc/32.0.0.371/flash_player_npapi_linux.x86_64.tar.gz"
JAVA_URL="https://archive.org/download/Java-Archive/Java%20SE%208%20%288u202%20and%20earlier%29/8u191/JRE/jre-8u191-linux-x64.tar.gz"

HOST_DIR="$HOME/firefox52-podman"
CONTAINER_NAME="firefox52-podman"
IMAGE_NAME="localhost/firefox52"

banner() {
    cat <<'EOF'
========================================================
         LEGACY FIREFOX 52 ESR IN PODMAN
========================================================

Firefox 52 with NPAPI plugin support running isolated
in a Podman container, accessible via web browser.

PLUGINS:
  Flash and Java (Oracle JRE 8) are baked into the image.
  Verify at about:plugins inside Firefox.

========================================================
EOF
}

find_free_port() {
    local port
    for port in $(seq 6080 6099); do
        if ! ss -tlnH | grep -q ":${port} "; then
            echo "$port"
            return
        fi
    done
    echo "ERROR: No free port in range 6080-6099" >&2
    exit 1
}

get_container_port() {
    podman port "$CONTAINER_NAME" 6080/tcp 2>/dev/null | sed 's/.*://'
}

is_running() {
    podman container exists "$CONTAINER_NAME" 2>/dev/null &&
    [ "$(podman inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" = "true" ]
}

is_installed() {
    [ -d "$HOST_DIR" ]
}

build_image() {
    if podman image exists "$IMAGE_NAME" 2>/dev/null; then
        return 0
    fi

    echo "[+] Building Firefox 52 image (one-time, may take a few minutes)..."

    local builddir buildlog
    builddir=$(mktemp -d)
    buildlog=$(mktemp)

    cat > "$builddir/Containerfile" << 'CEOF'
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
ENV MOZ_PLUGIN_PATH=/opt/plugins:/data/plugins
ARG FIREFOX_URL
ARG FLASH_URL
ARG JAVA_URL
RUN apt-get update && apt-get install -y --no-install-recommends \
        libdbus-glib-1-2 libgtk2.0-0 libgtk-3-0 libxt6 libasound2 \
        xvfb x11vnc novnc websockify openbox xterm \
        curl bzip2 ca-certificates && \
    curl -fSL "$FIREFOX_URL" | \
        tar -xj -C /opt && \
    mv /opt/firefox /opt/firefox52 && \
    mkdir -p /opt/plugins && \
    curl -fSL "$FLASH_URL" | \
        tar -xz -C /opt/plugins libflashplayer.so && \
    curl -fSL "$JAVA_URL" | \
        tar -xz -C /opt --strip-components=0 && \
    ln -sf /opt/jre1.8.0_191/lib/amd64/libnpjp2.so /opt/plugins/libnpjp2.so && \
    rm -rf /var/lib/apt/lists/* && \
    printf '<!DOCTYPE html>\n<meta http-equiv="refresh" content="0;url=vnc.html?autoconnect=true&resize=scale">\n' \
        > /usr/share/novnc/index.html && \
    mkdir -p /etc/xdg/openbox && \
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<openbox_menu xmlns="http://openbox.org/3.4/menu">\n  <menu id="root-menu" label="Applications">\n    <item label="Firefox 52"><action name="Execute"><execute>/opt/firefox52/firefox -no-remote -profile /data/profile</execute></action></item>\n    <item label="Terminal"><action name="Execute"><execute>xterm</execute></action></item>\n    <separator />\n    <item label="Reconfigure"><action name="Reconfigure" /></item>\n  </menu>\n</openbox_menu>\n' > /etc/xdg/openbox/menu.xml
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 6080
CMD ["/entrypoint.sh"]
CEOF

    cat > "$builddir/entrypoint.sh" << 'EEOF'
#!/bin/bash
mkdir -p /data/profile /data/plugins

if [ ! -f /data/profile/user.js ]; then
    cat > /data/profile/user.js << 'PREFS'
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("app.update.mode", 0);
user_pref("app.update.service.enabled", false);
user_pref("extensions.strictCompatibility", false);
user_pref("plugin.state.flash", 2);
user_pref("plugin.state.java", 2);
PREFS
fi

Xvfb :1 -screen 0 1280x800x24 -ac &
sleep 1
export DISPLAY=:1
openbox &
export MOZ_PLUGIN_PATH=/opt/plugins:/data/plugins
/opt/firefox52/firefox -no-remote -profile /data/profile &
x11vnc -display :1 -forever -nopw -shared -rfbport 5900 -q &
exec websockify --web=/usr/share/novnc/ 6080 localhost:5900
EEOF

    if ! podman build --isolation chroot \
        --build-arg FIREFOX_URL="$FIREFOX_URL" \
        --build-arg FLASH_URL="$FLASH_URL" \
        --build-arg JAVA_URL="$JAVA_URL" \
        -t "$IMAGE_NAME" "$builddir" > "$buildlog" 2>&1; then
        echo "ERROR: Image build failed. Build log:"
        cat "$buildlog"
        rm -rf "$builddir" "$buildlog"
        exit 1
    fi
    rm -rf "$builddir" "$buildlog"
    echo "[+] Image built."
}

start_env() {
    local bind_addr="${1:-127.0.0.1}"
    mkdir -p "$HOST_DIR/plugins" "$HOST_DIR/profile"
    build_image

    if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        if is_running; then
            local port
            port=$(get_container_port)
            echo "[+] Already running at http://127.0.0.1:$port"
            return
        fi
        podman rm "$CONTAINER_NAME" >/dev/null
    fi
    local port
    port=$(find_free_port)
    podman run -d \
        --name "$CONTAINER_NAME" \
        -p "${bind_addr}:${port}:6080" \
        -v "$HOST_DIR:/data:Z" \
        "$IMAGE_NAME" >/dev/null
    if [ "$bind_addr" = "0.0.0.0" ]; then
        echo "[+] Started (network exposed). Open http://$(hostname -I | awk '{print $1}'):${port}"
    else
        echo "[+] Started. Open http://127.0.0.1:${port}"
    fi
}

stop_env() {
    if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        podman stop "$CONTAINER_NAME" >/dev/null
        echo "[+] Stopped."
    else
        echo "[-] Container does not exist."
    fi
}

status_env() {
    if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "NOT INSTALLED"
        return
    fi
    if is_running; then
        local port
        port=$(get_container_port)
        echo "RUNNING (http://127.0.0.1:$port)"
    else
        echo "STOPPED"
    fi
}

uninstall_env() {
    echo "This removes everything:"
    echo "  - Container: $CONTAINER_NAME"
    echo "  - Data: $HOST_DIR"
    echo "  - Image: $IMAGE_NAME"
    read -p "Proceed? [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
        podman unshare rm -rf "$HOST_DIR" 2>/dev/null || rm -rf "$HOST_DIR"
        podman rmi -f "$IMAGE_NAME" 2>/dev/null || true
        echo "[+] Uninstalled."
    fi
}

run_action() {
    case "$1" in
        start)          start_env "127.0.0.1" ;;
        start-exposed)  start_env "0.0.0.0" ;;
        stop)           stop_env ;;
        status)         status_env ;;
        uninstall)      uninstall_env ;;
        *)              banner ;;
    esac
}

show_menu() {
    local -a items=("$@")
    echo ""
    local i=1
    for item in "${items[@]}"; do
        local label="${item%%=*}"
        echo "  ${i}) ${label}"
        ((i++))
    done
    echo "  q) quit"
    echo ""
    read -p "Select action: " choice
    if [[ "$choice" == "q" ]]; then
        exit 0
    elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#items[@]} )); then
        local selected="${items[$((choice-1))]}"
        local action="${selected##*=}"
        run_action "$action"
    else
        echo "Invalid option."
    fi
}

if [ $# -gt 0 ]; then
    run_action "$1"
else
    banner
    if ! is_installed; then
        echo ""
        read -p "Install Firefox 52 ESR? [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            mkdir -p "$HOST_DIR/plugins" "$HOST_DIR/profile"
            build_image
            show_menu "Start (localhost only)=start" "Start (network accessible)=start-exposed"
        fi
    elif is_running; then
        echo ""
        echo "[+] Running at http://127.0.0.1:$(get_container_port)"
        show_menu "stop=stop" "status=status" "uninstall=uninstall"
    else
        show_menu "Start (localhost only)=start" "Start (network accessible)=start-exposed" "status=status" "uninstall=uninstall"
    fi
fi
