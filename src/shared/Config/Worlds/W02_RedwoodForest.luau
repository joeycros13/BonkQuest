--!strict
-- World 2: The Redwood Forest (the user's name, 2026-10-11; it was planned as
-- The Frozen Caverns, then a forest under the placeholder The Whispering
-- Woods). The World 2 gate's sign shows the name.
--
-- Roster (decided with the user, 2026-10-11): angry wildlife plus a forest-spirit
-- boss. Starting numbers, not final. Sizes were set against World 1: the Fox is as
-- tall as the Chicken, the Bear slightly bigger than the Bull, the Boar between.
--
-- Drops use the World 2 weapons (switched on 2026-10-11). A drop must name a
-- weapon that exists in Config/Weapons. The Firefly Lantern (Legendary) comes only
-- from the park ranger's final quest.

local WorldTypes = require(script.Parent.Parent.WorldTypes)

-- World 2 balance (2026-10-20, the user: World 2's enemies match World 1's, Chicken -> Fox, Bull -> Boar,
-- Stallion -> Bear): HP x ~6.9 (the Birch Hatchet's damage per second over the Sickle's, so fights last as
-- long), damage tuned so an early fight costs ~14% of health like World 1, EXP equal to the World 1
-- counterpart, coins tuned with art/tools/balance/world_sim.py --world 2 for ~45 min from arriving to buying
-- the World 3 gate (typical 44.4). Old numbers in the comments.
local World: WorldTypes.WorldDef = {
	id = 2,
	name = "The Redwood Forest",
	folder = "W02_RedwoodForest",
	-- the Index world card (2026-10-12, no enemies; art/index/world_W02_2026-10-12.png)
	profile = "rbxassetid://110979330411375",

	-- Respawn seconds by kind (the user's rule, 2026-10-19): every enemy of a tier
	-- comes back after the same time in its world; bosses and the secret enemy
	-- after `boss` / `secret`. A spawn marker's RespawnSeconds attribute still wins.
	respawn = { small = 10, medium = 15, elite = 20, boss = 30, secret = 30 },

	enemies = {
		-- Minion: quick and common, at the front of both lanes
		-- (ServerStorage/Assets/Enemies/Fox).
		Fox = {
			id = "Fox",
			tier = "small",
			name = "Snarling Fox",
			portrait = "rbxassetid://102792357956654", -- calm face (2026-10-11)
			hp = 276, -- 110
			-- Quick pounces with a snap at the end.
			melee = { damage = 20, cooldown = 1.0, windup = 0.5, range = 1.5, chaseSpeed = 17, armor = 0, move = "pounce" },
			coins = { min = 22, max = 45 }, -- 15-25
			exp = 10, -- 35
			drops = {
				{ weapon = "Hatchet", chance = 0.20 },
				{ weapon = "Cleaver", chance = 0.05 },
			},
			-- crafting materials (Config/Materials): the first armour set
			materials = { { id = "FoxFur", chance = 0.5, min = 1, max = 2 } },
		},
		-- Tough minion: armoured hide and a tusk charge
		-- (ServerStorage/Assets/Enemies/Boar).
		Boar = {
			id = "Boar",
			tier = "medium",
			name = "Wild Boar",
			portrait = "rbxassetid://105726195455752", -- calm face (2026-10-11)
			hp = 966, -- 260
			melee = { damage = 38, cooldown = 1.8, windup = 0.55, range = 1.5, chaseSpeed = 15, armor = 0.15, move = "charge" },
			coins = { min = 90, max = 150 }, -- 30-45
			exp = 38, -- 70
			drops = {
				{ weapon = "Cleaver", chance = 0.20 },
				{ weapon = "Quarterstaff", chance = 0.15 },
				{ weapon = "Mace", chance = 0.08 },
			},
			materials = { { id = "BoarTusk", chance = 0.5, min = 1, max = 2 } },
		},
		-- Elite: one at the far end of each lane; rears up for a two-paw slam
		-- (ServerStorage/Assets/Enemies/Bear).
		Bear = {
			id = "Bear",
			tier = "elite",
			name = "Grizzly Bear",
			portrait = "rbxassetid://117018743106247", -- calm face (2026-10-11)
			hp = 1520, -- 550
			melee = { damage = 50, cooldown = 2.4, windup = 0.78, range = 1.6, chaseSpeed = 13, armor = 0.2, move = "slam" },
			coins = { min = 150, max = 226 }, -- 60-90
			exp = 56, -- 150
			drops = {
				{ weapon = "Mace", chance = 0.15 },
				{ weapon = "WoodsmansAxe", chance = 0.10 },
				{ weapon = "Greatclub", chance = 0.08 },
			},
			-- the second armour set
			materials = { { id = "BearClaw", chance = 0.4, min = 1, max = 1 } },
		},
		-- SECRET (2026-10-12): the Fairy of the hollow stump. Found by looking through the
		-- lookout telescope at the fairy ring, then standing in the ring for 5 s. A small
		-- mushroom-cap fairy with fluttering wings; flicks her acorn wand for a pop of
		-- fairy dust. Quick and a bit tougher than the Bear, but hits softer. Kept out of
		-- the Index (secret). Her drop -- one part of the secret crafted weapon -- is still
		-- to design (ServerStorage/Assets/Enemies/Fairy).
		Fairy = {
			id = "Fairy",
			name = "Fairy",
			hp = 600,
			secret = true,
			adminPortrait = "rbxassetid://128352315360379", -- admin panel only, never the Index (2026-10-17)
			melee = { damage = 24, cooldown = 1.6, windup = 0.45, range = 2.2, chaseSpeed = 18, armor = 0.1, move = "zap" },
			coins = { min = 80, max = 120 },
			exp = 180,
			-- the Forest Core: about 1%, once per player (trial numbers)
			materials = { { id = "ForestCore", chance = 0.01, min = 1, max = 1 } },
		},
	},

	bosses = {
		-- The Redwood Forest boss, in the mossy ruins arena
		-- (ServerStorage/Assets/Bosses/ElderTreant). Lifts a knee and stomps.
		ElderTreant = {
			id = "ElderTreant",
			name = "Elder Treant",
			portrait = "rbxassetid://98505547017601", -- calm face (2026-10-11)
			hp = 1200,
			-- Two attacks, picked 50/50, same damage and timing (user, 2026-10-11): the
			-- knee-up stomp and an overhead double-arm smash.
			melee = { damage = 70, cooldown = 2.4, windup = 0.72, range = 1.5, chaseSpeed = 10, armor = 0.3, move = "stomp", moves = { "stomp", "smash" } },
			coins = { min = 338, max = 526 }, -- 150-220
			exp = 150, -- 400
			drops = {
				{ weapon = "WoodsmansAxe", chance = 0.20 },
				{ weapon = "Greatclub", chance = 0.20 },
				-- Legendary: the treant's living heart
				{ weapon = "HeartwoodStaff", chance = 0.05 },
				-- the secret Marshmallow Stick (hidden in the Index until found)
				{ weapon = "MarshmallowStick", chance = 0.001 }, -- secrets drop at 0.1% (the user's rule); 2% until 2026-10-20
			},
			materials = { { id = "HeartwoodSap", chance = 0.5, min = 1, max = 1 } },
		},
	},

	worldEnemy = { archetype = "Fox" },
}

return World
