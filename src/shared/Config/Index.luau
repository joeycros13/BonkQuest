--!strict
-- Index: read-only views over the world and enemy config for the Index (the
-- bestiary / weapon book). Pure lookups shared by IndexService (server) and
-- the Index UI and discovery popups (client).
--
--   * roster(worldId): the world's enemies in Index order -- weakest first by
--     HP, bosses last. Secret enemies (def.secret) are never listed.
--   * isSecret(enemyId): true for a world's hidden secret enemy.
--   * dropsOf(enemyId): what an enemy can drop, likeliest first.
--   * sourcesOf(weaponId): which enemies drop a weapon, likeliest first.
--   * percent(chance): "25%" / "2.5%" for display.
--   * armorOf(worldId): the world's armour sets (Config/Armor) in order; the
--     Index lists them under the world's creatures (user, 2026-10-13).
--   * materialSource(materialId): where a recipe material comes from -- the
--     enemy that drops it and how often, or the questline that gives it.
--   * weaponsOf(worldId) / weaponCounts(def): the weapons the Index counts and
--     lists per world, low to high rarity then damage (user, 2026-10-13: drops, quest rewards and shop weapons,
--     secret drops included; not the Rusty Blade or the Worldheart tiers).
--   * weaponSources(weaponId): every way to get a weapon -- the enemies that drop
--     it (likeliest first), then the quests that give it.
--
-- The whole book (2026-10-20, the user: "cover almost everything", tab strip B on the
-- Index Expansion canvas, https://claude.ai/artifact/25K21YcFmckdyVGPEa3VpX): eight
-- sections per world, `Index.Sections` -- Creatures, Weapons, Armor, Tools, Materials,
-- Fish, Potions, Treasures. Cores and secret enemies are never in it.
--   * entries(worldId, section): what that page lists, in order (defs; creatures are
--     roster entries). Tools by tier then hotbar kind; Materials are the world's enemy
--     drops then its gathered ones (no fish, quest items or cores); Fish the world's
--     fished materials; Potions the ones the world's Crafter makes (Tier I by its
--     `world`, Tier II / III at the first world of their band) that have a recipe;
--     Treasures the world's quest items.
--   * itemDef(id): a tool, material or potion def by id (the "items" IndexService counts).
--   * found(section, id, progress): whether the player has found it. `progress` is
--     { kills, weapons, armor, items } (IndexService's attributes, progressOf(player)).
--   * progress(worldId, progress): found / total for the world and per section.
--   * Titles (Title 2 on the canvas): filling every page of a world earns its Collector
--     title; that plus the world's core infused into the Worldheart Blade earns its
--     Completionist title, which the book never names until it is earned. titleOf(id),
--     titlesOf(worldId), coreDone(player, worldId).
--
-- Drop tables themselves live on each enemy in Config/Worlds/<world>.

local Worlds = require(script.Parent.Worlds)
local Infuse = require(script.Parent.Infuse)
local Potions = require(script.Parent.Potions)
local Tools = require(script.Parent.Tools)
local Armor = require(script.Parent.Armor)
local Fishing = require(script.Parent.Fishing)
local Gathering = require(script.Parent.Gathering)
local Materials = require(script.Parent.Materials)
local Quests = require(script.Parent.Quests)
local Weapons = require(script.Parent.Weapons)
local WorldTypes = require(script.Parent.WorldTypes)

export type Entry = {
	id: string,
	def: WorldTypes.EnemyDef,
	worldId: number,
	isBoss: boolean,
}
export type Source = { enemy: string, chance: number }
-- quest = true: `name` is the quest giver's short name ("Dale") and there is no chance
export type MaterialSource = { name: string, chance: number?, quest: boolean }
-- an enemy drop (enemy, chance) or a quest reward (quest = the questline id)
export type WeaponSource = { enemy: string?, chance: number?, quest: string? }

-- the secret blade chain isn't counted in the Index (user, 2026-10-13)
local UNLISTED_RARITIES = { Relic = true, Transcendent = true }

local Index = {}

function Index.roster(worldId: number): { Entry }
	local world = Worlds.get(worldId)
	local out: { Entry } = {}
	if not world then
		return out
	end
	for _, pair in { { world.enemies, false }, { world.bosses, true } } do
		local list: { Entry } = {}
		for id, def in pair[1] :: { [string]: WorldTypes.EnemyDef } do
			if not def.secret then
				table.insert(list, { id = id, def = def, worldId = worldId, isBoss = pair[2] :: boolean })
			end
		end
		table.sort(list, function(a, b)
			return if a.def.hp == b.def.hp then a.id < b.id else a.def.hp < b.def.hp
		end)
		for _, e in list do
			table.insert(out, e)
		end
	end
	return out
end

-- Every world's roster, in world order.
function Index.all(): { Entry }
	local out: { Entry } = {}
	for _, worldId in Worlds.Order do
		for _, e in Index.roster(worldId) do
			table.insert(out, e)
		end
	end
	return out
end

function Index.isSecret(enemyId: string): boolean
	local def = Worlds.enemyDefs()[enemyId]
	return def ~= nil and def.secret == true
end

function Index.dropsOf(enemyId: string): { WorldTypes.DropDef }
	local def = Worlds.enemyDefs()[enemyId]
	local out = table.clone(def and def.drops or {})
	table.sort(out, function(a, b)
		return a.chance > b.chance
	end)
	return out
end

function Index.sourcesOf(weaponId: string): { Source }
	local out: { Source } = {}
	for _, e in Index.all() do
		for _, drop in e.def.drops or {} do
			if drop.weapon == weaponId then
				table.insert(out, { enemy = e.id, chance = drop.chance })
			end
		end
	end
	table.sort(out, function(a, b)
		return a.chance > b.chance
	end)
	return out
end

function Index.percent(chance: number): string
	local p = chance * 100
	return if p >= 10 or p == math.floor(p) then ("%d%%"):format(math.floor(p + 0.5)) else ("%.1f%%"):format(p)
end

-- low to high rarity, then low to high defense, like the weapons
function Index.armorOf(worldId: number): { Armor.ArmorDef }
	local out: { Armor.ArmorDef } = {}
	for _, def in Armor.list() do
		if def.world == worldId then
			table.insert(out, def)
		end
	end
	table.sort(out, function(a, b)
		local ra, rb = Index.rarityRank(a.rarity), Index.rarityRank(b.rarity)
		if ra ~= rb then
			return ra < rb
		end
		if a.defense ~= b.defense then
			return a.defense < b.defense
		end
		return a.id < b.id
	end)
	return out
end

function Index.materialSource(materialId: string): MaterialSource?
	local mat = Materials.get(materialId) :: any
	if not mat then
		return nil
	end
	if mat.quest then
		local line = Quests.lines[mat.source]
		return { name = if line and line.npc then line.npc.short else mat.source, quest = true }
	end
	if mat.fished then
		local spot = Fishing.spot(mat.source)
		return if spot then { name = spot.name, chance = Fishing.chanceAt(spot, materialId), quest = false } else nil
	end
	if mat.gathered then
		local node = Gathering.get(mat.source)
		for _, drop in (node and node.drops or {}) :: { any } do
			if drop.id == materialId then
				return { name = (node :: any).name, chance = drop.chance, quest = false }
			end
		end
		return nil
	end
	local enemy = Worlds.enemyDefs()[mat.source]
	for _, drop in (enemy and enemy.materials or {}) :: { any } do
		if drop.id == materialId then
			return { name = (enemy :: any).name, chance = drop.chance, quest = false }
		end
	end
	return nil
end

function Index.weaponCounts(def: any): boolean
	return def ~= nil and not def.unarmed and def.world ~= nil and not UNLISTED_RARITIES[def.rarity or ""]
end

-- a rarity's place in Weapons.Rarities (Common 1 ... Transcendent 9)
local rank: { [string]: number } = {}
for i, name in Weapons.Rarities do
	rank[name] = i
end
function Index.rarityRank(rarity: string?): number
	return rank[rarity or "Common"] or 0
end

-- low to high rarity, then low to high damage (user, 2026-10-13)
function Index.weaponsOf(worldId: number): { any }
	local out = {}
	for _, def in Weapons.list() do
		if def.world == worldId and Index.weaponCounts(def) then
			table.insert(out, def)
		end
	end
	table.sort(out, function(a, b)
		local ra, rb = Index.rarityRank(a.rarity), Index.rarityRank(b.rarity)
		if ra ~= rb then
			return ra < rb
		end
		if (a.damage or 0) ~= (b.damage or 0) then
			return (a.damage or 0) < (b.damage or 0)
		end
		return a.id < b.id
	end)
	return out
end

function Index.weaponSources(weaponId: string): { WeaponSource }
	local out: { WeaponSource } = {}
	for _, source in Index.sourcesOf(weaponId) do
		table.insert(out, { enemy = source.enemy, chance = source.chance })
	end
	for _, lineId in Quests.order do
		local line = Quests.lines[lineId]
		for _, step in (line and line.steps or {}) :: { any } do
			if step.reward and step.reward.weapon == weaponId then
				table.insert(out, { quest = lineId })
			end
		end
	end
	return out
end


-- ==================== the whole book (2026-10-20) ====================

Index.Sections = { "Creatures", "Weapons", "Armor", "Tools", "Materials", "Fish", "Potions", "Treasures" }

export type Progress = {
	kills: { [string]: number },
	weapons: { [string]: boolean },
	armor: { [string]: boolean },
	items: { [string]: number },
}

-- The world whose page lists a potion: its own `world` (Tiers I and II), Tier III the first
-- world of its band. nil when it can't be made yet (no recipe).
function Index.potionWorld(def: any): number?
	if not (def and def.recipe) then
		return nil
	end
	if def.world then
		return def.world
	end
	local band = Potions.Bands[def.tier]
	return band and band.from
end

local function byOrder(a: any, b: any): boolean
	if (a.order or 0) ~= (b.order or 0) then
		return (a.order or 0) < (b.order or 0)
	end
	return a.id < b.id
end

local kindRank: { [string]: number } = {}
for i, kind in Tools.Kinds do
	kindRank[kind] = i
end

function Index.entries(worldId: number, section: string): { any }
	local out = {}
	if section == "Creatures" then
		return Index.roster(worldId)
	elseif section == "Weapons" then
		return Index.weaponsOf(worldId)
	elseif section == "Armor" then
		return Index.armorOf(worldId)
	elseif section == "Tools" then
		for _, def in Tools.Defs do
			if def.world == worldId then
				table.insert(out, def)
			end
		end
		table.sort(out, function(a, b)
			if a.tier ~= b.tier then
				return a.tier < b.tier
			end
			return (kindRank[a.kind] or 0) < (kindRank[b.kind] or 0)
		end)
	elseif section == "Potions" then
		for _, def in Potions.list() do
			if Index.potionWorld(def) == worldId then
				table.insert(out, def)
			end
		end
	else
		local drops, gathered = {}, {}
		for _, def in Materials.list() do
			local m = def :: any
			if m.world ~= worldId or m.core then
				continue
			end
			if section == "Treasures" and m.quest then
				table.insert(out, m)
			elseif section == "Fish" and m.fished then
				table.insert(out, m)
			elseif section == "Materials" and not (m.quest or m.fished) then
				table.insert(if m.gathered then gathered else drops, m)
			end
		end
		table.sort(out, byOrder)
		if section == "Materials" then
			table.sort(drops, byOrder)
			table.sort(gathered, byOrder)
			table.move(gathered, 1, #gathered, #drops + 1, drops)
			return drops
		end
	end
	return out
end

-- A tool, material or potion by id: the "items" the Index counts (cores are materials
-- too, but never listed).
function Index.itemDef(id: string): any
	return Tools.get(id) or Materials.get(id) or Potions.get(id)
end

-- Which section an item is listed in ("Tools", "Materials", "Fish", "Potions",
-- "Treasures"), or nil for a core or anything the book doesn't list.
function Index.sectionOf(id: string): string?
	if Tools.get(id) then
		return "Tools"
	elseif Potions.get(id) then
		return if Index.potionWorld(Potions.get(id)) then "Potions" else nil
	end
	local m = Materials.get(id) :: any
	if not m or m.core then
		return nil
	end
	return if m.quest then "Treasures" elseif m.fished then "Fish" else "Materials"
end

function Index.found(section: string, id: string, progress: Progress): boolean
	if section == "Creatures" then
		return progress.kills[id] ~= nil
	elseif section == "Weapons" then
		return progress.weapons[id] == true
	elseif section == "Armor" then
		return progress.armor[id] == true
	end
	return (progress.items[id] or 0) > 0
end

export type WorldProgress = { found: number, total: number, sections: { [string]: { found: number, total: number } } }

function Index.progress(worldId: number, progress: Progress): WorldProgress
	local out: WorldProgress = { found = 0, total = 0, sections = {} }
	for _, section in Index.Sections do
		local found, total = 0, 0
		for _, entry in Index.entries(worldId, section) do
			total += 1
			if Index.found(section, entry.id, progress) then
				found += 1
			end
		end
		out.sections[section] = { found = found, total = total }
		out.found += found
		out.total += total
	end
	return out
end

-- Parse the player's Index attributes (IndexService publishes them; either side).
function Index.progressOf(player: Player): Progress
	local function counts(name: string): { [string]: number }
		local out: { [string]: number } = {}
		local raw = player:GetAttribute(name)
		if type(raw) == "string" then
			for id, n in raw:gmatch("([^,=]+)=(%d+)") do
				out[id] = tonumber(n) :: number
			end
		end
		return out
	end
	local function set(name: string): { [string]: boolean }
		local out: { [string]: boolean } = {}
		local raw = player:GetAttribute(name)
		if type(raw) == "string" then
			for id in raw:gmatch("[^,]+") do
				out[id] = true
			end
		end
		return out
	end
	return { kills = counts("IndexKills"), weapons = set("IndexWeapons"), armor = set("IndexArmor"), items = counts("IndexItems") }
end

-- ---------- titles ----------

-- Each world's two titles (the names are placeholders the user can change). A world
-- with no row gets "World N Collector" / "World N Completionist".
Index.TitleNames = {
	[1] = { collector = "Meadows Collector", completionist = "World 1 Completionist" },
	[2] = { collector = "Redwood Collector", completionist = "World 2 Completionist" },
	[3] = { collector = "Caverns Collector", completionist = "World 3 Completionist" },
} :: { [number]: { collector: string, completionist: string } }

export type Title = { id: string, name: string, world: number, secret: boolean }

-- "Collector1" / "Completionist1"
function Index.titleOf(id: any): Title?
	if type(id) ~= "string" then
		return nil
	end
	local kind, n = id:match("^(%a+)(%d+)$")
	local world = tonumber(n)
	if not (world and Worlds.get(world)) or (kind ~= "Collector" and kind ~= "Completionist") then
		return nil
	end
	local names = Index.TitleNames[world]
	local secret = kind == "Completionist"
	local name = if names then (if secret then names.completionist else names.collector) else ("World %d %s"):format(world, kind)
	return { id = id, name = name, world = world, secret = secret }
end

function Index.titlesOf(worldId: number): (Title, Title)
	return Index.titleOf("Collector" .. worldId) :: Title, Index.titleOf("Completionist" .. worldId) :: Title
end

-- The world's secret part of the Completionist title: its core infused into the
-- Worldheart Blade (which needs the core found first). A world with no core yet has
-- nothing secret to do.
function Index.coreDone(player: Player, worldId: number): boolean
	local core = Infuse.coreOfWorld(worldId)
	return core == nil or Infuse.infused(player)[core] == true
end

return Index
