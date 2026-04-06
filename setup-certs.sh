#!/usr/bin/env bash
# One-time setup: generates a locally-trusted wildcard cert for *.dev.bringup.dev
# Run this once after cloning: ./scripts/setup-certs.sh
set -e

DOMAIN="bringup.localhost"
CERT_DIR="$(cd "$(dirname "$0")" && pwd)/certs"

# ── Check for mkcert ──────────────────────────────────────────────────────────
if ! command -v mkcert &>/dev/null; then
  echo "mkcert not found. Installing..."
  if command -v brew &>/dev/null; then
    brew install mkcert
  elif command -v apt-get &>/dev/null; then
    sudo apt-get update && sudo apt-get install -y mkcert
  elif command -v choco &>/dev/null; then
    choco install mkcert
  else
    echo "ERROR: Could not install mkcert automatically."
    echo "Please install it manually: https://github.com/FiloSottile/mkcert#installation"
    exit 1
  fi
fi

# ── Install local CA (only needs to happen once per machine) ──────────────────
echo "Installing mkcert local CA (may prompt for password)..."
mkcert -install

# ── Generate wildcard cert ────────────────────────────────────────────────────
mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

mkcert \
  -cert-file cert.pem \
  -key-file key.pem \
  "*.${DOMAIN}" \
  "${DOMAIN}" \
  "localhost" \
  "127.0.0.1" \
  "::1"

# Copy mkcert root CA so containers (e.g. Next.js) can trust it
cp "$(mkcert -CAROOT)/rootCA.pem" "$CERT_DIR/rootCA.pem"

echo ""
echo "Done! Certs written to certs/"
echo "  cert.pem"
echo "  key.pem"
echo "  rootCA.pem"
echo ""
echo "Now run: docker compose up -d"
