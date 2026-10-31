#!/bin/sh
# tune.sh's knobs with World 2 / 3 coin trials, each in its own folder, simulated side by side
cd "$(dirname "$0")"
K1="--knob 1.medium=0.75 --knob 1.elite=0.68 --knob 1.boss=0.65 --knob 1.exp=1.2 --knob 1.coins=1.6 --knob 1.farmLevel=12 --knob 1.hkLevel=16"
F="finish time|deaths [0-9]|coins left|kills"
run() {  # name w2coins w3coins w2exp w3exp
  mkdir -p trial_$1
  WORLD_DIR=trial_$1 python rescale.py --quiet $K1 --knob 2.exp=$4 --knob 2.coins=$2 --knob 3.exp=$5 --knob 3.coins=$3
  WORLD_DIR=trial_$1 python world_sim.py --world 2 --from 1 --upgrades 3 --start-weapons PumpkinMace --start-armor FarmhandsGear,HarvestKnight --start-wear HarvestKnight --start-coins 200 --runs 150 | grep -E "$F" > trial_$1/w2.txt &
  WORLD_DIR=trial_$1 python world_sim.py --world 3 --from 2 --upgrades 6 --start-level 50 --start-weapons HeartwoodStaff --start-armor WoodlandHide,HeartwoodBark --start-wear HeartwoodBark --start-coins 1000 --runs 100 | grep -E "$F" > trial_$1/w3.txt &
}
run "$@"
wait
