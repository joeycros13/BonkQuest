--!strict
-- Leveling: the EXP curve, shared by ExpService (server) and the HUD's EXP bar.
--
-- A player has one number, their total EXP ("ExpTotal" attribute). Their
-- level and how far into it they are follow from it:
--   need(level)        EXP to go from `level` to `level + 1`
--   fromTotal(total)   level, EXP into that level, EXP that level needs
-- Players start at level 1 (the badge on the player card). Placeholder curve:
-- 100 to reach level 2, then 50 more for each level after.
--   maxHealth(level)   the player's max HP at that level (ExpService applies it)

local Leveling = {}

Leveling.START = 1
Leveling.FIRST = 100
Leveling.STEP = 50

function Leveling.need(level: number): number
	return Leveling.FIRST + Leveling.STEP * (level - Leveling.START)
end

-- Max health (user, 2026-10-11): 100 at level 1, and every level up adds 10.
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
