#!/usr/bin/env bash
set -u
BACKUP_DIR="$HOME/wsl-dotfile-backups"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
ARCHIVE="$BACKUP_DIR/dotfiles_$TIMESTAMP.tar.gz"
mkdir -p "$BACKUP_DIR"
# Add items to backup here
INCLUDE_ITEMS=(".bashrc" ".zshrc" ".profile" ".gitconfig" ".ssh" ".config/nvim" "scripts")
tar -czv --ignore-failed-read -f "$ARCHIVE" -C "$HOME" "${INCLUDE_ITEMS[@]}"