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
./setup.sh             # install and configure everything
./setup.sh obsidian    # just one target
```

Targets: `1password` `obsidian` `claude` `espanso` `voxtype` `hyprland`
`claude-code` `obsidian-jump` `fonts`. `hyprland`, `claude-code` and
`obsidian-jump` only write config and need no `sudo`.

The script is idempotent — re-running skips anything already done, so it is safe
to run repeatedly or to resume after a failure.

Expect roughly **15–25 minutes** on a clean instance. The slow parts are
1Password's 204 MB tarball, Claude Desktop's 158 MB download, and Espanso, which
compiles from Rust source.

### Afterwards

1. **Log out and back in** if the script added you to the `input` group. Neither
   Espanso nor Voxtype will capture keys until you do.
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

### Voxtype — slow build, and the models are a separate download

Unlike the other four, `voxtype` builds cleanly on aarch64 — its PKGBUILD
declares the architecture. The problems are elsewhere:

The build is **three sequential Rust release builds** (native CPU, Vulkan, then
the OSD frontends) with a `cargo clean` between each, so it takes roughly five
minutes on eight cores. The `check()` phase would add a fourth in debug mode,
so the script passes `--nocheck`.

The source tarball is **signed**, and `makepkg` stops dead if the two signing
keys are not already in your keyring. The script imports them up front rather
than letting an interactive prompt block an unattended run.

**Models are not bundled.** Install voxtype alone and the daemon starts, loads
nothing, and transcribes silence — which reads as a broken install rather than
a missing download. The script pulls `base.en` (~142 MB) and the Silero VAD
model. VAD stays disabled; voxtype ships it opt-in, and turning it on means
editing `~/.config/voxtype/config.toml`.

Hold **Scroll Lock** to dictate. Text is typed at the cursor via `wtype`.

Do not raise the PKGBUILD's `-j4` limit — it is there to avoid a cmake deadlock
in the whisper-rs build.

---

## Desktop configuration

Two targets write config rather than installing anything, and neither needs
`sudo`.

### `hyprland` — pin apps to fixed workspaces

Appends window rules to `~/.config/hypr/hyprland.lua`, between markers, after
backing the file up. Re-running is a no-op, and if equivalent rules were added
by hand the script leaves them alone rather than stacking duplicates.

| Workspace | Apps |
|-----------|------|
| 1 | Obsidian |
| 2 | Gmail web apps |
| 3 | Claude Desktop, Claude Code |
| 5 | Files (Nautilus) |
| 6 | 1Password, Voxtype settings |

Two things that are not obvious:

**Chromium derives a window class from the URL's host and path only** — the
query string is dropped. Per-account Gmail web apps differing only in
`?authuser=` therefore all share one class, so a single rule catches every one
of them. The flip side is that they cannot be told apart by class.

**Claude Code has its own class.** Omarchy launches it as
`foot --app-id org.omarchy.agent claude`, so pinning it does not drag ordinary
`foot` terminals along.

Rules apply to **newly opened windows only**. Anything already running stays
where it is until you close and reopen it.

### `obsidian-jump` — SUPER + N jumps to any note

Installs `~/.local/bin/obsidian-jump`, binds `SUPER + N`, and adds a
floating-window rule so the picker behaves like a launcher.

Obsidian's own Quick Switcher (`Ctrl+O`) only works once Obsidian is focused,
and **no plugin can change that** — the gap is on the desktop side, not
Obsidian's. The usual Linux answer is Rofi plus a helper plugin, which means
running a second launcher alongside Omarchy's own. This avoids that.

Vaults are read from Obsidian's registry
(`~/.var/app/md.obsidian.Obsidian/config/obsidian/obsidian.json`), falling back
to scanning `~/Documents` for `.obsidian` directories, so new vaults are picked
up without editing anything.

Three decisions worth keeping:

**It does not use `omarchy-menu-select`.** That picker serialises every option
into a *single* `perl` argument, and Linux caps one argument at 128 KB no matter
that `ARG_MAX` is 2 MB. A ~4,000-note vault produces ~370 KB and it dies with
`Argument list too long` — silently, with no window ever appearing. The same
limit applies to `omarchy menu file` on a large directory. `fzf` reads stdin, so
list size is irrelevant. (`fzf` is an Omarchy base package, so it is already
there.)

**Sorting stays on.** `--no-sort` preserves the newest-first input order but
disables match ranking, which buried an exact-title match at position 477.

**Matching is on the filename, not the path** (`--nth=-1`). With the whole path
searchable, an exact title loses to longer paths containing the same words, so
the note you just typed the name of is not the one under the cursor. `Ctrl-T`
widens matching back to the full path for narrowing by folder.

The listing is a single `find` piped through `sort` and `sed` — about 20 ms for
4,000 notes. An earlier per-line shell loop took 2.5 s, which felt broken.

---

### `claude-code` — stop the trust prompt on every launch

Claude Code asks whether you trust the working directory on each start unless
that directory is marked trusted in `~/.claude.json`. `$HOME` in particular
never persists on its own here, so the prompt returns every session. The script
sets `hasTrustDialogAccepted` for your home directory, backing the file up
first.

---

### `fonts` — the screensaver cannot draw its own glyphs

Omarchy's screensaver is `ttfx --random-effect`, and one of those effects is
matrix rain in Japanese katakana. **A stock instance has no font covering
U+30A2 / U+FF71**, so that effect renders as a full screen of tofu boxes.

This is not a local misconfiguration — it is true of any fresh install. Checked
on this machine before fixing:

```
U+30A2 (ア)  *** NO FONT ***
U+FF71 (ｱ)  *** NO FONT ***
U+2588 (█)  JetBrainsMono Nerd Font
U+2591 (░)  JetBrainsMono Nerd Font
```

Only katakana is missing. The Omarchy logo in `screensaver.txt` is block
characters, which JetBrainsMono already covers, so nothing else is affected.

The target installs `adobe-source-han-sans-jp-fonts` (~30 MB). `noto-fonts-cjk`
would also work and adds Chinese and Korean, but costs ~300 MB. Fontconfig
falls back per glyph, so the terminal font is unchanged and only the katakana
come from the new font — no terminal config to edit.

Verify with:

```bash
fc-list ':charset=30a2' family | head -1
```

---

## Known issues on this platform

These are environmental, not caused by anything above. Each one cost real time.

### `omarchy update` is currently broken

`aquamarine` 0.15.0 bumped its library version to `libaquamarine.so=14`.
`hyprtoolkit` has been rebuilt against it; **`hyprland` has not**, in any
configured repo — both `extra` and `try-omarchy` still require
`libaquamarine.so=13`. The dependency is unsatisfiable in either direction, so
`pacman -Syu` aborts during resolution and the whole update does nothing:

```
:: installing aquamarine (0.15.0-2) breaks dependency 'libaquamarine.so=13-64' required by hyprland
error: failed to prepare transaction (could not satisfy dependencies)
```

Nothing is half-installed — it fails before the transaction starts. This is
Arch Linux ARM lag waiting on a `hyprland` rebuild. To unblock the rest:

```bash
sudo pacman -Syu --ignore aquamarine --ignore hyprtoolkit
```

`omarchy-update` runs under `set -e` with the package step ahead of migrations,
hooks, AUR updates and orphan cleanup, so a failure here silently skips all of
them.

### `fcitx5` is missing from a base install

`fcitx5` is listed in `/usr/share/omarchy/install/omarchy-base.packages` and is
available in `extra`, but it was never installed here — it appears nowhere in
`pacman.log`. Migration `1785167800.sh` then enabled `omarchy-fcitx5.service`,
which has been restarting every two seconds ever since:

```
Unable to locate executable '/usr/bin/fcitx5': No such file or directory
```

Fix with `sudo pacman -S fcitx5 fcitx5-gtk fcitx5-qt`, or disable the service
with `systemctl --user disable --now omarchy-fcitx5.service` if you do not need
`~/.XCompose` CapsLock compose sequences.

### The GTK icon cache never rebuilds

Every package install ends with `gtk-update-icon-cache: The generated cache was
invalid.` `/usr/share/icons/hicolor/icon-theme.cache` is stale, so newly
installed apps can show a generic launcher icon. Harmless, but it affects every
app, not just the one being installed:

```bash
sudo gtk-update-icon-cache -f /usr/share/icons/hicolor
```

### The CPU has neither SVE nor SME

`/proc/cpuinfo` on this guest lists `asimd`, `asimddp`, `i8mm`, `bf16` — and
**no `sve`, no `sme`**. `gcc -mcpu=native` resolves to `generic`.

Any aarch64 binary compiled against those extensions dies with `SIGILL` /
`ILL_ILLOPC` here. Brave does exactly this and crash-loops, which once filled
the disk with coredumps. Expect it from any Chromium or Electron app.

The advertised feature set has appeared to differ between boots, so read
`/proc/cpuinfo` rather than trusting a cached list — and when an ARM binary
dies with SIGILL, disassemble the faulting instruction before assuming memory
corruption.

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
Voxtype          1.0.1-1
  model          present
workspace rules  applied
obsidian-jump    installed (SUPER + N)
katakana font    Source Han Sans JP
fcitx5           MISSING — omarchy-fcitx5.service will crash-loop
edk2-aarch64     202608-1
input group      yes
/dev/kvm         absent — Cowork sandbox degraded
```

