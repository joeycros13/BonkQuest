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
-- Drop tables themselves live on each enemy in Config/Worlds/<world>.

local Worlds = require(script.Parent.Worlds)
local Armor = require(script.Parent.Armor)
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

return Index
