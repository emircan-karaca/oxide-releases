**English** · [Türkçe](README.tr.md)

# Oxide — releases

Oxide is a daemonless container engine for macOS on Apple Silicon, built on
Virtualization.framework. Each container runs in its own short-lived virtual
machine that is created on demand and destroyed when the container exits; when
nothing is running there is no background process at all (0 processes, 0 MB).
The command line is Docker-compatible (same commands, flags and exit codes),
and Docker clients can talk to it over the Engine API.

This repository holds the signed and notarized release builds, the installer
and the release signing key. The source repository is private at the moment.

**Latest: 0.3.0** · Requirements: Apple Silicon Mac, macOS 13 or newer
(developed and verified on macOS 26).

## Install

Pick one.

**Homebrew**

```bash
brew install --cask emircan-karaca/oxide/oxide
```

**One line**

```bash
curl -fsSL https://raw.githubusercontent.com/emircan-karaca/oxide-releases/main/install.sh | sh
```

The script checks the machine, downloads the latest manifest and DMG, verifies
the sha256, Apple notarization and the publisher Team ID, installs `Oxide.app`
to `/Applications` (or `~/Applications`), links `oxide` into `~/.local/bin` and
installs shell completions. Read it first if you like: [install.sh](install.sh).

**DMG by hand**

1. Download the DMG from the table below and drag **Oxide.app** to **Applications**.
2. Put the command-line tool on your PATH (the app bundle carries it):

```bash
mkdir -p ~/.local/bin
ln -sf "/Applications/Oxide.app/Contents/Helpers/oxide" ~/.local/bin/oxide
export PATH="$HOME/.local/bin:$PATH"   # add to your shell profile
oxide version
```

The guest Linux kernel and initramfs ship inside the bundle
(`Contents/Resources/guest`); nothing else needs to be downloaded. Images are
pulled from Docker Hub (or any OCI registry) on first use into `~/.oxide`.

## Update

```bash
oxide self-update            # DMG / install.sh installs
oxide self-update --check    # just ask (exit 0 = current, 2 = newer release exists)
brew upgrade --cask oxide    # Homebrew installs
```

`oxide version --check` also reports whether a newer release exists. Nothing
checks in the background: the CLI only goes online when you ask, and the
desktop app asks once when its window opens.

## Downloads

| Version | File | SHA-256 |
|---|---|---|
| 0.3.0 (2026-10-05) | [Oxide-0.3.0.dmg](https://github.com/emircan-karaca/oxide-releases/releases/download/v0.3.0/Oxide-0.3.0.dmg) | `222726cc65aa3800964e8f92310663779670dcf19b5f8efb9535565d0985e60e` |
| 0.2.0 (2026-10-04) | [Oxide-0.2.0.dmg](https://github.com/emircan-karaca/oxide-releases/releases/download/v0.2.0/Oxide-0.2.0.dmg) | `c558891b7140d697bb9fbecb3a36a07ef5434adb9b38374236d7b293099a9074` |

Every release also ships `SHA256SUMS`, `manifest.json` and `manifest.json.sig`.

## Use it like Docker

```bash
oxide run --rm alpine echo hello            # pull + run, VM boots in ~0.5 s
oxide run -d --name web -p 8080:80 nginx    # detached, port published on the host
oxide ps
oxide logs web
oxide exec -it web sh
oxide stop web && oxide rm web

oxide build -t myapp .                      # multi-stage Dockerfiles, build cache
oxide compose up -d                         # compose.yaml stacks

oxide network create backend
oxide run -d --name db  --network backend postgres:16
oxide run -d --name api --network backend --network frontend myapp
oxide network connect backend api            # works while the container is running
```

`alias docker=oxide` works for everyday use. After the last container stops:

```bash
ps aux | grep oxide   # nothing — no daemon, no shared VM
```

## Docker clients

Start the Engine API listener and point any Docker client at it:

```bash
oxide api                                   # unix socket ~/.oxide/oxide.sock
export DOCKER_HOST=unix://$HOME/.oxide/oxide.sock
docker ps                                   # real docker CLI, dockerode, testcontainers, IDE plugins
```

## Networking notes (why this matters for the entitlement request)

- Containers on the same user-defined network reach each other directly and by
  name through a user-space layer-2 switch built on
  `VZFileHandleNetworkDeviceAttachment` (no entitlement needed). A container can
  join up to 32 networks; `network connect`/`disconnect` work on running
  containers.
- Outbound traffic and `-p` port publishing go through `VZNATNetworkDeviceAttachment`.
- What is **not** possible today: a container visible on the LAN with its own
  address (Docker's bridged/macvlan use case). That needs
  `VZBridgedNetworkDeviceAttachment`, which requires the restricted entitlement
  `com.apple.vm.networking`.

## How a release is trusted

| Path | What is verified |
|---|---|
| `install.sh` | HTTPS; DMG sha256 from the manifest; Gatekeeper accepts the DMG and the app (Apple notarization); the app is signed by Team ID `3FMDTGB65C` with bundle id `com.emircankaraca.oxide`; the manifest signature when the local `openssl` supports Ed25519 |
| `oxide self-update` | the manifest signature with the Ed25519 key embedded in the binary (below); DMG sha256 + size; `codesign --verify --strict --deep`, Team ID, bundle id, Gatekeeper; the new bundle's own `--version` |
| Homebrew | the Cask's `sha256` and Apple notarization (Homebrew does not re-sign) |

Release signing key ([keys/oxide-release.pub](keys/oxide-release.pub)):

```text
oxide-relpub1 b8432d0e682435cc DmlyTWkSIuEHkNbKKRkwhf2g0+TIdoLHX95IBTrkzrU=
```

Format: `oxide-relpub1 <keyid> <base64 raw Ed25519 public key>`; signatures in
`manifest.json.sig` are `oxide-sig1 <keyid> <base64 signature>` over the raw
bytes of `manifest.json`. `keyid` is the first 8 bytes of `sha256(public key)`.
A GitHub Actions run ([verify-release.yml](.github/workflows/verify-release.yml))
re-verifies every published release and runs the installer on a clean macOS runner.

## Verify the download by hand

```bash
shasum -a 256 -c SHA256SUMS
spctl -a -vv -t open --context context:primary-signature Oxide-0.3.0.dmg   # "Notarized Developer ID"
python3 verify-sig.py keys/oxide-release.pub manifest.json manifest.json.sig   # needs `pip install cryptography`
```
