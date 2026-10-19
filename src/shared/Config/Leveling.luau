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

local Leveling = {}

Leveling.START = 1
Leveling.FIRST = 30
Leveling.STEP = 15

function Leveling.need(level: number): number
	return Leveling.FIRST + Leveling.STEP * (level - Leveling.START)
end

-- Max health: 100 at level 1, and every level up adds 10 (the user, 2026-10-19; it
-- was 15 for a day). With the quicker curve that's still more HP at each point of a
-- world than the old one gave.
Leveling.BASE_HEALTH = 100
Leveling.HEALTH_PER_LEVEL = 10

function Leveling.maxHealth(level: number): number
	return Leveling.BASE_HEALTH + Leveling.HEALTH_PER_LEVEL * (math.max(level, Leveling.START) - Leveling.START)
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
