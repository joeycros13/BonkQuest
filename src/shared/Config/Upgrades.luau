--!strict
-- Upgrades: permanent stat upgrades bought with coins at each world's upgrader stall
-- (2026-10-19, the user's design; reworked 2026-10-28, the user: too many upgrades at
-- once, and each too small to feel).
--
-- Each world's upgrader sells only that world's three upgrades, 3 levels each (a "set").
-- Every upgrade is sold in two worlds (its `worlds`): levels 1-3 in the first, 4-6 in the
-- second, and the second set needs the first finished, which is only sold back at the
-- first world's upgrader (Defense: World 1, then World 4). A set opens once its world is
-- unlocked (HighestWorld). 8 worlds x 3 sets = 24 sets, each of the 12 upgrades twice.
-- Each level does a lot more than before (proposal on
-- https://claude.ai/artifact/57whQZev6Dm6pVNzVbN1oV, the user's yes). Paid strictly in coins.
--
-- A level's effect is `base + step * level` (`step` per level), read by the system
-- that owns the stat through Upgrades.value(player, id), which works on server and
-- client because UpgradeService publishes each level as the player's
-- "Upgrade_<id>" attribute:
--   Sprint       sprint speed x (0 = no sprinting at all; level 1 unlocks it)
--   Luck         x weapon drop chances (never materials or cores since 2026-10-26; stacks with passes)
--   Health       x max HP (the level's HP plus armour)
--   Defense      x damage taken
--   Attack       x weapon damage
--   AttackSpeed  x weapon swing time (cooldown)
--   CritDamage   a critical hit's damage multiplier (Balance.Melee.critMultiplier, 1.5, at level 0)
--   CritChance   the chance a hit is critical (Balance.Melee.critChance, 10%, at level 0)
--   Regen        extra share of max HP healed each second, on top of Roblox's 1% (+0.5% a level)
--   Coins        x kill coins
--   Exp          x kill EXP
--   Gathering    the chance each drop of a broken tree or rock comes doubled (+12% a level)
-- Most upgrades are SHOWN as a multiplier (the user, 2026-10-19: "easier tracking";
-- the Stats panel shows the same totals): Defense and Attack Speed as how much
-- tougher / faster you are (1 / the value). Chances and regen are percentages (the user,
-- 2026-10-22): Crit Chance "13% crit chance", Gathering "3% chance to double materials",
-- Regen the total with Roblox's own 1% ("1.45% max HP a second"); Gathering was +10%
-- materials a level and Regen +0.25% a level until then. Crit Damage and Crit Chance
-- joined on 2026-10-22 (the user: +0.05x crit damage and +1% crit chance a level),
-- after Attack Speed, as on the stand's 12-cubby scroll rack.
-- Every number here is a starting point to tune; prices are placeholders. Icons: set A
-- "puffy toy" (2026-10-19, the user's pick on https://claude.ai/artifact/G9vG6k7KNs8rGrbRmBtUKf),
-- rendered from art/tools/icons/upgrade_icons_v2.dc.html by svg_render.py and trimmed to
-- art/icons/upgrades/ (the first drafts are in art/icons/upgrades/_older/). The Stats
-- panel shows the same icons.

local Balance = require(script.Parent.Balance)

local Upgrades = {}

export type UpgradeDef = {
	id: string,
	name: string,
	icon: string,
	base: number, -- the value at level 0
	step: number, -- added per level
	-- how the value shows: as a multiplier, "x" as it is, "inverse" as 1 / it (a smaller
	-- damage taken or swing time reads as a bigger defense or speed); or as a percentage
	-- (2026-10-22, the user: chances and regen read as percentages), "percent" the value
	-- itself (Crit Chance 13%, Gathering 3%), "regen" the total regen with Roblox's own 1%
	show: "x" | "inverse" | "percent" | "regen",
	format: string, -- the effect line, with %s for the number (Text below has the words)
	costScale: number?, -- this upgrade's prices x this (Sprint is cheap: the first thing to buy)
	order: number,
	-- the two worlds whose upgraders sell its levels 1-3 and 4-6
	worlds: { number },
}

Upgrades.LEVELS_PER_WORLD = 3 -- levels in one world's set
Upgrades.SETS = 2 -- sets per upgrade (one in each of its two worlds)
Upgrades.MAX_WORLD = 8

-- Coins for the 1st / 2nd / 3rd level of a set, x its world's scale: x10 a world
-- since 2026-10-23 (it was 1, 4, 12, 30...), like the gates' coins (Config/Leveling, world scale).
-- A world's three upgrades (9 levels) cost about its gate's coins (2026-10-28, the user: 2,550
-- in World 1 against its 2,500 gate): the enemies are balanced on having them.
Upgrades.STEP_PRICES = { 100, 250, 500 }
Upgrades.WORLD_SCALE = { 1, 10, 100, 1000, 10000, 100000, 1000000, 10000000 }

Upgrades.Defs = {
	Sprint = { id = "Sprint", name = "Sprint", icon = "rbxassetid://73296530776054", base = 1.18, step = 0.12, show = "x", format = "%s sprint speed", order = 1, worlds = { 1, 4 } },
	Luck = { id = "Luck", name = "Luck", icon = "rbxassetid://140530795448870", base = 1, step = 0.20, show = "x", format = "%s luck", order = 2, worlds = { 3, 7 } },
	Health = { id = "Health", name = "Health", icon = "rbxassetid://104320402035577", base = 1, step = 0.15, show = "x", format = "%s max health", order = 3, worlds = { 1, 5 } },
	Defense = { id = "Defense", name = "Defense", icon = "rbxassetid://87669341236749", base = 1, step = -0.05, show = "inverse", format = "%s defense", order = 4, worlds = { 1, 4 } },
	Attack = { id = "Attack", name = "Attack", icon = "rbxassetid://101904574763468", base = 1, step = 0.12, show = "x", format = "%s damage", order = 5, worlds = { 2, 5 } },
	AttackSpeed = { id = "AttackSpeed", name = "Attack Speed", icon = "rbxassetid://94360279558290", base = 1, step = -0.06, show = "inverse", format = "%s attack speed", order = 6, worlds = { 3, 7 } },
	CritDamage = { id = "CritDamage", name = "Crit Damage", icon = "rbxassetid://136086913663998", base = Balance.Melee.critMultiplier, step = 0.20, show = "x", format = "%s crit damage", order = 7, worlds = { 6, 8 } },
	CritChance = { id = "CritChance", name = "Crit Chance", icon = "rbxassetid://112979523138128", base = Balance.Melee.critChance, step = 0.04, show = "percent", format = "%s crit chance", order = 8, worlds = { 4, 8 } },
	-- the share of max HP healed a second on top of Roblox's own 1% (+0.5% a level since
	-- 2026-10-28; was +0.15%, and +0.25% before 2026-10-22)
	Regen = { id = "Regen", name = "Regen", icon = "rbxassetid://111410183445207", base = 0, step = 0.005, show = "regen", format = "%s max HP a second", order = 9, worlds = { 3, 7 } },
	Coins = { id = "Coins", name = "Coins", icon = "rbxassetid://114082700684383", base = 1, step = 0.15, show = "x", format = "%s coins", order = 10, worlds = { 2, 6 } },
	Exp = { id = "Exp", name = "EXP", icon = "rbxassetid://72394547070909", base = 1, step = 0.15, show = "x", format = "%s EXP", order = 11, worlds = { 5, 8 } },
	-- the chance a tree's or rock's drop comes doubled (2026-10-22, the user: 0% at level 0;
	-- +12% a level since 2026-10-28, was +1%; it was +10% materials a level before)
	Gathering = { id = "Gathering", name = "Gathering", icon = "rbxassetid://138227733867903", base = 0, step = 0.12, show = "percent", format = "%s chance to double materials", order = 12, worlds = { 2, 6 } },
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
	maxWorld = "Max for World %d · more in World %d",
	maxHere = "All of World %d's levels",
	moreLater = "More levels in World %d",
	maxAll = "Fully upgraded",
	noSprint = "No sprint yet",
	-- the second set before the first is done: "Finish Defense at World 1's upgrader"
	finishFirst = "Finish %s at World %d's upgrader",
	finishShort = "World %d first",
	unlockWorld = "Unlock World %d",
	noneHere = "No upgrades here yet",
	-- refusals (BuyUpgrade's reason)
	coins = "Not enough coins",
	capped = "Unlock that world first",
	maxed = "Already fully upgraded",
	away = "Visit an upgrader",
	elsewhere = "Sold at another world's upgrader",
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

function Upgrades.maxLevel(): number
	return Upgrades.LEVELS_PER_WORLD * Upgrades.SETS
end

-- Which set (1 or 2) a level is in, and the world whose upgrader sells it.
function Upgrades.setOf(level: number): number
	return math.clamp(math.ceil(level / Upgrades.LEVELS_PER_WORLD), 1, Upgrades.SETS)
end

function Upgrades.worldOf(def: UpgradeDef, level: number): number
	return def.worlds[Upgrades.setOf(level)]
end

-- The highest level of `def` a player may own with `highestWorld` unlocked.
function Upgrades.cap(def: UpgradeDef, highestWorld: number): number
	local cap = 0
	for _, world in def.worlds do
		if world <= highestWorld then
			cap += Upgrades.LEVELS_PER_WORLD
		end
	end
	return cap
end

-- The set of `def` sold in `world` (1 or 2), or nil if that world doesn't sell it.
function Upgrades.setIn(def: UpgradeDef, world: number): number?
	return table.find(def.worlds, world)
end

-- The upgrades a world's upgrader sells, in order.
function Upgrades.soldIn(world: number): { UpgradeDef }
	local list = {}
	for _, def in Upgrades.list() do
		if Upgrades.setIn(def, world) then
			table.insert(list, def)
		end
	end
	return list
end

-- Coins to buy `level` of an upgrade.
function Upgrades.cost(def: UpgradeDef, level: number): number
	local world = Upgrades.worldOf(def, level)
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
-- swing). Returns the def itself when nothing changes, like Infuse.adjust. Anything without
-- a swing (a material, potion or armour set on a shared tile) passes through untouched.
function Upgrades.adjust(player: Player, def: any): any
	if not def or type(def.cooldown) ~= "number" then
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

-- What a level reads as, as a multiplier (see UpgradeDef.show; a "percent" or "regen"
-- upgrade's value is the share itself, see Upgrades.share).
function Upgrades.multiplier(def: UpgradeDef, level: number): number
	local v = Upgrades.at(def, level)
	if def.show == "inverse" then
		return 1 / v
	end
	return v
end

-- What a "percent" or "regen" upgrade's level reads as, a share (0.13 = 13%): the value,
-- or for Regen the total with Roblox's own 1% a second.
function Upgrades.share(def: UpgradeDef, level: number): number
	local v = Upgrades.at(def, level)
	return if def.show == "regen" then Upgrades.BASE_REGEN + v else v
end

function Upgrades.isPercent(def: UpgradeDef): boolean
	return def.show == "percent" or def.show == "regen"
end

-- "×1.24"
function Upgrades.times(n: number): string
	return ("×%.2f"):format(n)
end

-- "13%", "1.45%": a share as a percentage, up to two decimals with no trailing zeros.
function Upgrades.percent(share: number): string
	local text = ("%.2f"):format(share * 100):gsub("0+$", ""):gsub("%.$", "")
	return text .. "%"
end

-- The effect line for a level ("×1.10 luck", "13% crit chance", "1.45% max HP a second").
function Upgrades.describe(def: UpgradeDef, level: number): string
	if def.id == "Sprint" and level <= 0 then
		return Upgrades.Text.noSprint
	end
	if Upgrades.isPercent(def) then
		return def.format:format(Upgrades.percent(Upgrades.share(def, level)))
	end
	return def.format:format(Upgrades.times(Upgrades.multiplier(def, level)))
end

return Upgrades
