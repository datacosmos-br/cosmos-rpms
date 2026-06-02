#!/bin/bash
# Assemble the public dnf repo tree from signed RPMs and (optionally) sign repomd.xml.
# Produces:  <SITE>/<el>/<arch>/{*.rpm, repodata/}  +  <SITE>/RPM-GPG-KEY-datacosmos  +  <SITE>/cosmos-rpms.repo
# Usage: SITE=public RPMS_DIR=rpms EL=el8 scripts/make-repo.sh
set -euo pipefail

SITE="${SITE:-public}"
RPMS_DIR="${RPMS_DIR:?dir with signed *.rpm}"
EL="${EL:-el8}"
PUBKEY="${PUBKEY:-RPM-GPG-KEY-datacosmos}"
REPOFILE="${REPOFILE:-cosmos-rpms.repo}"

mkdir -p "$SITE"
cp -f "$PUBKEY" "$SITE/RPM-GPG-KEY-datacosmos"
cp -f "$REPOFILE" "$SITE/cosmos-rpms.repo"

# place each RPM under <el>/<arch>/ by its arch
for r in "$RPMS_DIR"/*.rpm; do
  [ -e "$r" ] || continue
  a="$(rpm -qp --qf '%{ARCH}\n' "$r" 2>/dev/null)"
  case "$a" in noarch) a="x86_64";; esac   # noarch goes to every arch tree; keep simple -> x86_64
  mkdir -p "$SITE/$EL/$a"
  cp -f "$r" "$SITE/$EL/$a/"
done

# createrepo per arch tree + sign repomd if a key is present
for d in "$SITE/$EL"/*/; do
  [ -d "$d" ] || continue
  createrepo_c --update "$d"
  if [ -n "${GPG_PRIVATE_KEY:-}" ]; then
    export GNUPGHOME; GNUPGHOME="$(mktemp -d)"; chmod 700 "$GNUPGHOME"
    printf '%s' "$GPG_PRIVATE_KEY" | gpg --batch --import
    gpg --batch --yes --pinentry-mode loopback ${GPG_PASSPHRASE:+--passphrase "$GPG_PASSPHRASE"} \
        --detach-sign --armor "${d}repodata/repomd.xml"
    rm -rf "$GNUPGHOME"
  fi
done
echo "== repo tree ==" && find "$SITE" -maxdepth 3 -type d | sort
