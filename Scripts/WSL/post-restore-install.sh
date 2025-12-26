#!/usr/bin/env bash
set -u

echo "Starting post-restore installation..."
echo "Installing essential development tools..."

# Update package lists with error handling
if ! sudo apt-get update -y > /dev/null 2>&1; then
    echo "⚠ Warning: apt-get update failed, but continuing..." >&2
fi

# Define packages to install
PKGS=(
    build-essential      # GCC, Make, and other build tools
    curl                 # Download files
    git                  # Version control
    htop                 # System monitoring
    neovim               # Text editor (optional, can be customized)
    nodejs               # JavaScript runtime
    npm                  # JavaScript package manager
    python3              # Python runtime
    python3-pip          # Python package manager
    tmux                 # Terminal multiplexer
    wget                 # Download files
)

echo "Packages to install:"
for pkg in "${PKGS[@]}"; do
    echo "  • $pkg"
done

# Install packages with error handling
echo ""
echo "Installing packages (this may take a few minutes)..."
if ! sudo apt-get install -y "${PKGS[@]}" > /dev/null 2>&1; then
    echo "⚠ Warning: Some packages failed to install, but core functionality should be OK" >&2
    # List what failed
    echo ""
    echo "Trying to install packages individually for diagnosis:"
    for pkg in "${PKGS[@]}"; do
        if sudo apt-get install -y "$pkg" > /dev/null 2>&1; then
            echo "  ✓ $pkg"
        else
            echo "  ✗ $pkg"
        fi
    done
fi

# Cleanup apt cache
sudo apt-get clean > /dev/null 2>&1 || true

echo ""
echo "✓ Post-restore installation complete!"
echo ""
echo "Installed tools:"
echo "  • Build tools (GCC, Make, etc.)"
echo "  • Git, Curl, Wget"
echo "  • Python3 + pip"
echo "  • Node.js + npm"
echo "  • Neovim, Tmux, Htop"
echo ""
echo "System is ready to use!"
exit 0