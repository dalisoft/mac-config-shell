#!/usr/bin/env bash
# Linux counterpart to the macOS app-removal helper. Accept an APT package or
# a Flatpak application ID and remove only that managed package and its data.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: remme <apt-package-or-flatpak-app-id>" >&2
  exit 2
fi

target=$1

if command -v flatpak >/dev/null 2>&1 && flatpak info --user "$target" >/dev/null 2>&1; then
  flatpak uninstall --user --delete-data -y "$target"
  exit 0
fi

if dpkg-query -W -f='${db:Status-Status}' "$target" 2>/dev/null | grep -qx installed; then
  sudo apt-get purge -y "$target"
  sudo apt-get autoremove -y
  exit 0
fi

echo "No installed APT package or user Flatpak matches: $target" >&2
exit 1
