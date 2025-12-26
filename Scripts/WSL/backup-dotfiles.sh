#!/usr/bin/env bash
set -u

BACKUP_DIR="$HOME/wsl-dotfile-backups"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
ARCHIVE="$BACKUP_DIR/dotfiles_$TIMESTAMP.tar.gz"

# Define items to backup
INCLUDE_ITEMS=(".bashrc" ".zshrc" ".profile" ".gitconfig" ".ssh" ".config/nvim" "scripts")

echo "Starting dotfiles backup..."
echo "Backup directory: $BACKUP_DIR"

# Create backup directory
if ! mkdir -p "$BACKUP_DIR"; then
    echo "Error: Failed to create backup directory: $BACKUP_DIR" >&2
    exit 1
fi

# Perform backup with detailed logging
echo "Backing up dotfiles..."
backup_count=0
skip_count=0

for item in "${INCLUDE_ITEMS[@]}"; do
    item_path="$HOME/$item"
    if [ -e "$item_path" ]; then
        echo "  ✓ Including: $item"
        ((backup_count++))
    else
        echo "  ⊘ Skipping (not found): $item"
        ((skip_count++))
    fi
done

echo "Included: $backup_count items, Skipped: $skip_count items"

# Create the archive
echo "Compressing archive..."
if ! tar -czv --ignore-failed-read -f "$ARCHIVE" -C "$HOME" "${INCLUDE_ITEMS[@]}" > /dev/null 2>&1; then
    echo "Error: Failed to create backup archive: $ARCHIVE" >&2
    exit 1
fi

# Verify archive was created and has content
if [ ! -f "$ARCHIVE" ]; then
    echo "Error: Backup archive was not created: $ARCHIVE" >&2
    exit 1
fi

ARCHIVE_SIZE=$(du -h "$ARCHIVE" | cut -f1)
echo ""
echo "✓ Backup complete!"
echo "  Archive: $ARCHIVE"
echo "  Size: $ARCHIVE_SIZE"
exit 0