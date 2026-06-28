# Daemon Update Signing — Key Runbook

## What is signed
Every published `bringupd` daemon artifact and the in-app bundled daemon get a
detached Ed25519 signature (`.sig`, base64) over the artifact's SHA-256 digest.
The daemon verifies this before self-replacing, on BOTH the mesh-push path
(desktop → edge agent) and the local unix self-upgrade path.

## Trust anchor
The trusted PUBLIC key(s) are compiled into the daemon
(`internal/agent/signing_keys.go`, `EmbeddedUpdateSigningKeys`). They cannot be
overridden in production. `BRINGUP_UPDATE_SIGNING_KEY` / `--update-signing-key`
are honored ONLY when `BRINGUP_ALLOW_DEV_SIGNING_KEY=true` (development).

Edge devices need NO key configuration. `device.sh` is unchanged; first-install
integrity rests on HTTPS to storage.bringup.dev + the manifest sha256.

## Generate a keypair
    cd apps/bringup_desktop_app/lib/bringup-daemon
    go run ./cmd/bringup-sign -genkey
Store the PRIVATE seed: `gh secret set BRINGUP_SIGN_PRIVATE_KEY --repo bringup-labs/bringup-release`
Embed the PUBLIC key in `EmbeddedUpdateSigningKeys` and release.

## Rotate a key (no flag day)
1. Append the NEW public key to `EmbeddedUpdateSigningKeys` (keep the OLD):
   `const EmbeddedUpdateSigningKeys = "<old>,<new>"`. Release the daemon.
2. Wait until the fleet runs a daemon that trusts both keys.
3. Replace the `BRINGUP_SIGN_PRIVATE_KEY` CI secret with the NEW private seed.
4. In a later release, drop the OLD key from `EmbeddedUpdateSigningKeys`.

## If signing is skipped (CI secret missing)
`publish-daemon.sh` and `copy-daemon.sh` print a warning and skip `.sig`
generation. A signed daemon will then REJECT updates (missing signature). Always
ensure `BRINGUP_SIGN_PRIVATE_KEY` is set in CI for releases.
