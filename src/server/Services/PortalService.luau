--!strict
-- PortalService: walk-in teleports (2026-10-12; first used for the secret rooms).
--
-- A zone is an invisible part tagged TeleportZone (MapLayout.Tags) holding an
-- ObjectValue "Target" that points at a part: standing inside the zone's box
-- sends you to that part (feet on its top face, facing its look direction; 2026-10-20:
-- feet at its centre sank them half a stud into World 1's spawn dais, and the physics
-- popped the character up on arrival).
-- Zone attributes:
--   Fade         true: fade the screen out and back (Remotes.TeleportFade)
--   KeepFalling  true: keep the player's downward speed (the silo drop lands you
--                still falling, so it reads as one long fall)
--   Round        true: the zone is a cylinder (its X size is the diameter), not a box
--   ChargeSeconds  stand inside this long before you go (the fairy ring's
--                sparkle-up); stepping out resets it. While anyone is charging,
--                the zone's ParticleEmitters named "ChargeFx" run and each part an
--                ObjectValue "Glow" points at turns Neon.
--   Countdown    a Folder of ObjectValues (named in lighting order: Step01, Step02...)
--                pointing at parts: they turn Neon one by one across the charge,
--                all lit `CountdownHold` seconds (default 1) before the teleport
--                (the fairy ring's mushrooms going round).
-- Polled like the walk-in rings (nothing in the game uses Touched); a player is
-- only teleported again after COOLDOWN, so arriving inside another zone can't loop.
--
-- A zone with a ProximityPrompt child named "Prompt" isn't walked into: pressing the
-- prompt sends you instead (the two secret rooms' exits, 2026-10-28, the user: the
-- walk-in exits kept bugging out). The prompt is hand-placed (ActionText "Leave",
-- Style Custom, so PromptController draws it as the speech bubble).
--
--   PortalService.send(player, target, opts?)   teleport by code (the Worlds menu will)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("MapLayout"))
local Worlds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Worlds"))

local PortalService = {}

local POLL = 0.1
local COOLDOWN = 2.5
local FADE_SECONDS = 0.25
-- the root sits this far above the feet (R6)
local ROOT_HEIGHT = 3
-- how long the screen stays fully black after the move, so the new spot (and its
-- lighting, AmbienceController) is settled before the fade-in shows it
local SETTLE_SECONDS = 0.15

local deps: any = nil
local fadeRemote: RemoteEvent? = nil
local busy: { [Player]: number } = {}
-- players standing in a charging zone, and since when
local charging: { [Player]: { zone: BasePart, since: number } } = {}

local function inside(zone: BasePart, point: Vector3): boolean
	local p = zone.CFrame:PointToObjectSpace(point)
	local h = zone.Size / 2
	if zone:GetAttribute("Round") == true then
		return math.abs(p.Y) <= h.Y and Vector2.new(p.X, p.Z).Magnitude <= h.X
	end
	return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
end

local function setGlow(part: BasePart, on: boolean)
	if on then
		if part:GetAttribute("BaseMaterial") == nil then
			part:SetAttribute("BaseMaterial", part.Material.Name)
		end
		part.Material = Enum.Material.Neon
	else
		local base = part:GetAttribute("BaseMaterial")
		part.Material = if type(base) == "string" then (Enum.Material :: any)[base] else Enum.Material.SmoothPlastic
	end
end

-- the charge-up effects of a zone; `elapsed` = the longest anyone has stood in it (nil: nobody)
local function chargeFx(zone: BasePart, elapsed: number?)
	local on = elapsed ~= nil
	if zone:GetAttribute("FxOn") ~= on then
		zone:SetAttribute("FxOn", on)
		for _, d in zone:GetDescendants() do
			if d:IsA("ParticleEmitter") and d.Name == "ChargeFx" then
				d.Enabled = on
			elseif d:IsA("ObjectValue") and d.Name == "Glow" and d.Value and d.Value:IsA("BasePart") then
				setGlow(d.Value :: BasePart, on)
			end
		end
	end
	local folder = zone:FindFirstChild("Countdown")
	if folder then
		local steps = folder:GetChildren()
		table.sort(steps, function(a, b)
			return a.Name < b.Name
		end)
		local charge = zone:GetAttribute("ChargeSeconds")
		local hold = zone:GetAttribute("CountdownHold")
		hold = if type(hold) == "number" then hold else 1
		local span = math.max((if type(charge) == "number" then charge else 1) - hold, 0.1)
		-- one lights as soon as you step on, the last one `hold` seconds before you go
		local lit = if elapsed then math.min(#steps, 1 + math.floor(elapsed / span * (#steps - 1) + 1e-6)) else 0
		for i, step in steps do
			if step:IsA("ObjectValue") and step.Value and step.Value:IsA("BasePart") then
				setGlow(step.Value :: BasePart, i <= lit)
			end
		end
	end
end

export type SendOptions = { fade: boolean?, keepFalling: boolean? }

-- Move a player's character so its root ends at `at`, behind the black fade unless
-- opts.fade is false. Yields through the fade.
function PortalService.sendTo(player: Player, at: CFrame, opts: SendOptions?)
	local o: SendOptions = opts or {}
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and root and root:IsA("BasePart")) then
		return
	end
	busy[player] = os.clock() + COOLDOWN
	local remote: RemoteEvent? = if o.fade ~= false then fadeRemote else nil
	if remote then
		remote:FireClient(player, "out", FADE_SECONDS)
		task.wait(FADE_SECONDS)
	end
	if character.Parent == nil then
		return
	end
	local fall = if o.keepFalling then math.min(root.AssemblyLinearVelocity.Y, 0) else 0
	character:PivotTo(at)
	root.AssemblyLinearVelocity = Vector3.new(0, fall, 0)
	root.AssemblyAngularVelocity = Vector3.zero
	if remote then
		task.wait(SETTLE_SECONDS)
		remote:FireClient(player, "in", FADE_SECONDS * 1.6)
	end
