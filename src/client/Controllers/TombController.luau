--!strict
-- TombController: World 4's secret tomb on this client (2026-10-29; Config/Tomb has the design and the
-- trap attributes, TombService the hits). Everything here is looks; the server judges.
--   * the traps, from the server clock (the same formulas TombService uses): spikes rattle then shoot
--     up, axes swing, buzzsaws spin back and forth in their slots, jackal heads glow then breathe fire,
--     the boulder rolls down the tunnel, and a dart wall fires a volley at its FiredAt (set by the
--     server when its plate is stepped on or on its beat)
--   * a cracked tile you stand on crumbles under you (only on your screen) as the server sends you back
--   * the quicksand: standing in it you sink, until the server's fade carries you into the tomb
--   * the shortcut tablet at the landing: sunk in the sand unless you've reached the burial chamber
--     (Tomb.FOUND_ATTR); then it rises as you land and its prompt works
-- One Scheduler system (Render), only while the camera is near the tomb or the quicksand.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tomb = require(Shared:WaitForChild("Config"):WaitForChild("Tomb"))
local Animation = require(Shared:WaitForChild("Animation"))
local Effects = Animation.Effects

local TombController = {}

local NEAR = 420 -- run only while the camera is this close to the tomb's middle
local SPIKE_DOWN = -2.4 -- spikes' offset when hidden in the floor
local SPIKE_PEEK = -1.55 -- rattling, the tips just showing
local SPIKE_SPEED_UP, SPIKE_SPEED_DOWN = 30, 9
local SINK_AFTER = 3 -- seconds standing in the quicksand before you start to sink (the user, 2026-10-29)
local SINK_SPEED, SINK_DEPTH = 1.3, 3.2
local RISE_SECONDS, RISE_NEAR = 1.2, 40
local CRUMBLE_SECONDS = 3

local player = Players.LocalPlayer

type Trap = { model: Model, kind: string, state: any }
local traps: { Trap } = {}
local centre: Vector3? = nil
local quicksand: BasePart? = nil
local tablet: Model? = nil
local tabletUp: CFrame? = nil
local tabletRise = 0 -- 0 sunk .. 1 risen
local sinking: { since: number, depth: number, anchored: boolean, root: BasePart? }? = nil
local tileFoot: { tile: BasePart, since: number }? = nil

local function setHidden(part: BasePart, hidden: boolean)
	local v = if hidden then 1 else 0
	part.LocalTransparencyModifier = v
	for _, d in part:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = v
		end
	end
end

local function adopt(model: Instance)
	if not (model:IsA("Model") and model:IsDescendantOf(Workspace)) then
		return
	end
	local kind = model:GetAttribute("Kind")
	if type(kind) ~= "string" then
		return
	end
	local trap: Trap = { model = model, kind = kind, state = {} }
	if kind == "Spikes" then
		local spikes = model:FindFirstChild("Spikes") :: Model?
		trap.state = { spikes = spikes, rest = spikes and spikes:GetPivot(), offset = 0 }
	elseif kind == "Blade" then
		-- every piece of the axe swings about the pivot
		local pivot = model:FindFirstChild("Pivot") :: BasePart?
		local axe = model:FindFirstChild("Axe")
		local rel = {}
		if pivot and axe then
			for _, p in axe:GetDescendants() do
				if p:IsA("BasePart") then
					table.insert(rel, { part = p, rel = pivot.CFrame:ToObjectSpace(p.CFrame) })
				end
			end
		end
		trap.state = { rel = rel }
	elseif kind == "Saw" then
		local pivot = model:FindFirstChild("Pivot") :: BasePart?
		local saw = model:FindFirstChild("Saw") :: Model?
		trap.state = { saw = saw, base = pivot and saw and pivot.CFrame:ToObjectSpace(saw:GetPivot()), pivot = pivot }
	elseif kind == "Fire" then
		trap.state = { on = nil, warn = nil }
	elseif kind == "Boulder" then
		trap.state = { ball = model:FindFirstChild("Ball") }
	elseif kind == "Darts" then
		model:GetAttributeChangedSignal("FiredAt"):Connect(function()
			local at = model:GetAttribute("FiredAt")
			if type(at) ~= "number" then
				return
			end
			local plate = model:FindFirstChild("Plate") :: BasePart?
			if plate then
				local rest = plate.CFrame
				plate.CFrame = rest * CFrame.new(0, -0.12, 0)
				task.delay(0.5, function()
					plate.CFrame = rest
				end)
			end
			task.delay(math.max(0, at - Workspace:GetServerTimeNow()), function()
				local zone = model:FindFirstChild("Zone") :: BasePart?
				local side = Tomb.num(model, "Side", 1)
				if not zone then
					return
				end
				local dir = zone.CFrame.RightVector * -side
				local assets = ReplicatedStorage:FindFirstChild("Assets")
				local effects = assets and assets:FindFirstChild("Effects")
				local template = effects and effects:FindFirstChild("TombDart")
				for _, hole in model:GetDescendants() do
					if hole.Name == "Hole" and hole:IsA("BasePart") then
						local from = hole.Position + dir * 0.4
						local dart: Instance
						if template and template:IsA("Model") then
							local copy = template:Clone()
							dart = copy
						else
							local part = Instance.new("Part")
							part.Size = Vector3.new(0.14, 0.14, 1.1)
							part.Color = Color3.fromRGB(58, 40, 26)
							part.Material = Enum.Material.SmoothPlastic
							part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
							dart = part
						end
						dart.Name = "Dart"
						local at = Instance.new("CFrameValue")
						at.Value = CFrame.lookAt(from, from + dir)
						local function place()
							if dart:IsA("Model") then
								dart:PivotTo(at.Value)
							elseif dart:IsA("BasePart") then
								dart.CFrame = at.Value
							end
						end
						place()
						at.Changed:Connect(place)
						dart.Parent = Workspace
						local tween = TweenService:Create(at, TweenInfo.new(0.24, Enum.EasingStyle.Linear), { Value = CFrame.lookAt(from + dir * 7.4, from + dir * 8.4) })
						tween:Play()
						tween.Completed:Connect(function()
							dart:Destroy()
							at:Destroy()
						end)
					end
				end
			end)
		end)
	end
	table.insert(traps, trap)