`/dev/kvm absent` is expected until nested virt is enabled on the macOS side.
`fcitx5 MISSING` is the upstream gap described above, not something this script
causes. Everything else should say installed or applied.

---

## Bootstrapping a fresh instance

On a brand-new Try-Omarchy VM, git is already present. One line gets you from
nothing to a configured instance:

```bash
git clone https://github.com/jhunt299/try-omarchy-setup && ./try-omarchy-setup/setup.sh
```

Nothing in this repo is private: no credentials, no vault content, no personal
paths beyond `~/Documents/Hunt-Remote` as the Obsidian vault location, and no
email addresses. Per-account web-app setup is deliberately left out for that
reason — it would hardcode addresses into a public repo.

---

## Versions this was built against

Captured 2026-09-14 from the working instance:

| Component | Version |
|---|---|
| 1Password | 8.12.36 (arm64) |
| Obsidian | 1.13.7 (flatpak, flathub) |
| Claude Desktop | 1.52386.6-1 (AUR) |
| Espanso | 2.4.1-1 (`espanso-wayland`, AUR) |
| Voxtype | 1.0.1-1 (AUR, built from source) |
| Whisper model | `ggml-base.en.bin` (~142 MB) |
| Hyprland | 0.56.1 |
| fzf | 0.74.3 (Omarchy base package) |
| Japanese font | adobe-source-han-sans-jp-fonts 2.005-2 |
| edk2-aarch64 | 202608-1 (Arch `extra`) |
| Kernel | 7.2.2-2-aarch64-ARCH |

The script pins nothing — it always fetches current versions. This table is for
diagnosing "it worked in September and broke in December."
