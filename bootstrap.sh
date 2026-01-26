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

# Spinner for progress indication
SPINNER_CHARS="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
SPINNER_IDX=0

spin() {
    local msg="$1"
    # Clear entire line and print spinner with message
    printf "\r\033[K${SPINNER_CHARS:$SPINNER_IDX:1} %s" "$msg"
    SPINNER_IDX=$(( (SPINNER_IDX + 1) % ${#SPINNER_CHARS} ))
}

spin_done() {
    printf "\r\033[K${GREEN}✓${NC} %s\n" "$1"
}

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
# Cache sudo credentials upfront to avoid repeated password prompts
# ─────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == false ]]; then
    info "Caching sudo credentials (you may be prompted for your system password)..."
    sudo -v < /dev/tty

    # Keep sudo alive in background (refresh every 50 seconds)
    # This runs until the script exits
    (while true; do sudo -n -v 2>/dev/null; sleep 50; done) &
    SUDO_KEEP_ALIVE_PID=$!

    # Ensure we kill the background process on script exit
    trap "kill $SUDO_KEEP_ALIVE_PID 2>/dev/null" EXIT
fi

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

            # Remove temporary loopback setting from gpg.conf after import
            # Keep allow-loopback-pinentry in gpg-agent.conf - it only allows loopback if explicitly requested
            # Note: Step 8 will re-add this temporarily for password-store operations
            if [[ "$LOOPBACK_ADDED" == true ]]; then
                if [[ "$IS_MACOS" == true ]]; then
                    sed -i '' '/^pinentry-mode loopback$/d' ~/.gnupg/gpg.conf 2>/dev/null || true
                else
                    sed -i '/^pinentry-mode loopback$/d' ~/.gnupg/gpg.conf 2>/dev/null || true
                fi
            fi

            # Restart gpg-agent
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

# Install Oh My Zsh
if [[ -d ~/.oh-my-zsh ]]; then
    skip "Oh My Zsh already installed"
else
    info "Installing Oh My Zsh..."
    if [[ "$DRY_RUN" == true ]]; then
        dry "Install Oh My Zsh via official script"
    else
        # --unattended: don't change shell, don't run zsh after install
        # --keep-zshrc: don't overwrite existing .zshrc (our dotfiles have custom config)
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
    fi
fi

# Install Oh My Zsh custom plugins
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
OMZ_PLUGINS=(
    "zsh-users/zsh-autosuggestions"
    "zsh-users/zsh-syntax-highlighting"
    "zdharma-continuum/fast-syntax-highlighting"
    "marlonrichert/zsh-autocomplete"
)

for plugin_repo in "${OMZ_PLUGINS[@]}"; do
    plugin_name="${plugin_repo##*/}"
    plugin_dir="$ZSH_CUSTOM/plugins/$plugin_name"

    if [[ -d "$plugin_dir" ]]; then
        skip "oh-my-zsh plugin: $plugin_name"
    else
        info "Installing oh-my-zsh plugin: $plugin_name..."
        if [[ "$DRY_RUN" == true ]]; then
            dry "git clone https://github.com/$plugin_repo $plugin_dir"
        else
            git clone --depth=1 "https://github.com/$plugin_repo.git" "$plugin_dir" 2>/dev/null || \
                warn "Failed to install plugin: $plugin_name"
        fi
    fi
done

# Install nvm (Node Version Manager)
if [[ -d ~/.nvm ]]; then
    skip "nvm already installed"
else
    info "Installing nvm..."
    if [[ "$DRY_RUN" == true ]]; then
        dry "Install nvm via official script"
    else
        # PROFILE=/dev/null prevents nvm from modifying shell configs (our dotfiles already have the config)
        export PROFILE=/dev/null
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
        unset PROFILE
    fi
fi

# Install default Node.js version via nvm
if [[ -d ~/.nvm ]]; then
    # Source nvm for this session
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    if command -v nvm &>/dev/null; then
        if nvm ls default &>/dev/null 2>&1 && [[ "$(nvm ls default 2>/dev/null)" != *"N/A"* ]]; then
            skip "Node.js default version already set"
        else
            info "Installing Node.js LTS via nvm..."
            if [[ "$DRY_RUN" == true ]]; then
                dry "nvm install --lts && nvm alias default lts/*"
            else
                nvm install --lts
                nvm alias default 'lts/*'
                info "Node.js LTS installed and set as default"
            fi
        fi
    fi
fi

# Install WezTerm terminal emulator (GUI only - skip on headless servers)
# Check if we have a graphical environment
HAS_GUI=false
if [[ "$IS_MACOS" == true ]]; then
    # macOS always has a GUI
    HAS_GUI=true
elif [[ -n "$DISPLAY" ]] || [[ -n "$WAYLAND_DISPLAY" ]] || [[ "$XDG_SESSION_TYPE" == "x11" ]] || [[ "$XDG_SESSION_TYPE" == "wayland" ]]; then
    # Linux with X11 or Wayland
    HAS_GUI=true
fi

if [[ "$HAS_GUI" == false ]]; then
    skip "WezTerm (no GUI environment detected - headless server)"
elif command -v wezterm &>/dev/null; then
    skip "WezTerm already installed"
else
    info "Installing WezTerm..."
    if [[ "$DRY_RUN" == true ]]; then
        if [[ "$IS_MACOS" == true ]]; then
            dry "brew install --cask wezterm"
        else
            dry "Install WezTerm via Flatpak or native package"
        fi
    else
        if [[ "$IS_MACOS" == true ]]; then
            brew install --cask wezterm
        else
            # Linux: WezTerm is not available via Homebrew, use native methods
            if command -v flatpak &>/dev/null; then
                # Flatpak is the most universal method
                flatpak install -y flathub org.wezfurlong.wezterm
                # Create symlink for CLI access
                FLATPAK_WEZTERM="/var/lib/flatpak/exports/bin/org.wezfurlong.wezterm"
                if [[ -f "$FLATPAK_WEZTERM" ]] && [[ ! -f /usr/local/bin/wezterm ]]; then
                    sudo ln -sf "$FLATPAK_WEZTERM" /usr/local/bin/wezterm 2>/dev/null || true
                fi
            elif command -v apt-get &>/dev/null; then
                # Debian/Ubuntu: Use WezTerm's official repo
                curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
                echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo tee /etc/apt/sources.list.d/wezterm.list
                sudo apt-get update
                sudo apt-get install -y wezterm
            elif command -v dnf &>/dev/null; then
                # Fedora: Use COPR
                sudo dnf copr enable -y wezfurlong/wezterm-nightly
                sudo dnf install -y wezterm
            elif command -v pacman &>/dev/null; then
                # Arch Linux
                sudo pacman -S --noconfirm wezterm
            else
                warn "Could not install WezTerm: no supported package manager found"
                warn "Please install WezTerm manually: https://wezfurlong.org/wezterm/install/linux.html"
            fi
        fi
    fi
fi

# Set WezTerm as default terminal on Linux (only if GUI is available)
if [[ "$IS_LINUX" == true ]] && [[ "$HAS_GUI" == true ]]; then
    WEZTERM_PATH=$(command -v wezterm 2>/dev/null || echo "")
    if [[ -n "$WEZTERM_PATH" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            dry "Set WezTerm as default terminal emulator"
        else
            # Try GNOME/GTK-based desktops
            if command -v gsettings &>/dev/null; then
                gsettings set org.gnome.desktop.default-applications.terminal exec "$WEZTERM_PATH" 2>/dev/null || true
                gsettings set org.gnome.desktop.default-applications.terminal exec-arg '' 2>/dev/null || true
                info "Set WezTerm as default terminal (GNOME)"
            fi

            # Try update-alternatives (Debian/Ubuntu)
            if command -v update-alternatives &>/dev/null; then
                # Register wezterm as an alternative if not already
                sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator "$WEZTERM_PATH" 50 2>/dev/null || true
                sudo update-alternatives --set x-terminal-emulator "$WEZTERM_PATH" 2>/dev/null || true
                info "Set WezTerm as default terminal (update-alternatives)"
            fi
        fi
    fi
fi

# ─────────────────────────────────────────────────────────────
step "7/11" "Essential Packages (pass, stow)"
# ─────────────────────────────────────────────────────────────

# Fix Homebrew directory permissions on Linux
# This can happen when Homebrew was installed by root or another user
# Always run this to catch nested directories with wrong permissions
if [[ "$IS_LINUX" == true ]] && [[ -d /home/linuxbrew/.linuxbrew ]]; then
    BREW_PREFIX="/home/linuxbrew/.linuxbrew"
    if [[ "$DRY_RUN" == true ]]; then
        dry "sudo chown -R $USER $BREW_PREFIX"
    else
        info "Fixing Homebrew directory permissions..."
        # Use sudo directly (not through run) to ensure it executes
        sudo chown -R "$USER" "$BREW_PREFIX" 2>/dev/null || true
        sudo chmod -R u+w "$BREW_PREFIX" 2>/dev/null || true
    fi
fi

# Fix any Homebrew linking issues before installing packages
if command -v brew &>/dev/null; then
    if [[ "$DRY_RUN" == true ]]; then
        dry "Fix any unlinked Homebrew packages"
    else
        # Link all installed formulae with --overwrite to fix any conflicts
        # This handles Python, Node, OpenSSL, and any other linking issues
        mapfile -t FORMULAE < <(brew list --formula -1 2>/dev/null)
        TOTAL_FORMULAE=${#FORMULAE[@]}

        if [[ $TOTAL_FORMULAE -gt 0 ]]; then
            COUNT=0
            for formula in "${FORMULAE[@]}"; do
                ((++COUNT))
                spin "[${COUNT}/${TOTAL_FORMULAE}] Linking packages..."
                brew link --overwrite "$formula" >/dev/null 2>&1 || true
            done
            spin_done "Linked ${TOTAL_FORMULAE} packages"
        else
            skip "No formulae to link"
        fi
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

# Prepare GPG for password-store operations
# The `pass` command uses GPG to decrypt, which needs a working pinentry
if [[ "$DRY_RUN" == false ]]; then
    # Ensure Homebrew GPG tools are first in PATH to avoid version mismatch
    if [[ "$IS_LINUX" == true ]] && [[ -d /home/linuxbrew/.linuxbrew/bin ]]; then
        export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
    elif [[ "$IS_MACOS" == true ]] && [[ -d /opt/homebrew/bin ]]; then
        export PATH="/opt/homebrew/bin:$PATH"
    fi

    # Kill any old gpg-agent to ensure we start fresh with the Homebrew version
    gpgconf --kill gpg-agent 2>/dev/null || true
    killall gpg-agent 2>/dev/null || true

    # Set GPG_TTY for pinentry to work with terminal
    export GPG_TTY=$(tty 2>/dev/null || echo /dev/tty)

    # Ensure loopback pinentry is enabled for this session
    if ! grep -q 'pinentry-mode loopback' ~/.gnupg/gpg.conf 2>/dev/null; then
        echo 'pinentry-mode loopback' >> ~/.gnupg/gpg.conf
    fi

    # Give the old agent time to fully stop
    sleep 1

    # Start fresh gpg-agent with correct version
    gpg-agent --daemon 2>/dev/null || true

    info "GPG agent initialized for password-store operations"
fi

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
    if [[ "$DRY_RUN" == true ]]; then
        dry "brew bundle install --file=$BREWFILE"
        info "(This installs packages and may take a while)"
    else
        # Count approximate total from Brewfile (brew, cask, tap, mas lines)
        TOTAL_PKGS=$(grep -cE '^(brew|cask|tap|mas) ' "$BREWFILE" 2>/dev/null | tr -cd '0-9')
        TOTAL_PKGS=${TOTAL_PKGS:-0}

        # Run brew bundle in background, capture output to temp file
        BREW_LOG=$(mktemp)
        brew bundle install --file="$BREWFILE" > "$BREW_LOG" 2>&1 &
        BREW_PID=$!

        # Spinner loop - animate while checking progress
        while kill -0 $BREW_PID 2>/dev/null; do
            # Count installed/using lines in log to track progress
            # Use tr to strip any non-numeric characters
            COUNT=$(grep -cE '^(Installing|Using|Upgrading|Skipping)' "$BREW_LOG" 2>/dev/null | tr -cd '0-9')
            COUNT=${COUNT:-0}
            spin "[${COUNT}/~${TOTAL_PKGS}] Installing packages..."
            sleep 0.1
        done

        # Get exit status
        wait $BREW_PID
        BREW_EXIT=$?

        # Final count
        FINAL_COUNT=$(grep -cE '^(Installing|Using|Upgrading|Skipping)' "$BREW_LOG" 2>/dev/null || echo "0")

        if [[ $BREW_EXIT -eq 0 ]]; then
            spin_done "Installed ${FINAL_COUNT} packages from Brewfile"
        else
            spin_done "Processed ${FINAL_COUNT} packages (some may have failed)"
            warn "Check $BREW_LOG for details"
            # Don't delete log on failure so user can debug
            BREW_LOG=""
        fi

        # Clean up temp file on success
        [[ -n "$BREW_LOG" ]] && rm -f "$BREW_LOG"
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
# Cleanup: Remove temporary GPG loopback setting
# ─────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == false ]]; then
    # Remove loopback pinentry mode from gpg.conf (security cleanup)
    # This was enabled for password-store operations during bootstrap
    if grep -q 'pinentry-mode loopback' ~/.gnupg/gpg.conf 2>/dev/null; then
        if [[ "$IS_MACOS" == true ]]; then
            sed -i '' '/^pinentry-mode loopback$/d' ~/.gnupg/gpg.conf 2>/dev/null || true
        else
            sed -i '/^pinentry-mode loopback$/d' ~/.gnupg/gpg.conf 2>/dev/null || true
        fi
        gpgconf --kill gpg-agent 2>/dev/null || true
        info "Cleaned up temporary GPG loopback config"
    fi
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
echo "  1. Verify SSH: ssh -T git@github.com"
echo "  2. Open Neovim and let plugins install: nvim"
echo ""
info "If anything failed, you can safely re-run this script."
info "Your development environment is ready!"
echo ""

# Switch to zsh immediately (no logout required)
if [[ "$DRY_RUN" == false ]] && command -v zsh &>/dev/null; then
    info "Switching to zsh..."
    exec zsh -l
fi
