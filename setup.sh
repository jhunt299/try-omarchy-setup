#!/usr/bin/env bash
#
# Try-Omarchy app setup — 1Password, Obsidian, Claude Desktop, Espanso
#
# Target: Omarchy "try-omarchy" channel, aarch64 Arch Linux ARM,
#         running as a VM guest on an M4 Max MacBook Pro.
#
# Every step is idempotent: re-running skips what is already done.
#
# Usage:
#   ./setup.sh                 # install and configure everything
#   ./setup.sh 1password       # one target
#   ./setup.sh obsidian claude # several
#   ./setup.sh --check         # report state, change nothing
#
#   Targets: 1password obsidian claude espanso voxtype hyprland claude-code
#            obsidian-jump fonts
#
set -euo pipefail

# ---------------------------------------------------------------- constants

AUR_CLAUDE="https://aur.archlinux.org/claude-desktop.git"
ONEPASSWORD_TAR="https://downloads.1password.com/linux/tar/stable/aarch64/1password-latest.tar.gz"
ARCH_API="https://archlinux.org/packages/search/json/?name=edk2-aarch64&repo=Extra"
# Arch mirrors file `any`-architecture packages under each real arch directory;
# there is no extra/os/any/ path (it 404s). x86_64 is the canonical one to pull
# from, and the package itself is architecture-independent firmware.
ARCH_MIRROR="https://geo.mirror.pkgbuild.com/extra/os/x86_64"

BUILD_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/try-omarchy-setup"

# ------------------------------------------------------------------ output

if [[ -t 1 ]]; then
  B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; D=$'\e[2m'; N=$'\e[0m'
else
  B=""; G=""; Y=""; R=""; D=""; N=""
fi

step() { printf '\n%s==>%s %s%s%s\n' "$B$G" "$N" "$B" "$*" "$N"; }
info() { printf '    %s\n' "$*"; }
skip() { printf '    %s— %s%s\n' "$D" "$*" "$N"; }
warn() { printf '    %s!  %s%s\n' "$Y" "$*" "$N"; }
die()  { printf '\n%sERROR:%s %s\n' "$R$B" "$N" "$*" >&2; exit 1; }

have()      { command -v "$1" >/dev/null 2>&1; }
pkg_local() { pacman -Q "$1" >/dev/null 2>&1; }

# ------------------------------------------------------------ sudo session
#
# A full run is 15-25 minutes, most of it Rust builds for Espanso and Voxtype.
# sudo's timestamp here is the default 15 minutes per tty, so a build that runs
# longer than that makes the *next* sudo call re-prompt, often unattended and
# halfway down the screen. Authenticate once up front, then refresh the
# timestamp in the background for as long as the script lives.
#
# Only started when a requested target actually needs root: running just
# `./setup.sh hyprland` must not ask for a password it never uses.

SUDO_KEEPALIVE_PID=""

stop_sudo_keepalive() {
  [[ -n $SUDO_KEEPALIVE_PID ]] || return 0
  kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  SUDO_KEEPALIVE_PID=""
}

start_sudo_keepalive() {
  step "Authenticating"
  info "Asking for your password once now, so long builds don't re-prompt later."
  sudo -v || die "Could not authenticate with sudo."

  # `kill -0 $$` — $$ stays the parent's pid inside a subshell, so the refresher
  # stops on its own if the script is killed rather than exiting cleanly.
  local parent=$$
  ( while kill -0 "$parent" 2>/dev/null; do
      sudo -n true 2>/dev/null || exit 0
      sleep 60
    done ) &
  SUDO_KEEPALIVE_PID=$!
  trap stop_sudo_keepalive EXIT INT TERM
}

# True when any requested target does privileged work.
targets_need_sudo() {
  local t
  for t in "$@"; do
    case "$t" in
      hyprland|workspaces|claude-code|cc|obsidian-jump|jump) ;;
      *) return 0 ;;
    esac
  done
  return 1
}

# --------------------------------------------------------------- preflight

