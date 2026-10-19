--!strict
-- LeaderboardService: the 9 leaderboards (Config/Leaderboards; 2026-10-19, the
-- user's design): coins earned, levels gained and kills, each daily, weekly and
-- all-time.
--
-- Counting (per player, saved as the "leaderboard" section of PlayerDataService):
--   coins earned   CoinService.onEarned (kills, quests...; not Robux bundles or admin)
--   levels gained  ExpService.onLevelUp, once the player's save has loaded
--   kills          WorldEnemyService.onDefeated (every enemy, boss and secret enemy)
-- Each player keeps this day's and this week's totals with the period they belong to
-- (a new day starts them at 0), lifetime coins and kills, the chat tag a reward gave
-- them and its expiry, and their trophies.
--
-- Boards: each is an OrderedDataStore (Leaderboards.storeName, one per period key).
-- Every WRITE_EVERY seconds a server writes its players' changed scores, and every
-- READ_EVERY it reads each current board's top 50 into a cache that
-- Remotes.GetLeaderboard(stat, period) answers from. All-time levels rank by total EXP.
-- Without DataStores (an unpublished place, Studio) the boards are this server's own
-- players, kept in memory, so the panel still works for testing.
--
-- Rewards: a board that has ended (a new day or week) is claimed by one server through
-- the "LBRewards" store (UpdateAsync: the first server to mark it pays it), which reads
-- its top 10 and posts each player's tier to their mailbox ("LBMailbox", u_<UserId>).
-- A player's mailbox is opened when they join (and checked every READ_EVERY): each
-- entry is granted (coins, EXP, potions, boosts, materials, chat tag, trophy) and a
-- chat message says what they won (Remotes.LeaderboardReward). Without DataStores,
-- the admin "lbReset" action pays a period's rewards straight from the in-memory boards.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Leaderboards = require(Config:WaitForChild("Leaderboards"))
local Potions = require(Config:WaitForChild("Potions"))
local Materials = require(Config:WaitForChild("Materials"))
local Leveling = require(Config:WaitForChild("Leveling"))

local LeaderboardService = {}

type Counts = { Coins: number, Levels: number, Kills: number }
type State = {
	day: number,
	week: number,
	daily: Counts,
	weekly: Counts,
	lifetime: { Coins: number, Kills: number },
	tag: string?,
	tagUntil: number?,
	trophies: { [string]: number },
	dirty: boolean,
}
type Row = { rank: number, userId: number, name: string, value: number }

local deps: any = nil
local states: { [Player]: State } = {}
local cache: { [string]: { Row } } = {} -- store name -> top rows
local names: { [number]: string } = {}
local storesOk = true -- false once a DataStore call says they're unavailable
local rewardRemote: RemoteEvent? = nil

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function zero(): Counts
	return { Coins = 0, Levels = 0, Kills = 0 }
end

local function fresh(): State
	local t = now()
	return {
		day = Leaderboards.dayOf(t),
		week = Leaderboards.weekOf(t),
		daily = zero(),
		weekly = zero(),
		lifetime = { Coins = 0, Kills = 0 },
		trophies = {},
		dirty = false,
	}
end

local function stateOf(player: Player): State
	local s = states[player]
	if not s then
		s = fresh()
		states[player] = s
	end
	-- a new day or week starts its counts again
	local t = now()
	local day, week = Leaderboards.dayOf(t), Leaderboards.weekOf(t)
	if s.day ~= day then
		s.day, s.daily = day, zero()
	end
	if s.week ~= week then
		s.week, s.weekly = week, zero()
	end
	return s
end

local function publishTag(player: Player, s: State)
	local live = s.tag ~= nil and (s.tagUntil or 0) > now()
	player:SetAttribute("LeaderTag", if live then s.tag else nil)
end

local function bump(player: Player, stat: string, amount: number)
	local s = stateOf(player)
	s.daily[stat] += amount
	s.weekly[stat] += amount
	if stat ~= "Levels" then
		s.lifetime[stat] += amount
	end
	s.dirty = true
end

-- A player's score on a board.
local function scoreOf(player: Player, stat: string, period: string): number
	local s = stateOf(player)
	if period == "Daily" then
		return s.daily[stat]
	elseif period == "Weekly" then
		return s.weekly[stat]
	elseif stat == "Levels" then
		return deps.Services.ExpService.get(player)
	end
	return s.lifetime[stat]
end

local function storeFor(stat: string, period: string, t: number): (string, OrderedDataStore?)
	local name = Leaderboards.storeName(stat, period, Leaderboards.periodKey(period, t))
	if not storesOk then
		return name, nil
	end
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	if not ok then
		storesOk = false
		return name, nil
	end
	return name, store
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	local name = if player then player.Name else nil
	if not name then
		local ok, result = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		name = if ok and type(result) == "string" then result else ("Player " .. userId)
	end
	names[userId] = name :: string
	return name :: string
end

-- The board straight from this server's players (no DataStores).
local function localBoard(stat: string, period: string): { Row }
	local rows = {}
	for _, player in Players:GetPlayers() do
		local value = scoreOf(player, stat, period)
		if value > 0 then
			table.insert(rows, { rank = 0, userId = player.UserId, name = player.Name, value = value })
		end
	end
	table.sort(rows, function(a, b)
		return a.value > b.value
	end)
	for i, row in rows do
		row.rank = i
	end
	return rows
end

local function readBoard(stat: string, period: string, t: number): { Row }?
	local _, store = storeFor(stat, period, t)
	if not store then
		return nil
	end
	local ok, pages = pcall(function()
		return (store :: OrderedDataStore):GetSortedAsync(false, Leaderboards.TOP)
	end)
	if not ok then
		storesOk = false
		return nil
	end
	local rows = {}
	for i, entry in (pages :: DataStorePages):GetCurrentPage() do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(rows, { rank = i, userId = userId, name = nameOf(userId), value = entry.value })
		end
	end
	return rows
end

local function writeScores()
	if not storesOk then
		return
	end
	local t = now()
	for player, s in states do
		if not s.dirty then
			continue
		end
		s.dirty = false
		for _, stat in Leaderboards.Stats do
			for _, period in Leaderboards.Periods do
				local value = math.floor(scoreOf(player, stat, period))
				local _, store = storeFor(stat, period, t)
				if store and value > 0 then
					local ok = pcall(function()
						(store :: OrderedDataStore):SetAsync(tostring(player.UserId), value)
					end)
					if not ok then
						storesOk = false
						return
					end
				end
			end
		end
	end
end

local function refreshCache()
	local t = now()
	for _, stat in Leaderboards.Stats do
		for _, period in Leaderboards.Periods do
			local name = Leaderboards.storeName(stat, period, Leaderboards.periodKey(period, t))
			cache[name] = readBoard(stat, period, t) or cache[name] or {}
		end
	end
end

-- ===== rewards =====

local function grant(player: Player, period: string, stat: string, rank: number, tier: Leaderboards.Tier)
	local reward = tier.reward
	local s = stateOf(player)
	local services = deps.Services
	if reward.coins then
		services.CoinService.add(player, reward.coins, "reward")
	end
	if reward.exp then
		services.ExpService.add(player, reward.exp)
	end
	local world = math.max(1, (player:GetAttribute("HighestWorld") :: number?) or 1)
	local band = Potions.tierAt(world) or 1
	for _, p in reward.potions or {} do
		services.PotionService.add(player, p.kind .. band, p.count)
	end
	for _, b in reward.boosts or {} do
		services.ShopService.addBoost(player, b.id, b.minutes * 60)
	end
	if reward.materials then
		for _, mat in Materials.list() do
			if (mat :: any).world == world and not (mat :: any).core and not (mat :: any).quest and not (mat :: any).gathered then
				services.MaterialService.add(player, mat.id, reward.materials)
			end
		end
	end
	if reward.tag then
		s.tag = reward.tag:format(Leaderboards.Text.statShort[stat] or stat)
		s.tagUntil = Leaderboards.resetsAt(period, now())
		publishTag(player, s)
	end
	if reward.trophy then
		s.trophies[reward.trophy] = (s.trophies[reward.trophy] or 0) + 1
	end
	s.dirty = true
	if rewardRemote then
		local t = Leaderboards.Text
		rewardRemote:FireClient(player, {
			text = t.won:format(tier.label, t.period[period], t.stat[stat], table.concat(Leaderboards.describe(reward), ", ")),
			rank = rank,
		})
	end
end

local mailbox: DataStore? = nil
local paid: DataStore? = nil

local function openMailbox(player: Player)
	if not (storesOk and mailbox) then
		return
	end
	local entries = {}
	local ok = pcall(function()
		(mailbox :: DataStore):UpdateAsync("u_" .. player.UserId, function(old)
			entries = if type(old) == "table" then old else {}
			return {}
		end)
	end)
	if not ok then
		return
	end
	for _, entry in entries do
		local tier = Leaderboards.tierFor(entry.period, entry.rank)
		if tier then
			grant(player, entry.period, entry.stat, entry.rank, tier)
		end
	end
end

-- Pay the boards of a period that has ended (key = the old period's key), once.
local function payPeriod(period: string, key: string)
	if not (storesOk and paid and mailbox) then
		return
	end
	local mine = false
	pcall(function()
		(paid :: DataStore):UpdateAsync(period .. "_" .. key, function(old)
			if old then
				return nil -- another server paid it
			end
			mine = true
			return true
		end)
	end)
	if not mine then
		return
	end
	for _, stat in Leaderboards.Stats do
		local name = Leaderboards.storeName(stat, period, key)
		local ok, pages = pcall(function()
			return DataStoreService:GetOrderedDataStore(name):GetSortedAsync(false, 10)
		end)
		if ok then
			for rank, entry in (pages :: DataStorePages):GetCurrentPage() do
				pcall(function()
					(mailbox :: DataStore):UpdateAsync("u_" .. entry.key, function(old)
						local list = if type(old) == "table" then old else {}
						table.insert(list, { period = period, stat = stat, rank = rank })
						return list
					end)
				end)
			end
		end
	end
end

-- Without DataStores: pay a period straight from this server's boards (admin "lbReset").
function LeaderboardService.payLocal(period: string): number
	local paidCount = 0
	for _, stat in Leaderboards.Stats do
		for _, row in localBoard(stat, period) do
			local tier = Leaderboards.tierFor(period, row.rank)
			local player = Players:GetPlayerByUserId(row.userId)
			if tier and player then
				grant(player, period, stat, row.rank, tier)
				paidCount += 1
			end
		end
	end
	return paidCount
end

-- ===== the remote =====

function LeaderboardService.board(player: Player, stat: any, period: any): any
	if not (table.find(Leaderboards.Stats, stat) and table.find(Leaderboards.Periods, period)) then
		return nil
	end
	local t = now()
	local rows = if storesOk then (cache[Leaderboards.storeName(stat, period, Leaderboards.periodKey(period, t))] or {}) else localBoard(stat, period)
	local you: any = { value = scoreOf(player, stat, period) }
	for _, row in rows do
		if row.userId == player.UserId then
			you.rank = row.rank
			break
		end
	end
	local shown = {}
	for _, row in rows do
		local value = row.value
		if stat == "Levels" and period == "All" then
			value = (Leveling.fromTotal(value))
		end
		table.insert(shown, { rank = row.rank, name = row.name, value = value, userId = row.userId })
	end
	if stat == "Levels" and period == "All" then
		you.value = (Leveling.fromTotal(you.value))
	end
	return { rows = shown, you = you, resetsAt = Leaderboards.resetsAt(period, t) }
end

-- ===== lifecycle =====

function LeaderboardService.init(injected: any)
	deps = injected
	rewardRemote = deps.Remotes.getEvent("LeaderboardReward")
	deps.Services.PlayerDataService.register("leaderboard", {
		load = function(player: Player, value: any)
			local s = fresh()
			if type(value) == "table" then
				local t = now()
				if value.day == Leaderboards.dayOf(t) and type(value.daily) == "table" then
					s.daily = { Coins = value.daily.Coins or 0, Levels = value.daily.Levels or 0, Kills = value.daily.Kills or 0 }
				end
				if value.week == Leaderboards.weekOf(t) and type(value.weekly) == "table" then
					s.weekly = { Coins = value.weekly.Coins or 0, Levels = value.weekly.Levels or 0, Kills = value.weekly.Kills or 0 }
				end
				if type(value.lifetime) == "table" then
					s.lifetime = { Coins = value.lifetime.Coins or 0, Kills = value.lifetime.Kills or 0 }
				end
				s.tag = if type(value.tag) == "string" then value.tag else nil
				s.tagUntil = if type(value.tagUntil) == "number" then value.tagUntil else nil
				s.trophies = if type(value.trophies) == "table" then value.trophies else {}
			end
			states[player] = s
			publishTag(player, s)
		end,
		save = function(player: Player): any
			local s = states[player]
			if not s then
				return nil
			end
			return {
				day = s.day, week = s.week, daily = s.daily, weekly = s.weekly,
				lifetime = s.lifetime, tag = s.tag, tagUntil = s.tagUntil, trophies = s.trophies,
			}
		end,
	})
end

function LeaderboardService.start()
	local services = deps.Services
	services.CoinService.onEarned(function(player, amount)
		bump(player, "Coins", amount)
	end)
	services.ExpService.onLevelUp(function(player, gained)
		if player:GetAttribute("DataLoaded") then
			bump(player, "Levels", gained)
		end
	end)
	services.WorldEnemyService.onDefeated(function(_enemy, killer)
		if killer then
			bump(killer, "Kills", 1)
		end
	end)
	deps.Remotes.getFunction("GetLeaderboard").OnServerInvoke = function(player: Player, stat: any, period: any)
		return LeaderboardService.board(player, stat, period)
	end
	Players.PlayerRemoving:Connect(function(player)
		task.delay(5, function()
			states[player] = nil
		end)
	end)

	local ok = pcall(function()
		mailbox = DataStoreService:GetDataStore("LBMailbox")
		paid = DataStoreService:GetDataStore("LBRewards")
	end)
	storesOk = ok
	Players.PlayerAdded:Connect(function(player)
		task.spawn(openMailbox, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(openMailbox, player)
	end

	-- the board loop: write, read, pay ended periods, expire tags
	task.spawn(function()
		local t = now()
		local lastKeys = { Daily = Leaderboards.periodKey("Daily", t), Weekly = Leaderboards.periodKey("Weekly", t) }
		local lastWrite = 0
		while true do
			if os.clock() - lastWrite >= Leaderboards.WRITE_EVERY then
				lastWrite = os.clock()
				writeScores()
			end
			refreshCache()
			local tt = now()
			for period, key in lastKeys do
				local current = Leaderboards.periodKey(period, tt)
				if current ~= key then
					lastKeys[period] = current
					writeScores()
					task.spawn(payPeriod, period, key)
				end
			end
			for _, player in Players:GetPlayers() do
				local s = states[player]
				if s then
					publishTag(player, s)
				end
				task.spawn(openMailbox, player)
			end
			task.wait(Leaderboards.READ_EVERY)
		end
	end)
end

return LeaderboardService
