#!/usr/bin/env python3
"""Check that a CTO plan contains the required output-contract headings."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REQUIRED = [
    (r"\bverdict\b", "Verdict"),
    (r"\bevidence\b", "Evidence"),
    (r"\b(non-?goals?|constraints?)\b", "Job/non-goals/constraints"),
    (r"\boptions?\b", "Options considered"),
    (r"\b(quality[- ]attribute|score|trade-?off)\b", "Quality-attribute score"),
    (r"\b(production contract|rollback|sli|slo|observability)\b", "Production contract"),
    (r"\b(thin[- ]slices?|increments?|phased|phases?)\b", "Thin slices"),
    (r"\btest\b", "Test plan"),
]


def check(text: str) -> list[str]:
    missing: list[str] = []
    for pattern, label in REQUIRED:
        if not re.search(pattern, text, flags=re.IGNORECASE):
            missing.append(label)
    return missing


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plan", type=Path, help="Path to a plan markdown file")
    args = parser.parse_args()
    if not args.plan.is_file():
        print(f"error: not a file: {args.plan}", file=sys.stderr)
        return 2
    missing = check(args.plan.read_text(encoding="utf-8"))
    if missing:
        print("missing required plan sections:")
        for label in missing:
            print(f"  - {label}")
        return 1
    print("plan contract: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
