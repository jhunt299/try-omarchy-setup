# Prompt for a new instance

Paste the block below as your first message to Claude Code on a fresh
Try-Omarchy VM. It is written in your voice, so it can be pasted verbatim.

---

I'm on a fresh Try-Omarchy instance: aarch64 Arch Linux ARM, Omarchy on the
`try-omarchy` channel, running as a VM guest on an Apple Silicon Mac. None of my
apps or config are set up yet.

Please set this machine up from my repo:

```bash
git clone https://github.com/jhunt299/try-omarchy-setup
cd try-omarchy-setup
./setup.sh --check     # reports what's missing, changes nothing
./setup.sh             # installs and configures everything
```

**Read `README.md` before you start.** It explains why each app needs special
handling — the obvious install command fails for every one of them, each for a
different reason — and its "Known issues on this platform" section documents
four environmental problems that will otherwise waste your time.

That installs 1Password, Obsidian, Claude Desktop, Espanso and Voxtype, then
applies my Hyprland workspace rules, the Claude Code trust flag, and the
`SUPER + N` Obsidian note jumper. Individual targets work too, e.g.
`./setup.sh voxtype hyprland`.

### How to work on this machine

- **`sudo` needs a password and you cannot supply one.** When something needs
  root, hand me the command and tell me to prefix it with `!` so it prompts in
  this session. `setup.sh` calls `sudo` itself, so I'll run the whole script
  that way.
- **Never assume a package exists.** This is Arch Linux ARM, not x86_64 Arch.
  Check `pacman -Si <pkg>` first, and check the `arch=()` line of any AUR
  PKGBUILD — several common packages are x86_64-only and simply cannot be
  installed here.
- **Read real state instead of assuming it.** `pacman -Q`, `hyprctl clients`,
  `systemctl --user status`, `/proc/cpuinfo`. The CPU in particular advertises
  neither SVE nor SME, and the exposed feature set has differed between boots,
  so check it rather than trusting any cached list.
- **Look before deleting.** An app installed outside pacman looks identical to
  an orphaned leftover. Check `pgrep` and config mtimes before proposing to
  remove anything — 1Password in particular is installed from a tarball and
  owned by no package.
- **Ask before opening windows on my desktop.** Launching an app to test
  something is fine, just tell me first.

### After Obsidian is signed in

The `SUPER + N` note jumper reads vaults from Obsidian's own registry, so it
finds nothing until Obsidian has been opened at least once and pointed at my
vaults. Set Obsidian up first, then re-run `./setup.sh obsidian-jump` and I'll
test it.

### When you're done

Run `./setup.sh --check` and tell me what's still missing and why. Expect
`fcitx5 MISSING` — that's an upstream gap the script documents but doesn't fix;
offer me `sudo pacman -S fcitx5 fcitx5-gtk fcitx5-qt`. Also expect
`omarchy update` to be broken if the `aquamarine`/`hyprland` soname conflict
hasn't been resolved upstream yet; the README has the workaround.

### Two things the repo deliberately leaves out

It's a public repo, so anything with my email addresses in it was excluded:

1. **Per-account Gmail web apps** — one per account, via
   `omarchy webapp install`, using `https://mail.google.com/mail/?authuser=<email>#inbox`.
   Note the URL form: `/mail/u/?authuser=` silently drops the parameter and
   lands on the default account, and `/mail/u/<email>/` 404s.
2. **A `mailto:` handler** pointing at one of them, via a small translator
   script using Gmail's `extsrc=mailto` entry point so subject and cc survive.

Ask me for the addresses when we get to those.
