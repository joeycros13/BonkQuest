#!/bin/sh
# the 2026-10-26 rescale's tuned knobs (rescale.py), then the four worlds' simulations (World 4: simw4.sh)
cd "$(dirname "$0")"
python rescale.py --quiet \
  --knob 1.medium=0.75 --knob 1.elite=0.68 --knob 1.boss=0.65 --knob 1.exp=1.2 --knob 1.coins=1.6 --knob 1.farmLevel=12 --knob 1.hkLevel=16 \
  --knob 2.exp=0.784 --knob 2.coins=1.25 \
  --knob 3.exp=0.93 --knob 3.coins=1.42 \
  --knob 4.exp=0.56 --knob 4.coins=0.56 "$@"
