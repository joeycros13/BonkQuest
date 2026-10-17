--!strict
-- Enemies: flat archetype lookup across every world. Bosses live in the same
-- namespace.
--
-- The data itself lives in Config/Worlds/<world>.luau, one file per world,
-- because an enemy type belongs to exactly one world.

local Worlds = require(script.Parent.Worlds)
local WorldTypes = require(script.Parent.WorldTypes)

export type EnemyDef = WorldTypes.EnemyDef

local Enemies = {}

Enemies.Defs = Worlds.enemyDefs()

function Enemies.get(id: string): EnemyDef?
	return Enemies.Defs[id]
end

return Enemies
