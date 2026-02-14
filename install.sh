#!/usr/bin/env bash
set -euo pipefail

REPO="dead-guru/keyboard"
INSTALL_DIR="/usr/local/bin"
BINARY_NAME="deadkbd-server"
CONFIG_DIR="$HOME/.config/deadkbd"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[*]${NC} $1"; }
ok()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[-]${NC} $1"; exit 1; }

# Detect OS and architecture
detect_platform() {
    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"

    case "$os" in
        Linux)  OS="linux" ;;
        Darwin) OS="macos" ;;
        *)      err "Unsupported OS: $os" ;;
    esac

    case "$arch" in
        x86_64|amd64)   ARCH="amd64" ;;
        aarch64|arm64)  ARCH="arm64" ;;
        *)              err "Unsupported architecture: $arch" ;;
    esac

    if [ "$OS" = "macos" ]; then
        ASSET_NAME="deadkbd-server-macos"
    else
        ASSET_NAME="deadkbd-server-linux-${ARCH}"
    fi
}

# Get latest release download URL
get_download_url() {
    local api_url="https://api.github.com/repos/${REPO}/releases/latest"

    info "Fetching latest release..."
    local release_json
    release_json="$(curl -fsSL "$api_url" 2>/dev/null)" || err "Failed to fetch release info. Check your internet connection."

    DOWNLOAD_URL="$(echo "$release_json" | grep -o "\"browser_download_url\": *\"[^\"]*${ASSET_NAME}\"" | head -1 | cut -d'"' -f4)"
    VERSION="$(echo "$release_json" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)"

    [ -z "$DOWNLOAD_URL" ] && err "No binary found for ${ASSET_NAME} in latest release"
    ok "Found ${VERSION} for ${OS}/${ARCH}"
}

download_binary() {
    local tmp
    tmp="$(mktemp)"

    info "Downloading ${ASSET_NAME}..."
    curl -fSL --progress-bar -o "$tmp" "$DOWNLOAD_URL" || err "Download failed"

    info "Installing to ${INSTALL_DIR}/${BINARY_NAME}..."
    if [ -w "$INSTALL_DIR" ]; then
        mv "$tmp" "${INSTALL_DIR}/${BINARY_NAME}"
    else
        sudo mv "$tmp" "${INSTALL_DIR}/${BINARY_NAME}"
    fi

    if [ -w "${INSTALL_DIR}/${BINARY_NAME}" ]; then
        chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
    else
        sudo chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
    fi

    ok "Installed to ${INSTALL_DIR}/${BINARY_NAME}"
}

setup_password() {
    mkdir -p "$CONFIG_DIR"
    local config_file="${CONFIG_DIR}/config"

    if [ -f "$config_file" ]; then
        warn "Config already exists at ${config_file}"
        printf "Overwrite password? [y/N]: " > /dev/tty
        read -r overwrite </dev/tty
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            info "Keeping existing password"
            return
        fi
    fi

    echo ""
    # Open /dev/tty as fd 3 for reliable interactive input
    exec 3</dev/tty
    while true; do
        printf "Enter password for dead-kbd server: " > /dev/tty
        stty -echo < /dev/tty 2>/dev/null || true
        read -r password <&3
        stty echo < /dev/tty 2>/dev/null || true
        echo "" > /dev/tty
        printf "Confirm password: " > /dev/tty
        stty -echo < /dev/tty 2>/dev/null || true
        read -r password2 <&3
        stty echo < /dev/tty 2>/dev/null || true
        echo "" > /dev/tty

        if [ "$password" = "$password2" ]; then
            break
        fi
        warn "Passwords don't match, try again"
    done
    exec 3<&-

    [ -z "$password" ] && err "Password cannot be empty"

    echo "PASSWORD=${password}" > "$config_file"
    chmod 600 "$config_file"
    ok "Password saved to ${config_file}"
}

