#!/bin/sh
set -eu

file="$PWD/data/Brewfile"
dir=$(dirname "$file")
name=$(basename "$file")

prefix=$(git -C "$dir" rev-parse --show-prefix)
repo_path="${prefix}${name}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

# Retrieve previous committed Brewfile
git -C "$dir" show "HEAD:$repo_path" >"$tmp/old"

# Restore only missing commented declarations
LC_ALL=C awk '
function identity(line, s, kind, name) {
    s = line

    # Ignore leading whitespace and optional comment marker
    sub(/^[[:space:]]*/, "", s)
    sub(/^#[[:space:]]*/, "", s)

    if (s !~ /^(tap|brew|cask|mas)[[:space:]]+/)
        return ""

    kind = s
    sub(/[[:space:]].*$/, "", kind)

    # Extract first double-quoted package name
    if (s !~ /"/)
        return ""

    name = s
    sub(/^[^"]*"/, "", name)
    sub(/".*$/, "", name)

    return kind SUBSEP name
}

# Read old committed Brewfile
FNR == NR {
    line = $0

    if (line ~ /^[[:space:]]*#/) {
        key = identity(line)

        if (key != "" && !(key in old_comments)) {
            old_comments[key] = line
            order[++count] = key
        }
    }

    next
}

# Read current Brewfile
{
    line = $0
    key = identity(line)

    if (key != "")
        existing[key] = 1

    current[++n] = line
}

END {
    # Keep current dump unchanged
    for (i = 1; i <= n; i++)
        print current[i]

    # Recover missing commented entries
    for (i = 1; i <= count; i++) {
        key = order[i]

        if (!(key in existing))
            print old_comments[key]
    }
}
' "$tmp/old" "$file" >"$tmp/new"

# Replace only after successful processing
cat "$tmp/new" >"$file"
