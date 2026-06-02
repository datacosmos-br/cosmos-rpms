#!/bin/bash
# Sign RPMs with the Datacosmos RPM key. The PRIVATE key + passphrase come from Vault (read by CI via
# GitHub-OIDC) and are passed in via env — never stored in GitHub. Usage: sign-rpm.sh <rpm>...
set -euo pipefail

: "${GPG_PRIVATE_KEY:?GPG_PRIVATE_KEY (ASCII-armored) required}"
: "${GPG_KEY_NAME:?GPG_KEY_NAME (uid / key id) required}"
PASS="${GPG_PASSPHRASE:-}"
[ "$#" -ge 1 ] || { echo "usage: sign-rpm.sh <rpm>..."; exit 2; }

export GNUPGHOME; GNUPGHOME="$(mktemp -d)"; chmod 700 "$GNUPGHOME"
printf '%s' "$GPG_PRIVATE_KEY" | gpg --batch --import
# loopback pinentry so rpm --addsign can supply the passphrase non-interactively
cat > "$GNUPGHOME/gpg.conf" <<'EOF'
pinentry-mode loopback
EOF

# rpm sign macros (rpm 4.14 / el8): drive gpg with loopback + passphrase
rpm --define "_gpg_name ${GPG_KEY_NAME}" \
    --define "__gpg_sign_cmd %{__gpg} gpg --batch --no-armor --pinentry-mode loopback ${PASS:+--passphrase ${PASS}} --no-secmem-warning -u \"%{_gpg_name}\" -sbo %{__signature_filename} --digest-algo sha256 %{__plaintext_filename}" \
    --addsign "$@"

# verify against OUR key: rpm uses its own keyring, so import our public key (derived from the imported
# private key) before checking. Each RPM must now report a good Datacosmos signature.
gpg --batch --export --armor "$GPG_KEY_NAME" > "$GNUPGHOME/our.pub"
rpm --import "$GNUPGHOME/our.pub"
for r in "$@"; do
  out="$(LC_ALL=C rpm -Kv "$r" 2>&1)"
  echo "$out" | grep -qE 'NOKEY|NOT OK|MISSING KEYS' && { echo "FATAL: re-sign verify FAILED for $r:"; echo "$out"; rm -rf "$GNUPGHOME"; exit 1; }
  echo "$out" | grep -qE '(RSA|DSA)/SHA[0-9]+ Signature.*: OK' || { echo "FATAL: no Datacosmos signature on $r:"; echo "$out"; rm -rf "$GNUPGHOME"; exit 1; }
  echo "OK $r — signed + verified with Datacosmos key"
done
rm -rf "$GNUPGHOME"
