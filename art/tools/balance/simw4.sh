#!/bin/sh
# World 4 (the maxed arrival from World 3) simulated across many processes, one seed each: a run there
# takes minutes, so `simw4.sh [jobs] [runs each]` (default 16 x 3) merges their --dump files.
# Set WORLD_DIR to simulate a trial folder's world4.json (trials.sh's way).
cd "$(dirname "$0")"
JOBS=${1:-16}; EACH=${2:-3}
OUT=$(mktemp -d)
i=1
while [ $i -le $JOBS ]; do
  python world_sim.py --world 4 --from 3 --upgrades 9 --start-level 75 --start-weapons QueensFang \
    --start-armor IronPlate,CaveRunner,CrystalQueen --start-wear CrystalQueen --start-coins 1000 \
    --runs $EACH --seed $i --dump "$OUT/r$i.json" > /dev/null &
  i=$((i + 1))
done
wait
python - "$OUT" <<'EOF'
import json, statistics, sys, glob
runs = [r for f in glob.glob(sys.argv[1] + "/r*.json") for r in json.load(open(f))]
t = sorted(r["t"] for r in runs)
q = lambda p: t[min(len(t) - 1, int(p / 100 * len(t)))]
print("World 4: %d runs, typical %.1f min | fastest quarter %.1f | slowest quarter %.1f | 9 in 10 by %.1f | worst %.1f"
      % (len(t), statistics.median(t), q(25), q(75), q(90), t[-1]))
print("  deaths %.2f, final level %.1f, coins left %.0f" % (statistics.mean(r["deaths"] for r in runs),
      statistics.mean(r["level"] for r in runs), statistics.mean(r["coins"] for r in runs)))
EOF
rm -rf "$OUT"
