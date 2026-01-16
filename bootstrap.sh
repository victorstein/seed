#!/bin/bash
# Idempotent Mac Bootstrap Script
# Safe to run multiple times - checks state before each action
# Supports --dry-run to preview changes without executing
# PROTECTED: Requires encryption password to proceed

set -e  # Exit on error

# ─────────────────────────────────────────────────────────────
# Dry-run mode
# ─────────────────────────────────────────────────────────────
DRY_RUN=false
if [[ "$1" == "--dry-run" ]] || [[ "$1" == "-n" ]]; then
    DRY_RUN=true
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
skip()    { echo -e "${BLUE}[SKIP]${NC} $1 (already done)"; }
dry()     { echo -e "${MAGENTA}[DRY-RUN]${NC} Would: $1"; }
step()    { echo -e "\n${GREEN}═══════════════════════════════════════════════════════════${NC}"; echo -e "${GREEN}  STEP $1: $2${NC}"; echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}\n"; }

# Execute command only if not in dry-run mode
run() {
    if [[ "$DRY_RUN" == true ]]; then
        dry "$*"
        return 0
    else
        "$@"
    fi
}

# Configuration
GITHUB_USER="victorstein"
SEED_REPO="seed"
DOTFILES_REPO="dotfiles"
GPG_KEY_ID="E84B48EB778BF9E6"
SSH_KEYS=("victorstein-GitHub" "coolify" "stein-coolify")

