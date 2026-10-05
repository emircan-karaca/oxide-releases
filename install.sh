#!/bin/bash
# Oxide installer — https://github.com/emircan-karaca/oxide-releases
#
#   curl -fsSL https://get.oxide.tr | sh
#   (get.oxide.tr is a Cloudflare 302 to raw.githubusercontent.com/emircan-karaca/oxide-releases/main/install.sh)
#
# What it does, in order (every step prints what it checked):
#   1. requires Apple Silicon + macOS 13 or newer
#   2. downloads manifest.json (+ .sig) for the latest release (or OXIDE_VERSION)
#   3. verifies the manifest signature when the local `openssl` speaks Ed25519
#      (OpenSSL 3 does; macOS's LibreSSL does not — then it says so and relies
#      on the checks below)
#   4. downloads the DMG, checks sha256 + size against the manifest
#   5. Gatekeeper must accept the DMG and the app (Apple notarization), and the
#      app must be signed by Team ID 3FMDTGB65C with bundle id com.emircankaraca.oxide
#   6. installs Oxide.app to /Applications (or ~/Applications when /Applications
#      is not writable; OXIDE_INSTALL_DIR overrides), replacing an older copy atomically
#   7. links the CLI into ~/.local/bin (OXIDE_BIN_DIR) and installs shell completions
#   8. runs `oxide version` and `oxide self-update --check` from the new install
#
# Environment:
#   OXIDE_VERSION      install this version instead of the latest (e.g. 0.3.0)
#   OXIDE_INSTALL_DIR  directory to put Oxide.app in
#   OXIDE_BIN_DIR      directory for the `oxide` symlink (default ~/.local/bin)
#   OXIDE_NO_COMPLETIONS=1  skip shell completions
#
# The whole script is one function called on the last line, so a truncated
# download never runs half a script.
set -euo pipefail

