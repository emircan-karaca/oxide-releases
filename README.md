# Oxide — releases

Oxide is a daemonless container engine for macOS on Apple Silicon, built on
Virtualization.framework. Each container runs in its own short-lived virtual
machine that is created on demand and destroyed when the container exits; when
nothing is running there is no background process at all (0 processes, 0 MB).
The command line is Docker-compatible (same commands, flags and exit codes),
and Docker clients can talk to it over the Engine API.

This repository holds only the signed and notarized release builds. The source
repository is private at the moment.

## Download

| Version | File | SHA-256 |
|---|---|---|
| 0.2.0 (2026-10-04) | [Oxide-0.2.0.dmg](https://github.com/emircan-karaca/oxide-releases/releases/download/v0.2.0/Oxide-0.2.0.dmg) | `c558891b7140d697bb9fbecb3a36a07ef5434adb9b38374236d7b293099a9074` |

Requirements: Apple Silicon Mac, macOS 26 (developed and verified on 26.6.2).
The DMG and the app inside it are signed with a Developer ID certificate,
notarized by Apple and stapled.

## Install

1. Open the DMG and drag **Oxide.app** to **Applications**.
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

## Verify the download

```bash
shasum -a 256 Oxide-0.2.0.dmg
spctl -a -vv -t open --context context:primary-signature Oxide-0.2.0.dmg   # "Notarized Developer ID"
```
