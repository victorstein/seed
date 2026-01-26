#!/bin/bash
# Idempotent Mac/Linux Bootstrap Script
# Safe to run multiple times - checks state before each action
# Supports --dry-run to preview changes without executing
# PROTECTED: Requires encryption password to proceed

set -e  # Exit on error

# ─────────────────────────────────────────────────────────────
# OS Detection
# ─────────────────────────────────────────────────────────────
OS="$(uname -s)"
IS_MACOS=false
IS_LINUX=false

if [[ "$OS" == "Darwin" ]]; then
    IS_MACOS=true
elif [[ "$OS" == "Linux" ]]; then
    IS_LINUX=true
else
    echo "Unsupported operating system: $OS"
    exit 1
fi

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

# Cross-platform symlink check
# Returns 0 if $1 is a symlink pointing to a path containing $2
# Handles differences between macOS and Linux readlink behavior
is_symlink_to() {
    local link="$1"
    local expected_pattern="$2"

    [[ -L "$link" ]] || return 1

    local target
    # Try GNU readlink -f first (works on Linux, and macOS with coreutils)
    if target=$(readlink -f "$link" 2>/dev/null); then
        [[ "$target" == *"$expected_pattern"* ]] && return 0
    fi

    # Fallback to basic readlink (macOS default)
    target=$(readlink "$link" 2>/dev/null)
    [[ "$target" == *"$expected_pattern"* ]] && return 0

    return 1
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
OS_NAME="Mac"
[[ "$IS_LINUX" == true ]] && OS_NAME="Linux"

echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ${OS_NAME} Bootstrap Script${NC}"
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
    # Read from /dev/tty to support curl | bash (stdin is the pipe, not terminal)
    printf "Enter encryption password: "
    read -s AUTH_PASSWORD < /dev/tty
    echo ""

    if [[ -z "$AUTH_PASSWORD" ]]; then
        error "No password provided. Exiting."
    fi

    info "Password stored. Will verify after dependencies are installed."
fi

echo ""
info "=== ${OS_NAME} Bootstrap Script (Idempotent) ==="
info "This script can be safely re-run if interrupted."

# ─────────────────────────────────────────────────────────────
step "1/11" "Build Dependencies & Git"
# ─────────────────────────────────────────────────────────────
if [[ "$IS_MACOS" == true ]]; then
    if xcode-select -p &>/dev/null; then
        skip "Xcode CLI tools"
    else
        info "Installing Xcode Command Line Tools..."
        run xcode-select --install
        if [[ "$DRY_RUN" == false ]]; then
            echo ""
            warn "A popup will appear. Click 'Install' and wait for completion."
            read -p "Press Enter after Xcode CLI tools installation completes..." < /dev/tty
        fi
    fi
elif [[ "$IS_LINUX" == true ]]; then
    # Detect package manager and install build dependencies
    # Supports: Debian/Ubuntu (apt), Fedora/RHEL/CentOS/Rocky/Alma (dnf), Arch/Omarchy (pacman)
    if command -v apt-get &>/dev/null; then
        # Debian/Ubuntu
        if dpkg -s build-essential curl git &>/dev/null 2>&1; then
            skip "Linux build dependencies (build-essential, curl, git)"
        else
            info "Installing Linux build dependencies (apt)..."
            run sudo apt-get update
            run sudo apt-get install -y build-essential procps curl file git
        fi
    elif command -v dnf &>/dev/null; then
        # Fedora/RHEL/CentOS/Rocky/AlmaLinux
        if rpm -q gcc make curl git &>/dev/null 2>&1; then
            skip "Linux build dependencies (Development Tools, curl, git)"
        else
            info "Installing Linux build dependencies (dnf)..."
            run sudo dnf groupinstall -y "Development Tools"
            run sudo dnf install -y procps-ng curl file git
        fi
    elif command -v pacman &>/dev/null; then
        # Arch Linux / Omarchy
        if pacman -Qi base-devel curl git &>/dev/null 2>&1; then
            skip "Linux build dependencies (base-devel, curl, git)"
        else
            info "Installing Linux build dependencies (pacman)..."
            run sudo pacman -Sy --noconfirm base-devel procps-ng curl git
        fi
    else
        error "Unsupported Linux distribution. Please install build tools, curl, and git manually."
    fi
fi

# Verify git is available before proceeding (required for cloning repos)
# Skip this check in dry-run mode since we may have only shown the install message
if [[ "$DRY_RUN" == false ]] && ! command -v git &>/dev/null; then
    error "Git is not available. Please install git manually and re-run this script."
fi

# ─────────────────────────────────────────────────────────────
step "2/11" "Homebrew"
# ─────────────────────────────────────────────────────────────
if command -v brew &>/dev/null; then
    skip "Homebrew"
else
    info "Installing Homebrew..."
    if [[ "$DRY_RUN" == true ]]; then
        dry "Install Homebrew via official script"
    else
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
fi

# Ensure brew is in PATH
if [[ "$IS_MACOS" == true ]]; then
    # Apple Silicon Macs
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
elif [[ "$IS_LINUX" == true ]]; then
    # Linux Homebrew
    BREW_PATH="/home/linuxbrew/.linuxbrew/bin/brew"
    if [[ -f "$BREW_PATH" ]] && [[ ! "$PATH" == */linuxbrew/.linuxbrew/bin* ]]; then
        if [[ "$DRY_RUN" == false ]]; then
            eval "$($BREW_PATH shellenv)"
        fi
        # Add to zsh config (since we're making zsh the default shell)
        # Also add to .profile for login shell compatibility
        ZSHRC="$HOME/.zshrc"
        ZPROFILE="$HOME/.zprofile"

        # Add to .zshrc for interactive shells
        if ! grep -q 'linuxbrew/.linuxbrew/bin/brew shellenv' "$ZSHRC" 2>/dev/null; then
            if [[ "$DRY_RUN" == true ]]; then
                dry "Add Homebrew to $ZSHRC"
            else
                # Create .zshrc if it doesn't exist
                touch "$ZSHRC"
                echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> "$ZSHRC"
            fi
        fi

        # Also add to .zprofile for login shells
        if ! grep -q 'linuxbrew/.linuxbrew/bin/brew shellenv' "$ZPROFILE" 2>/dev/null; then
            if [[ "$DRY_RUN" == true ]]; then
                dry "Add Homebrew to $ZPROFILE"
            else
                touch "$ZPROFILE"
                echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> "$ZPROFILE"
            fi
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────
step "3/11" "GnuPG"
# ─────────────────────────────────────────────────────────────
if command -v gpg &>/dev/null; then
    skip "gnupg"
else
    info "Installing gnupg..."
    run brew install gnupg
fi

# ─────────────────────────────────────────────────────────────
step "4/11" "Password Store (seed repo)"
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
step "5/11" "GPG Key Import (Authentication Verification)"
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

        # Secure password handling: use a temp file instead of echo piping
        # This prevents the password from appearing in process listings
        PASS_TEMP=$(mktemp)
        chmod 600 "$PASS_TEMP"
        printf '%s' "$AUTH_PASSWORD" > "$PASS_TEMP"

        # Temp file for decrypted key
        KEY_TEMP=$(mktemp)
        chmod 600 "$KEY_TEMP"

        if gpg --batch --yes --passphrase-file "$PASS_TEMP" --decrypt ~/.password-store/gpg-key.enc > "$KEY_TEMP" 2>/dev/null; then
            # Immediately remove password temp file
            rm -f "$PASS_TEMP"
            unset AUTH_PASSWORD

            info "Authentication successful!"
            echo ""

            info "Importing GPG key..."
            # Configure GPG for non-interactive import (required for curl | bash)
            mkdir -p ~/.gnupg
            chmod 700 ~/.gnupg

            # Configure gpg-agent to allow loopback pinentry
            if ! grep -q 'allow-loopback-pinentry' ~/.gnupg/gpg-agent.conf 2>/dev/null; then
                echo 'allow-loopback-pinentry' >> ~/.gnupg/gpg-agent.conf
            fi

            # Temporarily configure gpg to use loopback pinentry (will be removed after import)
            LOOPBACK_ADDED=false
            if ! grep -q 'pinentry-mode loopback' ~/.gnupg/gpg.conf 2>/dev/null; then
                echo 'pinentry-mode loopback' >> ~/.gnupg/gpg.conf
                LOOPBACK_ADDED=true
            fi

            # Kill any existing gpg-agent to ensure clean state
            gpgconf --kill gpg-agent 2>/dev/null || true

            # Unset agent info to prevent auto-connection
            unset GPG_AGENT_INFO

            # Import with batch mode, bypassing agent issues
            gpg --batch --import "$KEY_TEMP" 2>&1 || {
                # If that fails, try with explicit no-autostart
                warn "Retrying import with --no-autostart..."
                gpg --batch --no-autostart --import "$KEY_TEMP"
            }

            # Trust the key (using --import-ownertrust for reliability across GPG versions)
            info "Setting key trust level to ultimate..."
            echo "${GPG_KEY_ID}:6:" | gpg --import-ownertrust 2>/dev/null || {
                # Fallback to interactive method if import-ownertrust fails
                warn "Falling back to interactive trust method..."
                echo -e "5\ny\n" | gpg --command-fd 0 --expert --edit-key "$GPG_KEY_ID" trust 2>/dev/null || true
            }

            # Remove temporary loopback setting from gpg.conf (security cleanup)
            # Keep allow-loopback-pinentry in gpg-agent.conf - it only allows loopback if explicitly requested
            if [[ "$LOOPBACK_ADDED" == true ]]; then
                sed -i '/^pinentry-mode loopback$/d' ~/.gnupg/gpg.conf 2>/dev/null || true
                info "Cleaned up temporary GPG loopback config"
            fi

            # Restart gpg-agent to restore normal behavior
            gpgconf --kill gpg-agent 2>/dev/null || true

            # Secure deletion of the decrypted key
            # Note: On SSDs, secure deletion is not guaranteed due to wear-leveling.
            # We overwrite with random data as best-effort, but the key briefly existed in plaintext.
            # For high-security environments, consider using encrypted tmpfs or ramfs.
            if command -v shred &>/dev/null; then
                shred -u "$KEY_TEMP" 2>/dev/null || rm -f "$KEY_TEMP"
            else
                # Fallback: overwrite with random data before deletion
                dd if=/dev/urandom of="$KEY_TEMP" bs=1k count=10 conv=notrunc 2>/dev/null || true
                rm -f "$KEY_TEMP"
            fi
            info "GPG key imported and temp files deleted"
        else
            rm -f "$PASS_TEMP" "$KEY_TEMP"
            unset AUTH_PASSWORD
            echo ""
            error "Authentication failed. Wrong password. Exiting."
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────
step "6/11" "Zsh Shell"
# ─────────────────────────────────────────────────────────────
if command -v zsh &>/dev/null; then
    skip "zsh already installed"
else
    info "Installing zsh..."
    if [[ "$IS_MACOS" == true ]]; then
        run brew install zsh
    elif [[ "$IS_LINUX" == true ]]; then
        # Install zsh via native package manager (faster than brew)
        if command -v apt-get &>/dev/null; then
            run sudo apt-get install -y zsh
        elif command -v dnf &>/dev/null; then
            run sudo dnf install -y zsh
        elif command -v pacman &>/dev/null; then
            run sudo pacman -S --noconfirm zsh
        else
            # Fallback to Homebrew
            run brew install zsh
        fi
    fi
fi

# Make zsh the default shell
CURRENT_SHELL=$(basename "$SHELL")
ZSH_PATH=$(command -v zsh 2>/dev/null || echo "")

# In dry-run mode, zsh might not be installed yet, so predict the path
if [[ -z "$ZSH_PATH" ]]; then
    if [[ "$IS_MACOS" == true ]]; then
        ZSH_PATH="/opt/homebrew/bin/zsh"
        [[ $(uname -m) != "arm64" ]] && ZSH_PATH="/usr/local/bin/zsh"
    else
        ZSH_PATH="/usr/bin/zsh"
    fi
fi

if [[ "$CURRENT_SHELL" == "zsh" ]]; then
    skip "zsh is already the default shell"
else
    info "Setting zsh as default shell..."
    if [[ "$DRY_RUN" == true ]]; then
        dry "Add $ZSH_PATH to /etc/shells (if needed)"
        dry "chsh -s $ZSH_PATH"
    else
        # Verify zsh is actually installed before proceeding
        if [[ ! -x "$ZSH_PATH" ]]; then
            ZSH_PATH=$(command -v zsh 2>/dev/null || echo "")
            if [[ -z "$ZSH_PATH" ]]; then
                warn "zsh installation may have failed. Skipping shell change."
            fi
        fi

        if [[ -n "$ZSH_PATH" ]] && [[ -x "$ZSH_PATH" ]]; then
            # Ensure zsh is in /etc/shells
            if ! grep -q "^${ZSH_PATH}$" /etc/shells 2>/dev/null; then
                info "Adding $ZSH_PATH to /etc/shells..."
                echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
            fi
            # Change default shell using sudo (avoids password prompt that can't work in curl | bash)
            if sudo chsh -s "$ZSH_PATH" "$USER"; then
                info "Default shell changed to zsh"
                warn "You'll need to log out and back in for the shell change to take effect"
            else
                warn "Could not change default shell. You may need to run: sudo chsh -s $ZSH_PATH $USER"
            fi
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────
step "7/11" "Essential Packages (pass, stow)"
# ─────────────────────────────────────────────────────────────

# Fix Homebrew directory permissions on Linux (can happen after zsh install)
if [[ "$IS_LINUX" == true ]] && [[ -d /home/linuxbrew/.linuxbrew/share/zsh ]]; then
    if [[ ! -w /home/linuxbrew/.linuxbrew/share/zsh ]]; then
        info "Fixing Homebrew zsh directory permissions..."
        run sudo chown -R "$USER" /home/linuxbrew/.linuxbrew/share/zsh /home/linuxbrew/.linuxbrew/share/zsh/site-functions 2>/dev/null || true
        run chmod u+w /home/linuxbrew/.linuxbrew/share/zsh /home/linuxbrew/.linuxbrew/share/zsh/site-functions 2>/dev/null || true
    fi
fi

PACKAGES_TO_INSTALL=""
for pkg in pass stow; do
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
step "8/11" "SSH Keys"
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

# Add key to SSH agent (reuses existing agent to avoid orphan processes)
info "Ensuring SSH agent is running and key is added..."
if [[ "$DRY_RUN" == false ]]; then
    # Check if we already have a working SSH agent
    if ! ssh-add -l &>/dev/null && [[ "$SSH_AUTH_SOCK" == "" ]]; then
        # No agent running, try to find an existing one or start new
        # Check common socket locations
        for sock in /tmp/ssh-*/agent.* "$XDG_RUNTIME_DIR/ssh-agent.socket" "$HOME/.ssh/ssh-agent.sock"; do
            if [[ -S "$sock" ]]; then
                export SSH_AUTH_SOCK="$sock"
                if ssh-add -l &>/dev/null || [[ $? -eq 1 ]]; then
                    # Agent is working (exit 1 means no keys but agent is running)
                    info "Found existing SSH agent at $sock"
                    break
                fi
            fi
        done

        # If still no agent, start a new one
        if ! ssh-add -l &>/dev/null && [[ "$SSH_AUTH_SOCK" == "" || ! -S "$SSH_AUTH_SOCK" ]]; then
            info "Starting new SSH agent..."
            eval "$(ssh-agent -s)" >/dev/null
        fi
    else
        skip "SSH agent already running"
    fi

    # Add the key if not already added
    if ! ssh-add -l 2>/dev/null | grep -q "victorstein-GitHub"; then
        if [[ "$IS_MACOS" == true ]]; then
            ssh-add --apple-use-keychain ~/.ssh/victorstein-GitHub 2>/dev/null || ssh-add ~/.ssh/victorstein-GitHub 2>/dev/null || true
        else
            ssh-add ~/.ssh/victorstein-GitHub 2>/dev/null || true
        fi
    else
        skip "SSH key victorstein-GitHub already in agent"
    fi
else
    dry "Reuse or start ssh-agent and add victorstein-GitHub key"
fi

# ─────────────────────────────────────────────────────────────
step "9/11" "Dotfiles Repository"
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
step "10/11" "Stow Dotfiles"
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

            if is_symlink_to "$target" ".dotfiles/.config/$name"; then
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

# Stow top-level dotfiles (auto-detect hidden files/dirs, excluding .git and .config)
info "Linking top-level dotfiles..."
if [[ "$DRY_RUN" == true ]]; then
    dry "Symlink all top-level dotfiles (.*) from ~/.dotfiles to ~/"
    dry "(Excluding .git, .config, .gitignore, .DS_Store)"
else
    for item in .[!.]*; do
        # Skip non-existent (glob didn't match), directories we handle separately, and meta files
        [[ -e "$item" ]] || continue
        [[ "$item" == ".git" ]] && continue
        [[ "$item" == ".config" ]] && continue
        [[ "$item" == ".gitignore" ]] && continue
        [[ "$item" == ".DS_Store" ]] && continue

        target=~/"$item"
        source="$PWD/$item"

        if is_symlink_to "$target" ".dotfiles/$item"; then
            skip "$item"
        else
            if [[ -e "$target" ]] && [[ ! -L "$target" ]]; then
                warn "Backing up existing ~/$item"
                mv "$target" "$target.backup.$(date +%s)"
            fi
            info "Linking $item"
            ln -sf "$source" "$target"
        fi
    done
    cd ~
fi

# ─────────────────────────────────────────────────────────────
step "11/11" "Homebrew Packages (Brewfile)"
# ─────────────────────────────────────────────────────────────
# Determine correct Brewfile based on OS
if [[ "$IS_LINUX" == true ]]; then
    BREWFILE="$HOME/.dotfiles/Brewfile.linux"
else
    BREWFILE="$HOME/.dotfiles/Brewfile"
fi

# Check if Brewfile exists (even in dry-run, to give accurate output)
if [[ -f "$BREWFILE" ]]; then
    info "Installing packages from $(basename "$BREWFILE")..."
    if [[ "$DRY_RUN" == true ]]; then
        dry "brew bundle install --file=$BREWFILE"
        info "(This installs packages and may take a while)"
    else
        info "This may take a while..."
        brew bundle install --file="$BREWFILE" || warn "Some packages may have failed to install"
    fi
elif [[ "$DRY_RUN" == true ]]; then
    # In dry-run, dotfiles may not be cloned yet, so assume Brewfile would exist
    info "Brewfile not found yet (dotfiles may not be cloned in dry-run)"
    dry "brew bundle install --file=$BREWFILE"
    info "(This installs packages and may take a while)"
else
    warn "Brewfile not found at $BREWFILE"
    warn "Skipping Homebrew package installation"
    warn "Create $BREWFILE in your dotfiles to auto-install packages"
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
echo "  1. Log out and back in (for shell change to take effect)"
echo "     Or start a new zsh session: exec zsh"
echo "  2. Verify SSH: ssh -T git@github.com"
echo "  3. Open Neovim and let plugins install: nvim"
echo ""
info "If anything failed, you can safely re-run this script."
info "Your development environment is ready (with zsh as default shell)!"
