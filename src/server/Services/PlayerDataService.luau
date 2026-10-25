--!strict
-- PlayerDataService: everything a player earns, saved between sessions (the
-- user's call, 2026-10-09: "everything the player can obtain").
--
-- One record per player in DataStore "PlayerData", key "u_<UserId>":
--   { v = 1, [section] = value, ... }
-- Each service owns a section and registers it in its init():
--   PlayerDataService.register("coins", { load = fn(player, value), save = fn(player) -> value })
-- load(player, value) runs once the record is read (value is nil for a new
-- player or a missing section) and must cope with being called before the
-- service's own PlayerAdded handler; save(player) returns the section to store.
-- Sections load in registration order, which is SERVICE_ORDER: coins and EXP
-- before the quest, so a loaded balance never counts as quest progress.
-- Sections today: highestWorld (here, published as the player's "HighestWorld"
-- attribute), weapons (MeleeService), coins (CoinService), exp (ExpService),
-- materials (MaterialService), armor (ArmorService), tools (ToolService), quest
-- (QuestService), shop (ShopService), infuse (InfuseService), potions
-- (PotionService), upgrades (UpgradeService), leaderboard (LeaderboardService),
-- daily (DailyRewardService) and settings (SettingsService).
-- The Index keeps its own DataStore (IndexService): kills, discoveries, titles.
--
-- Saved every AUTOSAVE seconds, on leave and on shutdown; saveNow() for a
-- purchase receipt. A record that couldn't be read is never written over.
--
-- Nothing a player earned may be lost on the way out (issue 25, 2026-10-25: a
-- crafted Farmhand's Gear was gone after rejoining). Some services let a leaving
-- player's state go a frame later (Armor, Materials, Infuse), and when a session
-- ends the leave-save and the shutdown save used to run together: the second one
-- could snapshot after that state was gone and write the record without it. Now:
--   * on leave the snapshot is taken at once, and the player leaves the profile list
--     straight away, so neither the autosave nor the shutdown snapshots them again
--     (the shutdown waits for the leave-saves still writing);
--   * one player's writes go one at a time, newest snapshot last;
--   * a section whose saver has nothing to say (nil, or an error) keeps the value it
--     was loaded with or last saved with, instead of being dropped from the record.
-- When DataStores are unavailable (an unpublished place, or Studio without API
-- access) everything still works for the session and it warns once.
-- Each player gets "DataLoaded" = true once their record is applied.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local PlayerDataService = {}

local STORE_NAME = "PlayerData"
local VERSION = 1
local AUTOSAVE = 60
local RETRIES = 3
local MAX_WORLD = 3

type Section = { load: (Player, any) -> (), save: (Player) -> any }
type Profile = {
	loaded: boolean,
	readable: boolean,
	-- each section's value as loaded or last saved: kept when a saver returns nothing
	last: { [string]: any },
	-- a write for this player is under way (they go one at a time)
	writing: boolean,
}

local sections: { { name: string, section: Section } } = {}
local profiles: { [Player]: Profile } = {}
-- players who left and whose last save is still being written (the shutdown waits for them)
local leaving: { [Player]: boolean } = {}
local store: DataStore? = nil
local warned = false

local function keyOf(player: Player): string
	return "u_" .. player.UserId
end

local function unavailable(message: string)
	store = nil
	if not warned then
		warned = true
		warn("[PlayerDataService] DataStores unavailable (publish the place and turn on Studio API access to save); progress lasts this session only: " .. message)
	end
end

local function retry<T>(fn: () -> T): (boolean, T | string)
	local ok, result = false, nil :: any
	for attempt = 1, RETRIES do
		ok, result = pcall(fn)
		if ok then
			return true, result
		end
		task.wait(attempt)
	end
	return false, result
end

-- Read the stored record. Returns (readable, record): readable is false when
-- the store answered with an error, so the session must not overwrite it.
local function read(player: Player): (boolean, any)
	local ds = store
	if not ds then
		return false, nil
	end
	local ok, data = pcall(function()
		return ds:GetAsync(keyOf(player))
	end)
	if not ok then
		local message = tostring(data)
		-- an unpublished place or Studio without API access fails at once
		if message:find("publish") or message:find("API") or message:find("Studio") then
			unavailable(message)
			return false, nil
		end
		ok, data = retry(function()
			return ds:GetAsync(keyOf(player))
		end)
	end
	if not ok then
		warn(("[PlayerDataService] couldn't load %s's data (%s); it won't be saved this session"):format(player.Name, tostring(data)))
		return false, nil
	end
	return true, data
end

local function snapshot(player: Player, profile: Profile): any
	local record: { [string]: any } = { v = VERSION }
	for _, entry in sections do
		local ok, value = pcall(entry.section.save, player)
		if not ok then
			warn(("[PlayerDataService] section %s failed to save for %s: %s"):format(entry.name, player.Name, tostring(value)))
		end
		if ok and value ~= nil then
			record[entry.name] = value
			profile.last[entry.name] = value
		else
			-- never drop progress: keep what was loaded or last saved
			record[entry.name] = profile.last[entry.name]
		end
	end
	return record
end

-- Write a snapshot, after any write already under way for this player.
local function write(player: Player, profile: Profile, record: any): boolean
	local ds = store
	if not ds then
		return false
	end
	while profile.writing do
		task.wait()
	end
	profile.writing = true
	local ok, err = retry(function()
		return ds:SetAsync(keyOf(player), record, { player.UserId })
	end)
	profile.writing = false
	if not ok then
		warn(("[PlayerDataService] couldn't save %s's data: %s"):format(player.Name, tostring(err)))
	end
	return ok
end

local function canWrite(profile: Profile?): boolean
	return store ~= nil and profile ~= nil and profile.loaded and profile.readable
end

-- Write the player's record now. Returns true when it reached the store.
function PlayerDataService.saveNow(player: Player): boolean
	local profile = profiles[player]
	if not profile or not canWrite(profile) then
		return false
	end
	-- wait for a write under way first, so this snapshot is the newest when it lands
	while profile.writing do
		task.wait()
	end
	return write(player, profile, snapshot(player, profile))
end

-- Whether saves reach a DataStore at all in this server.
function PlayerDataService.canSave(): boolean
	return store ~= nil
end

function PlayerDataService.isLoaded(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.loaded
end

function PlayerDataService.register(name: string, section: Section)
	table.insert(sections, { name = name, section = section })
end

-- The highest world the player has unlocked (1 until world gates exist); coin
-- bundles in the shop scale with it.
function PlayerDataService.highestWorld(player: Player): number
	local value = player:GetAttribute("HighestWorld")
	return if type(value) == "number" then value else 1
end

function PlayerDataService.unlockWorld(player: Player, world: number)
	if world > PlayerDataService.highestWorld(player) then
		player:SetAttribute("HighestWorld", math.clamp(math.floor(world), 1, MAX_WORLD))
	end
end

local function onPlayer(player: Player)
	if profiles[player] then
		return
	end
	local profile: Profile = { loaded = false, readable = false, last = {}, writing = false }
	profiles[player] = profile
	player:SetAttribute("HighestWorld", 1)
	local readable, data = read(player)
	if profiles[player] ~= profile then
		return -- left while loading
	end
	local record = if type(data) == "table" then data else {}
	for _, entry in sections do
		profile.last[entry.name] = record[entry.name]
	end
	for _, entry in sections do
		local ok, err = pcall(entry.section.load, player, record[entry.name])
		if not ok then
			warn(("[PlayerDataService] section %s failed to load for %s: %s"):format(entry.name, player.Name, tostring(err)))
		end
	end
	profile.readable = readable
	profile.loaded = true
	player:SetAttribute("DataLoaded", true)
end

function PlayerDataService.init(_injected: any)
	PlayerDataService.register("highestWorld", {
		load = function(player: Player, value: any)
			if type(value) == "number" then
				player:SetAttribute("HighestWorld", math.clamp(math.floor(value), 1, MAX_WORLD))
			end
		end,
		save = function(player: Player): any
			return PlayerDataService.highestWorld(player)
		end,
	})
end

function PlayerDataService.start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		unavailable(tostring(result))
	end
	-- Every service has registered by now (all inits run before any start), and
	-- their PlayerAdded handlers are connected after this one; loaders cope.
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		local profile = profiles[player]
		profiles[player] = nil
		if not profile or not canWrite(profile) then
			return
		end
		-- the snapshot now, before any service lets the player's state go
		local record = snapshot(player, profile)
		leaving[player] = true
		write(player, profile, record)
		leaving[player] = nil
	end)
	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				PlayerDataService.saveNow(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while (pending > 0 or next(leaving) ~= nil) and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE)
			for player in profiles do
				task.spawn(PlayerDataService.saveNow, player)
			end
		end
	end)
end

return PlayerDataService
