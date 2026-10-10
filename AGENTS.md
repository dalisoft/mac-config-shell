# AGENTS.md

## Project

mac-config-shell: installers that reproduce one macOS setup on three platforms.

- `install.sh` — macOS (POSIX `sh`): Homebrew bundle, dotfiles, Bun/pip/uv global tools, fnm Node versions, macOS defaults.
- `install-debian.sh` — Debian/Ubuntu (Bash); `--plan` prints the plan without changes.
- `install-windows.ps1` — Windows (PowerShell); `-Plan` prints the plan without changes.
- `data/` — source of truth for package values: `Brewfile`, `bun.txt`, `node-vers.txt`, `pip.txt`, `uv.txt`. Installers must read from these files instead of hardcoding lists.
- `linux/`, `windows/` — TSV manifests that map every active `data/Brewfile` entry to a platform package or an explicit route (`automatic`, `replacement`, `unavailable`, ...).
- `scripts/` — helpers; `build.sh` re-dumps and sorts `data/Brewfile`.

## Checks

- Syntax: `sh -n install.sh`, `bash -n install-debian.sh`.
- Shell lint: `shellcheck install.sh` (one pre-existing SC2129 style warning).
- Portability: `python3 scripts/verify-portability-manifests.py` checks that `linux/` and `windows/` manifests cover all active `data/Brewfile` entries; it currently exits non-zero while those manifests still have missing/unknown entries.
- CI: `.github/workflows/portability.yml` runs the portability check and renders the Debian/Windows plans without installing.

## Rules

- Keep edits minimal and match each installer's existing style.
- Package lists and versions live in `data/`; do not reintroduce hardcoded values in installers.
- Preserve user changes; do not add files, abstractions or docs unless the task requires them.