end

local function stepTrap(trap: Trap, t: number, dt: number)
	local model, s = trap.model, trap.state
	if trap.kind == "Spikes" then
		if not (s.spikes and s.rest) then
			return
		end
		local target = SPIKE_DOWN
		if Tomb.active(model, t) then
			target = 0
		elseif Tomb.warning(model, t) then
			target = SPIKE_PEEK + 0.08 * math.sin(t * 55)
		end
		local speed = if target > s.offset then SPIKE_SPEED_UP else SPIKE_SPEED_DOWN
		local offset = s.offset + math.clamp(target - s.offset, -speed * dt, speed * dt)
		if math.abs(offset - s.offset) > 1e-3 then
			s.offset = offset
			s.spikes:PivotTo(s.rest * CFrame.new(0, offset, 0))
		end
	elseif trap.kind == "Blade" then
		local pivot = Tomb.bladePivot(model, t)
		if pivot then
			for _, r in s.rel do
				r.part.CFrame = pivot * r.rel
			end
		end
	elseif trap.kind == "Saw" then
		local saw, base, pivot = s.saw :: Model?, s.base :: CFrame?, s.pivot :: BasePart?
		if saw and base and pivot then
			local x, spin = Tomb.saw(model, t)
			-- the blade's middle is 0.3 over the slot; it spins about its own Z
			saw:PivotTo(pivot.CFrame * CFrame.new(x, 0, 0) * base * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, -spin) * CFrame.new(0, -0.3, 0))
		end
	elseif trap.kind == "Fire" then
		local on, warn = Tomb.active(model, t), Tomb.warning(model, t)
		if on ~= s.on then
			s.on = on
			for _, name in { "Flame", "FlameCore" } do
				local p = model:FindFirstChild(name)
				if p and p:IsA("BasePart") then
					p.Transparency = if on then (if name == "Flame" then 0.25 else 0.05) else 1
				end
			end
		end
		local glow = on or warn
		if glow ~= s.warn then
			s.warn = glow
			local eyes = model:FindFirstChild("Eyes", true)
			if eyes and eyes:IsA("BasePart") then
				eyes.Color = if glow then Color3.fromRGB(255, 70, 40) else Color3.fromRGB(255, 179, 71)
			end
		end
	elseif trap.kind == "Boulder" then
		local ball = s.ball :: BasePart?
		if not ball then
			return
		end
		local rolling, pos, u, dist = Tomb.boulder(model, t)
		if not rolling then
			ball.Transparency = 1
			return
		end
		local start, finish = model:FindFirstChild("Start") :: BasePart?, model:FindFirstChild("End") :: BasePart?
		local axis = if start and finish then (finish.Position - start.Position).Unit else Vector3.xAxis
		local side = axis:Cross(Vector3.yAxis)
		local r = ball.Size.Y / 2
		ball.CFrame = CFrame.new(pos) * CFrame.fromAxisAngle(side, -dist / r)
		ball.Transparency = math.clamp(1 - math.min(u, 1 - u) / 0.06, 0, 1)
	end
end

-- a cracked tile under the local player crumbles once they've stood on it long enough
local function stepTiles(root: BasePart)
	local pos = root.Position
	local found: BasePart? = nil
	local hold = 0.3
	for _, trap in traps do
		if trap.kind == "Collapse" then
			for _, tile in trap.model:GetChildren() do
				if tile.Name == "Cracked" and tile:IsA("BasePart") and tile.LocalTransparencyModifier < 1 and Tomb.over(tile, pos, 4.5, 0.15) then
					found = tile
					hold = Tomb.num(trap.model, "Hold", 0.3)
					break
				end
			end
		end
		if found then
			break
		end
	end
	if not found then
		tileFoot = nil
		return
	end
	if not tileFoot or tileFoot.tile ~= found then
		tileFoot = { tile = found, since = os.clock() }
	elseif os.clock() - tileFoot.since >= hold then
		local tile = found
		tileFoot = nil
		setHidden(tile, true)
		Effects.burst(tile.Position, "Dust", { count = 10 })
		task.delay(CRUMBLE_SECONDS, function()
			setHidden(tile, false)
		end)
	end
