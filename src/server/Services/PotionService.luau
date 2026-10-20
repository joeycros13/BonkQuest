--!strict
-- PotionService: brewing and drinking potions (Config/Potions, 2026-10-19).
--
--   * Brewing: Remotes.BrewPotion(id) at a Crafter of a world in the potion's tier band
--     (StallService.atStall "Crafting"). It spends the recipe's materials (MaterialService),
--     any lower-tier potion in it, and the coins, then adds the potion.
--   * Drinking: Remotes.DrinkPotion(id) from the Inventory. Health heals at once (over
--     Potions.HEAL_SECONDS) with a cooldown; the others start or extend their timer.
--   * Published on the player: "Potions" (held, "Health1=2,..."), and per kind
--     "Potion_<kind>" (seconds left), "PotionTier_<kind>" and "PotionOrder_<kind>" (when it
--     started, from ShopService's stamps so the BoostHud stacks potions and shop boosts in
--     the order they began). MeleeService and SprintController read the timers through
--     Potions.multiplier.
--   * Timers only tick while the player is in the game; dying doesn't touch them. Saved as
--     the "potions" section, so leaving pauses them.
--
-- Both remotes return (ok, reason). reason is one of:
--   "unknown"   no such potion, or it has no recipe yet
--   "range"     not at a Crafter that brews that tier
--   "coins"     not enough coins
--   "materials" a recipe material or potion is short
--   "none"      drinking a potion they don't hold
--   "weaker"    a stronger one of that kind is running
--   "full"      a Health potion at full health
--   "cooldown"  a Health potion before the cooldown ends
--   "dead"      no living character

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Materials = require(Config:WaitForChild("Materials"))
local Potions = require(Config:WaitForChild("Potions"))

local PotionService = {}

local FORGET_AFTER = 30 -- seconds a leaver's state is kept for the save on leave

type Running = { tier: number, left: number, started: number }
type State = {
	counts: { [string]: number },
	running: { [string]: Running },
	healReadyAt: number,
}

local deps: any = nil
local states: { [Player]: State } = {}
local fallbackStamp = 0

local function stateOf(player: Player): State
	local s = states[player]
	if not s then
		s = { counts = {}, running = {}, healReadyAt = 0 }
		states[player] = s
	end
	return s
end

local function stamp(): number
	local shop = deps and deps.Services.ShopService
	if shop and shop.nextStamp then
		return shop.nextStamp()
	end
	fallbackStamp += 1
	return fallbackStamp
end

local function publishCounts(player: Player, s: State)
	local parts = {}
	for id, n in s.counts do
		if n > 0 then
			table.insert(parts, id .. "=" .. n)
		end
	end
	table.sort(parts)
	player:SetAttribute("Potions", table.concat(parts, ","))
end

local function publishTimers(player: Player, s: State)
	for _, kind in Potions.Kinds do
		local run = s.running[kind]
		local on = run ~= nil and run.left > 0
		player:SetAttribute("Potion_" .. kind, if on then math.ceil((run :: Running).left) else nil)
		player:SetAttribute("PotionTier_" .. kind, if on then (run :: Running).tier else nil)
		player:SetAttribute("PotionOrder_" .. kind, if on then (run :: Running).started else nil)
	end
end

local function publish(player: Player, s: State)
	publishCounts(player, s)
	publishTimers(player, s)
end

-- ==================== held potions ====================

function PotionService.get(player: Player, id: string): number
	return stateOf(player).counts[id] or 0
end

-- Add (or, with a negative amount, take) potions. Never goes below 0.
function PotionService.add(player: Player, id: string, amount: number)
	if not Potions.get(id) then
		return
	end
	local s = stateOf(player)
	local n = math.max(0, (s.counts[id] or 0) + math.floor(amount))
	s.counts[id] = if n > 0 then n else nil
	publishCounts(player, s)
end

-- Ends every running potion (the admin panel).
function PotionService.clearRunning(player: Player)
	local s = stateOf(player)
	table.clear(s.running)
	publishTimers(player, s)
end

-- ==================== brewing ====================

local function atCrafterFor(player: Player, def: Potions.PotionDef): boolean
	local band = Potions.Bands[def.tier]
	if not band then
		return false
	end
	for world = band.from, band.to do
		if deps.Services.StallService.atStall(player, "Crafting", world) then
			return true
		end
	end
	return false
end

local function has(player: Player, item: Potions.Ingredient): boolean
	if Potions.get(item.id) then
		return PotionService.get(player, item.id) >= item.count
	end
	return deps.Services.MaterialService.get(player, item.id) >= item.count
end

-- Why the player can't brew `def` right now, or nil when they can.
function PotionService.brewBlocker(player: Player, def: Potions.PotionDef): string?
	local recipe = def.recipe
	if not recipe then
		return "unknown"
	end
	for _, item in recipe do
		if not has(player, item) then
			return "materials"
		end
	end
	if deps.Services.CoinService.get(player) < def.coins then
		return "coins"
	end
	if not atCrafterFor(player, def) then
		return "range"
	end
	return nil
