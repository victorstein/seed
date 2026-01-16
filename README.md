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
3. Imports GPG key (prompts for password)
4. Restores SSH keys from encrypted storage
5. Clones dotfiles and sets up symlinks
6. Installs all Homebrew packages

## Requirements

- Fresh macOS installation
- Internet connection
- Your GPG encryption password
