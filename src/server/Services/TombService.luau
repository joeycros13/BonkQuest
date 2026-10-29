--!strict
-- TombService: World 4's secret tomb on the server (2026-10-29; Config/Tomb has the design and the trap
-- attributes). The quicksand at Obelisk_3's shadow tip is a PortalService charge zone (stand 3 s), so
-- getting in needs nothing here. This service:
--   * keeps each player's checkpoint (Tomb.CHECKPOINT_ATTR): 1 (the landing) on arrival, raised by
--     stepping on a scarab plate (tagged TombCheckpoint, Index), cleared on leaving the tomb
--   * judges the traps every POLL against the server clock (the same formulas TombController animates):
--     a hit takes a share of max health (the trap's Damage) and flashes the body (Remotes.PlayerHurt);
--     a collapsing tile or the boulder sends you back to a checkpoint (PortalService, behind the fade)
--   * fires the dart walls: a plate stepped on sets the trap's FiredAt (server time) and the volley
--     hits whoever is in its zone at that moment
--   * saves reaching the burial chamber (section "tomb", Tomb.FOUND_ATTR), and from then on the
--     landing's ShortcutTablet prompt sends you straight to the chamber
-- Nothing here uses Touched; it polls like PortalService and HealZoneService.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Tomb = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tomb"))

local TombService = {}

local POLL = 0.1
-- the tomb's box, grown this much, counts as "in the tomb"
local BOUNDS_PAD = 4

local deps: any = nil
local lastHit: { [Player]: { [Instance]: number } } = {}
local onTile: { [Player]: { tile: BasePart, since: number }? } = {}
local rearmAt: { [Instance]: number } = {}

local tomb: Instance? = nil
local bounds: { lo: Vector3, hi: Vector3 }? = nil

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root, humanoid
	end
	return nil, nil
end

local function inTomb(point: Vector3): boolean
	local b = bounds
	return b ~= nil and point.X >= b.lo.X and point.X <= b.hi.X and point.Y >= b.lo.Y and point.Y <= b.hi.Y
		and point.Z >= b.lo.Z and point.Z <= b.hi.Z
end

local function inWorld(list: { Instance }): { Instance }
	local out = {}
	for _, inst in list do
		if inst:IsDescendantOf(Workspace) then
			table.insert(out, inst)
		end
	end
	return out
end

local function checkpointPart(index: number): BasePart?
	for _, plate in inWorld(CollectionService:GetTagged(Tomb.CHECKPOINT_TAG)) do
		if plate:IsA("BasePart") and plate:GetAttribute("Index") == index then
			return plate
		end
	end
	return nil
end

-- Back to a checkpoint (the player's own, or `index`), behind the fade.
local function sendBack(player: Player, index: number?)
	local portal = deps.Services.PortalService
	if portal.isBusy(player) then
		return
	end
	local current = player:GetAttribute(Tomb.CHECKPOINT_ATTR)
	local want = index or (if type(current) == "number" then current else 1)
	if index and type(current) == "number" then
		want = math.min(index, current)
	end
	local plate = checkpointPart(want) or checkpointPart(1)
	if plate then
		task.spawn(portal.sendTo, player, CFrame.new(plate.Position + Vector3.new(0, 3.2, 0)), { fade = true })
	end
end

local function hurt(player: Player, humanoid: Humanoid, trap: Instance, from: Vector3): boolean
	local hits = lastHit[player]
	if not hits then
		hits = {}
		lastHit[player] = hits
	end
	local t = os.clock()
	if (hits[trap] or 0) + Tomb.HIT_COOLDOWN > t then
		return false
	end
	hits[trap] = t
	local share = Tomb.num(trap, "Damage", 0.15)
	humanoid:TakeDamage(math.min(humanoid.MaxHealth * share, math.max(humanoid.Health, 0)))
	deps.Remotes.getEvent("PlayerHurt"):FireAllClients({ character = player.Character, from = from })
	return true
end

-- A dart volley: everyone in the trap's zone at the moment it flies.
local function volley(trap: Instance)
	local zone = trap:FindFirstChild("Zone") :: BasePart?
	if not zone then
		return
	end
	for _, player in Players:GetPlayers() do
		local root, humanoid = rootOf(player)
		if root and humanoid and Tomb.inside(zone, root.Position) then
			hurt(player, humanoid, trap, zone.Position)
		end
	end
end

local function judge(player: Player, root: BasePart, humanoid: Humanoid, trap: Instance, t: number)
	local kind = trap:GetAttribute("Kind")
	local pos = root.Position
	local zone = trap:FindFirstChild("Zone") :: BasePart?
	if kind == "Spikes" or kind == "Fire" then
		if zone and Tomb.inside(zone, pos) and Tomb.active(trap, t) then
			hurt(player, humanoid, trap, zone.Position)
		end
	elseif kind == "Blade" then
		local pivot = Tomb.bladePivot(trap, t)
		if pivot and zone and Tomb.inside(zone, pos, 2) then
			local centre = (pivot * CFrame.new(0, -Tomb.num(trap, "Length", 10.2), 0)).Position
			local d = pos - centre
			local along, lat = pivot.LookVector, pivot.RightVector
			if math.abs(d:Dot(along)) < 1.3 and math.abs(d:Dot(lat)) < Tomb.num(trap, "Radius", 1.8) + 1 then
				hurt(player, humanoid, trap, centre)
			end
		end
	elseif kind == "Darts" then
		local plate = trap:FindFirstChild("Plate") :: BasePart?
		if plate and Tomb.over(plate, pos, 4.5, 0.4) and (rearmAt[trap] or 0) <= t then
			local delay = Tomb.num(trap, "Delay", 0.45)
			rearmAt[trap] = t + Tomb.num(trap, "Rearm", 2)
			trap:SetAttribute("FiredAt", t + delay)
			task.delay(delay, volley, trap)
		end
	elseif kind == "Collapse" then
		local standing: BasePart? = nil
		for _, tile in trap:GetChildren() do
			if tile.Name == "Cracked" and tile:IsA("BasePart") and Tomb.over(tile, pos, 4.5, 0.15) then
				standing = tile
				break
			end
		end
		local state = onTile[player]
		if standing then
			if not state or state.tile ~= standing then
				onTile[player] = { tile = standing, since = os.clock() }
			elseif os.clock() - state.since >= Tomb.num(trap, "Hold", 0.3) then
				onTile[player] = nil
				-- the tile crumbles under them (TombController shows it) and they wake at the checkpoint
				task.delay(0.35, sendBack, player)
			end
		elseif state and state.tile.Parent == trap then
			onTile[player] = nil
		end
	elseif kind == "Boulder" then
		local rolling, centre = Tomb.boulder(trap, t)
		if rolling and zone and Tomb.inside(zone, pos) then
			local start, finish = trap:FindFirstChild("Start") :: BasePart?, trap:FindFirstChild("End") :: BasePart?
			local axis = if start and finish then (finish.Position - start.Position).Unit else Vector3.xAxis
			if math.abs((pos - centre):Dot(axis)) < Tomb.num(trap, "Radius", 4.5) + 0.8 then
				if hurt(player, humanoid, trap, centre) then
					sendBack(player, Tomb.num(trap, "ResetTo", 4))
				end
			end
		end
	end
end

local function poll()
	if not (tomb and tomb.Parent) then
		return
	end
	local t = now()
	local traps = inWorld(CollectionService:GetTagged(Tomb.TRAP_TAG))
	local plates = inWorld(CollectionService:GetTagged(Tomb.CHECKPOINT_TAG))
	local structures = tomb
	local chamber = structures:FindFirstChild("ChamberZone", true) :: BasePart?
	for _, player in Players:GetPlayers() do
		local root, humanoid = rootOf(player)
		if not (root and humanoid) or not inTomb(root.Position) then
			if player:GetAttribute(Tomb.CHECKPOINT_ATTR) ~= nil and not (root and inTomb(root.Position)) then
				player:SetAttribute(Tomb.CHECKPOINT_ATTR, nil)
			end
			onTile[player] = nil
			continue
		end
		local pos = root.Position
		local current = player:GetAttribute(Tomb.CHECKPOINT_ATTR)
		local best = if type(current) == "number" then current else 1
		for _, plate in plates do
			local index = plate:GetAttribute("Index")
			if plate:IsA("BasePart") and type(index) == "number" and index > best and Tomb.over(plate, pos, 5) then
				best = index
			end
		end
		if best ~= current then
			player:SetAttribute(Tomb.CHECKPOINT_ATTR, best)
		end
		if chamber and player:GetAttribute(Tomb.FOUND_ATTR) ~= true and Tomb.inside(chamber, pos) then
			player:SetAttribute(Tomb.FOUND_ATTR, true)
		end
		if deps.Services.PortalService.isBusy(player) then
			continue
		end
		for _, trap in traps do
			judge(player, root, humanoid, trap, t)
		end
	end
end

local function wireShortcut()
	local tablet = tomb and tomb:FindFirstChild("ShortcutTablet", true)
	local prompt = tablet and tablet:FindFirstChild("Prompt", true)
	local arrival = tomb and tomb:FindFirstChild("ChamberArrival", true)
	if not (prompt and prompt:IsA("ProximityPrompt") and arrival and arrival:IsA("BasePart")) then
		warn("[TombService] the tomb has no ShortcutTablet prompt or ChamberArrival")
		return
	end
	prompt.Triggered:Connect(function(player: Player)
		local root = rootOf(player)
		if not root or player:GetAttribute(Tomb.FOUND_ATTR) ~= true or deps.Services.PortalService.isBusy(player) then
			return
		end
		if (root.Position - (prompt.Parent :: BasePart).Position).Magnitude > 16 then
			return
		end
		task.spawn(deps.Services.PortalService.send, player, arrival, { fade = true })
	end)
end

function TombService.init(injected: any)
	deps = injected
	deps.Services.PlayerDataService.register("tomb", {
		load = function(player: Player, value: any)
			player:SetAttribute(Tomb.FOUND_ATTR, type(value) == "table" and value.found == true)
		end,
		save = function(player: Player): any
			return { found = player:GetAttribute(Tomb.FOUND_ATTR) == true }
		end,
	})
end

function TombService.start()
	local worlds = Workspace:FindFirstChild("Worlds")
	local w4 = worlds and worlds:FindFirstChild("W04_ScorchingSands")
	local structures = w4 and w4:FindFirstChild("Structures")
	tomb = structures and structures:FindFirstChild("SecretTomb")
	local ground = w4 and w4:FindFirstChild("Ground")
	local shell = ground and ground:FindFirstChild("SecretTomb")
	if not (tomb and shell) then
		warn("[TombService] no secret tomb in World 4")
		return
	end
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, part in shell:GetDescendants() do
		if part:IsA("BasePart") then
			local h = part.Size / 2
			lo = lo:Min(part.Position - h)
			hi = hi:Max(part.Position + h)
		end
	end
	local pad = Vector3.one * BOUNDS_PAD
	bounds = { lo = lo - pad, hi = hi + pad }
	wireShortcut()
	for _, player in Players:GetPlayers() do
		if player:GetAttribute(Tomb.FOUND_ATTR) == nil then
			player:SetAttribute(Tomb.FOUND_ATTR, false)
		end
	end
	Players.PlayerAdded:Connect(function(player)
		if player:GetAttribute(Tomb.FOUND_ATTR) == nil then
			player:SetAttribute(Tomb.FOUND_ATTR, false)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastHit[player] = nil
		onTile[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(POLL)
			local ok, err = pcall(poll)
			if not ok then
				warn("[TombService] " .. tostring(err))
			end
		end
	end)
end

return TombService