end

-- Move a player onto a part: feet on its top face, facing along its LookVector.
function PortalService.send(player: Player, target: BasePart, opts: SendOptions?)
	local look = target.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 1e-3 then
		look = Vector3.new(0, 0, -1)
	end
	local top = target.Position.Y + target.Size.Y / 2
	local at = Vector3.new(target.Position.X, top + ROOT_HEIGHT, target.Position.Z)
	PortalService.sendTo(player, CFrame.lookAt(at, at + look.Unit), opts)
end

-- True while a player is mid-teleport (or just after one).
function PortalService.isBusy(player: Player): boolean
	return (busy[player] or 0) > os.clock()
end

local function promptOf(zone: Instance): ProximityPrompt?
	local prompt = zone:FindFirstChild("Prompt")
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
end

-- Send a player through a zone (its Target, with its Fade / KeepFalling).
local function useZone(player: Player, zone: BasePart)
	local value = zone:FindFirstChild("Target")
	local target = value and value:IsA("ObjectValue") and value.Value
	if target and target:IsA("BasePart") then
		busy[player] = os.clock() + COOLDOWN
		task.spawn(PortalService.send, player, target, {
			fade = zone:GetAttribute("Fade") == true,
			keepFalling = zone:GetAttribute("KeepFalling") == true,
		})
	else
		warn(("[PortalService] %s has no Target part"):format(zone:GetFullName()))
	end
end

-- A prompt zone sends whoever presses its prompt (not mid-teleport, and alive).
local wired: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local function wirePrompt(zone: Instance)
	local prompt = promptOf(zone)
	if not (prompt and zone:IsA("BasePart")) or wired[prompt] then
		return
	end
	wired[prompt] = true
	prompt.Triggered:Connect(function(player: Player)
		if (busy[player] or 0) > os.clock() or not zone:IsDescendantOf(workspace) then
			return
		end
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			useZone(player, zone :: BasePart)
		end
	end)
end

local function poll()
	local zones = CollectionService:GetTagged(MapLayout.Tags.TeleportZone)
	if #zones == 0 then
		return
	end
	local now = os.clock()
	local active: { [BasePart]: number } = {}
	for _, player in Players:GetPlayers() do
		if (busy[player] or 0) > now then
			charging[player] = nil
			continue
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			charging[player] = nil
			continue
		end
		local found: BasePart? = nil
		for _, zone in zones do
			if zone:IsA("BasePart") and zone:IsDescendantOf(workspace) and not promptOf(zone) and inside(zone, root.Position) then
				found = zone
				break
			end
		end
		if not found then
			charging[player] = nil
			continue
		end
		local zone = found :: BasePart
		local charge = zone:GetAttribute("ChargeSeconds")
		if type(charge) == "number" and charge > 0 then
			local c = charging[player]
			if not c or c.zone ~= zone then
				charging[player] = { zone = zone, since = now }
				active[zone] = math.max(active[zone] or 0, 0)
				continue
			end
			if now - c.since < charge then
				active[zone] = math.max(active[zone] or 0, now - c.since)
				continue
			end
			charging[player] = nil
		end
		useZone(player, zone)
	end
	-- charge-up effects follow whoever is standing in a charging zone
	for _, zone in zones do
		if zone:IsA("BasePart") and zone:GetAttribute("ChargeSeconds") ~= nil then
			chargeFx(zone, active[zone])
		end
	end
end

function PortalService.init(injected: any)
	deps = injected
end

-- The Worlds menu (2026-10-12): Remotes.TravelToWorld(world) sends the player to that world's
-- Spawns/PlayerSpawn with the fade, if they have unlocked it (HighestWorld; the gates unlock worlds).
-- Returns (ok, reason): "unknown" no such world / no spawn yet, "locked", "busy" mid-teleport.
function PortalService.travel(player: Player, world: any): (boolean, string?)
	local def = if type(world) == "number" then Worlds.get(world) else nil
	if not def then
		return false, "unknown"
	end
	if world > deps.Services.PlayerDataService.highestWorld(player) then
		return false, "locked"
	end
	if (busy[player] or 0) > os.clock() then
		return false, "busy"
	end
	local root = workspace:FindFirstChild("Worlds")
	local folder = root and root:FindFirstChild(def.folder)
	local spawns = folder and folder:FindFirstChild("Spawns")
	local spawn = spawns and spawns:FindFirstChild("PlayerSpawn")
	if not (spawn and spawn:IsA("BasePart")) then
		return false, "unknown"
	end
	task.spawn(PortalService.send, player, spawn, { fade = true })
	return true, nil
end

function PortalService.start()
	fadeRemote = deps.Remotes.getEvent("TeleportFade")
	deps.Remotes.getFunction("TravelToWorld").OnServerInvoke = function(player: Player, world: any)
		return PortalService.travel(player, world)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		busy[player] = nil
		charging[player] = nil
	end)
	for _, zone in CollectionService:GetTagged(MapLayout.Tags.TeleportZone) do
		wirePrompt(zone)
	end
	CollectionService:GetInstanceAddedSignal(MapLayout.Tags.TeleportZone):Connect(wirePrompt)
	task.spawn(function()
		while true do
			poll()
			task.wait(POLL)
		end
	end)
end

return PortalService
