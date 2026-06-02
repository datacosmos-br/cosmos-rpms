# AGENTS.md — cosmos-rpms governance

Official source of Datacosmos custom RPMs. Everything here is **in the GitOps/CI loop** — no manual RPM
builds, no out-of-loop artifact generation, no hand-uploaded binaries.

## Principles

- **Reproducible builds only.** Every RPM is produced by `.github/workflows/build.yml` in the el8
  container (`build/Containerfile`) from a declared `specs/<pkg>/package.yaml`. Never commit prebuilt RPMs.
- **Standardized harness.** One build path: `scripts/build-rpm.sh` (fetch upstream spec → `dnf builddep`
  → set version → `olddefconfig` → `rpmbuild`). Per-package variation lives in `package.yaml`, not in forks
  of the script.
- **Multi-arch is first-class.** amd64 + arm64 build on native runners. For the kernel, el8 has no
  upstream aarch64 config — the el9 config is the documented donor (`build-rpm.sh`).
- **Signed + verifiable.** All RPMs + `repomd.xml` are GPG-signed; clients use `gpgcheck=1` +
  `repo_gpgcheck=1`.

## Signing-key lifecycle (Vault is SSOT)

- The Datacosmos RPM GPG **private** key + passphrase live ONLY in Vault at
  `secret/datacosmos/global/system/rpm-signing` (`private`, `public`, `passphrase`, `keyname`).
- CI reads it via **GitHub OIDC → Vault** (`auth/jwt` mount `jwt-github`, role `cosmos-rpms-ci` bound to
  `repository:datacosmos-br/cosmos-rpms`). No GPG secret is stored in GitHub Actions.
- The **public** key is committed as `RPM-GPG-KEY-datacosmos` and served from Pages.
- Key generation/rotation is a documented break-glass that writes Vault directly; never weaken to a
  GitHub-stored key.

## Publishing

- GitHub Releases hold the signed RPM assets (tag = main package NVR).
- GitHub Pages serves the `createrepo_c` repo at `el8/<arch>/` + the public key + `cosmos-rpms.repo`.

## Consumers

The OKE `kernel-pin-installer` (cosmos-charts `cosmos-kube-system`) adds `cosmos-rpms.repo` and
`dnf install kernel-ml-<nvr>` (ADR-087). This repo is the single source; do not vendor these RPMs elsewhere.