end

-- the quicksand: stand in it SINK_AFTER seconds (stepping off before then resets it) and you start to sink
-- (anchored on this client only, so there's no getting out), with sand puffing round you (the zone's
-- "SinkFx" emitters, on this client); the server's charge zone (ChargeSeconds = SINK_AFTER + the sink)
-- teleports you as you go under
local function inQuicksand(zone: BasePart, root: BasePart): boolean
	local p = zone.CFrame:PointToObjectSpace(root.Position)
	return Vector2.new(p.X, p.Z).Magnitude <= zone.Size.X / 2 and math.abs(p.Y) <= zone.Size.Y / 2
end

local function sinkFx(zone: BasePart, on: boolean)
	for _, d in zone:GetDescendants() do
		if d:IsA("ParticleEmitter") and d.Name == "SinkFx" then
			d.Enabled = on
		end
	end
end

local function stepQuicksand(root: BasePart, dt: number)
	local zone = quicksand
	if not zone then
		return
	end
	local s = sinking
	if s then
		if s.root ~= root or (root.Position - zone.Position).Magnitude > 30 or os.clock() - s.since > SINK_AFTER + 8 then
			-- teleported (or gave up): let the body go
			if s.root and s.anchored then
				s.root.Anchored = false
			end
			sinkFx(zone, false)
			sinking = nil
			return
		end
		if not s.anchored then
			if not inQuicksand(zone, root) then
				sinking = nil -- stepped off in time
				return
			end
			if os.clock() - s.since < SINK_AFTER then
				return
			end
			s.anchored = true
			root.Anchored = true
			sinkFx(zone, true)
		end
		if s.depth < SINK_DEPTH then
			local step = math.min(SINK_SPEED * dt, SINK_DEPTH - s.depth)
			s.depth += step
			root.CFrame = root.CFrame - Vector3.new(0, step, 0)
		end
		return
	end
	if inQuicksand(zone, root) then
		sinking = { since = os.clock(), depth = 0, anchored = false, root = root }
	end
end

local function stepTablet(root: BasePart?, dt: number)
	local t = tablet
	local up = tabletUp
	if not (t and up) then
		return
	end
	local found = player:GetAttribute(Tomb.FOUND_ATTR) == true
	local near = root ~= nil and (root.Position - up.Position).Magnitude <= RISE_NEAR
	local target = if found and near then 1 else 0
	if target == 0 and not near then
		tabletRise = 0
	end
	if tabletRise ~= target then
		tabletRise = math.clamp(tabletRise + (if target > tabletRise then dt / RISE_SECONDS else -dt / RISE_SECONDS), 0, 1)
	end
	local sink = Tomb.num(t, "Sink", 4.2)
	local eased = 1 - (1 - tabletRise) ^ 3
	t:PivotTo(up * CFrame.new(0, -sink * (1 - eased), 0))
	local prompt = t:FindFirstChild("Prompt", true)
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = found and tabletRise >= 1
	end
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and quicksand and ((root.Position - quicksand.Position).Magnitude < 20 or sinking) then
		stepQuicksand(root, dt)
	end
	if not (centre and camera) or (camera.CFrame.Position - centre).Magnitude > NEAR then
		return
	end
	local t = Workspace:GetServerTimeNow()
	for _, trap in traps do
		stepTrap(trap, t, dt)
	end
	if root then
		stepTiles(root)
	end
	stepTablet(root, dt)
end

function TombController.init(_deps: any) end

function TombController.start()
	local worlds = Workspace:WaitForChild("Worlds", 30)
	local w4 = worlds and worlds:WaitForChild("W04_ScorchingSands", 30)
	local structures = w4 and w4:WaitForChild("Structures", 30)
	local tomb = structures and structures:WaitForChild("SecretTomb", 30)
	if not tomb then
		return
	end
	local ground = w4 and w4:FindFirstChild("Ground")
	local shell = ground and ground:FindFirstChild("SecretTomb")
	if shell then
		local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, part in shell:GetDescendants() do
			if part:IsA("BasePart") then
				lo = lo:Min(part.Position - part.Size / 2)
				hi = hi:Max(part.Position + part.Size / 2)
			end
		end
		centre = (lo + hi) / 2
	end
	quicksand = tomb:FindFirstChild("QuicksandZone", true) :: BasePart?
	local tab = tomb:FindFirstChild("ShortcutTablet", true)
	if tab and tab:IsA("Model") then
		tablet = tab
		tabletUp = tab:GetPivot()
		tab:PivotTo(tab:GetPivot() * CFrame.new(0, -Tomb.num(tab, "Sink", 4.2), 0))
		local prompt = tab:FindFirstChild("Prompt", true)
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = false
		end
	end
	for _, model in CollectionService:GetTagged(Tomb.TRAP_TAG) do
		adopt(model)
	end
	CollectionService:GetInstanceAddedSignal(Tomb.TRAP_TAG):Connect(adopt)
	Animation.Scheduler.bind("Render", "TombController", 30, step)
end

return TombController
