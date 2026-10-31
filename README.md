# Seed

Bootstrap script for setting up a new Mac.

## Quick Start

**Preview what will happen (dry-run):**
```bash
curl -fsSL https://raw.githubusercontent.com/victorstein/seed/main/bootstrap.sh | bash -s -- --dry-run
```

**Run the setup:**
```bash
curl -fsSL https://raw.githubusercontent.com/victorstein/seed/main/bootstrap.sh | bash
```

## What it does

1. Installs Xcode CLI tools
2. Installs Homebrew
3. Imports GPG key (prompts for password — touch your YubiKey)
4. Restores SSH keys from encrypted storage
5. Clones dotfiles and sets up symlinks
6. Installs all Homebrew packages
7. macOS only: sets up the memory-server client — installs and logs in to
   Tailscale (reusing an App Store or standalone app if present), runs the
   dotfiles setup wizard (`~/.dotfiles/install.sh --interactive`), installs
   Claude Code if missing and signs it in per profile, and finishes with
   `memory doctor`. Until the dotfiles carry the wizard
   (`scripts/memory-wizard.capability`) it stops after Tailscale; re-run the
   same command later to finish it.

## Requirements

- Fresh macOS installation
- Internet connection
- Your YubiKey programmed with the static-password slot used for this repo,
  plugged into the new machine. Touch the key when the script prompts for the
  encryption password — do not type anything.

> **Lost the YubiKey?** Recovery requires the static string stored in your
> private offline vault. Without it, `gpg-key.enc` cannot be decrypted and
> the bootstrap cannot complete.
