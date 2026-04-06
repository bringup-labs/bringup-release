# Bringup Platform

Self-hosted deployment for the Bringup platform.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/bringup-labs/bringup-release/main/install.sh | sudo bash
```

Or clone and run manually:

```sh
git clone https://github.com/bringup-labs/bringup-release.git
cd bringup-release
sudo ./install.sh
```

The script will:
- Install Docker (Linux) or verify it's running (Mac)
- Install `mkcert` and generate locally-trusted TLS certs
- Add all subdomains to `/etc/hosts`
- Start all services

Once complete, open **https://app.bringup.localhost**

## Uninstall

```sh
docker compose -f /opt/bringup/docker-compose.yml down -v
sudo rm -rf /opt/bringup
```
