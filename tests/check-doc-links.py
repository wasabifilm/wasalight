#!/usr/bin/env python3
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0

"""Check that local Markdown links resolve inside the repository."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[1]
LINK = re.compile(r"(?<!!)\[[^]]*]\(([^)]+)\)")


def local_target(document: Path, raw_target: str) -> Path | None:
    target = raw_target.strip().split(maxsplit=1)[0].strip("<>")
    target = unquote(target.split("#", 1)[0])
    if not target or "://" in target or target.startswith(("mailto:", "#")):
        return None
    if target.startswith("/"):
        return ROOT / target.lstrip("/")
    return document.parent / target


def main() -> int:
    missing: list[str] = []
    documents = [ROOT / "README.md", *sorted((ROOT / "docs").rglob("*.md"))]
    for document in documents:
        text = document.read_text(encoding="utf-8")
        for line_number, line in enumerate(text.splitlines(), start=1):
            for raw_target in LINK.findall(line):
                target = local_target(document, raw_target)
                if target is not None and not target.resolve().exists():
                    relative = document.relative_to(ROOT)
                    missing.append(f"{relative}:{line_number}: {raw_target}")
    if missing:
        print("Broken local documentation links:", file=sys.stderr)
        print("\n".join(missing), file=sys.stderr)
        return 1
    print(f"Documentation links verified ({len(documents)} files).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
