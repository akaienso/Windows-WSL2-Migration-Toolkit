#!/usr/bin/env bash
echo "Installing Core Tools..."
sudo apt update -y
PKGS=(git build-essential tmux htop neovim curl wget python3 python3-pip nodejs npm)
sudo apt install -y "${PKGS[@]}"
echo "Done."