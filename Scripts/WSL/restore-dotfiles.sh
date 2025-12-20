#!/usr/bin/env bash
ARCHIVE="${1:-}"
if [[ -z "$ARCHIVE" ]]; then echo "No archive provided."; exit 1; fi
echo "Restoring from: $ARCHIVE"
tar -xzvf "$ARCHIVE" -C "$HOME"
if [[ -d "$HOME/.ssh" ]]; then
  chmod 700 "$HOME/.ssh"
  find "$HOME/.ssh" -type f -exec chmod 600 {} \;
fi