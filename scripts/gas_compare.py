#!/usr/bin/env python3
"""Compare two Foundry gas snapshots and print the totals and per-test deltas.

Usage: python3 scripts/gas_compare.py <baseline.txt> <current.txt>
"""
import re
import sys
from pathlib import Path

PATTERN = re.compile(r"^(.+?) \(gas: (\d+)\)$")


def load(path):
    result = {}
    for line in Path(path).read_text().splitlines():
        match = PATTERN.match(line.strip())
        if match:
            result[match.group(1)] = int(match.group(2))
    return result


def main():
    baseline = load(sys.argv[1])
    current = load(sys.argv[2])
    common = sorted(set(baseline) & set(current))
    if not common:
        raise SystemExit("no matching test names in the two snapshots")

    before_total = sum(baseline[name] for name in common)
    after_total = sum(current[name] for name in common)
    saved_total = before_total - after_total
    print(f"tests compared: {len(common)}")
    print(f"total gas: {before_total} -> {after_total} ({saved_total} saved, "
          f"{saved_total / before_total:.2%})")

    rows = []
    for name in common:
        before = baseline[name]
        after = current[name]
        rows.append((before - after, name, before, after))
    rows.sort(reverse=True)

    print("\nlargest absolute savings:")
    for saved, name, before, after in rows[:10]:
        print(f"  {saved:>7}  {saved / before:6.2%}  {name}  ({before} -> {after})")

    regressions = [row for row in rows if row[0] < 0]
    print(f"\nregressions: {len(regressions)}")
    for saved, name, before, after in regressions:
        print(f"  {saved:>7}  {name}  ({before} -> {after})")

    pct = [row[0] / row[2] for row in rows]
    print(f"\nper-test saving: min {min(pct):.2%}, max {max(pct):.2%}, "
          f"median {sorted(pct)[len(pct) // 2]:.2%}")


if __name__ == "__main__":
    main()
