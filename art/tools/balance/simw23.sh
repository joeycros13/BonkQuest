#!/bin/sh
# World 2 and 3 runs for one set of extra knobs ("$@" goes to tune.sh); prints both
cd "$(dirname "$0")"
F="finish time|walking  |gathering|resting  |deaths [0-9]|armour sets"
python world_sim.py --world 2 --from 1 --upgrades 3 --start-weapons PumpkinMace --start-armor FarmhandsGear,HarvestKnight --start-wear HarvestKnight --start-coins 200 --runs 150 | grep -E "$F" > "sim_w2_$TAG.txt" &
python world_sim.py --world 3 --from 2 --upgrades 6 --start-level 50 --start-weapons HeartwoodStaff --start-armor WoodlandHide,HeartwoodBark --start-wear HeartwoodBark --start-coins 1000 --runs 100 | grep -E "$F" > "sim_w3_$TAG.txt" &
wait