setup_autostart_linux() {
    local service_file="$HOME/.config/systemd/user/deadkbd.service"

    mkdir -p "$HOME/.config/systemd/user"

    cat > "$service_file" << EOF
[Unit]
Description=Dead Keyboard Server
After=network.target

[Service]
Type=simple
EnvironmentFile=${CONFIG_DIR}/config
ExecStart=${INSTALL_DIR}/${BINARY_NAME} --password \${PASSWORD}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable deadkbd.service
    systemctl --user start deadkbd.service

    ok "Systemd user service enabled and started"
    info "Commands: systemctl --user {start|stop|restart|status} deadkbd"
}

setup_autostart_macos() {
    local plist_file="$HOME/Library/LaunchAgents/guru.dead.kbd.plist"

    mkdir -p "$HOME/Library/LaunchAgents"

    # Read password from config
    local password
    password="$(grep '^PASSWORD=' "${CONFIG_DIR}/config" | cut -d= -f2-)"

    cat > "$plist_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>guru.dead.kbd</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_DIR}/${BINARY_NAME}</string>
        <string>--password</string>
        <string>${password}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${CONFIG_DIR}/server.log</string>
    <key>StandardErrorPath</key>
    <string>${CONFIG_DIR}/server.log</string>
</dict>
</plist>
EOF

    launchctl bootout gui/$(id -u) "$plist_file" 2>/dev/null || true
    launchctl bootstrap gui/$(id -u) "$plist_file"

    ok "LaunchAgent installed and started"
    info "Commands: launchctl kickstart -k gui/$(id -u)/guru.dead.kbd"
    info "Logs: tail -f ${CONFIG_DIR}/server.log"
}

setup_autostart() {
    echo ""
    printf "Add to autostart? [Y/n]: " > /dev/tty
    read -r autostart </dev/tty
    if [[ "$autostart" =~ ^[Nn]$ ]]; then
        info "Skipping autostart. Run manually:"
        info "  source ${CONFIG_DIR}/config && ${BINARY_NAME} --password \$PASSWORD"
        return
    fi

    if [ "$OS" = "linux" ]; then
        setup_autostart_linux
    else
        setup_autostart_macos
    fi
}

setup_accessibility_macos() {
    echo ""
    warn "Accessibility permission is required for keyboard/mouse control."
    echo ""
    info "Opening System Settings..."
    info "  1. Click  +  button"
    info "  2. Press  Cmd+Shift+G"
    info "  3. Type:  /usr/local/bin"
    info "  4. Select  deadkbd-server  and click Open"
    echo ""
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true
    printf "Press Enter when done... " > /dev/tty
    read -r _ </dev/tty
}

setup_uinput_linux() {
    echo ""
    info "Setting up /dev/uinput access..."
    if [ ! -w /dev/uinput ]; then
        sudo chmod 0660 /dev/uinput
        sudo chown root:"$USER" /dev/uinput
        ok "/dev/uinput permissions set"
    else
        ok "/dev/uinput already accessible"
    fi

    # Persist across reboots via udev rule
    local udev_rule="/etc/udev/rules.d/99-deadkbd.rules"
    if [ ! -f "$udev_rule" ]; then
        echo "KERNEL==\"uinput\", MODE=\"0660\", GROUP=\"$USER\"" | sudo tee "$udev_rule" > /dev/null
        ok "udev rule created for persistence"
    fi
}

post_install_notes() {
    echo ""
    echo -e "${GREEN}=== Installation complete ===${NC}"
    echo ""
    info "Default port: 9877"
}

# Main
echo ""
echo -e "${CYAN}  dead-kbd server installer${NC}"
echo ""

detect_platform
setup_password
get_download_url
download_binary

if [ "$OS" = "macos" ]; then
    setup_accessibility_macos
elif [ "$OS" = "linux" ]; then
    setup_uinput_linux
fi

setup_autostart
post_install_notes
