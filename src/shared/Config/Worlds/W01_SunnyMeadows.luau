--!strict
-- World 1: The Sunny Meadows (renamed from The Green Meadows, 2026-10-11).
--
-- A world file owns everything about one world: its enemy roster and its boss.
-- Adding a world means adding a file like this one and listing it in
-- Worlds/init.luau.

local WorldTypes = require(script.Parent.Parent.WorldTypes)

local World: WorldTypes.WorldDef = {
	id = 1,
	name = "The Sunny Meadows",
	folder = "W01_SunnyMeadows",
	-- the Index world card (re-shot 2026-10-19 for the grown map, no enemies; art/portraits/worlds/world_W01_2026-10-19.png)
	profile = "rbxassetid://89359546830130",

	-- Respawn seconds by kind (the user's rule, 2026-10-19): every enemy of a tier
	-- comes back after the same time in its world; bosses and the secret enemy
	-- after `boss` / `secret`. A spawn marker's RespawnSeconds attribute still wins.
	respawn = { small = 10, medium = 15, elite = 20, boss = 30, secret = 30 },

	enemies = {
		-- Minion: the weakest world enemy, in flocks along the front of every path
		-- (ServerStorage/Assets/Enemies/Chicken).
		Chicken = {
			id = "Chicken",
			tier = "small",
			name = "Angry Chicken",
			hp = 40,
			portrait = "rbxassetid://119866244895251", -- calm face (2026-10-11)
			-- Quick, weak pecks.
			melee = { damage = 6, cooldown = 1.2, windup = 0.25, range = 1.5, chaseSpeed = 15, armor = 0, move = "peck" },
			-- Coins and rates are tuned for a ~30-minute World 1 (2026-10-19; see Balance).
			coins = { min = 6, max = 12 },
			exp = 8,
			drops = {
				{ weapon = "Sickle", chance = 0.20 },
				{ weapon = "Machete", chance = 0.05 },
			},
			-- crafting materials (Config/Materials): the first armour set
			materials = { { id = "ChickenFeather", chance = 0.5, min = 1, max = 2 } },
		},
		-- Elite: guards the far end of each path before the boss platform. Hits
		-- harder, so it is a real check before the boss
		-- (ServerStorage/Assets/Enemies/Bull).
		Bull = {
			id = "Bull",
			tier = "medium",
			name = "Raging Bull",
			hp = 140,
			portrait = "rbxassetid://105217136953827", -- calm face (2026-10-11)
			-- Slow, heavy horn charges with a long reach.
			melee = { damage = 16, cooldown = 2.0, windup = 0.45, range = 1.5, chaseSpeed = 14, armor = 0.1, move = "gore" },
			coins = { min = 24, max = 40 },
			exp = 30,
			drops = {
				{ weapon = "Machete", chance = 0.25 },
				{ weapon = "Pitchfork", chance = 0.15 },
				{ weapon = "Shovel", chance = 0.15 },
			},
			materials = { { id = "BullHide", chance = 0.5, min = 1, max = 2 } },
		},
		-- Elite: the third enemy (user, 2026-10-12), a dappled grey wild horse guarding the
		-- path up to the King's platform. Rears up and slams both front hooves down (the
		-- Bear's "slam"). Tougher and faster than the Bull. Its crafting material,
		-- Horsehair, goes in the second World 1 armour set (ServerStorage/Assets/Enemies/Stallion).
		Stallion = {
			id = "Stallion",
			tier = "elite",
			name = "Wild Stallion",
			hp = 220,
			portrait = "rbxassetid://73569429526048", -- calm face (2026-10-12)
			melee = { damage = 20, cooldown = 2.2, windup = 0.78, range = 1.6, chaseSpeed = 16, armor = 0.1, move = "slam" },
			coins = { min = 40, max = 60 },
			exp = 45,
			drops = {
				{ weapon = "Shovel", chance = 0.15 },
				{ weapon = "Scythe", chance = 0.10 },
			},
			-- the second armour set
			materials = { { id = "Horsehair", chance = 0.5, min = 1, max = 1 } },
		},
		-- SECRET (2026-10-12): the Corn Wraith haunts the hidden cellar under the farm
		-- (drop down the silo). A floating corn-cob head with a leaf crown over a mass of
		-- flowing leaves; a one-handed diagonal slash with its right leaf arm. Elite sized, a little
		-- tougher than the Bull. Kept out of the Index (secret). Its drop -- one part of the
		-- secret crafted weapon -- is still to design (ServerStorage/Assets/Enemies/CornWraith).
		CornWraith = {
			id = "CornWraith",
			name = "Corn Wraith",
			hp = 180,
			secret = true,
			adminPortrait = "rbxassetid://85851674951625", -- admin panel only, never the Index (2026-10-17)
			melee = { damage = 15, cooldown = 1.7, windup = 0.48, range = 1.8, chaseSpeed = 15, armor = 0.1, move = "slash" },
			coins = { min = 25, max = 40 },
			exp = 60,
			-- the Farm Core: 1%, once per player; luck never changes a core's chance
			materials = { { id = "FarmCore", chance = 0.01, min = 1, max = 1 } },
		},
	},

	bosses = {
		-- The Sunny Meadows boss, waiting on the boss platform
		-- (ServerStorage/Assets/Bosses/BossScarecrow).
		BossScarecrow = {
			id = "BossScarecrow",
			name = "Scarecrow King",
			-- 32 x the old boss multiplier of 4, so the fight is unchanged.
			hp = 128,
			portrait = "rbxassetid://80515484828150", -- calm black face, with the elbow and knee ties (2026-10-11; was 122472392610626)
			-- Pitchfork jabs with the longest reach; armour halves weapon damage so the
			-- fight outlasts the Bull's.
			melee = { damage = 22, cooldown = 2.2, windup = 0.5, range = 1.2, chaseSpeed = 11, armor = 0.5, move = "stab" },
			coins = { min = 90, max = 140 },
			exp = 120,
			drops = {
				{ weapon = "Pitchfork", chance = 0.25 },
				{ weapon = "Scythe", chance = 0.20 },
				-- Legendary: his own pumpkin head on a stake
				{ weapon = "PumpkinMace", chance = 0.05 },
				-- the secret Corn Cob (0.1%, the user's rate for secrets)
				{ weapon = "CornCob", chance = 0.001 },
			},
			materials = { { id = "GoldenStraw", chance = 0.5, min = 1, max = 1 } },
		},
	},

	worldEnemy = { archetype = "Chicken" },
}

return World