main() {
    REPO="emircan-karaca/oxide-releases"
    TEAM_ID="3FMDTGB65C"
    BUNDLE_ID="com.emircankaraca.oxide"
    # Release signing public key (ed25519). Same line as crates/cli/src/selfupdate/keys.rs.
    PUBKEY_LINE="oxide-relpub1 b8432d0e682435cc DmlyTWkSIuEHkNbKKRkwhf2g0+TIdoLHX95IBTrkzrU="

    say "Oxide installer"

    # --- 1. machine -------------------------------------------------------
    [ "$(uname -s)" = "Darwin" ] || die "Oxide runs on macOS only (this is $(uname -s))."
    [ "$(uname -m)" = "arm64" ] || die "Oxide needs Apple Silicon (this Mac is $(uname -m)); the guest Linux is arm64-only."
    macos="$(sw_vers -productVersion)"
    case "$macos" in
        1[3-9].*|[2-9][0-9].*|1[3-9]|[2-9][0-9]) ;;
        *) die "macOS 13 or newer required (this is $macos)." ;;
    esac
    for t in curl hdiutil codesign spctl shasum ditto; do
        command -v "$t" >/dev/null 2>&1 || die "'$t' not found; it ships with macOS, your PATH looks unusual."
    done
    ok "macOS $macos on Apple Silicon"

    tmp="$(mktemp -d "${TMPDIR:-/tmp}/oxide-install.XXXXXX")"
    MNT=""
    trap 'cleanup' EXIT

    # --- 2. manifest ------------------------------------------------------
    if [ -n "${OXIDE_INSTALL_BASE_URL:-}" ]; then
        # Test hook: serve manifest.json(.sig) + the DMG from a local server.
        base="$OXIDE_INSTALL_BASE_URL"
    elif [ -n "${OXIDE_VERSION:-}" ]; then
        base="https://github.com/$REPO/releases/download/v${OXIDE_VERSION#v}"
    else
        base="https://github.com/$REPO/releases/latest/download"
    fi
    fetch "$base/manifest.json" "$tmp/manifest.json"
    fetch "$base/manifest.json.sig" "$tmp/manifest.json.sig"
    version="$(json_str version)"
    dmg_url="$(json_str url)"
    # Not json_str name: the top-level "name": "oxide" comes first in the file.
    dmg_name="${dmg_url##*/}"
    dmg_sha="$(json_str sha256)"
    dmg_size="$(json_num size)"
    schema="$(json_num schema)"
    [ "$schema" = "1" ] || die "manifest schema $schema is newer than this installer understands; download the DMG from https://github.com/$REPO/releases"
    [ -n "$version" ] && [ -n "$dmg_url" ] && [ -n "$dmg_sha" ] && [ -n "$dmg_size" ] || die "manifest.json is missing fields"
    if [ -n "${OXIDE_VERSION:-}" ] && [ "$version" != "${OXIDE_VERSION#v}" ]; then
        die "asked for ${OXIDE_VERSION}, manifest says $version"
    fi
    case "$dmg_url" in
        https://*) ;;
        http://127.0.0.1*|http://localhost*) [ -n "${OXIDE_INSTALL_BASE_URL:-}" ] || die "loopback asset URL outside a test: $dmg_url" ;;
        *) die "manifest asset URL is not https: $dmg_url" ;;
    esac
    ok "manifest: Oxide $version ($dmg_name, $dmg_size bytes)"

    # --- 3. manifest signature (best effort: needs an Ed25519-capable openssl) --
    verify_manifest_signature "$tmp/manifest.json" "$tmp/manifest.json.sig"

    # --- 4. dmg -------------------------------------------------------------
    dmg="$tmp/$dmg_name"
    fetch "$dmg_url" "$dmg"
    got_sha="$(shasum -a 256 "$dmg" | cut -d' ' -f1)"
    [ "$got_sha" = "$dmg_sha" ] || die "DMG sha256 mismatch: got $got_sha, manifest $dmg_sha"
    got_size="$(stat -f '%z' "$dmg")"
    [ "$got_size" = "$dmg_size" ] || die "DMG size mismatch: got $got_size, manifest $dmg_size"
    ok "sha256 and size match the manifest"

    # --- 5. Apple's chain: notarization + Team ID ---------------------------
    if ! spctl -a -t open --context context:primary-signature "$dmg" >/dev/null 2>&1; then
        die "Gatekeeper rejects the DMG (not notarized?). Refusing to install."
    fi
    MNT="$tmp/mnt"
    mkdir -p "$MNT"
    hdiutil attach -nobrowse -readonly -noautoopen -quiet -mountpoint "$MNT" "$dmg" \
        || die "could not mount the DMG"
    app_src="$MNT/Oxide.app"
    [ -d "$app_src" ] || die "no Oxide.app inside the DMG"
    codesign --verify --strict --deep "$app_src" 2>/dev/null || die "Oxide.app signature does not verify"
    info="$(codesign -dvv "$app_src" 2>&1)"
    team="$(printf '%s\n' "$info" | sed -n 's/^TeamIdentifier=//p' | head -1)"
    ident="$(printf '%s\n' "$info" | sed -n 's/^Identifier=//p' | head -1)"
    [ "$team" = "$TEAM_ID" ] || die "Oxide.app is signed by team '$team', expected $TEAM_ID — not the Oxide publisher"
    [ "$ident" = "$BUNDLE_ID" ] || die "bundle identifier is '$ident', expected $BUNDLE_ID"
    spctl -a -t exec "$app_src" >/dev/null 2>&1 || die "Gatekeeper rejects Oxide.app (not notarized?)"
    app_ver="$("$app_src/Contents/Helpers/oxide" --version 2>/dev/null | awk '{print $NF}')"
    [ "$app_ver" = "$version" ] || die "the app says version '$app_ver', manifest says $version"
    ok "notarized, Team ID $TEAM_ID, bundle $BUNDLE_ID, version $version"

    # --- 6. install ---------------------------------------------------------
    if [ -n "${OXIDE_INSTALL_DIR:-}" ]; then
        dest_dir="$OXIDE_INSTALL_DIR"
    elif [ -w /Applications ]; then
        dest_dir="/Applications"
    else
        dest_dir="$HOME/Applications"
    fi
    mkdir -p "$dest_dir"
    [ -w "$dest_dir" ] || die "$dest_dir is not writable; set OXIDE_INSTALL_DIR to a directory you own"
    dest="$dest_dir/Oxide.app"
    staging="$dest_dir/.Oxide.app.new-$$"
    old="$dest_dir/.Oxide.app.old-$$"
    rm -rf "$staging"
    ditto "$app_src" "$staging"
    hdiutil detach -quiet "$MNT" || true
    MNT=""
    if [ -d "$dest" ]; then
        if [ -d "/opt/homebrew/Caskroom/oxide" ] || [ -d "/usr/local/Caskroom/oxide" ]; then
            rm -rf "$staging"
            die "Oxide is installed with Homebrew; use: brew upgrade --cask oxide"
        fi
        prev="$("$dest/Contents/Helpers/oxide" --version 2>/dev/null | awk '{print $NF}' || true)"
        mv "$dest" "$old"
    fi
    if ! mv "$staging" "$dest"; then
        [ -d "$old" ] && mv "$old" "$dest"
        die "could not move Oxide.app into $dest_dir"
    fi
    [ -d "$old" ] && rm -rf "$old"
    if [ -n "${prev:-}" ]; then ok "installed $dest (replaced $prev)"; else ok "installed $dest"; fi

    # --- 7. CLI + completions ------------------------------------------------
    bin_dir="${OXIDE_BIN_DIR:-$HOME/.local/bin}"
    mkdir -p "$bin_dir"
    ln -sf "$dest/Contents/Helpers/oxide" "$bin_dir/oxide"
    ok "command: $bin_dir/oxide -> $dest/Contents/Helpers/oxide"
    if [ -z "${OXIDE_NO_COMPLETIONS:-}" ] && [ -d "$dest/Contents/Resources/completions" ]; then
        share="${XDG_DATA_HOME:-$HOME/.local/share}"
        install -d "$share/bash-completion/completions" "$share/zsh/site-functions" "$share/fish/vendor_completions.d"
        cp "$dest/Contents/Resources/completions/oxide.bash" "$share/bash-completion/completions/oxide"
        cp "$dest/Contents/Resources/completions/_oxide"     "$share/zsh/site-functions/_oxide"
        cp "$dest/Contents/Resources/completions/oxide.fish" "$share/fish/vendor_completions.d/oxide.fish"
        ok "shell completions under $share (bash/zsh/fish)"
    fi
    case ":$PATH:" in
        *":$bin_dir:"*) ;;
        *) note "$bin_dir is not on your PATH. Add to your shell profile:"
           note "    export PATH=\"$bin_dir:\$PATH\"" ;;
    esac

    # --- 8. prove it ---------------------------------------------------------
    say "verification"
    "$bin_dir/oxide" version | sed 's/^/  /'
    set +e
    "$bin_dir/oxide" self-update --check >/dev/null 2>"$tmp/chk.err"; rc=$?
    set -e
    case "$rc" in
        0) ok "self-update: up to date; manifest signature verified by the installed binary" ;;
        2) ok "self-update: a newer release exists already; run: oxide self-update" ;;
        *) note "self-update --check failed: $(head -1 "$tmp/chk.err")" ;;
    esac
    echo
    echo "Done. Try:  oxide run alpine echo hello"
}

