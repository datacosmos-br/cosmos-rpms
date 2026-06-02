#!/bin/bash
# Standardized RPM build for cosmos-rpms — the official Datacosmos custom-RPM source.
# Runs INSIDE the oraclelinux:8 builder (build/Containerfile), driven by the CI matrix.
# For kernel-ml: rebuild a clean kernel-ml <VERSION> for el8 from the elrepo spec + kernel.org tarball
# + a config adapted from the elrepo donor via `make olddefconfig`, forcing the exact elrepo NVR.
#
# Env: PKG (kernel-ml), VERSION (6.12.92), ARCH (x86_64|aarch64; default uname -m), EL (el8), OUT (/out)
set -euo pipefail

PKG="${PKG:-kernel-ml}"
VERSION="${VERSION:?set VERSION e.g. 6.12.92}"
ARCH="${ARCH:-$(uname -m)}"
EL="${EL:-el8}"
DIST="${DIST:-.${EL}.elrepo}"
OUT="${OUT:-/out}"
RAW="https://raw.githubusercontent.com/elrepo/kernel/main"
SERIES="v$(printf '%s' "$VERSION" | cut -d. -f1).x"

[ "$PKG" = "kernel-ml" ] || { echo "build-rpm: unknown PKG '$PKG'"; exit 2; }
echo "== cosmos-rpms build: PKG=$PKG VERSION=$VERSION ARCH=$ARCH EL=$EL DIST=$DIST =="

work="$(mktemp -d)"; cd "$work"
mkdir -p "$OUT" ~/rpmbuild/SOURCES ~/rpmbuild/SPECS

# 1) elrepo spec + donor config — discovered dynamically (elrepo bumps versions/filenames over time).
#    Build spec = el8 kernel-ml spec. Donor config: el8 has x86_64 only; aarch64 lives in el9.
API="https://api.github.com/repos/elrepo/kernel/contents"
ghls() { curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} "$1" | grep -oE '"name":[[:space:]]*"[^"]+"' | sed -E 's/.*"([^"]+)"$/\1/'; }
case "$ARCH" in
  x86_64)  cfg_el="$EL" ;;
  aarch64) cfg_el="el9" ;;   # el8 has no aarch64 config -> el9 donor
  *) echo "unsupported ARCH $ARCH"; exit 2 ;;
esac
spec_name="$(ghls "${API}/kernel-ml/${EL}" | grep -E '^kernel-ml-[0-9.]+\.spec$' | sort -V | tail -1)"
donor_name="$(ghls "${API}/kernel-ml/${cfg_el}" | grep -E "^config-[0-9.]+-${ARCH}$" | sort -V | tail -1)"
[ -n "$spec_name" ] && [ -n "$donor_name" ] || { echo "FATAL: could not discover spec ($spec_name) / config ($donor_name)"; exit 1; }
echo "spec=${spec_name} donor=${cfg_el}/${donor_name}"
curl -fsSL "${RAW}/kernel-ml/${EL}/${spec_name}" -o ~/rpmbuild/SPECS/kernel-ml.spec
curl -fsSL "${RAW}/kernel-ml/${cfg_el}/${donor_name}" -o donor.config

# 2) pin the spec to VERSION (elrepo macro %define LKAver) + make the config Source arch-generic
sed -ri "s/^(%define[[:space:]]+LKAver[[:space:]]+).*/\1${VERSION}/" ~/rpmbuild/SPECS/kernel-ml.spec
sed -ri "s/^(Source1:[[:space:]]*config-%\{version\}-)x86_64/\1%{_target_cpu}/" ~/rpmbuild/SPECS/kernel-ml.spec
# best-effort el8/aarch64: the el8 kernel-ml spec gates a few defines behind %ifarch x86_64, so they are
# undefined on aarch64 and break the parse ("bad %if condition"). elrepo does NOT officially ship el8
# aarch64 kernel-ml; pre-define the safe ones so the spec at least parses + builds. (x86_64 unaffected.)
if [ "$ARCH" = "aarch64" ]; then
  sed -i '1i %define zipmodules 0' ~/rpmbuild/SPECS/kernel-ml.spec
  sed -i '1i %define with_vdso_install 0' ~/rpmbuild/SPECS/kernel-ml.spec
fi

# 3) all elrepo BuildRequires, exactly as the spec declares them
dnf -y config-manager --set-enabled ol8_codeready_builder >/dev/null 2>&1 || true
dnf -y builddep ~/rpmbuild/SPECS/kernel-ml.spec

# 4) adapt the donor config to the target tree (olddefconfig = non-interactive; the spec's later
#    `make oldconfig` then finds no new symbols and never prompts)
curl -fsSLO "https://cdn.kernel.org/pub/linux/kernel/${SERIES}/linux-${VERSION}.tar.xz"
tar xf "linux-${VERSION}.tar.xz"
cp donor.config "linux-${VERSION}/.config"
make -C "linux-${VERSION}" ARCH="$ARCH" olddefconfig
cp "linux-${VERSION}/.config" ~/rpmbuild/SOURCES/"config-${VERSION}-${ARCH}"
cp "linux-${VERSION}.tar.xz" ~/rpmbuild/SOURCES/

# 5) the spec's other Sources (cpupower units, mod-extra, filters, bls) come from elrepo too
for s in cpupower.service cpupower.config mod-extra.sh mod-extra.list mod-extra-blacklist.sh \
         filter-x86_64.sh filter-aarch64.sh filter-modules.sh generate_bls_conf.sh; do
  curl -fsSL "${RAW}/kernel-ml/${EL}/${s}" -o ~/rpmbuild/SOURCES/"${s}" 2>/dev/null || true
done

# 6) build binary RPMs for the target arch, forcing the exact dist tag
rpmbuild -bb \
  --target "$ARCH" \
  --define "dist ${DIST}" \
  --define "_topdir ${HOME}/rpmbuild" \
  --without debug --without debuginfo --without doc --without perf --without tools --without bpftool \
  ~/rpmbuild/SPECS/kernel-ml.spec

cp ~/rpmbuild/RPMS/"${ARCH}"/kernel-ml*-"${VERSION}"-*"${DIST}"."${ARCH}".rpm "$OUT"/
echo "== built ==" && ls -1 "$OUT"
# fail loud if the exact NVR we pin wasn't produced
ls "$OUT"/kernel-ml-"${VERSION}"-1"${DIST}"."${ARCH}".rpm >/dev/null
