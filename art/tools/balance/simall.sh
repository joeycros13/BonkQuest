#!/bin/sh
cd "$(dirname "$0")"
echo "== World 1"; python world_sim.py --world 1 --runs 1000 | grep -E "finish time|deaths [0-9]|at the gate|kills|first 10"
echo "== World 2 (maxed arrival)"; python world_sim.py --world 2 --from 1 --upgrades 3 --start-weapons PumpkinMace --start-armor FarmhandsGear,HarvestKnight --start-wear HarvestKnight --start-coins 200 --runs 400 | grep -E "finish time|deaths [0-9]|at the gate|kills|first 10"
echo "== World 3 (maxed arrival)"; python world_sim.py --world 3 --from 2 --upgrades 6 --start-level 50 --start-weapons HeartwoodStaff --start-armor WoodlandHide,HeartwoodBark --start-wear HeartwoodBark --start-coins 1000 --runs 300 | grep -E "finish time|deaths [0-9]|at the gate|kills|first 10"
echo "== World 2 with no armour (upgrades 3, the Mace)"; python world_sim.py --world 2 --from 1 --upgrades 3 --start-weapons PumpkinMace --start-armor FarmhandsGear --start-wear FarmhandsGear --start-coins 200 --runs 100 | grep -E "finish time|deaths [0-9]|first 10"