# --- helpers -------------------------------------------------------------------
say()  { printf '\n\033[1m== %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32mok\033[0m    %s\n' "$1"; }
note() { printf '  \033[33mnote\033[0m  %s\n' "$1"; }
die()  { printf '  \033[31merror\033[0m %s\n' "$1" >&2; exit 1; }

cleanup() {
    [ -n "${MNT:-}" ] && hdiutil detach -quiet "$MNT" >/dev/null 2>&1 || true
    [ -n "${tmp:-}" ] && rm -rf "$tmp"
}

fetch() {
    # https only — except loopback during tests (OXIDE_INSTALL_BASE_URL).
    proto='=https'
    case "$1" in http://127.0.0.1*|http://localhost*) [ -n "${OXIDE_INSTALL_BASE_URL:-}" ] && proto='=https,http' ;; esac
    curl -fsSL --proto "$proto" --retry 3 -o "$2" "$1" \
        || die "download failed: $1 (not released yet, or no network?)"
}

# manifest.json is pretty-printed, one key per line; these read the FIRST match.
json_str() { sed -n "s/^[[:space:]]*\"$1\":[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$tmp/manifest.json" | head -1; }
json_num() { sed -n "s/^[[:space:]]*\"$1\":[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$tmp/manifest.json" | head -1; }

# Ed25519 verify with openssl when available. The public key line is
# `oxide-relpub1 <keyid> <base64 raw 32 bytes>`; openssl wants SPKI PEM, which is
# a fixed 12-byte DER prefix + the raw key.
verify_manifest_signature() {
    manifest="$1"; sigfile="$2"
    keyid="$(printf '%s' "$PUBKEY_LINE" | awk '{print $2}')"
    pub_b64="$(printf '%s' "$PUBKEY_LINE" | awk '{print $3}')"
    if ! command -v openssl >/dev/null 2>&1 || ! command -v xxd >/dev/null 2>&1; then
        note "openssl/xxd not found; manifest signature check skipped (DMG is still verified via Apple notarization + Team ID)"
        return 0
    fi
    pem="$tmp/pub.pem"
    { printf -- '-----BEGIN PUBLIC KEY-----\n'
      { printf '302a300506032b6570032100' | xxd -r -p; printf '%s' "$pub_b64" | base64 -d; } | base64
      printf -- '-----END PUBLIC KEY-----\n'; } > "$pem"
    if ! openssl pkey -pubin -in "$pem" -noout >/dev/null 2>&1; then
        note "this openssl ($(openssl version | cut -d' ' -f1-2)) has no Ed25519; manifest signature check skipped (the installed oxide verifies it itself in step 8)"
        return 0
    fi
    sig_b64="$(awk -v k="$keyid" '$1=="oxide-sig1" && $2==k {print $3; exit}' "$sigfile")"
    [ -n "$sig_b64" ] || die "manifest.json.sig has no signature by key $keyid — the release key changed or the file is tampered; get the DMG from https://github.com/$REPO/releases"
    printf '%s' "$sig_b64" | base64 -d > "$tmp/manifest.sig.bin"
    # Three outcomes, told apart by openssl's own words: verified, a real
    # mismatch (refuse), or openssl could not run the check at all (say so,
    # fall back to the Apple chain; the installed oxide re-verifies in step 8).
    # `|| true`: under set -e a failing command substitution would end the
    # script silently (seen on the CI runner) before the case below can speak.
    out="$(openssl pkeyutl -verify -pubin -inkey "$pem" -rawin -in "$manifest" -sigfile "$tmp/manifest.sig.bin" 2>&1 || true)"
    case "$out" in
        *"Verified Successfully"*) ok "manifest signature valid (key $keyid, $(openssl version | cut -d' ' -f1-2))" ;;
        *"Verification Failure"*)  die "manifest signature INVALID — refusing to continue" ;;
        *) note "manifest signature check skipped: $(openssl version | cut -d' ' -f1-2) could not verify Ed25519 ($(printf '%s' "$out" | head -1))" ;;
    esac
}

main "$@"
