#!/bin/sh
set -eu

file="$PWD/data/Brewfile"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT HUP INT TERM

LC_ALL=C awk '
{
    line = $0
    entry = line

    # Ignore the leading # for sorting
    sub(/^[[:space:]]*#[[:space:]]*/, "", entry)

    if (entry ~ /^tap[[:space:]]+/)       rank = 1
    else if (entry ~ /^brew[[:space:]]+/) rank = 2
    else if (entry ~ /^cask[[:space:]]+/) rank = 3
    else if (entry ~ /^mas[[:space:]]+/)  rank = 4
    else {
        if (entry ~ /^[[:space:]]*$/) next
        print "Unsupported line: " line > "/dev/stderr"
        exit 1
    }

    # Extract package name from first quoted argument
    name = entry
    sub(/^[^"]*"/, "", name)
    sub(/".*$/, "", name)

    # Prefix with sortable keys, preserve original line
    printf "%d\t%s\t%s\n", rank, tolower(name), line
}
' "$file" |
  LC_ALL=C sort -t "$(printf '\t')" -k1,1n -k2,2 -k3,3 |
  cut -f3- >"$tmp"

cat "$tmp" >"$file"
