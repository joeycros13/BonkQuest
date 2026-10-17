--!strict
-- Format: how numbers read on the HUD. Every count the player sees (coins,
-- EXP, health, rewards) gets thousands separators, like the shop's prices
-- (user's request, 2026-10-11): 12500 -> "12,500".

local Format = {}

-- Whole numbers with commas; rounds to the nearest whole first.
function Format.commas(n: number): string
	local whole = math.floor(n + 0.5)
	local sign = if whole < 0 then "-" else ""
	local digits = tostring(math.abs(whole))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return sign .. (grouped:gsub("^,", ""))
end

-- "x / y" for bars, both with commas.
function Format.ratio(x: number, y: number): string
	return Format.commas(x) .. " / " .. Format.commas(y)
end

function Format.init() end
function Format.start() end

return Format