# ─────────────────────────────────────────────────────────────
# AUTHENTICATION GATE
# ─────────────────────────────────────────────────────────────
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Mac Bootstrap Script${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}  DRY-RUN MODE - No changes will be made${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    info "Skipping authentication in dry-run mode"
    AUTH_PASSWORD="dry-run-placeholder"
else
    echo -e "${YELLOW}This script is protected. Please authenticate to continue.${NC}"
    echo ""
    read -s -p "Enter encryption password: " AUTH_PASSWORD
    echo ""
    
    if [[ -z "$AUTH_PASSWORD" ]]; then
        error "No password provided. Exiting."
    fi
    
    info "Password stored. Will verify after dependencies are installed."
fi

echo ""
info "=== Mac Bootstrap Script (Idempotent) ==="
info "This script can be safely re-run if interrupted."

# ─────────────────────────────────────────────────────────────
step "1/10" "Xcode Command Line Tools"
# ─────────────────────────────────────────────────────────────
if xcode-select -p &>/dev/null; then
    skip "Xcode CLI tools"
else
    info "Installing Xcode Command Line Tools..."
    run xcode-select --install
    if [[ "$DRY_RUN" == false ]]; then
        echo ""
        warn "A popup will appear. Click 'Install' and wait for completion."
        read -p "Press Enter after Xcode CLI tools installation completes..."
    fi
fi

# ─────────────────────────────────────────────────────────────
step "2/10" "Homebrew"
# ─────────────────────────────────────────────────────────────
if command -v brew &>/dev/null; then
    skip "Homebrew"
else
    info "Installing Homebrew..."
    if [[ "$DRY_RUN" == true ]]; then
        dry "Install Homebrew via official script"
    else
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
fi

# Ensure brew is in PATH (for Apple Silicon)
if [[ $(uname -m) == "arm64" ]] && [[ ! "$PATH" == */opt/homebrew/bin* ]]; then
    if [[ "$DRY_RUN" == false ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    # Add to zprofile if not already there
    if ! grep -q 'homebrew/bin/brew shellenv' ~/.zprofile 2>/dev/null; then
        if [[ "$DRY_RUN" == true ]]; then
            dry "Add Homebrew to ~/.zprofile"
        else
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────
step "3/10" "GnuPG"
# ─────────────────────────────────────────────────────────────
if command -v gpg &>/dev/null; then
    skip "gnupg"
else
    info "Installing gnupg..."
    run brew install gnupg
fi

# ─────────────────────────────────────────────────────────────
step "4/10" "Password Store (seed repo)"
# ─────────────────────────────────────────────────────────────
if [[ -d ~/.password-store/.git ]]; then
    skip "Password store already cloned"
    info "Pulling latest changes..."
    if [[ "$DRY_RUN" == false ]]; then
        cd ~/.password-store && git pull --ff-only || warn "Could not pull (maybe offline)"
        cd ~
    else
        dry "git pull in ~/.password-store"
    fi
else
    if [[ -d ~/.password-store ]]; then
        warn "~/.password-store exists but is not a git repo"
        warn "Backing up to ~/.password-store.backup"
        run mv ~/.password-store ~/.password-store.backup.$(date +%s)
    fi
    info "Cloning seed repository..."
    run git clone "https://github.com/${GITHUB_USER}/${SEED_REPO}.git" ~/.password-store
fi

# ─────────────────────────────────────────────────────────────
step "5/10" "GPG Key Import (Authentication Verification)"
# ─────────────────────────────────────────────────────────────
if gpg --list-secret-keys "$GPG_KEY_ID" &>/dev/null; then
    skip "GPG key already imported"
else
    if [[ "$DRY_RUN" == true ]]; then
        dry "Decrypt ~/.password-store/gpg-key.enc"
        dry "Import GPG key"
        dry "Set trust level to ultimate"
        dry "Delete temp decrypted key"
    else
        if [[ ! -f ~/.password-store/gpg-key.enc ]]; then
            error "Encrypted GPG key not found at ~/.password-store/gpg-key.enc"
        fi

        info "Verifying authentication..."
        info "Decrypting GPG key with provided password..."

        # Use the password captured at the start
        if echo "$AUTH_PASSWORD" | gpg --batch --yes --passphrase-fd 0 --decrypt ~/.password-store/gpg-key.enc > /tmp/gpg-private-key.asc 2>/dev/null; then
            info "Authentication successful!"
            echo ""
            
            info "Importing GPG key..."
            gpg --import /tmp/gpg-private-key.asc

            # Trust the key
            info "Setting key trust level..."
            echo -e "5\ny\n" | gpg --command-fd 0 --expert --edit-key "$GPG_KEY_ID" trust 2>/dev/null || true

            # Securely delete the decrypted key
            rm -P /tmp/gpg-private-key.asc 2>/dev/null || rm -f /tmp/gpg-private-key.asc
            info "GPG key imported and temp file deleted"
        else
            echo ""
            error "Authentication failed. Wrong password. Exiting."
        fi
        
        # Clear password from memory
        unset AUTH_PASSWORD
    fi
fi

# ─────────────────────────────────────────────────────────────
step "6/10" "Essential Packages (pass, git, stow)"
# ─────────────────────────────────────────────────────────────
PACKAGES_TO_INSTALL=""
for pkg in pass git stow; do
    if ! command -v "$pkg" &>/dev/null; then
        PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $pkg"
    else
        skip "$pkg"
    fi
done

if [[ -n "$PACKAGES_TO_INSTALL" ]]; then
    info "Installing:$PACKAGES_TO_INSTALL"
    run brew install $PACKAGES_TO_INSTALL
fi

# ─────────────────────────────────────────────────────────────
step "7/10" "SSH Keys"
# ─────────────────────────────────────────────────────────────
run mkdir -p ~/.ssh
run chmod 700 ~/.ssh

for key in "${SSH_KEYS[@]}"; do
    if [[ -f ~/.ssh/"$key" ]] && [[ -s ~/.ssh/"$key" ]]; then
        skip "SSH key: $key"
    else
        info "Extracting SSH key: $key"
        if [[ "$DRY_RUN" == true ]]; then
            dry "pass ssh/$key > ~/.ssh/$key"
            dry "chmod 600 ~/.ssh/$key"
            dry "ssh-keygen -y -f ~/.ssh/$key > ~/.ssh/$key.pub"
        else
            pass ssh/"$key" > ~/.ssh/"$key"
            chmod 600 ~/.ssh/"$key"
            # Regenerate public key
            info "Regenerating public key for $key"
            ssh-keygen -y -f ~/.ssh/"$key" > ~/.ssh/"$key".pub
            chmod 644 ~/.ssh/"$key".pub
        fi
    fi
done

# SSH config
if [[ -f ~/.ssh/config ]] && [[ -s ~/.ssh/config ]]; then
    skip "SSH config"
else
    info "Extracting SSH config"
    if [[ "$DRY_RUN" == true ]]; then
        dry "pass ssh/config > ~/.ssh/config"
    else
        pass ssh/config > ~/.ssh/config
        chmod 644 ~/.ssh/config
    fi
fi

# Add key to SSH agent (idempotent - safe to run multiple times)
info "Ensuring SSH agent is running and key is added..."
if [[ "$DRY_RUN" == false ]]; then
    eval "$(ssh-agent -s)" 2>/dev/null || true
    ssh-add --apple-use-keychain ~/.ssh/victorstein-GitHub 2>/dev/null || true
else
    dry "Start ssh-agent and add victorstein-GitHub key"
fi

# ─────────────────────────────────────────────────────────────
step "8/10" "Dotfiles Repository"
# ─────────────────────────────────────────────────────────────
if [[ -d ~/.dotfiles/.git ]]; then
    skip "Dotfiles already cloned"
    info "Pulling latest changes..."
    if [[ "$DRY_RUN" == false ]]; then
        cd ~/.dotfiles && git pull --ff-only || warn "Could not pull (maybe offline or uncommitted changes)"
        cd ~
    else
        dry "git pull in ~/.dotfiles"
    fi
else
    if [[ -d ~/.dotfiles ]]; then
        warn "~/.dotfiles exists but is not a git repo"
        warn "Backing up to ~/.dotfiles.backup"
        run mv ~/.dotfiles ~/.dotfiles.backup.$(date +%s)
    fi
    info "Cloning dotfiles..."
    run git clone "git@github.com:${GITHUB_USER}/${DOTFILES_REPO}.git" ~/.dotfiles
fi

# ─────────────────────────────────────────────────────────────
step "9/10" "Stow Dotfiles"
# ─────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == false ]]; then
    cd ~/.dotfiles
fi

# Create .config if it doesn't exist
run mkdir -p ~/.config

# Stow items from .config directory
info "Linking .config items..."
if [[ "$DRY_RUN" == true ]]; then
    dry "Symlink .config/nvim → ~/.config/nvim"
    dry "Symlink .config/lazygit → ~/.config/lazygit"
    dry "Symlink .config/starship.toml → ~/.config/starship.toml"
else
    for item in .config/*; do
        if [[ -e "$item" ]]; then
            name=$(basename "$item")
            target=~/.config/"$name"
            source="$PWD/$item"

            if [[ -L "$target" ]] && [[ "$(readlink "$target")" == "$source" || "$(readlink "$target")" == *".dotfiles/.config/$name"* ]]; then
                skip ".config/$name"
            else
                # Remove existing (backup if it's a real dir/file)
                if [[ -e "$target" ]] && [[ ! -L "$target" ]]; then
                    warn "Backing up existing ~/.config/$name"
                    mv "$target" "$target.backup.$(date +%s)"
                fi
                info "Linking .config/$name"
                ln -sf "$source" "$target"
            fi
        fi
    done
fi

# Stow top-level dotfiles
info "Linking top-level dotfiles..."
if [[ "$DRY_RUN" == true ]]; then
    dry "Symlink .zshrc → ~/.zshrc"
    dry "Symlink .wezterm.lua → ~/.wezterm.lua"
    dry "Symlink .aicommit2 → ~/.aicommit2"
else
    for item in .zshrc .wezterm.lua .aicommit2; do
        if [[ -e "$item" ]]; then
            target=~/"$item"
            source="$PWD/$item"

            if [[ -L "$target" ]] && [[ "$(readlink "$target")" == "$source" || "$(readlink "$target")" == *".dotfiles/$item"* ]]; then
                skip "$item"
            else
                if [[ -e "$target" ]] && [[ ! -L "$target" ]]; then
                    warn "Backing up existing ~/$item"
                    mv "$target" "$target.backup.$(date +%s)"
                fi
                info "Linking $item"
                ln -sf "$source" "$target"
            fi
        fi
    done
    cd ~
fi

# ─────────────────────────────────────────────────────────────
step "10/10" "Homebrew Packages (Brewfile)"
# ─────────────────────────────────────────────────────────────
if [[ -f ~/.dotfiles/Brewfile ]] || [[ "$DRY_RUN" == true ]]; then
    info "Installing packages from Brewfile..."
    if [[ "$DRY_RUN" == true ]]; then
        dry "brew bundle install --file=~/.dotfiles/Brewfile"
        info "(This installs ~50 packages and may take 10-15 minutes)"
    else
        info "This may take a while (10-15 minutes)..."
        brew bundle install --file=~/.dotfiles/Brewfile || warn "Some packages may have failed to install"
    fi
else
    warn "Brewfile not found at ~/.dotfiles/Brewfile"
    warn "Skipping Homebrew package installation"
fi

# ─────────────────────────────────────────────────────────────
# COMPLETE
# ─────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  SETUP COMPLETE!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
info "Next steps:"
echo "  1. Restart your terminal (or run: source ~/.zshrc)"
echo "  2. Verify SSH: ssh -T git@github.com"
echo "  3. Open Neovim and let plugins install: nvim"
echo ""
info "If anything failed, you can safely re-run this script."
info "Your development environment is ready!"
