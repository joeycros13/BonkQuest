--!strict
-- CoinService: coins from defeated enemies.
--
-- Coins came back on 2026-10-07 at the user's request (they had been removed on
-- purpose before). They are published as the player's "Coins" attribute -- the
-- HUD counter and the shops read it -- and saved as the "coins" section of
-- PlayerDataService (2026-10-09).
--
-- Kill coins are multiplied by the player's "CoinBoost" attribute (passes and
-- timed boosts, ShopService). Coins added any other way (quest rewards, bought
-- bundles) are not.
--
-- When a player defeats an enemy (WorldEnemyService.onDefeated) they get a random amount from the enemy's `coins` range in
-- Config/Worlds. The killer's client is told through Remotes.CoinsDropped so
-- it can play the spill: Balance.Coins.piecesMin..piecesMax coins fling out of
-- the body and fly to the counter. The pieces are only the look; `amount` is
-- what is added.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Enemies = require(Config:WaitForChild("Enemies"))

local CoinService = {}

local deps: any = nil
local dropped: RemoteEvent? = nil
local random = Random.new()

function CoinService.get(player: Player): number
	local value = player:GetAttribute("Coins")
	return if type(value) == "number" then value else 0
end

function CoinService.add(player: Player, amount: number)
	player:SetAttribute("Coins", CoinService.get(player) + math.floor(amount))
end

-- Coins that come from somewhere other than a kill (a quest reward from Dale,
-- 2026-10-11): the same spill, thrown out at `position`, then added. With
-- `afterTalk` the client holds the spill until its conversation closes, so the
-- coins land in front of the player rather than behind the dialogue card.
function CoinService.spill(player: Player, amount: number, position: Vector3, afterTalk: boolean?)
	if amount <= 0 then
		return
	end
	if dropped then
		dropped:FireClient(player, {
			position = position,
			amount = amount,
			pieces = random:NextInteger(Balance.Coins.piecesMin, Balance.Coins.piecesMax),
			afterTalk = afterTalk == true,
		})
	end
	CoinService.add(player, amount)
end

local function bodyPosition(body: Instance): Vector3?
	if body:IsA("Model") then
		return body:GetBoundingBox().Position
	elseif body:IsA("BasePart") then
		return body.Position
	end
	return nil
end

local function onKill(enemy: any, killer: Player?)
	if not killer then
		return
	end
	local def = Enemies.get(enemy.archetype)
	local range = def and def.coins
	if not range then
		return
	end
	local amount = random:NextInteger(range.min, math.max(range.min, range.max))
	local boost = killer:GetAttribute("CoinBoost")
	if type(boost) == "number" and boost > 0 then
		amount = math.max(1, math.floor(amount * boost + 0.5))
	end
	-- Announce the spill before the balance changes: the client holds its
	-- counter for coins it knows are on their way.
	if dropped then
		dropped:FireClient(killer, {
			body = enemy.instance,
			position = bodyPosition(enemy.instance) or enemy.origin,
			amount = amount,
			pieces = random:NextInteger(Balance.Coins.piecesMin, Balance.Coins.piecesMax),
		})
	end
	CoinService.add(killer, amount)
end

function CoinService.init(injected: any)
	deps = injected
	dropped = deps.Remotes.getEvent("CoinsDropped")
	deps.Services.PlayerDataService.register("coins", {
		load = function(player: Player, value: any)
			if type(value) == "number" then
				player:SetAttribute("Coins", math.max(0, math.floor(value)))
			end
		end,
		save = function(player: Player): any
			return CoinService.get(player)
		end,
	})
end

function CoinService.start()
	deps.Services.WorldEnemyService.onDefeated(onKill)
	local function onPlayer(player: Player)
		if player:GetAttribute("Coins") == nil then
			player:SetAttribute("Coins", 0)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return CoinService
