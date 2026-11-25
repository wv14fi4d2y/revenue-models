#!/usr/bin/env python3
"""Assert the subscription_revenue contract on a CSV export before release.

Checks, in order:
  * required columns are present
  * (account_id, month_start) is unique
  * month_start is the first day of a month
  * recognized revenue is non-negative
  * no row covers more days than its month has

Exit code 1 on the first violated rule; prints one line per violation.
"""

from __future__ import annotations

import csv
import sys
from datetime import date
from pathlib import Path

REQUIRED = ("account_id", "month_start", "recognized_revenue_cents", "days_with_revenue")


def days_in_month(month_start: date) -> int:
    nxt = date(month_start.year + month_start.month // 12, month_start.month % 12 + 1, 1)
    return (nxt - month_start).days


def check(path: Path) -> list[str]:
    problems: list[str] = []
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        missing = [c for c in REQUIRED if c not in (reader.fieldnames or [])]
        if missing:
            return [f"missing columns: {', '.join(missing)}"]

        seen: set[tuple[str, str]] = set()
        for lineno, row in enumerate(reader, start=2):
            key = (row["account_id"], row["month_start"])
            if key in seen:
                problems.append(f"line {lineno}: duplicate grain {key}")
            seen.add(key)

            try:
                month = date.fromisoformat(row["month_start"])
            except ValueError:
                problems.append(f"line {lineno}: bad month_start {row['month_start']!r}")
                continue
            if month.day != 1:
                problems.append(f"line {lineno}: month_start not first of month")

            if float(row["recognized_revenue_cents"]) < 0:
                problems.append(f"line {lineno}: negative revenue")

            if int(row["days_with_revenue"]) > days_in_month(month):
                problems.append(f"line {lineno}: more days than the month has")

    return problems


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: check_revenue_contract.py EXPORT.csv", file=sys.stderr)
        return 2
    problems = check(Path(argv[1]))
    for problem in problems:
        print(problem)
    print(f"{len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
