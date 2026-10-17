--!strict
-- World 3: The Crystal Caverns, a cave (the user's call, 2026-10-11; it was
-- planned as The Molten Peak).
--
-- Roster (picked with the user, 2026-10-13): Cave Bat, Pebble Golem, Crystal Golem
-- and the Spider Queen boss. Starting numbers, about twice World 2's.
--
-- Drops use the World 3 weapons (2026-10-13, memory world3-weapons). The Diamond
-- Pickaxe (Legendary) comes only from the World 3 quest's final reward.

local WorldTypes = require(script.Parent.Parent.WorldTypes)

local World: WorldTypes.WorldDef = {
	id = 3,
	name = "The Crystal Caverns",
	folder = "W03_CrystalCaverns",
	enemies = {
		-- Minion: a small bat that hovers low at the front of every lane and in the
		-- halls; swoops down for a bite (ServerStorage/Assets/Enemies/CaveBat).
		CaveBat = {
			id = "CaveBat",
			name = "Cave Bat",
			portrait = "rbxassetid://72271902069536", -- calm face (2026-10-13)
			hp = 240,
			melee = { damage = 18, cooldown = 1.2, windup = 0.47, range = 1.6, chaseSpeed = 18, armor = 0, move = "swoop" },
			coins = { min = 30, max = 50 },
			exp = 70,
			drops = {
				{ weapon = "BatwingBlade", chance = 0.20 },
				{ weapon = "IronPickaxe", chance = 0.05 },
			},
			materials = { { id = "BatWing", chance = 0.5, min = 1, max = 2 } },
		},
		-- Tough minion: stacked stones round a glowing core, mid-lane; a wind-up
		-- punch (ServerStorage/Assets/Enemies/PebbleGolem).
		PebbleGolem = {
			id = "PebbleGolem",
			name = "Pebble Golem",
			portrait = "rbxassetid://92185614445143", -- calm face (2026-10-13)
			hp = 550,
			melee = { damage = 30, cooldown = 1.8, windup = 0.48, range = 1.5, chaseSpeed = 14, armor = 0.15, move = "punch" },
			coins = { min = 65, max = 95 },
			exp = 150,
			drops = {
				{ weapon = "IronPickaxe", chance = 0.20 },
				{ weapon = "PebbleMallet", chance = 0.15 },
				{ weapon = "GoldGauntlets", chance = 0.08 },
			},
			materials = { { id = "GolemPebble", chance = 0.5, min = 1, max = 2 } },
		},
		-- Elite: dark slate with crystal clusters, guarding the two lanes into the boss
		-- hall; an overhead double-fist slam (ServerStorage/Assets/Enemies/CrystalGolem).
		CrystalGolem = {
			id = "CrystalGolem",
			name = "Crystal Golem",
			portrait = "rbxassetid://84986641261720", -- calm face (2026-10-13)
			hp = 1100,
			melee = { damage = 48, cooldown = 2.4, windup = 0.74, range = 1.6, chaseSpeed = 12, armor = 0.2, move = "smash" },
			coins = { min = 130, max = 190 },
			exp = 320,
			drops = {
				{ weapon = "GoldGauntlets", chance = 0.15 },
				{ weapon = "GeodeGlaive", chance = 0.10 },
				{ weapon = "EmberCoalMaul", chance = 0.08 },
			},
			materials = { { id = "GolemCrystal", chance = 0.4, min = 1, max = 1 } },
		},
		-- SECRET (2026-10-13): the Gem Mole of the hidden mine. Found by striking the
		-- three pulsing crystals in the order the tunnel's hint shows (blue, pink,
		-- purple), which opens the front mineshaft into the room carved out of the
		-- first rock island. A friendly round mole in a tiny hard hat with a pink
		-- diamond nose; swipes with a big digging paw. A little tougher than the
		-- Crystal Golem but hits softer. Kept out of the Index (secret). Drops the
		-- Cave Core, the third gem of the Worldheart Blade
		-- (ServerStorage/Assets/Enemies/GemMole).
		GemMole = {
			id = "GemMole",
			name = "Gem Mole",
			hp = 1200,
			secret = true,
			melee = { damage = 40, cooldown = 1.8, windup = 0.48, range = 1.8, chaseSpeed = 15, armor = 0.15, move = "slash" },
			coins = { min = 160, max = 230 },
			exp = 360,
			-- the Cave Core: about 1%, once per player (trial numbers)
			materials = { { id = "CaveCore", chance = 0.01, min = 1, max = 1 } },
		},
	},

	bosses = {
		-- The Crystal Caverns boss, in the far hall (ServerStorage/Assets/Bosses/SpiderQueen).
		-- Two attacks, picked 50/50 with the same timing: a front-leg stab and a
		-- rear-up slam.
		SpiderQueen = {
			id = "SpiderQueen",
			name = "Spider Queen",
			portrait = "rbxassetid://80870479752276", -- calm face (2026-10-13)
			hp = 2600,
			melee = { damage = 60, cooldown = 2.4, windup = 0.74, range = 1.5, chaseSpeed = 11, armor = 0.3, move = "legstab", moves = { "legstab", "rearslam" } },
			coins = { min = 320, max = 460 },
			exp = 850,
			drops = {
				{ weapon = "GeodeGlaive", chance = 0.20 },
				{ weapon = "EmberCoalMaul", chance = 0.20 },
				-- Legendary: the Queen's own fang
				{ weapon = "QueensFang", chance = 0.05 },
				-- the secret Rock Candy Club (hidden in the Index until found)
				{ weapon = "RockCandyClub", chance = 0.02 },
			},
			materials = { { id = "QueensSilk", chance = 0.5, min = 1, max = 1 } },
		},
	},

	worldEnemy = { archetype = "CaveBat" },
}

return World
