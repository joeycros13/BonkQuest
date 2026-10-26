--!strict
-- World 4: The Scorching Sands, a desert (the user's name, 2026-10-25).
--
-- Laid out by art/tools/w4/build_ground.py (option B "Pinwheel", turned 45 degrees south-west
-- of World 2): a dune-walled square with a road round a stepped pyramid, the oasis in the north
-- arm and a dormant volcano in the south. The pyramid is hollow and is the boss hall (2026-10-26).
-- Its gate, the Caravan Gate, stands in the corridor out of World 2's south-west corner and needs
-- World 3 (Config/Gates).
--
-- The entry exists so the game knows World 4 (2026-10-26): the world guard keeps out players who
-- haven't bought the gate, the banner names it, and SpawnService can send a player to its
-- Spawns/PlayerSpawn, just inside the corridor. The roster, drops, lighting and Index picture
-- come later; until then it has no enemies (WorldEnemyService places none) and takes the
-- lighting as built in Studio (World 1's golden afternoon). Numbers follow the base-fight rules
-- (memory world-scaling-baseline) once the roster is picked.
local WorldTypes = require(script.Parent.Parent.WorldTypes)

local World: WorldTypes.WorldDef = {
	id = 4,
	name = "The Scorching Sands",
	folder = "W04_ScorchingSands",
	-- Respawn seconds by kind (the user's rule, 2026-10-19), as every other world's.
	respawn = { small = 10, medium = 15, elite = 20, boss = 30, secret = 30 },
	enemies = {},
	bosses = {},
}

return World
