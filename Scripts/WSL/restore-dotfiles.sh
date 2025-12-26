#!/usr/bin/env bash
set -u

ARCHIVE="${1:-}"

# Validate argument
if [[ -z "$ARCHIVE" ]]; then
    echo "Error: No archive provided. Usage: $0 <path-to-archive>" >&2
    exit 1
fi

# Verify archive exists
if [[ ! -f "$ARCHIVE" ]]; then
    echo "Error: Archive file not found: $ARCHIVE" >&2
    exit 1
fi

echo "Restoring dotfiles from: $ARCHIVE"
echo "Extracting to home directory..."

# Extract archive
if ! tar -xzvf "$ARCHIVE" -C "$HOME" 2>&1 | head -20; then
    echo "Error: Failed to extract archive: $ARCHIVE" >&2
    exit 1
fi

# Fix SSH permissions if present (critical for SSH functionality)
if [[ -d "$HOME/.ssh" ]]; then
    echo "Fixing SSH permissions..."
    if ! chmod 700 "$HOME/.ssh"; then
        echo "Warning: Failed to set .ssh directory permissions" >&2
    fi
    
    if ! find "$HOME/.ssh" -type f -exec chmod 600 {} \+ 2>/dev/null; then
        echo "Warning: Failed to set .ssh file permissions" >&2
    fi
fi

# Fix Git credentials permissions if present
if [[ -f "$HOME/.gitconfig" ]]; then
    echo "Setting Git config permissions..."
    chmod 644 "$HOME/.gitconfig" 2>/dev/null || true
fi

# Fix config directory permissions
if [[ -d "$HOME/.config" ]]; then
    echo "Setting config directory permissions..."
    chmod 755 "$HOME/.config" 2>/dev/null || true
    find "$HOME/.config" -type d -exec chmod 755 {} \+ 2>/dev/null || true
    find "$HOME/.config" -type f -exec chmod 644 {} \+ 2>/dev/null || true
fi

echo ""
echo "✓ Restore complete!"
echo "  • SSH permissions fixed"
echo "  • Config permissions fixed"
echo "  • Dotfiles restored to $HOME"
exit 0