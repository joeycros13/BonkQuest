#!/bin/sh
# the 2026-10-26 rescale's tuned knobs (rescale.py), then the three worlds' simulations
cd "$(dirname "$0")"
python rescale.py --quiet \
  --knob 1.medium=0.75 --knob 1.elite=0.68 --knob 1.boss=0.65 --knob 1.exp=1.2 --knob 1.coins=1.6 \
  --knob 2.medium=0.55 --knob 2.elite=0.5 --knob 2.boss=0.55 --knob 2.exp=1.12 --knob 2.coins=1.12 \
  --knob 3.medium=0.55 --knob 3.elite=0.5 --knob 3.boss=0.5 --knob 3.exp=1.5 --knob 3.coins=1.1 "$@"
