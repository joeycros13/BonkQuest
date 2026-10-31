#!/bin/sh
# runs simall.sh's four simulations side by side, one output file each (sim_w1.txt ...)
cd "$(dirname "$0")"
F="finish time|deaths [0-9]|at the gate|kills|first 10"
python world_sim.py --world 1 --runs 600 | grep -E "$F" > sim_w1.txt &
python world_sim.py --world 2 --from 1 --upgrades 3 --start-weapons PumpkinMace --start-armor FarmhandsGear,HarvestKnight --start-wear HarvestKnight --start-coins 200 --runs 300 | grep -E "$F" > sim_w2.txt &
python world_sim.py --world 3 --from 2 --upgrades 6 --start-level 50 --start-weapons HeartwoodStaff --start-armor WoodlandHide,HeartwoodBark --start-wear HeartwoodBark --start-coins 1000 --runs 200 | grep -E "$F" > sim_w3.txt &
python world_sim.py --world 2 --from 1 --upgrades 3 --start-weapons PumpkinMace --start-armor FarmhandsGear --start-wear FarmhandsGear --start-coins 200 --runs 100 | grep -E "$F" > sim_w2bare.txt &
wait
for f in sim_w1 sim_w2 sim_w3 sim_w2bare; do echo "== $f"; cat $f.txt; done
