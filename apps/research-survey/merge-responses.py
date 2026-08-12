#!/usr/bin/env python3
"""Merge shopkeeper-survey CSV exports from several devices and report the signal.

Each interviewer's device holds its own responses, so fieldwork produces one CSV
per device. This merges them, drops duplicates by interview id, and prints a read
on the six decisive questions.

    ./merge-responses.py ~/Downloads/grocery-mart-*.csv
    ./merge-responses.py ~/Downloads/*.csv -o merged.csv
"""

import argparse
import csv
import sys
from collections import Counter

# question id -> (label, values that count as a "yes" for the headline percentage)
DECISIVE = [
    ("B3", "keeps a digital price list", {"pos", "sheet"}),
    ("B9", "could supply top-100 within hours", {"now", "hours"}),
    ("E7", "never varies price by customer", {"never"}),
    ("I3", "will hand over the price list", {"yes"}),
]

LABELS = {
    "B3": {"pos": "in POS", "sheet": "spreadsheet", "paper": "paper only", "none": "no list"},
    "B9": {"now": "has it now", "hours": "a few hours", "days": "a few days", "cant": "couldn't"},
    "E7": {"never": "never", "sometimes": "sometimes", "often": "often"},
    "I3": {"yes": "yes", "no": "no", "maybe": "maybe later"},
    "I1": {str(i): str(i) for i in range(1, 6)},
}


def load(paths):
    rows, fieldnames = [], []
    for p in paths:
        try:
            with open(p, encoding="utf-8-sig", newline="") as fh:
                reader = csv.DictReader(fh)
                if not reader.fieldnames:
                    print(f"  ! {p}: empty, skipped", file=sys.stderr)
                    continue
                for name in reader.fieldnames:
                    if name not in fieldnames:
                        fieldnames.append(name)
                found = list(reader)
                rows.extend(found)
                print(f"  · {p}: {len(found)} rows")
        except OSError as e:
            print(f"  ! {p}: {e}", file=sys.stderr)
    return rows, fieldnames


def dedupe(rows):
    seen, out, dupes = set(), [], 0
    for r in rows:
        rid = r.get("_id") or ""
        if rid and rid in seen:
            dupes += 1
            continue
        if rid:
            seen.add(rid)
        out.append(r)
    return out, dupes


def pct(n, d):
    return f"{round(n / d * 100)}%" if d else "—"


def report(rows):
    qualified = [r for r in rows if str(r.get("_screenedOut", "")).lower() not in ("true", "1")]
    n = len(qualified)

    print(f"\n  {len(rows)} interviews · {n} qualified · {len(rows) - n} screened out")

    by_area = Counter(r.get("_area", "") or "(none)" for r in rows)
    by_who = Counter(r.get("_interviewer", "") or "(none)" for r in rows)
    print(f"  areas: {', '.join(f'{k} {v}' for k, v in by_area.most_common())}")
    print(f"  interviewers: {', '.join(f'{k} {v}' for k, v in by_who.most_common())}")

    if not n:
        print("\n  No qualified interviews yet — nothing to read.\n")
        return

    print(f"\n  Decisive questions (n={n})")
    print("  " + "-" * 52)

    for qid, label, good in DECISIVE:
        hits = sum(1 for r in qualified if r.get(qid, "") in good)
        dist = Counter(r.get(qid, "") or "(blank)" for r in qualified)
        spread = "  ".join(
            f"{LABELS.get(qid, {}).get(k, k)}:{v}" for k, v in dist.most_common()
        )
        print(f"  {qid}  {label:<38} {pct(hits, n):>5}")
        print(f"        {spread}")

    scores = [int(r["E2"]) for r in qualified if str(r.get("E2", "")).isdigit()]
    if scores:
        mean = sum(scores) / len(scores)
        low = sum(1 for s in scores if s <= 2)
        print(f"  E2  mean comfort with price comparison   {mean:>5.1f} / 5")
        print(f"        {low} of {len(scores)} answered 1–2 ({pct(low, len(scores))} uncomfortable)")

    # the gap that matters: stated intent vs the one costly commitment
    intent = [int(r["I1"]) for r in qualified if str(r.get("I1", "")).isdigit()]
    keen = sum(1 for s in intent if s >= 4)
    committed = sum(1 for r in qualified if r.get("I3", "") == "yes")
    if intent:
        print(f"\n  Stated vs revealed")
        print("  " + "-" * 52)
        print(f"  I1 >= 4 (likely to list)                  {keen:>3}  {pct(keen, n)}")
        print(f"  I3 = yes (hands over the price list)      {committed:>3}  {pct(committed, n)}")
        if keen:
            print(f"  follow-through                            {pct(committed, keen):>5}")
    print()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("csv", nargs="+", help="exported CSV files, one or more")
    ap.add_argument("-o", "--out", help="write the merged CSV here")
    args = ap.parse_args()

    print(f"\nReading {len(args.csv)} file(s)")
    rows, fieldnames = load(args.csv)
    if not rows:
        print("Nothing to merge.", file=sys.stderr)
        return 1

    rows, dupes = dedupe(rows)
    if dupes:
        print(f"  dropped {dupes} duplicate row(s) by _id")

    rows.sort(key=lambda r: r.get("_endedAt", ""))
    report(rows)

    if args.out:
        with open(args.out, "w", encoding="utf-8", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=fieldnames, extrasaction="ignore")
            w.writeheader()
            w.writerows(rows)
        print(f"  merged {len(rows)} rows -> {args.out}\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
