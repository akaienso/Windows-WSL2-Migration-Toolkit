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

echo "Restoring from: $ARCHIVE"

# Extract archive
if ! tar -xzvf "$ARCHIVE" -C "$HOME"; then
    echo "Error: Failed to extract archive: $ARCHIVE" >&2
    exit 1
fi

# Fix SSH permissions if present
if [[ -d "$HOME/.ssh" ]]; then
    if ! chmod 700 "$HOME/.ssh"; then
        echo "Warning: Failed to set .ssh directory permissions" >&2
    fi
    
    if ! find "$HOME/.ssh" -type f -exec chmod 600 {} \+; then
        echo "Warning: Failed to set .ssh file permissions" >&2
    fi
fi

echo "✓ Restore complete"