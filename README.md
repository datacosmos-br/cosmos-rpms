# cosmos-rpms — Datacosmos custom RPM source

The **official, public source of Datacosmos custom RPMs** for Oracle Linux 8 (el8), built and signed in
CI and served as a GPG-signed `dnf` repository.

First package: **`kernel-ml` 6.12 LTS** — a clean mainline-stable kernel below the `(6.14, 7.0.10]`
BPF-JIT/verifier regression that wedges cilium/coroot eBPF on OKE nodes (ADR-087). elrepo does not ship
6.12 for el8, so we rebuild it from the elrepo `kernel-ml` spec + the kernel.org tarball.

## Use it

```bash
sudo curl -fsSL https://datacosmos-br.github.io/cosmos-rpms/cosmos-rpms.repo \
  -o /etc/yum.repos.d/cosmos-rpms.repo
sudo dnf install -y kernel-ml-6.12.92          # GPG-verified (gpgcheck=1, repo_gpgcheck=1)
```

Public dnf repo: `https://datacosmos-br.github.io/cosmos-rpms/el8/<arch>/` (x86_64, aarch64).
Public signing key: `https://datacosmos-br.github.io/cosmos-rpms/RPM-GPG-KEY-datacosmos`.

## How it works

- `specs/<pkg>/package.yaml` declares each package's versions + arches + upstream spec source.
- CI (`.github/workflows/build.yml`) generates a build matrix, builds each `(package × arch)` in an
  **Oracle Linux 8 container** (`build/Containerfile`) on a **native runner** (amd64 / arm64 — no QEMU),
  installing the exact upstream `BuildRequires` via `dnf builddep`.
- RPMs are **GPG-signed** with the Datacosmos RPM key, which lives **only in Vault**
  (`datacosmos/global/system/rpm-signing`) and is read by CI via **GitHub OIDC → Vault** — no private key
  is ever stored in GitHub.
- Signed RPMs are attached to a **GitHub Release** (durable store) and published as a signed
  `createrepo_c` repo on **GitHub Pages**.

## Add a package

1. `specs/<name>/package.yaml` (name, el, dist, specSource, versions, arches).
2. If it needs custom build logic, extend `scripts/build-rpm.sh` (keep it standardized; no out-of-loop
   artifact-generation scripts).
3. Push to `main` (or run the workflow) — CI builds, signs, releases, publishes.

## Known limitations

- **`kernel-ml` aarch64 on el8 is not currently shipped.** elrepo has no upstream el8 aarch64 kernel-ml
  spec/config (the el8 spec is x86_64-only; aarch64 lives in el9 with an el9 file layout). The arm64
  matrix leg is **best-effort** and currently fails at the el8 spec's arch-gated `%prep`/`%install`; the
  release/pages jobs run `if: !cancelled()` so **x86_64 publishes regardless**. Producing a real el8
  aarch64 kernel needs porting the el8 spec for arm + validating boot on an actual arm node pool — there
  are none yet (the OKE fleet is `VM.Standard.E6.Flex`, x86_64). Tracked for when arm nodes are added.
- **Era-matched elrepo spec.** Because elrepo's *current* spec targets the latest mainline (7.0+), whose
  `%files` layout differs from 6.12, the kernel build pins `SPEC_REF` to elrepo's **6.12-era** spec
  (`scripts/build-rpm.sh`). Bumping to a newer minor (6.13+, 7.x) requires re-pinning `SPEC_REF` to that
  era's elrepo commit.

## Trust

All packages and repo metadata (`repomd.xml`) are GPG-signed. Verify with the published public key.
See `AGENTS.md` for governance and the signing-key lifecycle.
