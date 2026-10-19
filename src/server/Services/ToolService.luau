--!strict
-- ToolService: which gathering tools each player owns (Config/Tools, 2026-10-18).
--
-- Tools are bought on each world's Weapons stall Tools tab (StallService.buyTool) or
-- given by the admin panel. Gaining one re-checks the hand (MeleeService.refreshTool),
-- so a better tool of the kind in hand replaces it at once. The set is published as the player's "OwnedTools" attribute (comma-separated
-- ids; read it with Tools.owned) and saved as the "tools" section of PlayerDataService:
--   { owned = { id, ... } }
-- Holding a tool is MeleeService's job (one thing in hand); it asks `best` for the tool
-- a hotbar slot holds.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tools = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tools"))

local ToolService = {}

local deps: any = nil
local owned: { [Player]: { [string]: boolean } } = {}

local function publish(player: Player, set: { [string]: boolean })
	local ids = {}
	for id in set do
		table.insert(ids, id)
	end
	table.sort(ids)
	player:SetAttribute("OwnedTools", table.concat(ids, ","))
end

local function setOf(player: Player): { [string]: boolean }
	local set = owned[player]
	if not set then
		set = {}
		for _, id in Tools.testStartTools do
			if Tools.get(id) then
				set[id] = true
			end
		end
		owned[player] = set
		publish(player, set)
	end
	return set
end

function ToolService.owns(player: Player, id: string): boolean
	return setOf(player)[id] == true
end

-- The best tool of a kind the player owns (the one its hotbar slot holds), or nil.
function ToolService.best(player: Player, kind: string): Tools.ToolDef?
	return Tools.bestOf(setOf(player), kind)
end

-- Add a tool. Returns true if it is new to them.
function ToolService.grant(player: Player, id: string): boolean
	if not Tools.get(id) then
		return false
	end
	local set = setOf(player)
	if set[id] then
		return false
	end
	set[id] = true
	publish(player, set)
	-- a better tool of the kind in hand comes straight out in its place (user,
	-- 2026-10-19); the hotbar slot shows the best one by itself
	deps.Services.MeleeService.refreshTool(player)
	return true
end

-- Take a tool away (the admin panel). Returns true if they had it.
function ToolService.revoke(player: Player, id: string): boolean
	local set = setOf(player)
	if not set[id] then
		return false
	end
	set[id] = nil
	publish(player, set)
	-- the slot may now hold a lower tier, or nothing: re-check what is in hand
	deps.Services.MeleeService.refreshTool(player)
	return true
end

function ToolService.init(injected: any)
	deps = injected
	deps.Services.PlayerDataService.register("tools", {
		load = function(player: Player, value: any)
			if type(value) ~= "table" or type(value.owned) ~= "table" then
				return
			end
			local set = setOf(player)
			for _, id in value.owned do
				if Tools.get(id) then
					set[id] = true
				end
			end
			publish(player, set)
		end,
		-- read from the attribute, which outlives this service's state while leaving
		save = function(player: Player): any
			local ids = {}
			for id in Tools.owned(player) do
				table.insert(ids, id)
			end
			return { owned = ids }
		end,
	})
end

function ToolService.start()
	local function onPlayer(player: Player)
		setOf(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		task.defer(function()
			owned[player] = nil
		end)
	end)
end

return ToolService
