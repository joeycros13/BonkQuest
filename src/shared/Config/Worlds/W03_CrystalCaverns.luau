--!strict
-- World 3: The Crystal Caverns, a cave (the user's call, 2026-10-11; it was
-- planned as The Molten Peak).
--
-- Roster (picked with the user, 2026-10-13): Cave Bat, Pebble Golem, Crystal Golem
-- and the Spider Queen boss. Starting numbers, about twice World 2's.
--
-- Drops use the World 3 weapons (2026-10-13, memory world3-weapons). The Diamond
-- Pickaxe (Legendary) comes only from the World 3 quest's final reward.

-- The health ladder and a prepared player (2026-10-20, as World 2's): the base is a level-36 arrival (450 HP)
-- in Heartwood Bark (+160 HP, 32%) with World 2's upgrades maxed (x1.30 HP, x0.94 damage taken, x1.18 damage,
-- x0.91 swing time) swinging the Heartwood Staff: 793 HP, taking x0.639, 118 damage a second. Each enemy
-- mirrors its World 1 counterpart against a fresh level-1 Dagger player: hits take 6 / 12 / 20 / 22% of health
-- (Bat 74, Pebble Golem 149, Crystal Golem 248, Spider Queen 273; the Gem Mole 15%, 186) and kills take as long
-- (Bat 314, Pebble Golem 747 at 10% armour, Crystal Golem 1,022 at 15%, Spider Queen 1,572 at 20%, Gem Mole
-- 1,415 at 10%). Coins and EXP are not re-simulated yet (World 3 has no world_sim dump).
local WorldTypes = require(script.Parent.Parent.WorldTypes)

-- World scale (2026-10-23, Config/Leveling), PROVISIONAL until World 3 is rebuilt and simulated:
-- health x32 (the weapons are x32), damage and EXP x16. Numbers in older comments are before it.

local World: WorldTypes.WorldDef = {
	id = 3,
	name = "The Crystal Caverns",
	folder = "W03_CrystalCaverns",
	-- the Index world card and Worlds-menu banner (2026-10-17, no enemies, past the stalls
	-- looking at the boarded-up mine entrance; art/portraits/worlds/world_W03_2026-10-17.png)
	profile = "rbxassetid://106928307558031",
	-- "Deep sapphire" (the user's pick, 2026-10-24): a blue cave light and haze with more
	-- contrast and colour, so the glowing crystals and the lake stand out. No sky shows
	-- underground, so the sun settings only keep the look steady.
	lighting = {
		ClockTime = 14,
		Brightness = 2,
		ExposureCompensation = -0.1,
		Ambient = Color3.fromHex("7d7fb8"),
		OutdoorAmbient = Color3.fromHex("7d7fb8"),
		ColorShift_Top = Color3.fromHex("e6e8ff"),
		Atmosphere = { Density = 0.38, Offset = 0, Color = Color3.fromHex("6f78c8"), Decay = Color3.fromHex("2a2d66"), Glare = 0, Haze = 1.6 },
		ColorCorrection = { Brightness = 0, Contrast = 0.18, Saturation = 0.22, TintColor = Color3.fromHex("d6dcff") },
		SunRays = { Intensity = 0, Spread = 0.6 },
	},
	-- Respawn seconds by kind (the user's rule, 2026-10-19): every enemy of a tier
	-- comes back after the same time in its world; bosses and the secret enemy
	-- after `boss` / `secret`. A spawn marker's RespawnSeconds attribute still wins.
	respawn = { small = 10, medium = 15, elite = 20, boss = 30, secret = 30 },

	enemies = {
		-- Minion: a small bat that hovers low at the front of every lane and in the
		-- halls; swoops down for a bite (ServerStorage/Assets/Enemies/CaveBat).
		CaveBat = {
			id = "CaveBat",
			tier = "small",
			name = "Cave Bat",
			portrait = "rbxassetid://72271902069536", -- calm face (2026-10-13)
			hp = 10048, -- 240 before the 2026-10-20 ladder
			melee = { damage = 1184, cooldown = 1.2, windup = 0.47, range = 1.6, chaseSpeed = 18, armor = 0, move = "swoop" },
			coins = { min = 30, max = 50 },
			exp = 1120,
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
			tier = "medium",
			name = "Pebble Golem",
			portrait = "rbxassetid://92185614445143", -- calm face (2026-10-13)
			hp = 23904, -- 550 before the 2026-10-20 ladder
			melee = { damage = 2384, cooldown = 1.8, windup = 0.48, range = 1.5, chaseSpeed = 14, armor = 0.1, move = "punch" },
			coins = { min = 65, max = 95 },
			exp = 2400,
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
			tier = "elite",
			name = "Crystal Golem",
			portrait = "rbxassetid://84986641261720", -- calm face (2026-10-13)
			hp = 32704, -- 1,100 before the 2026-10-20 ladder
			melee = { damage = 3968, cooldown = 2.4, windup = 0.74, range = 1.6, chaseSpeed = 12, armor = 0.15, move = "smash" },
			coins = { min = 130, max = 190 },
			exp = 5120,
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
			hp = 45280, -- 1,200 before the 2026-10-20 ladder
			secret = true,
			adminPortrait = "rbxassetid://95259297161320", -- admin panel only, never the Index (2026-10-17)
			melee = { damage = 2976, cooldown = 1.8, windup = 0.48, range = 1.8, chaseSpeed = 15, armor = 0.1, move = "slash" },
			coins = { min = 160, max = 230 },
			exp = 5760,
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
			hp = 50304, -- 2,600 with 30% armour before the 2026-10-20 ladder
			melee = { damage = 4368, cooldown = 2.4, windup = 0.74, range = 1.5, chaseSpeed = 11, armor = 0.2, move = "legstab", moves = { "legstab", "rearslam" } },
			coins = { min = 320, max = 460 },
			exp = 13600,
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
