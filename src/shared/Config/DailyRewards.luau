--!strict
-- DailyRewards: the Daily Rewards stand in World 1's hub and its promo codes (2026-10-19,
-- the user's design; the panel is option A "week row" on
-- https://claude.ai/artifact/FNn8enN7mGMHDjrBX3GWDf).
--   One claim a day. Days flip at 00:00 UTC, the same moment as the daily leaderboards.
--   Claiming on the next day climbs the 7-day Ladder; missing a day starts it again at
--   day 1, and after day 7 it starts again at day 1.
--   Coins scale with the player's highest world, like the coin bundles (Shop.WorldScale);
--   potions come at the tier of the player's world band (Potions.tierAt); materials are
--   the highest world's enemy materials (never cores, quest items or gathered ones).
--   Never weapons or upgrade levels (the leaderboard rewards' rule).
--   Codes: type one at the stand for a one-time reward. Edit Codes below to add or retire
--   one; `expires` (optional) is a UTC time (os.time-style seconds) after which it stops.
-- Amounts are placeholders to tune.

local DailyRewards = {}

DailyRewards.DAY = 86400

export type Reward = {
	coins: number?,
	exp: number?,
	potions: { { kind: string, count: number } }?,
	boosts: { { id: string, minutes: number } }?,
	materials: number?,
}
export type Day = {
	coins: number?,
	exp: number?,
	potions: { { kind: string, count: number } }?,
	boosts: { { id: string, minutes: number } }?,
	materials: number?,
	icon: string, -- a DailyRewards.Icons key, or "Potion" (the first potion's own icon)
	big: boolean?, -- the wide last tile
}

-- Icons: the coin stack, the potions' own icons (Config/Potions, at the player's tier),
-- the shop's coin-boost potion, the Oak Log and the shop's coin chest.
DailyRewards.Icons = {
	Coins = "rbxassetid://114082700684383",
	BoostCoins = "rbxassetid://71275351764138",
	Materials = "rbxassetid://104043389166635",
	Chest = "rbxassetid://113481215581201",
}

DailyRewards.Ladder = {
	{ coins = 250, icon = "Coins" },
	{ potions = { { kind = "Health", count = 2 } }, icon = "Potion" },
	{ coins = 500, icon = "Coins" },
	{ boosts = { { id = "Coins", minutes = 15 } }, icon = "BoostCoins" },
	{ materials = 5, icon = "Materials" },
	{ potions = { { kind = "Strength", count = 2 } }, icon = "Potion" },
	{ coins = 2500, boosts = { { id = "Luck", minutes = 30 } }, icon = "Chest", big = true },
} :: { Day }

DailyRewards.Codes = {
	BONKQUEST = { reward = { coins = 500 } },
	FIRSTBONK = { reward = { coins = 250, potions = { { kind = "Health", count = 3 } } } },
} :: { [string]: { reward: Reward, expires: number? } }

-- Every word the panel and its messages show.
DailyRewards.Text = {
	title = "DAILY REWARDS",
	streak = "%d day streak",
	streakNone = "No streak yet",
	hint = "Come back every day! Miss one and you start at Day 1.",
	day = "DAY %d",
	today = "TODAY",
	claim = "CLAIM DAY %d!",
	claimed = "COME BACK TOMORROW",
	nextIn = "Next reward in %s",
	codeLabel = "Have a code?",
	codeHint = "Enter code",
	redeem = "REDEEM",
	coins = "%s Coins",
	exp = "%s EXP",
	potion = "%d %s Potions",
	potionOne = "1 %s Potion",
	boost = "2x %s %d min",
	materials = "%d of each Material",
	chest = "BIG CHEST",
	-- results
	claimedMessage = "You got %s!",
	codeOk = "Code redeemed: %s",
	codeUsed = "You already used that code.",
	codeUnknown = "That code doesn't exist.",
	codeExpired = "That code has expired.",
	codeEmpty = "Type a code first.",
	away = "Stand at the Daily Rewards stand.",
	busy = "One moment...",
}

function DailyRewards.dayOf(t: number): number
	return math.floor(t / DailyRewards.DAY)
end

function DailyRewards.resetsAt(t: number): number
	return (DailyRewards.dayOf(t) + 1) * DailyRewards.DAY
end

-- Where a player stands on the ladder, from their save (`streak` = days claimed in a row
-- in the current week of the ladder, 0..7; `lastDay` = the UTC day of the last claim) and
-- today's day number:
--   ready    whether today's reward can be claimed
--   claimed  how many of this week's tiles show as claimed
--   next     the ladder day the next claim gives (today's if ready, else tomorrow's)
function DailyRewards.status(streak: number, lastDay: number?, today: number): (boolean, number, number)
	local n = #DailyRewards.Ladder
	if lastDay == today then
		return false, streak, (streak % n) + 1
	elseif lastDay == today - 1 and streak < n then
		return true, streak, streak + 1
	end
	-- never claimed, a missed day, or the week finished yesterday: a new week starts
	return true, 0, 1
end

-- A code as typed: no spaces, upper case.
function DailyRewards.normalise(code: any): string
	if type(code) ~= "string" then
		return ""
	end
	return (string.upper((code:gsub("%s+", ""))))
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	while true do
		local swapped, count = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		s = swapped
		if count == 0 then
			return s
		end
	end
end

-- The coins a reward gives a player whose highest world is `world`.
function DailyRewards.coinsFor(reward: Reward, world: number, scale: { number }): number
	if not reward.coins then
		return 0
	end
	return reward.coins * (scale[math.clamp(world, 1, #scale)] or 1)
end

-- A reward as words, for the tiles and the result message.
function DailyRewards.describe(reward: Reward, coins: number?): { string }
	local t = DailyRewards.Text
	local out = {}
	if reward.coins then
		table.insert(out, t.coins:format(commas(coins or reward.coins)))
	end
	if reward.exp then
		table.insert(out, t.exp:format(commas(reward.exp)))
	end
	for _, p in reward.potions or {} do
		table.insert(out, if p.count == 1 then t.potionOne:format(p.kind) else t.potion:format(p.count, p.kind))
	end
	for _, b in reward.boosts or {} do
		table.insert(out, t.boost:format(b.id, b.minutes))
	end
	if reward.materials then
		table.insert(out, t.materials:format(reward.materials))
	end
	return out
end

return DailyRewards
