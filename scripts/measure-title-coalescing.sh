#!/bin/bash
# Verify that animated tab titles stay coalesced, from outside the app.
#
# `prowl list` reports `tab.title` from the same live snapshot the tab bar
# observes, so polling it measures exactly the write rate that title coalescing
# governs (docs-ai/032.004, Fix 7). Agent TUIs animate spinner glyphs into the
# title at roughly 10 Hz; the shipped coalescing must hold every animating tab
# at or near one visible change per second. This is the one claim from the
# #644–#665 wave that a Release build can be checked against with no
# instrumentation at all.
#
# Usage:  bash scripts/measure-title-coalescing.sh [duration_seconds] [max_changes_per_second]
#         bash scripts/measure-title-coalescing.sh 30 1.25     # default
#
# The threshold leaves headroom over the exact 1/s contract because sampling
# jitter can split one interval across two observation windows.
#
# Environment:
#   PROWL_MEASURE_DIR   where runs are written
#                       (default ~/Library/Logs/Prowl/measurements)
#
# Exit codes: 0 pass; 1 an animating tab exceeded the threshold; 2 CLI
# unavailable; 3 inconclusive (no tab changed at all — nothing was animating);
# 64 usage error.
set -euo pipefail
umask 077

DURATION=${1:-30}
MAX_RATE=${2:-1.25}

usage_error() {
  echo "$1" >&2
  exit 64
}

case "$DURATION" in
  '' | *[!0-9]*) usage_error "duration_seconds must be a positive integer." ;;
esac
[ "$DURATION" -gt 0 ] || usage_error "duration_seconds must be greater than zero."
case "$MAX_RATE" in
  '' | *[!0-9.]* | . | *.*.*) usage_error "max_changes_per_second must be a positive number." ;;
esac

command -v prowl >/dev/null || { echo "prowl CLI is not on PATH." >&2; exit 2; }
prowl list --json >/dev/null 2>&1 || { echo "prowl CLI cannot reach a running app." >&2; exit 2; }

OUT="${PROWL_MEASURE_DIR:-$HOME/Library/Logs/Prowl/measurements}/title-rates/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$OUT"

# Rates are computed against measured wall-clock, not the nominal poll count:
# CLI latency stretches every polling loop, and dividing by the intended
# duration would overstate each tab's change rate.
status=0
DURATION="$DURATION" MAX_RATE="$MAX_RATE" OUT="$OUT" python3 <<'PY' || status=$?
import json
import os
import subprocess
import sys
import time

duration = int(os.environ["DURATION"])
max_rate = float(os.environ["MAX_RATE"])
out = os.environ["OUT"]

poll_interval = 0.125
changes = {}
titles = {}
last = {}
polls = 0

start = time.monotonic()
with open(os.path.join(out, "titles.jsonl"), "w") as log:
    while time.monotonic() - start < duration:
        result = subprocess.run(["prowl", "list", "--json"], capture_output=True, text=True)
        now = time.monotonic() - start
        try:
            items = json.loads(result.stdout)["data"]["items"]
        except (json.JSONDecodeError, KeyError):
            continue
        polls += 1
        snapshot = {}
        for item in items:
            tab = item.get("tab") or {}
            tab_id, title = tab.get("id"), tab.get("title")
            if tab_id is None or title is None:
                continue
            snapshot[tab_id] = title
            titles.setdefault(tab_id, title)
            if tab_id in last and last[tab_id] != title:
                changes[tab_id] = changes.get(tab_id, 0) + 1
            last[tab_id] = title
        log.write(json.dumps({"t": round(now, 3), "tabs": snapshot}) + "\n")
        time.sleep(poll_interval)
elapsed = time.monotonic() - start

lines = [f"polls={polls}  elapsed={elapsed:.1f}s  threshold={max_rate}/s"]
worst = 0.0
for tab_id, title in titles.items():
    count = changes.get(tab_id, 0)
    rate = count / elapsed
    worst = max(worst, rate)
    flag = "  <-- OVER" if rate > max_rate else ""
    lines.append(f"  {tab_id[:8]}  changes={count:3d}  rate={rate:.2f}/s  {title[:60]}{flag}")

summary = "\n".join(lines)
print(summary)
with open(os.path.join(out, "summary.txt"), "w") as f:
    f.write(summary + "\n")

if polls == 0:
    print("no successful polls; is the app responding?", file=sys.stderr)
    sys.exit(2)
if not changes:
    print("\nno tab title changed at all — nothing was animating, run is inconclusive.", file=sys.stderr)
    sys.exit(3)
sys.exit(1 if worst > max_rate else 0)
PY
echo
echo "run dir: $OUT"
exit "$status"
