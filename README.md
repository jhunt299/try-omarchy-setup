# Try-Omarchy Setup

Automated install of **1Password, Obsidian, Claude Desktop, and Espanso** on a
fresh Try-Omarchy instance.

**Target:** Omarchy `try-omarchy` channel · aarch64 Arch Linux ARM · running as a
VM guest on an M4 Max MacBook Pro.

Everything here was derived from the working install on this machine, so each
workaround below is a fix for a problem that actually happened — not a
precaution.

---

## Run it

```bash
git clone https://github.com/jhunt299/try-omarchy-setup
cd try-omarchy-setup
./setup.sh --check     # report what's installed, change nothing
./setup.sh             # install all four
./setup.sh obsidian    # just one (1password | obsidian | claude | espanso)
```

The script is idempotent — re-running skips anything already done, so it is safe
to run repeatedly or to resume after a failure.

Expect roughly **15–25 minutes** on a clean instance. The slow parts are
1Password's 204 MB tarball, Claude Desktop's 158 MB download, and Espanso, which
compiles from Rust source.

### Afterwards

1. **Log out and back in** if the script added you to the `input` group. Espanso
   will not expand anything until you do.
2. Open Obsidian and point it at `~/Documents/Hunt-Remote`.
3. Sign in to 1Password and Claude Desktop.

---

## Why each app needs special handling

This is the part worth keeping. The obvious install command fails for **all
four** apps on this machine, each for a different reason.

### 1Password — no package exists for aarch64

The AUR `1password` package is x86_64-only, so there is no pacman route at all.
1Password does publish an official **aarch64 tarball** that ships its own
installer:

```
https://downloads.1password.com/linux/tar/stable/aarch64/1password-latest.tar.gz
```

The bundled `install.sh` handles the parts that are easy to get wrong, so the
script just calls it rather than reimplementing any of it:

