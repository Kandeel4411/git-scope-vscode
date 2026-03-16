#!/bin/sh
set -e

REPO="Kandeel4411/git-scope-vscode"
DOWNLOAD_DIR="/tmp/git-scope"

rm -rf "$DOWNLOAD_DIR" && mkdir -p "$DOWNLOAD_DIR"
gh release download --repo "$REPO" --pattern "*.vsix" --dir "$DOWNLOAD_DIR"

VSIX_PATH=$(ls "$DOWNLOAD_DIR"/*.vsix | head -1)
code --install-extension "$VSIX_PATH"
echo "Installed. Reload VSCode to apply."
