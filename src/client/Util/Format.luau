--!strict
-- Format: how numbers read on the HUD. Every count the player sees (coins,
-- EXP, health, rewards) gets thousands separators, like the shop's prices
-- (user's request, 2026-10-11): 12500 -> "12,500". Coins use Format.coins,
-- which shortens a million and up.

local Format = {}

-- Whole numbers with commas; rounds to the nearest whole first.
function Format.commas(n: number): string
	local whole = math.floor(n + 0.5)
	local sign = if whole < 0 then "-" else ""
	local digits = tostring(math.abs(whole))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return sign .. (grouped:gsub("^,", ""))
end

-- Coin amounts (user, 2026-10-19): in full with commas up to 999,999, then
-- shortened to one decimal: 1,100,000 -> "1.1M", 1,500,000,000 -> "1.5B".
-- Rounded down, so a balance never reads more than the player has, and a
-- trailing ".0" is dropped ("1M", not "1.0M").
local SUFFIXES = { "M", "B", "T", "Qa", "Qi" }

function Format.coins(n: number): string
	local whole = math.floor(n + 0.5)
	local size = math.abs(whole)
	if size < 1e6 then
		return Format.commas(whole)
	end
	local sign = if whole < 0 then "-" else ""
	local index = math.floor(math.log10(size) / 3) - 1
	-- log10 can land a hair under a whole power of ten
	if index < #SUFFIXES and size >= 10 ^ (index * 3 + 6) then
		index += 1
	end
	index = math.clamp(index, 1, #SUFFIXES)
	local tenths = math.floor(size / 10 ^ (index * 3 + 3) * 10)
	local text = if tenths % 10 == 0 then Format.commas(tenths // 10) else ("%d.%d"):format(tenths // 10, tenths % 10)
	return sign .. text .. SUFFIXES[index]
end

-- "x / y" for bars, both with commas.
function Format.ratio(x: number, y: number): string
	return Format.commas(x) .. " / " .. Format.commas(y)
end

function Format.init() end
function Format.start() end

return Format
