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

	-- The undead roster (2026-10-28, the user's picks; memory world4-roster). Numbers from the base-fight
	-- rescale (2026-10-29, art/tools/balance/rescale.py, like Worlds 2 and 3): the Jackal's health from a 12 s
	-- fight against the arrival's Queen's Fang, the rest by the health ladder; every enemy's damage solved from
	-- its own fight (WORLD_FIGHTS); kill EXP and coins x0.56 (tune.sh) so a maxed arrival reaches a stand-in
	-- World 5 gate in about 150 min.
	-- Weapon drops (2026-10-29) follow World 3's table slot for slot: each enemy drops the weapon that makes it quicker,
	-- one that beats the next enemy and a rare one that beats it easily. Portraits (2026-10-29): art/portraits/enemies/portrait_<id>.png;
	-- the Phantom Pharaoh, a secret, gets none.
	enemies = {
		BoneJackal = {
			id = "BoneJackal",
			tier = "small",
			name = "Bone Jackal",
			portrait = "rbxassetid://75318763153938",
			hp = 115590,
			melee = { damage = 17007, cooldown = 0.6, windup = 0.25, range = 1.5, chaseSpeed = 17, armor = 0, move = "pounce" },
			coins = { min = 1568, max = 3080 },
			exp = 1680,
			drops = {
				{ weapon = "BoneClub", chance = 0.1562 },
				{ weapon = "Khopesh", chance = 0.05 },
				{ weapon = "ScarabMace", chance = 0.0094 },
			},
			materials = { { id = "JackalFang", chance = 0.5, min = 1, max = 1 } },
		},
		ShamblingMummy = {
			id = "ShamblingMummy",
			tier = "medium",
			name = "Shambling Mummy",
			portrait = "rbxassetid://131789092253692",
			hp = 353380,
			melee = { damage = 21821, cooldown = 1.1, windup = 0.3, range = 1.5, chaseSpeed = 12, armor = 0.1, move = "punch" },
			coins = { min = 2968, max = 5824 },
			exp = 3192,
			drops = {
				{ weapon = "ScarabMace", chance = 0.0937 },
				{ weapon = "LinenSpear", chance = 0.0312 },
				{ weapon = "DesertScimitar", chance = 0.0062 },
			},
			materials = { { id = "MummyLinen", chance = 0.5, min = 1, max = 1 } },
		},
		TombGuardian = {
			id = "TombGuardian",
			tier = "elite",
			name = "Tomb Guardian",
			portrait = "rbxassetid://137733596334165",
			hp = 539970,
			melee = { damage = 43261, cooldown = 1, windup = 0.3, range = 1.6, chaseSpeed = 12, armor = 0.15, move = "slash" },
			coins = { min = 4200, max = 8288 },
			exp = 4536,
			drops = {
				{ weapon = "DesertScimitar", chance = 0.0625 },
				{ weapon = "SarcophagusGreatsword", chance = 0.0187 },
				{ weapon = "CursedAnkh", chance = 0.0031 },
			},
			materials = { { id = "GuardianBronze", chance = 0.5, min = 1, max = 1 } },
		},
		PhantomPharaoh = {
			id = "PhantomPharaoh",
			name = "Phantom Pharaoh",
			hp = 599970,
			secret = true,
			melee = { damage = 40673, cooldown = 1, windup = 0.25, range = 1.8, chaseSpeed = 15, armor = 0.1, move = "zap" },
			coins = { min = 5824, max = 11592 },
			exp = 6384,
			drops = {},
			materials = { { id = "DesertCore", chance = 0.0001, min = 1, max = 1 } },
		},
	},

	bosses = {
		SandPharaoh = {
			id = "SandPharaoh",
			name = "Sand Pharaoh",
			portrait = "rbxassetid://114101663877562",
			hp = 733170,
			melee = { damage = 84626, cooldown = 1.4, windup = 0.35, range = 1.5, chaseSpeed = 11, armor = 0.2, move = "smash", moves = { "smash", "stomp" } },
			coins = { min = 17920, max = 35840 },
			exp = 19600,
			drops = {
				{ weapon = "CursedAnkh", chance = 0.05 },
				{ weapon = "PharaohsCrook", chance = 0.0075 },
				{ weapon = "CactusClub", chance = 0.00005 },
			},
			materials = { { id = "PharaohsGold", chance = 0.5, min = 1, max = 1 } },
		},
	},

	worldEnemy = { archetype = "BoneJackal" },
}

return World
