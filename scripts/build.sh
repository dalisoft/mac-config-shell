#!/bin/sh
set -eu

brew bundle dump --taps --brews --casks --mas --no-vscode --force --no-describe --file "$PWD/data/Brewfile"

sh "$PWD/scripts/restore_comment.sh"
sh "$PWD/scripts/sort_brewfile.sh"
