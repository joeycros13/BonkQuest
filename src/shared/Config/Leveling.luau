--!strict
-- Leveling: the EXP curve, shared by ExpService (server) and the HUD's EXP bar.
--
-- A player has one number, their total EXP ("ExpTotal" attribute). Their
-- level and how far into it they are follow from it:
--   need(level)        EXP to go from `level` to `level + 1`
--   fromTotal(total)   level, EXP into that level, EXP that level needs
-- Players start at level 1 (the badge on the player card). The curve (2026-10-19,
-- the user: levelling should be much quicker, early HP being scarce): 30 to reach
-- level 2, then 15 more for each level after. It replaced 100 + 50 per level; every
-- level requirement (armour, gates, quest steps) moved to the level that needs the
-- same total EXP, so they still come at the same point in a world.
--   maxHealth(level)   the player's max HP at that level (ExpService applies it)
--   scaleAt(level)     the world scale a level is at (below)
--
-- World scale (2026-10-23, the user: World 1's numbers near 100, World 2's 1K, World 3's 10K, up to
-- 100M in World 7). The shape of each world is balanced with art/tools/balance/world_sim.py; on top
-- of it every world is multiplied by its scale:
--   SCALE[world]       x1, x4, x16, x64... : enemy damage, armour health, kill and quest EXP, and
--                      here the player's health and the EXP a level needs, from the level of the
--                      gate into that world (Config/Gates) on (scaleAt)
--   2 x SCALE[world]   x2, x8, x32...      : weapon damage, enemy health, tool power, node health
--                      (World 1's too, so its best weapons hit near 100), the Worldheart tiers
-- Both sides of every fight grow alike, so a world plays as before; with the worlds' own growth
-- (about x2.7 a world) that makes about x10 a world. Coins already grew x10 a world (the gates:
-- 2,500, 25,000), so they're unscaled; the coin bundles and the Upgrades stand go x10 a world.

local Gates = require(script.Parent.Gates)

local Leveling = {}

Leveling.SCALE = { 1, 4, 16, 64, 256, 1024, 4096, 16384 }

-- The scale of the world a level belongs to: a level at or past a gate's level is in that gate's
-- world, whether or not the gate is bought yet (it can't be bought before).
function Leveling.scaleAt(level: number): number
	local world = 1
	for _, gate in Gates.list do
		if level >= gate.level and gate.world > world then
			world = gate.world
		end
	end
	return Leveling.SCALE[math.min(world, #Leveling.SCALE)]
end

Leveling.START = 1
Leveling.FIRST = 30
Leveling.STEP = 15

function Leveling.need(level: number): number
	return (Leveling.FIRST + Leveling.STEP * (level - Leveling.START)) * Leveling.scaleAt(level)
end

-- Max health: 100 at level 1, and every level up adds 10 (the user, 2026-10-19; it
-- was 15 for a day). With the quicker curve that's still more HP at each point of a
-- world than the old one gave. Times the world scale (scaleAt) since 2026-10-23.
Leveling.BASE_HEALTH = 100
Leveling.HEALTH_PER_LEVEL = 10

function Leveling.maxHealth(level: number): number
	local l = math.max(level, Leveling.START)
	return (Leveling.BASE_HEALTH + Leveling.HEALTH_PER_LEVEL * (l - Leveling.START)) * Leveling.scaleAt(l)
end

function Leveling.fromTotal(total: number): (number, number, number)
	local level = Leveling.START
	local left = math.max(0, total)
	while left >= Leveling.need(level) do
		left -= Leveling.need(level)
		level += 1
	end
	return level, left, Leveling.need(level)
end

return Leveling
