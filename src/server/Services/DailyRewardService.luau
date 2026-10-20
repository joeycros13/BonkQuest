--!strict
-- DailyRewardService: the Daily Rewards stand and promo codes (Config/DailyRewards;
-- 2026-10-19, the user's design).
--
-- Saved as the "daily" section of PlayerDataService: { streak, lastDay, codes = { CODE = true } }.
-- Published for the panel: "DailyStreak" (days claimed in a row this ladder week, 0..7) and
-- "DailyLastDay" (the UTC day of the last claim, -1 for never). The client works out the
-- rest with DailyRewards.status and the server clock.
--
-- Remotes (both only at the stand: StallService.atStall, Station "Daily"):
--   ClaimDaily()      -> (ok, reason | words): grants today's ladder day, or "claimed" / "away"
--   RedeemCode(code)  -> (ok, words): "used" / "unknown" / "expired" / "empty" / "away" as
--                        DailyRewards.Text lines, or the reward in words
-- Coins come out as a spill from the stand's counter toward the player (CoinService.spill,
-- source "reward": not counted as coins earned on the leaderboards).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local DailyRewards = require(Config:WaitForChild("DailyRewards"))
local Potions = require(Config:WaitForChild("Potions"))
local Materials = require(Config:WaitForChild("Materials"))
local Shop = require(Config:WaitForChild("Shop"))

local DailyRewardService = {}

local STATION = "Daily"
local SPILL_TOWARD = 4 -- studs from the stand's ring toward the player, like a quest reward

type State = { streak: number, lastDay: number?, codes: { [string]: boolean } }

local deps: any = nil
local states: { [Player]: State } = {}
local busy: { [Player]: boolean } = {}

local function today(): number
	return DailyRewards.dayOf(Workspace:GetServerTimeNow())
end

local function stateOf(player: Player): State
	local s = states[player]
	if not s then
		s = { streak = 0, lastDay = nil, codes = {} }
		states[player] = s
	end
	return s
end

local function publish(player: Player, s: State)
	player:SetAttribute("DailyStreak", s.streak)
	player:SetAttribute("DailyLastDay", s.lastDay or -1)
end

local function highestWorld(player: Player): number
	local value = player:GetAttribute("HighestWorld")
	return if type(value) == "number" then math.max(1, value) else 1
end

-- Where the coins spill: the stand's ring, a little toward the player.
local function spillSpot(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	for _, ring in game:GetService("CollectionService"):GetTagged("Interactable") do
		if ring:IsA("BasePart") and ring:GetAttribute("Station") == STATION and ring:IsDescendantOf(Workspace) then
			local flat = Vector3.new(root.Position.X - ring.Position.X, 0, root.Position.Z - ring.Position.Z)
			local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zero
			return root.Position - dir * SPILL_TOWARD
		end
	end
	return root.Position
end

-- Hand a reward over; returns it in words.
function DailyRewardService.grant(player: Player, reward: DailyRewards.Reward): { string }
	local services = deps.Services
	local world = highestWorld(player)
	local coins = DailyRewards.coinsFor(reward, world, Shop.WorldScale)
	if coins > 0 then
		local spot = spillSpot(player)
		if spot then
			services.CoinService.spill(player, coins, spot, false, "reward")
		else
			services.CoinService.add(player, coins, "reward")
		end
	end
	if reward.exp then
		services.ExpService.add(player, reward.exp)
	end
	local band = Potions.tierAt(world) or 1
	for _, p in reward.potions or {} do
		services.PotionService.add(player, p.kind .. band, p.count)
	end
	for _, b in reward.boosts or {} do
		services.ShopService.addBoost(player, b.id, b.minutes * 60)
	end
	if reward.materials then
		for _, mat in Materials.list() do
			local m = mat :: any
			if m.world == world and not m.core and not m.quest and not m.gathered and not m.fished then
				services.MaterialService.add(player, mat.id, reward.materials)
			end
		end
	end
	return DailyRewards.describe(reward, if coins > 0 then coins else nil)
end

function DailyRewardService.claim(player: Player): (boolean, any)
	if busy[player] then
		return false, "busy"
	end
	if not deps.Services.StallService.atStall(player, STATION) then
		return false, "away"
	end
	local s = stateOf(player)
	local day = today()
	local ready, _, nextDay = DailyRewards.status(s.streak, s.lastDay, day)
	if not ready then
		return false, "claimed"
	end
	busy[player] = true
	s.streak = nextDay
	s.lastDay = day
	publish(player, s)
	local words = DailyRewardService.grant(player, DailyRewards.Ladder[nextDay])
	busy[player] = nil
	return true, table.concat(words, ", ")
end

function DailyRewardService.redeem(player: Player, raw: any): (boolean, string)
	local t = DailyRewards.Text
	if not deps.Services.StallService.atStall(player, STATION) then
		return false, t.away
	end
	local code = DailyRewards.normalise(raw)
	if code == "" then
		return false, t.codeEmpty
	end
	local entry = DailyRewards.Codes[code]
	if not entry then
		return false, t.codeUnknown
	end
	if entry.expires and Workspace:GetServerTimeNow() > entry.expires then
		return false, t.codeExpired
	end
	local s = stateOf(player)
	if s.codes[code] then
		return false, t.codeUsed
	end
	s.codes[code] = true
	return true, t.codeOk:format(table.concat(DailyRewardService.grant(player, entry.reward), ", "))
end

-- Admin / testing: forget the last claim, or set the streak (AdminService "daily").
function DailyRewardService.set(player: Player, streak: number?, lastDay: number?)
	local s = stateOf(player)
	s.streak = math.clamp(math.floor(streak or 0), 0, #DailyRewards.Ladder)
	s.lastDay = lastDay
	publish(player, s)
end

function DailyRewardService.today(): number
	return today()
end

function DailyRewardService.init(injected: any)
	deps = injected
	deps.Services.PlayerDataService.register("daily", {
		load = function(player: Player, value: any)
			local s = stateOf(player)
			if type(value) == "table" then
				s.streak = if type(value.streak) == "number" then math.clamp(math.floor(value.streak), 0, #DailyRewards.Ladder) else 0
				s.lastDay = if type(value.lastDay) == "number" then value.lastDay else nil
				s.codes = {}
				if type(value.codes) == "table" then
					for code, used in value.codes do
						if type(code) == "string" and used == true then
							s.codes[code] = true
						end
					end
				end
			end
			publish(player, s)
		end,
		save = function(player: Player): any
			local s = states[player]
			if not s then
				return nil
			end
			return { streak = s.streak, lastDay = s.lastDay, codes = s.codes }
		end,
	})
end

function DailyRewardService.start()
	deps.Remotes.getFunction("ClaimDaily").OnServerInvoke = function(player: Player)
		return DailyRewardService.claim(player)
	end
	deps.Remotes.getFunction("RedeemCode").OnServerInvoke = function(player: Player, code: any)
		return DailyRewardService.redeem(player, code)
	end
	local function onPlayer(player: Player)
		-- a player without a save yet still gets the attributes
		if player:GetAttribute("DailyStreak") == nil then
			publish(player, stateOf(player))
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		-- the saver reads the state on leave, so keep it a moment
		task.delay(30, function()
			if not player.Parent then
				states[player] = nil
				busy[player] = nil
			end
		end)
	end)
end

return DailyRewardService
