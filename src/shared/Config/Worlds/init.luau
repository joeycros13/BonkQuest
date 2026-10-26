--!strict
-- Worlds: the registry of every world in the game, collected from the per-world
-- files beside this one. Each world owns its enemy and boss roster; Enemies.luau
-- is a flat view over all of them.
--
-- To add a world: drop in a WNN_Name.luau file and add one line to FILES below.
-- Nothing else in the codebase needs to change.
--
-- Pure data plus lookups; no side effects and no instance access.

local WorldTypes = require(script.Parent.WorldTypes)

export type EnemyDef = WorldTypes.EnemyDef
export type WorldDef = WorldTypes.WorldDef

-- Listed explicitly rather than discovered by iterating children: the order is
-- deterministic, a typo fails loudly at load, and the type checker can see it.
local FILES: { WorldDef } = {
	require(script.W01_SunnyMeadows),
	require(script.W02_RedwoodForest),
	require(script.W03_CrystalCaverns),
	require(script.W04_ScorchingSands),
}

local Worlds = {}

Worlds.Defs = {} :: { [number]: WorldDef }
Worlds.Order = {} :: { number }

for _, def in FILES do
	if Worlds.Defs[def.id] then
		warn(("[Worlds] duplicate world id %d (%s); keeping the first"):format(def.id, def.name))
	else
		Worlds.Defs[def.id] = def
		table.insert(Worlds.Order, def.id)
	end
end
table.sort(Worlds.Order)

-- Flat archetype lookup across every world, built once. Enemies and bosses share
-- one namespace because everything downstream (WorldEnemyService, MeleeService,
-- the Index, quests) resolves an archetype by bare id.
local flatDefs: { [string]: EnemyDef } = {}
local ownerOf: { [string]: number } = {}

for _, id in Worlds.Order do
	local world = Worlds.Defs[id]
	for _, roster in { world.enemies, world.bosses } do
		for enemyId, def in roster do
			if flatDefs[enemyId] then
				warn(
					("[Worlds] %s is defined in more than one world (%d and %d); an enemy should belong to exactly one"):format(
						enemyId,
						ownerOf[enemyId],
						id
					)
				)
			else
				flatDefs[enemyId] = def
				ownerOf[enemyId] = id
			end
		end
	end
end

function Worlds.get(id: number): WorldDef?
	return Worlds.Defs[id]
end

-- Look a world up by its Workspace.Worlds folder name.
function Worlds.byFolder(folder: string): WorldDef?
	for _, id in Worlds.Order do
		local world = Worlds.Defs[id]
		if world.folder == folder then
			return world
		end
	end
	return nil
end

-- Every enemy and boss in the game, keyed by id.
function Worlds.enemyDefs(): { [string]: EnemyDef }
	return flatDefs
end

return Worlds