preflight() {
  [[ $EUID -ne 0 ]] || die "Run as your normal user, not root. Individual steps call sudo themselves."
  [[ "$(uname -m)" == "aarch64" ]] || die "This script targets aarch64. Detected: $(uname -m)."
  have pacman || die "pacman not found — this is not an Arch system."

  # base-devel + git are needed to build anything from the AUR. base-devel is a
  # package *group*, so `pacman -Q base-devel` always fails and must not be used
  # as the test — checking for the tools themselves is what actually works.
  local need=()
  if ! { have gcc && have make && have fakeroot; }; then need+=(base-devel); fi
  have git || need+=(git)
  if ((${#need[@]})); then
    step "Installing build prerequisites: ${need[*]}"
    sudo pacman -S --needed --noconfirm "${need[@]}"
  fi

  mkdir -p "$BUILD_DIR"
}

# ------------------------------------------------------------- 1) 1Password
#
# There is no working pacman/AUR route on aarch64: the AUR `1password` package
# is x86_64-only. 1Password does publish an official aarch64 tarball, which
# ships its own installer. That installer does all the fiddly work — polkit
# policy for system unlock, the `onepassword` / `onepassword-mcp` groups, the
# setuid bit on chrome-sandbox, the .desktop entry, icons, and the /usr/bin
# symlinks — so we do not reimplement any of it.

install_1password() {
  step "1Password"

  if [[ -d /opt/1Password ]]; then
    local v
    v=$(find /opt/1Password -maxdepth 1 -name '1password-*.arm64' -printf '%f\n' 2>/dev/null | head -1)
    skip "already installed${v:+ ($v)}"
    info "To update: sudo /opt/1Password/after-remove.sh && sudo rm -rf /opt/1Password, then re-run."
    return 0
  fi

  local tmp; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' RETURN

  info "Downloading official aarch64 tarball (~204 MB)..."
  curl -fL# -o "$tmp/1password.tar.gz" "$ONEPASSWORD_TAR" || die "1Password download failed."

  info "Extracting..."
  tar -xzf "$tmp/1password.tar.gz" -C "$tmp"

  local src
  src=$(find "$tmp" -maxdepth 1 -type d -name '1password-*' | head -1)
  [[ -n "$src" && -x "$src/install.sh" ]] || die "Unexpected tarball layout — no install.sh found."

  info "Running vendor installer (needs root)..."
  sudo sh "$src/install.sh"

  info "Installed. Launch from the app launcher or run: 1password"
  warn "Tar installs do NOT auto-update (the vendor's updater is deb/rpm only)."
  warn "Re-run this script after removing /opt/1Password to upgrade."
}

# --------------------------------------------------------------- 2) Obsidian
#
# Flatpak, not AUR: Flathub publishes an aarch64 build, and the AUR package
# expects x86_64. The GPU override is the important part — this VM gets no
# GPU acceleration (no /dev/kvm, no passthrough), and Obsidian's Electron
# renderer fails to paint without it.

install_obsidian() {
  step "Obsidian"

  have flatpak || { info "Installing flatpak..."; sudo pacman -S --needed --noconfirm flatpak; }

  if ! flatpak remotes --columns=name | grep -qx flathub; then
    info "Adding Flathub remote..."
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  fi

  if flatpak info md.obsidian.Obsidian >/dev/null 2>&1; then
    skip "already installed ($(flatpak info --show-version md.obsidian.Obsidian 2>/dev/null))"
  else
    info "Installing from Flathub..."
    flatpak install -y --noninteractive flathub md.obsidian.Obsidian
  fi

  # Software rendering. Without this Obsidian opens to a blank/black window.
  info "Forcing software rendering (OBSIDIAN_DISABLE_GPU=1)..."
  flatpak override --user --env=OBSIDIAN_DISABLE_GPU=1 md.obsidian.Obsidian

  info "Vault access: the Flatpak holds filesystem=home by default, which covers"
  info "~/Documents/Hunt-Remote. Point Obsidian at it on first launch."
}

# --------------------------------------------------- 3) Claude Desktop (AUR)
#
# Two aarch64-specific problems, both handled here:
#
#   1. yay cannot install this package. The PKGBUILD correctly splits
#      depends_x86_64 / depends_aarch64, but yay's AUR resolver ignores the
#      split and tries to satisfy BOTH — so on aarch64 it demands edk2-ovmf
#      (x86-only) and aborts. makepkg honors $CARCH, so we build directly.
#
#   2. Arch Linux ARM ships no edk2-* package at all, so the real aarch64
#      dependency (edk2-aarch64, UEFI firmware for Cowork's QEMU sandbox) is
#      missing. It is an `any`-architecture package — firmware blobs, nothing
#      linked — so the build from Arch's x86_64 mirror installs cleanly here.

ensure_edk2() {
  if pkg_local edk2-aarch64; then
    skip "edk2-aarch64 already installed"
    return 0
  fi

  info "Resolving current edk2-aarch64 version from the Arch package API..."
  local fname
  fname=$(curl -fsSL "$ARCH_API" | python3 -c \
    'import json,sys; r=json.load(sys.stdin)["results"]; print(r[0]["filename"] if r else "")') \
    || die "Could not query the Arch package API."
  [[ -n "$fname" ]] || die "Arch API returned no edk2-aarch64 package."

  local tmp; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' RETURN
  info "Downloading $fname..."
  curl -fL# -o "$tmp/$fname" "$ARCH_MIRROR/$fname" || die "edk2-aarch64 download failed."

  # Signed by an Arch developer whose key is already in the ALARM keyring, so
  # this verifies even though the package comes from a different distro's mirror.
  if curl -fsSL -o "$tmp/$fname.sig" "$ARCH_MIRROR/$fname.sig"; then
    if gpg --homedir /etc/pacman.d/gnupg --verify "$tmp/$fname.sig" "$tmp/$fname" >/dev/null 2>&1; then
      info "Signature verified against the pacman keyring."
    else
      warn "Signature did NOT verify. Inspect $tmp/$fname before trusting it."
      die "Refusing to install an unverified firmware package."
    fi
  else
    warn "No .sig available; continuing (LocalFileSigLevel is Optional)."
  fi

  info "Installing edk2-aarch64..."
  sudo pacman -U --noconfirm "$tmp/$fname"
  warn "edk2-aarch64 comes from Arch, not ALARM — 'pacman -Syu' will not update it."
}

install_claude() {
  step "Claude Desktop"

  if pkg_local claude-desktop; then
    skip "already installed ($(pacman -Q claude-desktop | awk '{print $2}'))"
  else
    ensure_edk2

    info "Installing runtime dependencies..."
    sudo pacman -S --needed --noconfirm virtiofsd qemu-system-aarch64

    local repo="$BUILD_DIR/claude-desktop"
    if [[ -d "$repo/.git" ]]; then
      info "Updating existing AUR checkout..."
      git -C "$repo" pull --ff-only
    else
      info "Cloning AUR package..."
      rm -rf "$repo"
      git clone --quiet "$AUR_CLAUDE" "$repo"
    fi

    echo
    warn "Review the PKGBUILD before building (this is AUR, i.e. untrusted):"
    warn "  less $repo/PKGBUILD"
    echo

    # -d skips makepkg's dep check: we installed the aarch64 deps above, and
    # makepkg would otherwise re-resolve them. -f overwrites a stale build.
    info "Building (downloads a ~158 MB .deb, takes a few minutes)..."
    ( cd "$repo" && makepkg -f -d )

    local built
    built=$(find "$repo" -maxdepth 1 -name 'claude-desktop-*.pkg.tar.*' | head -1)
    [[ -n "$built" ]] || die "Build produced no package."

    info "Installing $(basename "$built")..."
    sudo pacman -U --noconfirm "$built"
  fi

  # Cowork runs its sandbox in QEMU. That is nested virtualisation here.
  if [[ -e /dev/kvm ]]; then
    info "/dev/kvm present — Cowork's VM sandbox should be hardware-accelerated."
  else
    warn "/dev/kvm is absent: nested virtualisation is not exposed to this guest."
    warn "Cowork's sandbox will fall back to slow software emulation, or fail."
    warn "Fix on the macOS side: enable nested virtualisation for this VM in your"
    warn "hypervisor. The M4 Max supports it (Apple Silicon added it with M3)."
    warn "Chat and Claude Code are unaffected."
  fi
}

# ---------------------------------------------------------------- 4) Espanso
#
# Wayland needs the separate `espanso-wayland` AUR build (the plain `espanso`
# package is X11). It reads the keyboard through evdev, so the user must be in
# the `input` group — without it espanso starts but silently expands nothing.

install_espanso() {
  step "Espanso"

  if pkg_local espanso-wayland; then
    skip "espanso-wayland already installed ($(pacman -Q espanso-wayland | awk '{print $2}'))"
  else
    have yay || die "yay not found. Install an AUR helper, or build espanso-wayland with makepkg."
    info "Installing espanso-wayland from the AUR (Rust build — this is slow)..."
    yay -S --needed espanso-wayland
  fi

  if id -nG "$USER" | tr ' ' '\n' | grep -qx input; then
    skip "$USER is already in the 'input' group"
  else
    info "Adding $USER to the 'input' group (required for key capture on Wayland)..."
    sudo gpasswd -a "$USER" input
    warn "Log out and back in for the new group to take effect."
  fi

  if [[ -f "$HOME/.config/systemd/user/espanso.service" ]]; then
    skip "service already registered"
  else
    info "Registering the espanso user service..."
    espanso service register
  fi

  systemctl --user enable --now espanso >/dev/null 2>&1 || \
    warn "Could not start the service — try 'systemctl --user status espanso' after relogin."

  info "Config lives in ~/.config/espanso (config/default.yml, match/base.yml)."
  info "Test with ':espanso' — it should expand to 'Hi there!'."
}

# --------------------------------------------------------------- 5) voxtype
#
# Push-to-talk voice-to-text. The AUR package builds from Rust source and does
# declare aarch64, so it works here — but three things make it slow or fragile:
#
#   * The PKGBUILD runs three sequential release builds (native CPU, Vulkan,
#     then the OSD frontends) with a `cargo clean` between each. Its check()
#     phase would add a fourth in debug mode, so we skip it.
#   * The source tarball is signed, and makepkg aborts if the two signing keys
#     are not already in the user keyring. We import them first rather than
#     letting the build stop on an interactive prompt.
#   * Models are not bundled. Without them the daemon starts and transcribes
#     nothing, which looks like a broken install rather than a missing download.

VOXTYPE_KEYS=(
  E79F5BAF8CD51A806AA27DBB7DA2709247D75BC6  # maintainer (legacy assets)
  9CCF7915B750CAE8B095ED1AA3FC9F33FD209279  # CI release signing
)
VOXTYPE_MODEL="base.en"

ensure_input_group() {
  if id -nG "$USER" | tr ' ' '\n' | grep -qx input; then
    skip "$USER is already in the 'input' group"
  else
    info "Adding $USER to the 'input' group (required for key capture on Wayland)..."
    sudo gpasswd -a "$USER" input
    warn "Log out and back in for the new group to take effect."
  fi
}

install_voxtype() {
  step "Voxtype"

  if pkg_local voxtype; then
    skip "voxtype already installed ($(pacman -Q voxtype | awk '{print $2}'))"
  else
    have yay || die "yay not found. Install an AUR helper, or build voxtype with makepkg."

    info "Importing the voxtype signing keys..."
    for k in "${VOXTYPE_KEYS[@]}"; do
      gpg --list-keys "$k" >/dev/null 2>&1 && continue
      gpg --keyserver keyserver.ubuntu.com --recv-keys "$k" >/dev/null 2>&1 || \
        warn "Could not fetch key $k — the build may stop to ask about it."
    done

    info "Building voxtype from the AUR (three Rust release builds — ~5 min on 8 cores)..."
    yay -S --needed --mflags --nocheck voxtype
  fi

  ensure_input_group

  # Whisper model. Without --no-post-install this prints a second copy of the
  # package's own next-steps banner.
  if compgen -G "$HOME/.local/share/voxtype/models/*.bin" >/dev/null; then
    skip "a model is already present ($(basename "$(ls "$HOME"/.local/share/voxtype/models/*.bin | head -1)"))"
  else
    info "Downloading the $VOXTYPE_MODEL Whisper model (~142 MB)..."
    voxtype setup --download --model "$VOXTYPE_MODEL" --no-post-install
  fi

  # Silero VAD — downloaded here, but left disabled: voxtype ships it opt-in.
  if [[ -f "$HOME/.local/share/voxtype/models/ggml-silero-vad.bin" ]]; then
    skip "VAD model already present"
  else
    info "Downloading the Silero VAD model..."
    voxtype setup vad >/dev/null 2>&1 || warn "VAD download failed — not fatal."
  fi

  systemctl --user enable --now voxtype >/dev/null 2>&1 || \
    warn "Could not start the service — try 'systemctl --user status voxtype'."

  info "Hold Scroll Lock to dictate; text is typed at the cursor via wtype."
  info "To enable VAD, set [vad] enabled = true in ~/.config/voxtype/config.toml."
}

# ------------------------------------------------- 6) desktop configuration

# Hyprland window rules pinning apps to fixed workspaces. Appended to the user
# config rather than written over it, and guarded by a marker so re-running
# does not stack duplicates.
HYPR_MARKER="-- >>> try-omarchy-setup: workspace rules >>>"

configure_hyprland() {
  step "Hyprland workspace rules"

  local conf="$HOME/.config/hypr/hyprland.lua"
  [[ -f $conf ]] || { warn "$conf not found — skipping."; return 0; }

  if grep -qF -- "$HYPR_MARKER" "$conf"; then
    skip "workspace rules already present"
  elif grep -qF 'md\\.obsidian' "$conf"; then
    skip "equivalent rules already added by hand — leaving them alone"
  else
    info "Appending workspace rules to hyprland.lua..."
    cp "$conf" "$conf.bak.$(date +%s)"
    cat >>"$conf" <<'RULES'

-- >>> try-omarchy-setup: workspace rules >>>
-- Obsidian (all vaults share one class) on workspace 1.
o.window("^md\\.obsidian\\.Obsidian$", { workspace = "1" })

-- Gmail web apps on workspace 2. Chromium derives the window class from the
-- URL's host and path only — the ?authuser= query is dropped — so every
-- per-account Gmail web app shares this one class. Harmless if none exist.
o.window("^brave-mail\\.google\\.com__mail.*-Default$", { workspace = "2" })

-- Claude Desktop and Claude Code on workspace 3. Claude Code runs as
-- `foot --app-id org.omarchy.agent claude`, so it has its own class and this
-- does not affect ordinary foot terminals.
o.window("^com\\.anthropic\\.Claude$", { workspace = "3" })
o.window("^org\\.omarchy\\.agent$", { workspace = "3" })

-- Files on workspace 5.
o.window("^org\\.gnome\\.Nautilus$", { workspace = "5" })

-- 1Password and the voxtype settings TUI on workspace 6.
o.window("^com\\.onepassword\\.OnePassword$", { workspace = "6" })
o.window("^voxtype$", { workspace = "6" })
-- <<< try-omarchy-setup: workspace rules <<<
RULES
  fi

  if have hyprctl && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    hyprctl reload >/dev/null 2>&1 || true
    local errs
    errs=$(hyprctl configerrors 2>/dev/null | tr -d '[:space:]')
    [[ -z $errs ]] || warn "hyprctl reported config errors — run 'hyprctl configerrors'."
  else
    info "Hyprland is not running; rules apply at next login."
  fi

  info "Rules apply to newly opened windows only — existing ones stay put."
}

# Claude Code prompts to trust the working directory on every launch unless the
# directory is marked trusted in ~/.claude.json. $HOME in particular never
# persists on its own here.
configure_claude_code() {
  step "Claude Code trust prompt"

  local cfg="$HOME/.claude.json"
  if [[ ! -f $cfg ]]; then
    skip "no ~/.claude.json yet — run Claude Code once, then re-run this step"
    return 0
  fi

  have python3 || { warn "python3 not found — skipping."; return 0; }

  python3 - "$cfg" "$HOME" <<'PY'
import json, shutil, sys, time
cfg, home = sys.argv[1], sys.argv[2]
with open(cfg) as f:
    data = json.load(f)
proj = data.setdefault("projects", {}).setdefault(home, {})
if proj.get("hasTrustDialogAccepted") is True:
    print("    \033[2m— already trusted\033[0m")
else:
    shutil.copy2(cfg, f"{cfg}.bak.{int(time.time())}")
    proj["hasTrustDialogAccepted"] = True
    with open(cfg, "w") as f:
        json.dump(data, f, indent=2)
    print(f"    marked {home} as trusted (backup written)")
PY
}

# -------------------------------------------------- 7) obsidian note jumper
#
# SUPER + N opens a fuzzy picker over every note in every vault and opens the
# choice in Obsidian. Obsidian's own Quick Switcher only works when Obsidian is
# already focused, and no plugin can fix that — the gap is on the desktop side.
#
# Two things this deliberately does not do:
#   * It does not use omarchy-menu-select. That picker serialises every option
#     into a single perl argument, and Linux caps one argument at 128 KB
#     regardless of ARG_MAX. A few thousand notes exceed that and it dies with
#     "Argument list too long", silently, with no window. fzf reads stdin.
#   * It does not add rofi. Omarchy already has a launcher; a second one means
#     a second config and a second theme to keep in sync.

JUMP_BIN="$HOME/.local/bin/obsidian-jump"
JUMP_MARKER="-- >>> try-omarchy-setup: obsidian jump >>>"

configure_obsidian_jump() {
  step "Obsidian note jumper (SUPER + N)"

  have fzf || { warn "fzf not installed — skipping."; return 0; }

  local src="$(dirname "$(readlink -f "$0")")/bin/obsidian-jump"
  if [[ ! -f $src ]]; then
    warn "bin/obsidian-jump missing from the repo — skipping."
    return 0
  fi

  mkdir -p "$HOME/.local/bin"
  if [[ -f $JUMP_BIN ]] && cmp -s "$src" "$JUMP_BIN"; then
    skip "obsidian-jump already up to date"
  else
    install -m 755 "$src" "$JUMP_BIN"
    info "Installed $JUMP_BIN"
  fi

  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) warn "~/.local/bin is not on PATH — the keybinding will not find the script." ;;
  esac

  # Keybinding
  local binds="$HOME/.config/hypr/bindings.lua"
  if [[ ! -f $binds ]]; then
    warn "$binds not found — skipping keybinding."
  elif grep -qF -- "$JUMP_MARKER" "$binds" || grep -qF 'obsidian-jump' "$binds"; then
    skip "SUPER + N already bound"
  else
    cp "$binds" "$binds.bak.$(date +%s)"
    cat >>"$binds" <<'BIND'

-- >>> try-omarchy-setup: obsidian jump >>>
-- Jump straight to any Obsidian note, across every vault, without Obsidian
-- needing focus first.
o.bind("SUPER + N", "Obsidian note", "obsidian-jump")
-- <<< try-omarchy-setup: obsidian jump <<<
BIND
    info "Bound SUPER + N"
  fi

  # Float the picker terminal like a launcher rather than tiling it.
  local conf="$HOME/.config/hypr/hyprland.lua"
  if [[ -f $conf ]] && ! grep -qF 'obsidian-jump' "$conf"; then
    cat >>"$conf" <<'FLOAT'

-- The SUPER + N note picker: a floating terminal running fzf.
o.window("^obsidian-jump$", { float = true, center = true, size = { 900, 600 } })
FLOAT
    info "Added the floating-window rule"
  else
    skip "window rule already present"
  fi

  if have hyprctl && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    hyprctl reload >/dev/null 2>&1 || true
  fi

  info "Press SUPER + N, type part of a note name, Enter. Ctrl-T widens the"
  info "search from the filename to the full path."
}

# ----------------------------------------------------------------- 8) fonts
#
# Omarchy's screensaver is ttfx with --random-effect, and one of those effects
# is matrix rain drawn in Japanese katakana. A stock instance has no font
# covering U+30A2 / U+FF71, so the effect renders as a screen of tofu boxes.
# Nothing else in the screensaver is affected — its logo is block characters,
# which JetBrainsMono Nerd Font already covers.
#
# Source Han Sans JP is the balance: ~30 MB for Japanese, against ~300 MB for
# noto-fonts-cjk if Chinese and Korean are also wanted. Fontconfig falls back
# per glyph, so the terminal font is unchanged and only the katakana come from
# here — no terminal config edit.

JP_FONT_PKG="adobe-source-han-sans-jp-fonts"

have_katakana() {
  # U+30A2 KATAKANA LETTER A — present iff some font can draw the matrix rain.
  [[ -n $(fc-list ':charset=30a2' family 2>/dev/null | head -1) ]]
}

install_fonts() {
  step "Japanese font (screensaver katakana)"

  if ! have fc-list; then
    warn "fontconfig not found — skipping."
    return 0
  fi

  if have_katakana; then
    skip "katakana already covered by $(fc-list ':charset=30a2' family 2>/dev/null | head -1 | cut -d, -f1)"
    return 0
  fi

  if pkg_local "$JP_FONT_PKG"; then
    info "$JP_FONT_PKG is installed but katakana is still unresolved; refreshing the font cache..."
    fc-cache -f >/dev/null 2>&1 || true
  else
    info "Installing $JP_FONT_PKG (~30 MB) so the matrix screensaver renders..."
    sudo pacman -S --needed --noconfirm "$JP_FONT_PKG"
    fc-cache -f >/dev/null 2>&1 || true
  fi

  if have_katakana; then
    info "Katakana now resolves to: $(fc-list ':charset=30a2' family 2>/dev/null | head -1 | cut -d, -f1)"
  else
    warn "Katakana still unresolved — try 'fc-cache -fv' and re-check with 'fc-list :charset=30a2'."
  fi
}

# ------------------------------------------------------------------- report

report() {
  step "Current state"
  printf '    %-16s %s\n' "1Password" \
    "$([[ -d /opt/1Password ]] && echo "installed" || echo "MISSING")"
  printf '    %-16s %s\n' "Obsidian" \
    "$(flatpak info md.obsidian.Obsidian >/dev/null 2>&1 && echo "installed (flatpak)" || echo "MISSING")"
  printf '    %-16s %s\n' "Claude Desktop" \
    "$(pkg_local claude-desktop && pacman -Q claude-desktop | awk '{print $2}' || echo "MISSING")"
  printf '    %-16s %s\n' "Espanso" \
    "$(pkg_local espanso-wayland && pacman -Q espanso-wayland | awk '{print $2}' || echo "MISSING")"
  printf '    %-16s %s\n' "Voxtype" \
    "$(pkg_local voxtype && pacman -Q voxtype | awk '{print $2}' || echo "MISSING")"
  printf '    %-16s %s\n' "  model" \
    "$(compgen -G "$HOME/.local/share/voxtype/models/*.bin" >/dev/null && echo "present" || echo "MISSING — daemon transcribes nothing")"
  printf '    %-16s %s\n' "workspace rules" \
    "$(grep -qF 'md\\.obsidian' "$HOME/.config/hypr/hyprland.lua" 2>/dev/null && echo "applied" || echo "not applied")"
  printf '    %-16s %s\n' "obsidian-jump" \
    "$([[ -x "$HOME/.local/bin/obsidian-jump" ]] && echo "installed (SUPER + N)" || echo "MISSING")"
  printf '    %-16s %s\n' "katakana font" \
    "$(f=$(fc-list ':charset=30a2' family 2>/dev/null | head -1 | cut -d, -f1); echo "${f:-MISSING — matrix screensaver renders as boxes}")"
  printf '    %-16s %s\n' "fcitx5" \
    "$(pkg_local fcitx5 && echo "installed" || echo "MISSING — omarchy-fcitx5.service will crash-loop")"
  printf '    %-16s %s\n' "edk2-aarch64" \
    "$(pkg_local edk2-aarch64 && pacman -Q edk2-aarch64 | awk '{print $2}' || echo "MISSING")"
  printf '    %-16s %s\n' "input group" \
    "$(id -nG "$USER" | tr ' ' '\n' | grep -qx input && echo "yes" || echo "NO — espanso will not capture keys")"
  printf '    %-16s %s\n' "/dev/kvm" \
    "$([[ -e /dev/kvm ]] && echo "present" || echo "absent — Cowork sandbox degraded")"
  echo
}

# --------------------------------------------------------------------- main

main() {
  if [[ "${1:-}" == "--check" ]]; then report; exit 0; fi
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
  fi

  local targets=("$@")
  ((${#targets[@]})) || targets=(1password obsidian claude espanso voxtype hyprland claude-code obsidian-jump fonts)

  if targets_need_sudo "${targets[@]}"; then
    start_sudo_keepalive
  fi

  preflight

  for t in "${targets[@]}"; do
    case "$t" in
      1password|1p)            install_1password ;;
      obsidian)                install_obsidian ;;
      claude|claude-desktop)   install_claude ;;
      espanso)                 install_espanso ;;
      voxtype)                 install_voxtype ;;
      hyprland|workspaces)     configure_hyprland ;;
      claude-code|cc)          configure_claude_code ;;
      obsidian-jump|jump)      configure_obsidian_jump ;;
      fonts|font)              install_fonts ;;
      *) die "Unknown target: $t (valid: 1password obsidian claude espanso voxtype hyprland claude-code obsidian-jump fonts)" ;;
    esac
  done

  stop_sudo_keepalive

  report
  step "Done."
  info "If you were added to the 'input' group, log out and back in."
}

main "$@"
