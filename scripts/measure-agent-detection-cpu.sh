#!/bin/bash
# Measure Prowl's steady-state CPU and attribute it to the agent-detection and
# SwiftUI-flush paths, alongside the baseline recorded in
# docs-ai/032-performance-hardening/004-agent-detection-steady-state.md.
#
# A CPU percentage means nothing without its workload, so every run records the
# agent mix and the host load average next to the per-symbol attribution. Treat
# a sample taken above roughly one runnable process per core as unusable:
# starvation inflates every number, and it inflates them unevenly.
set -uo pipefail

# Each run gets its own directory so earlier samples stay comparable.
# ~/Library/Logs is where macOS keeps user-visible diagnostics, so runs survive a
# reboot and Console.app can see them. $TMPDIR is wrong for this: it is cleared
# periodically and on reboot, which silently discards the baseline a later run is
# meant to be compared against. ~/Library/Caches would be worse still, since the
# system may evict it under disk pressure.
RUN_ID=$(date +%Y%m%d-%H%M%S)
OUT="${PROWL_MEASURE_DIR:-$HOME/Library/Logs/Prowl/measurements}/$RUN_ID"
mkdir -p "$OUT"

# Keep the console output and the on-disk record identical.
exec > >(tee "$OUT/summary.txt") 2>&1

PID=$(ps -Ao pid,comm | grep "Prowl Debug.app/Contents/MacOS/ProwlApp" | grep -v grep | awk '{print $1}' | head -1)
if [ -z "$PID" ]; then
  echo "Prowl Debug is not running." >&2
  exit 1
fi

echo "pid: $PID  (up $(ps -o etime= -p "$PID" | tr -d ' '))"
echo "load: $(uptime | sed 's/.*load averages*: //')   cores: $(sysctl -n hw.ncpu)"
echo

echo "=== agent mix ==="
# Working agents drive the expensive detection path, so the mix is needed to
# compare two runs honestly.
prowl agents --json 2>/dev/null > "$OUT/agents.json" || true
jq -r 'if .ok then "total=\(.data.agents|length)   " + (.data.agents|group_by(.status)|map("\(.[0].status)=\(length)")|join("  ")) else "CLI unavailable" end' \
  < "$OUT/agents.json" 2>/dev/null || echo "CLI unavailable"
echo

echo "=== process CPU (20 s) ==="
top -l 21 -s 1 -pid "$PID" -stats pid,cpu 2>/dev/null \
  | grep -E "^ *$PID" | awk '{print $2}' | tail -20 > "$OUT/cpu.txt"
python3 - "$OUT/cpu.txt" <<'PY'
import statistics as s, sys
v = [float(x) for x in open(sys.argv[1]).read().split()]
if v:
    print(f"mean={s.mean(v):.1f}%  median={s.median(v):.1f}%  min={min(v):.1f}%  max={max(v):.1f}%")
PY
echo

echo "=== stack sample (20 s) ==="
sample "$PID" 20 -f "$OUT/sample.txt" >/dev/null 2>&1
python3 - "$OUT/sample.txt" <<'PY'
import re, sys

lines = open(sys.argv[1]).read().splitlines()
hdr = []
for i, l in enumerate(lines):
    m = re.match(r'^\s+(\d+) (Thread_\w+.*)$', l)
    if m:
        hdr.append((i, int(m.group(1)), m.group(2).strip()))
if not hdr:
    print("no thread blocks parsed")
    raise SystemExit

# (symbol, pre-fix % of one core) — baseline was 20 agents: 1 working, 2 blocked.
syms = [
    ('detectAgentState',             15.88),
    ('AgentSessionResolver.resolve(', 13.02),
    ('resolveUncached',              12.98),
    ('bestMatch',                    11.38),
    ('normalize(',                    6.70),
    ('transcriptStrings',             2.47),
    ('recentCandidates',              1.57),
    ('flushTransactions',              None),
    ('RepositorySectionView',          None),
    ('SidebarActiveAgentsOverlay',     None),
]
tot = {s: 0 for s, _ in syms}

for idx, (i, _t, _desc) in enumerate(hdr):
    end = hdr[idx + 1][0] if idx + 1 < len(hdr) else len(lines)
    ent = []
    for l in lines[i + 1:end]:
        m = re.search(r'(\d+) (\S.*)$', l)
        if m:
            ent.append((m.start(1), int(m.group(1)), m.group(2)))
    # Sum only the shallowest occurrences so nested frames are not double counted.
    for s, _ in syms:
        counted, mind = [], None
        for d, c, sym in ent:
            if s in sym:
                if mind is None or d <= mind:
                    counted.append(c)
                    mind = d
        tot[s] += sum(counted)

W = hdr[0][1]
print(f"window={W} samples/thread;  1 core = {W} samples\n")
print(f"{'%core':>7}  {'was':>7}   symbol")
for s, base in syms:
    pct = 100 * tot[s] / W
    was = f"{base:.2f}%" if base is not None else "  -  "
    print(f"{pct:6.2f}%  {was:>7}   {s}")

det = 100 * tot['detectAgentState'] / W
if det > 0:
    print("\ncomposition of detectAgentState (load-independent):")
    for s, base in [('AgentSessionResolver.resolve(', 82), ('bestMatch', 72), ('normalize(', 42)]:
        share = 100 * tot[s] / max(tot['detectAgentState'], 1)
        print(f"  {s:32s} {share:5.1f}%  (was {base}%)")
PY

echo
echo "run dir: $OUT"
echo "  sample.txt / cpu.txt / summary.txt"