- the polkit policy for system unlock (templated with the machine's real users)
- the `onepassword` and `onepassword-mcp` groups, with setgid helper binaries
- the setuid bit on `chrome-sandbox` (Electron refuses to sandbox without it)
- the `.desktop` entry, icons, and the `/usr/bin/1password` symlink

> [!warning] No auto-updates
> 1Password's updater only registers an apt/dnf repository, and neither applies
> here. A tarball install **never updates itself**. To upgrade:
> ```bash
> sudo /opt/1Password/after-remove.sh && sudo rm -rf /opt/1Password
> ./setup.sh 1password
> ```

### Obsidian — Flatpak, and it must not use the GPU

Flathub publishes an aarch64 build; the AUR package targets x86_64. So: Flatpak.

The critical part is this override:

```bash
flatpak override --user --env=OBSIDIAN_DISABLE_GPU=1 md.obsidian.Obsidian
```

This VM has no GPU acceleration. Without the override Obsidian launches to a
blank window — the Electron renderer never paints. This is the single setting
that makes Obsidian usable here.

Vault access needs no extra permission: the Flatpak already holds
`filesystem=home`, which covers `~/Documents/Hunt-Remote`.

### Claude Desktop — yay cannot install it

Two separate aarch64 problems stack up here.

**1. yay mishandles architecture-split dependencies.** The AUR PKGBUILD is
correct — it declares `depends_x86_64` and `depends_aarch64` separately — but
yay's resolver tries to satisfy *both* sets and aborts on an aarch64 machine:

```
-> No AUR package found for edk2-ovmf (required by: claude-desktop)
-> could not find all required packages: edk2-ovmf
```

`edk2-ovmf` is the **x86** firmware; it is irrelevant here and correctly scoped
to x86_64 in the PKGBUILD. `makepkg` honors `$CARCH` properly, so the script
clones the AUR repo and builds directly, bypassing yay entirely. Worth
remembering for any other split-architecture AUR package.

**2. Arch Linux ARM ships no `edk2-*` package at all.** The genuine aarch64
dependency — `edk2-aarch64`, the UEFI firmware Cowork's QEMU sandbox boots from —
is in Arch proper but absent from every ALARM repo. It is an
**`any`-architecture** package (firmware blobs, nothing linked), so Arch's own
build installs cleanly on ALARM. The script resolves the current version from
the Arch package API, verifies the signature against the local pacman keyring,
and installs it.

> [!note] Mirror path gotcha
> `any` packages are **not** served from `extra/os/any/` — that path 404s. They
> live under each real architecture directory, so the script pulls from
> `extra/os/x86_64/` even though the package itself is architecture-independent.

> [!warning] Outside the update stream
> `edk2-aarch64` comes from Arch, not ALARM, so `pacman -Syu` will never update
> it. It is firmware that changes rarely, so this is low-stakes — but it is yours
> to re-pull manually.

### Espanso — Wayland build, plus the `input` group

Two requirements, and missing either produces a **silent** failure:

- Install `espanso-wayland` from the AUR, not `espanso` (that one is X11).
- Your user must be in the **`input`** group. Espanso reads the keyboard through
  evdev; without group membership it starts cleanly, reports itself as running,
  and expands nothing.

Then register the user service:

```bash
espanso service register
systemctl --user enable --now espanso
```

Config lives in `~/.config/espanso/` — `config/default.yml` and
`match/base.yml`. Test with `:espanso`, which should expand to "Hi there!".

> [!tip] Your snippets are not in this repo
> `House/Internet/Espanso archive` and `Textexpander archive` are both **empty**.
> The script installs a working Espanso with stock config only. If your real
> match files exist somewhere else, drop them into `~/.config/espanso/match/` —
> and consider committing them alongside this script so a rebuild restores them
> automatically.

---

## Cowork and nested virtualisation

Claude Desktop's **Cowork** feature runs its sandbox inside a QEMU VM. On this
machine that is nested virtualisation, and it is currently **not available**:

- `/dev/kvm` — **absent**. The hypervisor is not exposing nested virt to this guest.
- `/dev/vhost-vsock` — present, so the host↔VM channel itself is fine.

The M4 Max hardware does support nested virtualisation (Apple Silicon added it
with M3), so this is a macOS-side setting, not a hardware limit — your
virtualisation app needs nested virt enabled for this guest, and support varies
by app. Until then Cowork falls back to software emulation.

**Chat and Claude Code are unaffected** and work normally.

---

## Verifying

```bash
./setup.sh --check
```

A healthy instance reports:

```
1Password        installed
Obsidian         installed (flatpak)
Claude Desktop   1.52386.6-1
Espanso          2.4.1-1
edk2-aarch64     202608-1
input group      yes
/dev/kvm         absent — Cowork sandbox degraded
```

`/dev/kvm absent` is expected until nested virt is enabled on the macOS side.
Everything else should say installed.

---

## Bootstrapping a fresh instance

On a brand-new Try-Omarchy VM, git is already present. One line gets you from
nothing to all four apps:

```bash
git clone https://github.com/jhunt299/try-omarchy-setup && ./try-omarchy-setup/setup.sh
```

Nothing in this repo is private: no credentials, no vault content, no personal
paths beyond `~/Documents/Hunt-Remote` as the Obsidian vault location.

---

## Versions this was built against

Captured 2026-09-14 from the working instance:

| Component | Version |
|---|---|
| 1Password | 8.12.36 (arm64) |
| Obsidian | 1.13.7 (flatpak, flathub) |
| Claude Desktop | 1.52386.6-1 (AUR) |
| Espanso | 2.4.1-1 (`espanso-wayland`, AUR) |
| edk2-aarch64 | 202608-1 (Arch `extra`) |
| Kernel | 7.2.2-2-aarch64-ARCH |

The script pins nothing — it always fetches current versions. This table is for
diagnosing "it worked in September and broke in December."
