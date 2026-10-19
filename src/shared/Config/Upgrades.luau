--!strict
-- Upgrades: permanent stat upgrades bought with coins at the Upgrades stand in
-- World 1's spawn hub (2026-10-19, the user's design; the stand is only in World 1).
--
-- Each upgrade has levels; a player may own LEVELS_PER_WORLD (3) of each per world
-- they've unlocked, so in World 1 they can reach level 3, and the next three open
-- when the World 2 gate is bought (HighestWorld). Upgrades are never needed to
-- finish a world (the user's rule), so the balance simulation leaves them out.
-- Paid strictly in coins.
--
-- A level's effect is `base + step * level` (`step` per level), read by the system
-- that owns the stat through Upgrades.value(player, id), which works on server and
-- client because UpgradeService publishes each level as the player's
-- "Upgrade_<id>" attribute:
--   Sprint       sprint speed x (0 = no sprinting at all; level 1 unlocks it)
--   Luck         x drop chances (weapons and materials, never cores; stacks with passes)
--   Health       x max HP (the level's HP plus armour)
--   Defense      x damage taken
--   Attack       x weapon damage
--   AttackSpeed  x weapon swing time (cooldown)
--   Regen        extra share of max HP healed each second, on top of Roblox's 1%
--   Coins        x kill coins
--   Exp          x kill EXP
--   Gathering    x the materials a broken tree or rock gives (the fraction rolled)
-- Every upgrade is SHOWN as a multiplier (the user, 2026-10-19: "easier tracking";
-- the Stats panel shows the same totals): Defense and Attack Speed as how much
-- tougher / faster you are (1 / the value), Regen against Roblox's base 1% a second.
-- Every number here is a starting point to tune; prices are placeholders. Icons: set A
-- "puffy toy" (2026-10-19, the user's pick on https://claude.ai/artifact/G9vG6k7KNs8rGrbRmBtUKf),
-- rendered from art/tools/icons/upgrade_icons_v2.dc.html by svg_render.py and trimmed to
-- art/icons/upgrades/ (the first drafts are in art/icons/upgrades/_older/). The Stats
-- panel shows the same icons.

local Upgrades = {}

export type UpgradeDef = {
	id: string,
	name: string,
	icon: string,
	base: number, -- the value at level 0
	step: number, -- added per level
	-- how the value shows as a multiplier: "x" as it is, "inverse" as 1 / it (a smaller
	-- damage taken or swing time reads as a bigger defense or speed), "regen" as the
	-- total regen over Roblox's base
	show: "x" | "inverse" | "regen",
	format: string, -- the effect line, with %s for the number (Text below has the words)
	costScale: number?, -- this upgrade's prices x this (Sprint is cheap: the first thing to buy)
	order: number,
}

Upgrades.LEVELS_PER_WORLD = 3
Upgrades.MAX_WORLD = 8

-- Coins for the 1st / 2nd / 3rd level bought inside a world, x that world's scale.
Upgrades.STEP_PRICES = { 100, 250, 500 }
Upgrades.WORLD_SCALE = { 1, 4, 12, 30, 70, 150, 300, 600 }

Upgrades.Defs = {
	Sprint = { id = "Sprint", name = "Sprint", icon = "rbxassetid://73296530776054", base = 1.16, step = 0.04, show = "x", format = "%s sprint speed", costScale = 0.5, order = 1 },
	Luck = { id = "Luck", name = "Luck", icon = "rbxassetid://140530795448870", base = 1, step = 0.05, show = "x", format = "%s luck", order = 2 },
	Health = { id = "Health", name = "Health", icon = "rbxassetid://82838416987322", base = 1, step = 0.05, show = "x", format = "%s max health", order = 3 },
	Defense = { id = "Defense", name = "Defense", icon = "rbxassetid://87669341236749", base = 1, step = -0.01, show = "inverse", format = "%s defense", order = 4 },
	Attack = { id = "Attack", name = "Attack", icon = "rbxassetid://101904574763468", base = 1, step = 0.03, show = "x", format = "%s damage", order = 5 },
	AttackSpeed = { id = "AttackSpeed", name = "Attack Speed", icon = "rbxassetid://94360279558290", base = 1, step = -0.015, show = "inverse", format = "%s attack speed", order = 6 },
	Regen = { id = "Regen", name = "Regen", icon = "rbxassetid://111410183445207", base = 0, step = 0.0025, show = "regen", format = "%s regen", order = 7 },
	Coins = { id = "Coins", name = "Coins", icon = "rbxassetid://114082700684383", base = 1, step = 0.04, show = "x", format = "%s coins", order = 8 },
	Exp = { id = "Exp", name = "EXP", icon = "rbxassetid://72394547070909", base = 1, step = 0.04, show = "x", format = "%s EXP", order = 9 },
	Gathering = { id = "Gathering", name = "Gathering", icon = "rbxassetid://75333539272846", base = 1, step = 0.1, show = "x", format = "%s materials", order = 10 },
} :: { [string]: UpgradeDef }

-- Every word the panel shows (the user's rule: UI text lives in code).
Upgrades.Text = {
	title = "UPGRADES",
	worldPill = "World %d · %s",
	levelOf = "Level %d of %d in World %d",
	now = "NOW",
	next = "NEXT",
	allLevels = "ALL LEVELS",
	worldShort = "W%d",
	buy = "Upgrade",
	maxWorld = "Max for World %d · unlock World %d",
	maxAll = "Fully upgraded",
	noSprint = "No sprint yet",
	-- refusals (BuyUpgrade's reason)
	coins = "Not enough coins",
	capped = "Unlock the next world for more levels",
	maxed = "Already fully upgraded",
	away = "Visit the Upgrades stand",
}

function Upgrades.get(id: any): UpgradeDef?
	return if type(id) == "string" then Upgrades.Defs[id] else nil
end

function Upgrades.list(): { UpgradeDef }
	local list = {}
	for _, def in Upgrades.Defs do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		return a.order < b.order
	end)
	return list
end

-- The highest level a player may own with `highestWorld` unlocked.
function Upgrades.cap(highestWorld: number): number
	return Upgrades.LEVELS_PER_WORLD * math.clamp(highestWorld, 1, Upgrades.MAX_WORLD)
end

function Upgrades.maxLevel(): number
	return Upgrades.LEVELS_PER_WORLD * Upgrades.MAX_WORLD
end

-- The world a level belongs to (levels 1-3 World 1, 4-6 World 2...).
function Upgrades.worldOf(level: number): number
	return math.ceil(level / Upgrades.LEVELS_PER_WORLD)
end

-- Coins to buy `level` of an upgrade.
function Upgrades.cost(def: UpgradeDef, level: number): number
	local world = Upgrades.worldOf(level)
	local step = (level - 1) % Upgrades.LEVELS_PER_WORLD + 1
	local price = Upgrades.STEP_PRICES[step] * (Upgrades.WORLD_SCALE[world] or Upgrades.WORLD_SCALE[#Upgrades.WORLD_SCALE])
	return math.floor(price * (def.costScale or 1) / 5 + 0.5) * 5
end

function Upgrades.attr(id: string): string
	return "Upgrade_" .. id
end

function Upgrades.level(player: Player, id: string): number
	local value = player:GetAttribute(Upgrades.attr(id))
	return if type(value) == "number" then value else 0
end

-- The effect at a level: base + step * level.
function Upgrades.at(def: UpgradeDef, level: number): number
	return def.base + def.step * level
end

-- This player's value of an upgrade (see the header for what each means). Sprint is
-- 0 until its first level: no sprinting.
function Upgrades.value(player: Player, id: string): number
	local def = Upgrades.Defs[id]
	if not def then
		return 1
	end
	local level = Upgrades.level(player, id)
	if id == "Sprint" and level <= 0 then
		return 0
	end
	return Upgrades.at(def, level)
end

-- A weapon's stats with this player's upgrades applied (Attack Speed shortens the
-- swing). Returns the def itself when nothing changes, like Infuse.adjust.
function Upgrades.adjust(player: Player, def: any): any
	if not def then
		return def
	end
	local speed = Upgrades.value(player, "AttackSpeed")
	if speed == 1 then
		return def
	end
	local copy = table.clone(def)
	copy.cooldown = def.cooldown * speed
	return copy
end

-- Roblox's own Health script heals this share of max HP a second (Regen shows against it).
Upgrades.BASE_REGEN = 0.01

-- What a level reads as, as a multiplier (see UpgradeDef.show).
function Upgrades.multiplier(def: UpgradeDef, level: number): number
	local v = Upgrades.at(def, level)
	if def.show == "inverse" then
		return 1 / v
	elseif def.show == "regen" then
		return (Upgrades.BASE_REGEN + v) / Upgrades.BASE_REGEN
	end
	return v
end

-- "×1.24"
function Upgrades.times(n: number): string
	return ("×%.2f"):format(n)
end

-- The effect line for a level ("×1.10 luck", "×1.24 sprint speed").
function Upgrades.describe(def: UpgradeDef, level: number): string
	if def.id == "Sprint" and level <= 0 then
		return Upgrades.Text.noSprint
	end
	return def.format:format(Upgrades.times(Upgrades.multiplier(def, level)))
end

return Upgrades