end

function PotionService.brew(player: Player, id: any): (boolean, string?)
	local def = Potions.get(id)
	if not def then
		return false, "unknown"
	end
	local blocker = PotionService.brewBlocker(player, def)
	if blocker then
		return false, blocker
	end
	for _, item in def.recipe :: { Potions.Ingredient } do
		if Potions.get(item.id) then
			PotionService.add(player, item.id, -item.count)
		elseif Materials.get(item.id) then
			deps.Services.MaterialService.add(player, item.id, -item.count)
		end
	end
	deps.Services.CoinService.add(player, -def.coins)
	PotionService.add(player, def.id, 1)
	task.spawn(deps.Services.PlayerDataService.saveNow, player)
	return true, nil
end

-- ==================== drinking ====================

local function heal(humanoid: Humanoid, amount: number)
	local steps = 10
	for _ = 1, steps do
		if humanoid.Health <= 0 or not humanoid.Parent then
			return
		end
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount / steps)
		task.wait(Potions.HEAL_SECONDS / steps)
	end
end

function PotionService.drink(player: Player, id: any): (boolean, string?)
	local def = Potions.get(id)
	if not def then
		return false, "unknown"
	end
	local s = stateOf(player)
	if (s.counts[def.id] or 0) < 1 then
		return false, "none"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid.Health > 0) then
		return false, "dead"
	end
	if def.kind == "Health" then
		if os.clock() < s.healReadyAt then
			return false, "cooldown"
		end
		if humanoid.Health >= humanoid.MaxHealth then
			return false, "full"
		end
		s.healReadyAt = os.clock() + Potions.HEALTH_COOLDOWN
		player:SetAttribute("PotionHealReady", workspace:GetServerTimeNow() + Potions.HEALTH_COOLDOWN)
		task.spawn(heal, humanoid, humanoid.MaxHealth * def.power)
	else
		local run = s.running[def.kind]
		if run and run.left > 0 and run.tier > def.tier then
			return false, "weaker"
		end
		if run and run.left > 0 and run.tier == def.tier then
			run.left += def.seconds -- the same tier adds its time and keeps its place
		else
			-- a fresh start, or a higher tier replacing a lower one
			s.running[def.kind] = { tier = def.tier, left = def.seconds, started = stamp() }
		end
		publishTimers(player, s)
	end
	PotionService.add(player, def.id, -1)
	return true, nil
end

-- ==================== lifecycle ====================

function PotionService.init(injected: any)
	deps = injected
	deps.Services.PlayerDataService.register("potions", {
		load = function(player: Player, value: any)
			local s = stateOf(player)
			if type(value) == "table" then
				for id, n in (if type(value.counts) == "table" then value.counts else {}) do
					if Potions.get(id) and type(n) == "number" and n > 0 then
						s.counts[id] = math.floor(n)
					end
				end
				-- running timers, oldest first, so the HUD keeps their order
				local running = if type(value.running) == "table" then value.running else {}
				local order = if type(value.order) == "table" then value.order else {}
				local seen: { [string]: boolean } = {}
				local function restore(kind: any)
					local run = running[kind]
					if type(kind) ~= "string" or seen[kind] or not table.find(Potions.Kinds, kind) or type(run) ~= "table" then
						return
					end
					seen[kind] = true
					local tier, left = run.tier, run.left
					if type(tier) == "number" and Potions.get(kind .. tier) and type(left) == "number" and left > 0 then
						s.running[kind] = { tier = tier, left = left, started = stamp() }
					end
				end
				for _, kind in order do
					restore(kind)
				end
				for kind in running do
					restore(kind)
				end
			end
			publish(player, s)
		end,
		save = function(player: Player): any
			local s = states[player]
			if not s then
				return nil
			end
			local running, order = {}, {}
			for kind, run in s.running do
				if run.left > 0 then
					running[kind] = { tier = run.tier, left = math.ceil(run.left) }
					table.insert(order, kind)
				end
			end
			table.sort(order, function(a, b)
				return s.running[a].started < s.running[b].started
			end)
			return { counts = table.clone(s.counts), running = running, order = order }
		end,
	})
end

function PotionService.start()
	deps.Remotes.getFunction("BrewPotion").OnServerInvoke = function(player: Player, id: any)
		return PotionService.brew(player, id)
	end
	deps.Remotes.getFunction("DrinkPotion").OnServerInvoke = function(player: Player, id: any)
		return PotionService.drink(player, id)
	end
	local function onPlayer(player: Player)
		publish(player, stateOf(player))
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		task.delay(FORGET_AFTER, function()
			states[player] = nil
		end)
	end)

	-- the clocks: one second off every running potion of everyone in the game
	task.spawn(function()
		while true do
			task.wait(1)
			for player, s in states do
				if player.Parent ~= Players then
					continue
				end
				local changed = false
				for kind, run in s.running do
					run.left -= 1
					if run.left <= 0 then
						s.running[kind] = nil
					end
					changed = true
				end
				if changed then
					publishTimers(player, s)
				end
			end
		end
	end)
end

return PotionService
