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
-- come later (the enemies below are placed, with placeholder numbers); it takes the lighting as
-- built in Studio (World 1's golden afternoon). Numbers follow the base-fight rules (memory
-- world-scaling-baseline) once the weapons are in.
local WorldTypes = require(script.Parent.Parent.WorldTypes)

local World: WorldTypes.WorldDef = {
	id = 4,
	name = "The Scorching Sands",
	folder = "W04_ScorchingSands",
	-- Respawn seconds by kind (the user's rule, 2026-10-19), as every other world's.
	respawn = { small = 10, medium = 15, elite = 20, boss = 30, secret = 30 },
	attackStart = 10,
	chaseScale = 2.0,

	-- The undead roster (2026-10-28, the user's picks; memory world4-roster). PLACEHOLDER numbers
	-- (2026-10-29): about x10 World 3's at each rank, so the bodies can stand on the map; the real
	-- ones come from the base-fight rescale (art/tools/balance/rescale.py) with World 4's weapons.
	-- Weapon drops (2026-10-29) follow World 3's table slot for slot: each enemy drops the weapon that makes it quicker,
	-- one that beats the next enemy and a rare one that beats it easily. No portraits yet.
	enemies = {
		BoneJackal = {
			id = "BoneJackal",
			tier = "small",
			name = "Bone Jackal",
			hp = 115000,
			melee = { damage = 18000, cooldown = 0.7, windup = 0.25, range = 1.5, chaseSpeed = 17, armor = 0, move = "pounce" },
			coins = { min = 2800, max = 5500 },
			exp = 3000,
			drops = {
				{ weapon = "BoneClub", chance = 0.25 },
				{ weapon = "Khopesh", chance = 0.08 },
				{ weapon = "ScarabMace", chance = 0.015 },
			},
			materials = { { id = "JackalFang", chance = 0.5, min = 1, max = 1 } },
		},
		ShamblingMummy = {
			id = "ShamblingMummy",
			tier = "medium",
			name = "Shambling Mummy",
			hp = 370000,
			melee = { damage = 19000, cooldown = 1.1, windup = 0.3, range = 1.5, chaseSpeed = 12, armor = 0.1, move = "punch" },
			coins = { min = 5300, max = 10400 },
			exp = 5700,
			drops = {
				{ weapon = "ScarabMace", chance = 0.125 },
				{ weapon = "LinenSpear", chance = 0.042 },
				{ weapon = "DesertScimitar", chance = 0.008 },
			},
			materials = { { id = "MummyLinen", chance = 0.5, min = 1, max = 1 } },
		},
		TombGuardian = {
			id = "TombGuardian",
			tier = "elite",
			name = "Tomb Guardian",
			hp = 590000,
			melee = { damage = 48000, cooldown = 1.4, windup = 0.35, range = 1.6, chaseSpeed = 12, armor = 0.15, move = "slash" },
			coins = { min = 7500, max = 14800 },
			exp = 8100,
			drops = {
				{ weapon = "DesertScimitar", chance = 0.071 },
				{ weapon = "SarcophagusGreatsword", chance = 0.021 },
				{ weapon = "CursedAnkh", chance = 0.004 },
			},
			materials = { { id = "GuardianBronze", chance = 0.5, min = 1, max = 1 } },
		},
		PhantomPharaoh = {
			id = "PhantomPharaoh",
			name = "Phantom Pharaoh",
			hp = 655000,
			secret = true,
			melee = { damage = 33000, cooldown = 1, windup = 0.3, range = 1.8, chaseSpeed = 15, armor = 0.1, move = "zap" },
			coins = { min = 10400, max = 20700 },
			exp = 11400,
			drops = {},
			materials = { { id = "DesertCore", chance = 0.01, min = 1, max = 1 } },
		},
	},

	bosses = {
		SandPharaoh = {
			id = "SandPharaoh",
			name = "Sand Pharaoh",
			hp = 845000,
			melee = { damage = 61000, cooldown = 1.4, windup = 0.35, range = 1.5, chaseSpeed = 11, armor = 0.2, move = "smash", moves = { "smash", "stomp" } },
			coins = { min = 32000, max = 64000 },
			exp = 35000,
			drops = {
				{ weapon = "CursedAnkh", chance = 0.05 },
				{ weapon = "PharaohsCrook", chance = 0.0125 },
				{ weapon = "CactusClub", chance = 0.001 },
			},
			materials = { { id = "PharaohsGold", chance = 0.5, min = 1, max = 1 } },
		},
	},

	worldEnemy = { archetype = "BoneJackal" },
}

return World
