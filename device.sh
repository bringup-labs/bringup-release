#!/usr/bin/env bash
set -euo pipefail

# device.sh — install the latest bringupd daemon on a robot or edge gateway.
#
#   curl -fsSL https://bringup.dev/device.sh | sudo bash
#
# Detects the OS/architecture, reads the published manifest, downloads the
# matching daemon binary, verifies its checksum, installs it to
# /usr/local/bin/bringupd, and registers it as a service (systemd / launchd).
# Re-run to upgrade.

BASE_URL="${BRINGUP_BASE_URL:-https://bringup.dev}"
MANIFEST_URL="${BRINGUP_MANIFEST_URL:-${BASE_URL}/daemon/manifest.yml}"
INSTALL_PATH="/usr/local/bin/bringupd"

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: device.sh must be run as root (use sudo)" >&2
    exit 1
fi

# ── Detect platform key ─────────────────────────────────────────────────────
OS="$(uname -s)"
MACHINE="$(uname -m)"
case "${OS}" in
    Linux)
        case "${MACHINE}" in
            x86_64|amd64)        KEY="linux-amd64" ;;
            aarch64|arm64)       KEY="linux-arm64" ;;
            armv7l|armv7|armhf)  KEY="linux-arm" ;;
            *) echo "Unsupported Linux architecture: ${MACHINE}" >&2; exit 1 ;;
        esac
        ;;
    Darwin)
        KEY="darwin-universal"
        ;;
    *)
        echo "Unsupported OS: ${OS}" >&2
        exit 1
        ;;
esac

echo "Detected platform: ${KEY}"

# ── Fetch and parse the manifest ────────────────────────────────────────────
MANIFEST="$(curl -fsSL "${MANIFEST_URL}")"

VERSION="$(printf '%s\n' "${MANIFEST}" | awk '/^version:/ {print $2; exit}')"

# Extract the path/sha256 lines from the indented block under "  <KEY>:".
ARTIFACT_PATH="$(printf '%s\n' "${MANIFEST}" \
    | awk -v k="  ${KEY}:" '$0==k {f=1; next} f && /^  [^ ]/ {exit} f && /path:/ {print $2; exit}')"
ARTIFACT_SHA="$(printf '%s\n' "${MANIFEST}" \
    | awk -v k="  ${KEY}:" '$0==k {f=1; next} f && /^  [^ ]/ {exit} f && /sha256:/ {print $2; exit}')"

if [ -z "${ARTIFACT_PATH}" ] || [ -z "${ARTIFACT_SHA}" ]; then
    echo "Error: manifest has no artifact for ${KEY}" >&2
    exit 1
fi

echo "Latest daemon version: ${VERSION}"

# ── Download and verify ─────────────────────────────────────────────────────
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
TMP_BIN="${TMP_DIR}/bringupd"

echo "Downloading ${BASE_URL}/${ARTIFACT_PATH} ..."
curl -fsSL "${BASE_URL}/${ARTIFACT_PATH}" -o "${TMP_BIN}"

if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL_SHA="$(sha256sum "${TMP_BIN}" | awk '{print $1}')"
else
    ACTUAL_SHA="$(shasum -a 256 "${TMP_BIN}" | awk '{print $1}')"
fi

if [ "${ACTUAL_SHA}" != "${ARTIFACT_SHA}" ]; then
    echo "Error: checksum mismatch" >&2
    echo "  expected: ${ARTIFACT_SHA}" >&2
    echo "  actual:   ${ACTUAL_SHA}" >&2
    exit 1
fi
echo "Checksum verified."

# ── Install binary ──────────────────────────────────────────────────────────
echo "Installing daemon to ${INSTALL_PATH} ..."
install -m 0755 "${TMP_BIN}" "${INSTALL_PATH}"

# ── Register service ────────────────────────────────────────────────────────
case "${OS}" in
    Linux)
        UNIT_DST="/etc/systemd/system/bringupd.service"
        echo "Installing systemd service to ${UNIT_DST} ..."
        cat > "${UNIT_DST}" <<'EOF'
[Unit]
Description=BringUp Daemon
After=network.target docker.service
Wants=docker.service

[Service]
Type=simple
ExecStart=/usr/local/bin/bringupd --socket /var/run/bringupd.sock --service bringupd --binary /usr/local/bin/bringupd
Restart=on-failure
RestartSec=3
User=root
Group=root

# Security hardening
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
NoNewPrivileges=true
MemoryDenyWriteExecute=true
LockPersonality=true
RestrictRealtime=true
RestrictSUIDSGID=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ReadWritePaths=/var/run /var/lib/bringupd /var/log
RuntimeDirectory=bringupd
RuntimeDirectoryMode=0750

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable bringupd
        systemctl restart bringupd
        echo "bringupd service started (systemd)."
        ;;
    Darwin)
        PLIST_DST="/Library/LaunchDaemons/com.bringup.daemon.plist"
        echo "Installing launchd daemon to ${PLIST_DST} ..."
        cat > "${PLIST_DST}" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.bringup.daemon</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/bringupd</string>
    <string>--socket</string>
    <string>/tmp/bringupd.sock</string>
    <string>--service-manager</string>
    <string>launchd</string>
    <string>--service</string>
    <string>com.bringup.daemon</string>
    <string>--binary</string>
    <string>/usr/local/bin/bringupd</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/var/log/bringupd.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/bringupd.err.log</string>
</dict>
</plist>
EOF
        chown root:wheel "${PLIST_DST}"
        chmod 644 "${PLIST_DST}"

        launchctl bootout system/com.bringup.daemon 2>/dev/null || true
        for _ in $(seq 1 10); do
            launchctl print system/com.bringup.daemon &>/dev/null || break
            sleep 0.5
        done
        launchctl bootstrap system "${PLIST_DST}"
        launchctl kickstart -k system/com.bringup.daemon
        echo "bringupd service started (launchd)."
        ;;
esac

echo "Installation complete — bringupd v${VERSION}."