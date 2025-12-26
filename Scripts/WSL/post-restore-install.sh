#!/usr/bin/env bash
set -u

echo "Installing Core Tools..."

# Update package lists
if ! sudo apt update -y; then
    echo "Warning: apt update failed. Continuing anyway..." >&2
fi

# Install packages
PKGS=(git build-essential tmux htop neovim curl wget python3 python3-pip nodejs npm)

if ! sudo apt install -y "${PKGS[@]}"; then
    echo "Warning: Some packages failed to install" >&2
fi

echo "✓ Post-restore installation complete"