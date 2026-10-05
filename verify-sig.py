#!/usr/bin/env python3
"""Verify an Oxide release manifest signature.

    python3 verify-sig.py keys/oxide-release.pub manifest.json manifest.json.sig

Formats (see https://github.com/emircan-karaca/oxide-releases#how-a-release-is-trusted):
    public key line : oxide-relpub1 <keyid> <base64 raw Ed25519 public key>
    signature line  : oxide-sig1    <keyid> <base64 Ed25519 signature>
The signature covers the raw bytes of manifest.json. keyid = sha256(pubkey)[:8] hex.
Needs the `cryptography` package. Exit 0 on success, 1 otherwise.
"""
import base64
import hashlib
import sys

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey


def lines(path):
    with open(path, encoding="utf-8") as f:
        for raw in f:
            s = raw.strip()
            if s and not s.startswith("#"):
                yield s.split()


def main(pub_path, manifest_path, sig_path):
    keys = {}
    for parts in lines(pub_path):
        if len(parts) != 3 or parts[0] != "oxide-relpub1":
            sys.exit(f"bad public key line: {' '.join(parts)}")
        raw = base64.b64decode(parts[2])
        keyid = hashlib.sha256(raw).hexdigest()[:16]
        if keyid != parts[1]:
            sys.exit(f"keyid mismatch in {pub_path}: {parts[1]} vs {keyid}")
        keys[keyid] = Ed25519PublicKey.from_public_bytes(raw)

    with open(manifest_path, "rb") as f:
        data = f.read()

    seen = []
    for parts in lines(sig_path):
        if len(parts) != 3 or parts[0] != "oxide-sig1":
            sys.exit(f"bad signature line: {' '.join(parts)}")
        seen.append(parts[1])
        key = keys.get(parts[1])
        if key is None:
            continue
        try:
            key.verify(base64.b64decode(parts[2]), data)
        except InvalidSignature:
            sys.exit(f"signature by {parts[1]} does NOT verify")
        print(f"manifest signature valid (keyid {parts[1]})")
        return 0
    sys.exit(f"no signature by a trusted key (trusted {sorted(keys)}, in file {seen})")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    sys.exit(main(*sys.argv[1:]))
