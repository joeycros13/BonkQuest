--!strict
-- Materials: the crafting materials players collect for armour (Config/Armor),
-- decided with the user on 2026-10-12.
--
-- Each world has four enemy materials, one per enemy, plus one quest item:
--   * enemies 1 and 2 drop theirs for the world's first armour set;
--   * enemy 3 and the boss drop theirs for the second set;
--   * the quest item comes from the world's questline (the "defeat the boss" step,
--     Config/Quests `reward.item`) and also goes into the second set.
-- Which enemy drops what, how often and how many lives in that enemy's
-- `materials` table in Config/Worlds (MaterialService rolls it on every kill).
--
--   id      the key, saved in the player's "materials" section
--   name    shown in the Crafting panel, the Materials view and the drop pop-up
--   world   the world it belongs to (the Materials view groups by it)
--   order   sort order inside its world
--   source  the enemy that drops it (an enemy id), or the questline it comes from
--   rarity  its tile colour, one of Weapons.Rarities (user, 2026-10-12): in each world the
--           first enemy's material is Common, the second's Uncommon, the third's Rare,
--           the boss's Epic; quest items are Legendary
--   quest   true for a quest item: given once, never dropped
--   core    true for a secret-weapon core (2026-10-12): one per world, dropped about 1% by
--           that world's secret enemy, at most once per player (no duplicates, no pity);
--           it shows the big Index-style popup (rarity "Core") instead of a side toast, and
--           is infused into the Rusty Blade at that world's Crafter (the Farm Core first)
--   color   its signature colour (the drop pop-up's accent until it has an icon)
--   icon    its drawn picture (designed on the Crafting & Armor canvas, art/icons/)

local Materials = {}

export type MaterialDef = {
	id: string,
	name: string,
	world: number,
	order: number,
	rarity: string,
	source: string,
	quest: boolean?,
	core: boolean?,
	color: Color3,
	icon: string?,
}

Materials.Defs = {
	-- ==================== World 1 (The Sunny Meadows) ====================
	ChickenFeather = {
		id = "ChickenFeather",
		rarity = "Common",
		icon = "rbxassetid://100543718756830",
		name = "Chicken Feather",
		world = 1,
		order = 1,
		source = "Chicken",
		color = Color3.fromRGB(250, 246, 236),
	},
	BullHide = {
		id = "BullHide",
		rarity = "Uncommon",
		icon = "rbxassetid://85942265201882",
		name = "Bull Hide",
		world = 1,
		order = 2,
		source = "Bull",
		color = Color3.fromRGB(122, 74, 46),
	},
	Horsehair = {
		id = "Horsehair",
		rarity = "Rare",
		icon = "rbxassetid://97499083216514",
		name = "Horsehair",
		world = 1,
		order = 3,
		source = "Stallion",
		color = Color3.fromRGB(58, 60, 68),
	},
	GoldenStraw = {
		id = "GoldenStraw",
		rarity = "Epic",
		icon = "rbxassetid://84240567751498",
		name = "Golden Straw",
		world = 1,
		order = 4,
		source = "BossScarecrow",
		color = Color3.fromRGB(255, 205, 64),
	},
	LuckyHorseshoe = {
		id = "LuckyHorseshoe",
		rarity = "Legendary",
		icon = "rbxassetid://133553972989886",
		name = "Dale's Lucky Horseshoe",
		world = 1,
		order = 5,
		source = "DaleFarm",
		quest = true,
		color = Color3.fromRGB(176, 182, 190),
	},
	FarmCore = {
		id = "FarmCore",
		rarity = "Core",
		icon = "rbxassetid://71518709693512", -- the mirrored quad gem (2026-10-13)
		name = "Farm Core",
		world = 1,
		order = 6,
		source = "CornWraith",
		core = true,
		color = Color3.fromRGB(184, 50, 58),
	},
	-- ==================== World 2 (The Redwood Forest) ====================
	FoxFur = {
		id = "FoxFur",
		rarity = "Common",
		icon = "rbxassetid://86600481340451",
		name = "Fox Fur",
		world = 2,
		order = 1,
		source = "Fox",
		color = Color3.fromRGB(240, 120, 40),
	},
	BoarTusk = {
		id = "BoarTusk",
		rarity = "Uncommon",
		icon = "rbxassetid://121748887194395",
		name = "Boar Tusk",
		world = 2,
		order = 2,
		source = "Boar",
		color = Color3.fromRGB(244, 236, 214),
	},
	BearClaw = {
		id = "BearClaw",
		rarity = "Rare",
		icon = "rbxassetid://100972982041577",
		name = "Bear Claw",
		world = 2,
		order = 3,
		source = "Bear",
		color = Color3.fromRGB(46, 40, 38),
	},
	HeartwoodSap = {
		id = "HeartwoodSap",
		rarity = "Epic",
		icon = "rbxassetid://131595994723597",
		name = "Heartwood Sap",
		world = 2,
		order = 4,
		source = "ElderTreant",
		color = Color3.fromRGB(255, 176, 46),
	},
	RangerBadge = {
		id = "RangerBadge",
		rarity = "Legendary",
		icon = "rbxassetid://129405277446389",
		name = "Ranger's Badge",
		world = 2,
		order = 5,
		source = "RangerRedwoods",
		quest = true,
		color = Color3.fromRGB(232, 186, 60),
	},
	ForestCore = {
		id = "ForestCore",
		rarity = "Core",
		icon = "rbxassetid://102403704250894", -- the mirrored quad gem (2026-10-13)
		name = "Forest Core",
		world = 2,
		order = 6,
		source = "Fairy",
		core = true,
		color = Color3.fromRGB(30, 140, 74),
	},
	-- ==================== World 3 (The Crystal Caverns) ====================
	-- (2026-10-13; no icons drawn yet, so the drop pop-up shows each colour)
	BatWing = {
		id = "BatWing",
		icon = "rbxassetid://88978398173349",
		rarity = "Common",
		name = "Bat Wing",
		world = 3,
		order = 1,
		source = "CaveBat",
		color = Color3.fromRGB(91, 79, 114),
	},
	GolemPebble = {
		id = "GolemPebble",
		icon = "rbxassetid://81057452845619",
		rarity = "Uncommon",
		name = "Golem Pebble",
		world = 3,
		order = 2,
		source = "PebbleGolem",
		color = Color3.fromRGB(255, 167, 51),
	},
	GolemCrystal = {
		id = "GolemCrystal",
		icon = "rbxassetid://117290053300265",
		rarity = "Rare",
		name = "Golem Crystal",
		world = 3,
		order = 3,
		source = "CrystalGolem",
		color = Color3.fromRGB(127, 244, 255),
	},
	QueensSilk = {
		id = "QueensSilk",
		icon = "rbxassetid://99319386625760",
		rarity = "Epic",
		name = "Queen's Silk",
		world = 3,
		order = 4,
		source = "SpiderQueen",
		color = Color3.fromRGB(255, 92, 168),
	},
	-- the World 3 quest item (2026-10-13): given by Explorer Pip's defeat-the-Spider-Queen step
	-- (ExplorerCaverns step 8, 2026-10-17). Goes into Crystal Queen.
	MinersLantern = {
		id = "MinersLantern",
		icon = "rbxassetid://110907424907998",
		rarity = "Legendary",
		name = "Miner's Lantern",
		world = 3,
		order = 5,
		source = "ExplorerCaverns",
		quest = true,
		color = Color3.fromRGB(242, 194, 48),
	},
	-- the World 3 secret core (2026-10-13): pink with a gold pickaxe, dropped by the Gem Mole in the
	-- hidden mine.
	CaveCore = {
		id = "CaveCore",
		rarity = "Core",
		icon = "rbxassetid://128965725393405",
		name = "Cave Core",
		world = 3,
		order = 6,
		source = "GemMole",
		core = true,
		color = Color3.fromRGB(217, 58, 140),
	},
} :: { [string]: MaterialDef }

function Materials.get(id: any): MaterialDef?
	return if type(id) == "string" then Materials.Defs[id] else nil
end

-- Every material, by world and then order.
function Materials.list(): { MaterialDef }
	local list: { MaterialDef } = {}
	for _, def in Materials.Defs do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		if a.world ~= b.world then
			return a.world < b.world
		end
		return a.order < b.order
	end)
	return list
end

-- The player's counts, from their "Materials" attribute ("BullHide=3,ChickenFeather=12";
-- MaterialService publishes it). Works on both sides.
function Materials.counts(player: Player): { [string]: number }
	local out: { [string]: number } = {}
	local text = player:GetAttribute("Materials")
	for id, n in (if type(text) == "string" then text else ""):gmatch("([^,=]+)=(%d+)") do
		out[id] = tonumber(n) :: number
	end
	return out
end

return Materials
