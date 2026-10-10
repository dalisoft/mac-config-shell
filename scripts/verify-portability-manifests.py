#!/usr/bin/env python3
"""Keep Debian and Windows coverage in lockstep with active Brewfile entries."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BREWFILE = ROOT / "data" / "Brewfile"
ENTRY_RE = re.compile(r'^\s*(brew|cask|mas)\s+"([^"]+)"', re.MULTILINE)

MANIFESTS = {
    "Debian": (
        (ROOT / "linux" / "apt-packages.tsv", 2),
        (ROOT / "linux" / "apt-desktop.tsv", 2),
        (ROOT / "linux" / "flatpak-apps.tsv", 2),
        (ROOT / "linux" / "other-packages.tsv", 5),
    ),
    "Windows": (
        (ROOT / "windows" / "winget-packages.tsv", 2),
        (ROOT / "windows" / "other-packages.tsv", 5),
    ),
}

ROUTES = {"automatic", "built-in", "manual", "replacement", "unavailable", "web", "wsl"}
PARITY = {"exact", "partial", "none"}


def active_entries() -> set[str]:
    return {name for _, name in ENTRY_RE.findall(BREWFILE.read_text(encoding="utf-8"))}


def manifest_entries(specifications: tuple[tuple[Path, int], ...]) -> set[str]:
    entries: set[str] = set()
    for path, column_count in specifications:
        if not path.is_file():
            raise ValueError(f"Missing manifest: {path.relative_to(ROOT)}")
        for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            fields = line.split("|")
            if len(fields) != column_count or not fields[0].strip() or not fields[1].strip():
                raise ValueError(f"Invalid row in {path.relative_to(ROOT)}:{line_number}: {raw_line}")
            if column_count == 5:
                route, target, parity, note = (field.strip() for field in fields[1:])
                if route not in ROUTES or parity not in PARITY or not target or not note:
                    raise ValueError(f"Invalid parity row in {path.relative_to(ROOT)}:{line_number}: {raw_line}")
            source = fields[0].strip()
            if not source.startswith("@"):
                entries.add(source)
    return entries


def main() -> int:
    expected = active_entries()
    failed = False
    for platform, paths in MANIFESTS.items():
        found = manifest_entries(paths)
        missing = sorted(expected - found)
        extra = sorted(found - expected)
        print(f"{platform}: {len(expected) - len(missing)}/{len(expected)} active Brewfile entries covered")
        if missing:
            failed = True
            print(f"  Missing: {', '.join(missing)}")
        if extra:
            failed = True
            print(f"  Unknown sources: {', '.join(extra)}")
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
