# try-omarchy-setup: notes for Claude Code

`setup.sh` installs and configures the owner's apps and settings on a fresh Omarchy install running as a VM on an
Apple Silicon Mac (Arch Linux ARM, **aarch64**). `NEW-INSTANCE-PROMPT.md` is the first message the owner pastes on a
new VM and describes how they want Claude to work there; `README.md` explains each target.

- **Check every package on aarch64.** Many AUR packages are x86_64 only. Confirm with `pacman -Si` or the PKGBUILD's
  `arch=()` before assuming something installs.
- **sudo needs a password Claude can't supply.** Hand the owner commands to run with the `!` prefix (that shell starts
  in `$HOME`, so use full paths). The script asks for sudo once and holds it for the run. pam_faillock locks the
  account for 10 minutes after 3 bad attempts.
- **Hyprland 0.56 uses Lua.** `hyprctl dispatch` and `eval` take Lua (`hl.dsp.*`, `hl.get_window("address:0x…")`); the
  old string dispatch syntax errors out.
- Claude Code on these machines is installed through mise (`mise upgrade claude`, not `claude update`). Obsidian is
  the flatpak `md.obsidian.Obsidian` with the vault at `~/Documents/NAR-Notes`.
- A native x86_64 port for a 2017 iMac (`setup-imac.sh`, `IMAC_SETUP_NOTES.md`, `IMAC_SETUP_PROMPT.md`) lives in the
  owner's Obsidian vault, not here. Its aarch64 workarounds don't apply there and vice versa.
- Plan (2026-09-26): the owner's always-on Omarchy desktop becomes the main Claude Code machine, reached from the VM
  over SSH + tmux + Tailscale. Setup steps are in the vault at `REMOTE_BASE_SETUP.md`.
- Git on the VM has no global identity. Commit with
  `-c user.name="Joshua Hunt" -c user.email="77076724+jhunt299@users.noreply.github.com"`.
