--!strict
-- HealZoneService: places that heal a player to full (2026-10-19, the user's
-- request: World 1's plaza fountain, because early HP is scarce and regen is slow).
--
-- A zone is an invisible part tagged "HealZone" (World 1: Structures/Fountain/HealZone,
-- the basin, so hopping into the water or standing on its rim counts). Attributes:
--   Cooldown   seconds before the same player can be healed by any zone again (30)
--   Round      true: the zone is a cylinder (its X size is the diameter), as PortalService
-- Nothing in the game uses Touched, so this polls like PortalService.
--
-- A player standing in a zone while hurt is healed to max at once, and the cooldown
-- starts; at full health nothing happens, so walking past never wastes it. Their
-- "HealZoneReady" attribute is the server time the next heal is allowed, and
-- Remotes.HealZone tells their client to play it: { kind = "healed", amount } or
-- { kind = "cooldown", seconds } (stepping in while it recharges, at most every few
-- seconds), drawn by Client.Controllers.HealZoneController.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local HealZoneService = {}

local TAG = "HealZone"
local POLL = 0.2
local DEFAULT_COOLDOWN = 30
-- how often the "ready in Ns" note may repeat while a player stands in a zone
local NOTE_EVERY = 4

local deps: any = nil
local remote: RemoteEvent? = nil
local readyAt: { [Player]: number } = {}
local notedAt: { [Player]: number } = {}

local function inside(zone: BasePart, point: Vector3): boolean
	local p = zone.CFrame:PointToObjectSpace(point)
	local h = zone.Size / 2
	if zone:GetAttribute("Round") == true then
		return math.abs(p.Y) <= h.Y and Vector2.new(p.X, p.Z).Magnitude <= h.X
	end
	return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
end

-- Zones in the world only: copies kept in ServerStorage backups keep their tags.
local function zones(): { BasePart }
	local list = {}
	for _, zone in CollectionService:GetTagged(TAG) do
		if zone:IsA("BasePart") and zone:IsDescendantOf(Workspace) then
			table.insert(list, zone)
		end
	end
	return list
end

local function check(player: Player, zone: BasePart, now: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid.Health > 0) or humanoid.Health >= humanoid.MaxHealth then
		return
	end
	local ready = readyAt[player] or 0
	if now < ready then
		if now - (notedAt[player] or -math.huge) >= NOTE_EVERY then
			notedAt[player] = now
			if remote then
				remote:FireClient(player, { kind = "cooldown", seconds = math.ceil(ready - now) })
			end
		end
		return
	end
	local amount = math.floor(humanoid.MaxHealth - humanoid.Health + 0.5)
	humanoid.Health = humanoid.MaxHealth
	local cooldown = zone:GetAttribute("Cooldown")
	readyAt[player] = now + (if type(cooldown) == "number" then cooldown else DEFAULT_COOLDOWN)
	player:SetAttribute("HealZoneReady", readyAt[player])
	if remote then
		remote:FireClient(player, { kind = "healed", amount = amount })
	end
end

function HealZoneService.init(injected: any)
	deps = injected
	remote = deps.Remotes.getEvent("HealZone")
end

function HealZoneService.start()
	Players.PlayerRemoving:Connect(function(player)
		readyAt[player] = nil
		notedAt[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(POLL)
			local list = zones()
			if #list == 0 then
				continue
			end
			local now = Workspace:GetServerTimeNow()
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if not (root and root:IsA("BasePart")) then
					continue
				end
				for _, zone in list do
					if inside(zone, root.Position) then
						check(player, zone, now)
						break
					end
				end
			end
		end
	end)
end

return HealZoneService
