#!/usr/bin/env bash
set -u

BACKUP_DIR="$HOME/wsl-dotfile-backups"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
ARCHIVE="$BACKUP_DIR/dotfiles_$TIMESTAMP.tar.gz"

# Create backup directory
if ! mkdir -p "$BACKUP_DIR"; then
    echo "Error: Failed to create backup directory: $BACKUP_DIR" >&2
    exit 1
fi

# Add items to backup here
INCLUDE_ITEMS=(".bashrc" ".zshrc" ".profile" ".gitconfig" ".ssh" ".config/nvim" "scripts")

# Perform backup
if ! tar -czv --ignore-failed-read -f "$ARCHIVE" -C "$HOME" "${INCLUDE_ITEMS[@]}"; then
    echo "Error: Failed to create backup archive: $ARCHIVE" >&2
    exit 1
fi

# Verify archive was created
if [ ! -f "$ARCHIVE" ]; then
    echo "Error: Backup archive was not created: $ARCHIVE" >&2
    exit 1
fi

echo "✓ Backup complete: $ARCHIVE"