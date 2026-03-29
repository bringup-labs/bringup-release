#!/usr/bin/env bash

set -e

APP_NAME="bringup"
INSTALL_DIR="/opt/bringup"
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
DOMAIN="bringup.local"
CERT_DIR="$INSTALL_DIR/certs"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 0. Ensure sudo/root
if [ "$EUID" -ne 0 ]; then
  error "Please run as root or with sudo"
  exit 1
fi

USER_NAME=${SUDO_USER:-$(whoami)}
OS="$(uname -s)"

log "User: $USER_NAME"
log "OS: $OS"

# ----------------------------
# Docker Setup
# ----------------------------

install_docker_linux() {
  log "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  usermod -aG docker "$USER_NAME"
}

check_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed"
    return
  fi

  case "$OS" in
    Linux)
      install_docker_linux
      ;;
    Darwin)
      error "Install Docker Desktop for Mac"
      exit 1
      ;;
    *)
      error "Unsupported OS"
      exit 1
      ;;
  esac
}

check_docker

if ! docker info >/dev/null 2>&1; then
  error "Docker not running"
  exit 1
fi

# ----------------------------
# mkcert Setup
# ----------------------------

install_mkcert() {
  log "Installing mkcert..."

  case "$OS" in
    Linux)
      apt-get update -y || true
      apt-get install -y libnss3-tools curl || true

      curl -L -o /usr/local/bin/mkcert \
        https://github.com/FiloSottile/mkcert/releases/latest/download/mkcert-v1.4.4-linux-amd64

      chmod +x /usr/local/bin/mkcert
      ;;
    Darwin)
      brew install mkcert nss
      ;;
    *)
      error "Install mkcert manually for this OS"
      exit 1
      ;;
  esac
}

if ! command -v mkcert >/dev/null 2>&1; then
  install_mkcert
fi

log "Setting up mkcert CA..."
mkcert -install

# ----------------------------
# Prepare directories
# ----------------------------

mkdir -p "$INSTALL_DIR"
mkdir -p "$CERT_DIR"

# ----------------------------
# Download docker compose
# ----------------------------

log "Downloading docker compose..."
curl -L https://raw.githubusercontent.com/bringup-labs/bringup-release/main/docker-compose.yml \
  -o "$COMPOSE_FILE"

# ----------------------------
# Generate TLS cert
# ----------------------------

log "Generating TLS cert via mkcert..."

mkcert -key-file "$CERT_DIR/key.pem" \
       -cert-file "$CERT_DIR/cert.pem" \
       "$DOMAIN" localhost 127.0.0.1

# ----------------------------
# Hosts entry
# ----------------------------

if ! grep -q "$DOMAIN" /etc/hosts; then
  log "Adding domain to /etc/hosts"
  echo "127.0.0.1 $DOMAIN" >> /etc/hosts
fi

# ----------------------------
# Pull images
# ----------------------------

log "Pulling images..."
docker compose -f "$COMPOSE_FILE" pull

# ----------------------------
# Start services
# ----------------------------

log "Starting services..."
docker compose -f "$COMPOSE_FILE" up -d

# ----------------------------
# Wait for readiness
# ----------------------------

log "Waiting for app..."

MAX_RETRIES=40
RETRY=0

until curl -s https://$DOMAIN >/dev/null 2>&1; do
  sleep 2
  RETRY=$((RETRY+1))

  if [ $RETRY -ge $MAX_RETRIES ]; then
    error "App did not become ready"
    docker compose -f "$COMPOSE_FILE" logs
    exit 1
  fi
done

# ----------------------------
# Done
# ----------------------------

log "Installation complete 🎉"

echo ""
echo "👉 Open: https://$DOMAIN"
echo ""
echo "If Docker group was updated, re-login may be required."
