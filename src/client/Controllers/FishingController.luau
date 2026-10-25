--!strict
-- FishingController: the local player's fishing (2026-10-18, the user's design; rules and
-- numbers in Config/Fishing, the server's side in FishingService).
--
--   * Cast: with the rod out, a click plays the rod's two-handed Cast swing (an ordinary
--     WeaponController swing, so other players see it). At its "Hit" marker the bobber
--     (ReplicatedStorage/Assets/Fishing/Bobber) leaves the rod tip and flies
--     Fishing.castDistance ahead in an arc. Over water (a part tagged Fishing.Tag) it
--     splashes down and floats, and the server hears where; over land it thuds down,
--     "Cast into the water!" pops up and the line comes back in. Water whose spot needs a
--     better rod (Config/Fishing `tier`) is treated like land: it splashes and comes back, with
--     the wrong-tool hint at the splash (Util.ToolHint, 2026-10-25: "Needs a Stone Rod /
--     Upgrade it at the Weaponsmith", the rod's hotbar slot shaking in orange-red).
--   * The line is a Beam from the rod tip (the rod Grip's "Tip" attachment) to the
--     bobber's "Line" attachment, sagging while slack and pulled straight while a fish
--     fights. Both ends are attachments in Terrain, moved every frame, so the sag always
--     hangs down whatever the rod is doing.
--   * The wait: the server says when a fish comes ("Approach": the one dark FishShadow
--     model swims in under the water) and bites ("Bite": the bobber is pulled under,
--     with a splash and a "!"). While nothing bites, a click reels the line in.
--   * Hooked: a click while the bobber is under hooks the fish; FishingRingUI plays the
--     three closing rings the server starts, and every click is judged there.
--   * Caught: the rod yanks back (the Reel swing), the bobber comes home and the fish
--     leaps out of the water in an arc to just over the player's head, spins and pops.
--     The fish itself arrives as a material (the side toast). Escaped: "It got away!",
--     the shadow darts off and the line comes in.
-- Clicks with the rod out go through WeaponController.setClickFilter: only the cast
-- itself is a swing. Everything here is local; other players see the swings only.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Fishing = require(Shared:WaitForChild("Config"):WaitForChild("Fishing"))
local MapLayout = require(Shared:WaitForChild("Config"):WaitForChild("MapLayout"))
local Animation = require(Shared:WaitForChild("Animation"))
local Effects = Animation.Effects

local FishingController = {}

local player = Players.LocalPlayer
local deps: any = nil
local WeaponController: any = nil
local actionRemote: RemoteEvent? = nil

-- Look
local LINE_COLOR = Color3.fromRGB(245, 245, 240)
local LINE_WIDTH = 0.045
local FLOAT_BOB = 0.07 -- studs the bobber rides up and down while floating
local SINK_DEPTH = 1.0 -- how far a bite pulls it under
-- In the water the fish is the same model laid on its side and pressed flat (its side
-- profile, the shape on the minigame's icon) just on top of the surface: the pond water
-- is too opaque for a real fish under it to show. It gets its full shape back to leap out.
local SHADOW_FLAT = 0.08 -- its thickness, as a fraction of the model's
local SHADOW_LIFT = 0.1 -- studs over the surface
local SHADOW_ROLL = CFrame.Angles(0, 0, math.pi / 2)
local SHADOW_FROM = 7 -- studs away the fish starts its approach
-- solid: two see-through surfaces (the fish and the pond) sort badly and washed it out
local SHADOW_TRANSPARENCY = 0
local REEL_SECONDS = 0.35 -- the bobber flying back to the rod
local LEAP_SECONDS = 0.7 -- the caught fish's arc out of the water to the player
local LEAP_HEIGHT = 7
local SHOW_SECONDS = 0.7 -- it spins over the player's head this long, then pops
local POPUP_HEIGHT = 2.5

-- nil = no line out | "Flying" | "Waiting" | "Approach" | "Bite" | "Hooking" | "Ring" | "Landing" | "Reeling"
local phase: string? = nil

type Line = {
	bobber: Model,
	root: BasePart, -- the bobber's PrimaryPart
	tip: Attachment,
	tail: Attachment,
	beam: Beam,
	from: Vector3,
	to: Vector3,
	surface: number, -- the water's top under the bobber
	wet: boolean, -- landed on fishing water the rod can fish
	needs: number?, -- landed on water that needs a better rod: the rod tier it needs
	flyStart: number,
	mode: string, -- "fly" | "float" | "reel"
	depth: number, -- current depth under the float line (eased toward `sink`)
	sink: number,
	reelStart: number,
	reelFrom: Vector3,
}

type Shadow = {
	model: Model,
	from: Vector3,
	to: Vector3,
	start: number,
	seconds: number,
	mode: string, -- "swim" | "hold" | "flee" | "leap" | "show"
	fade: boolean,
}

local line: Line? = nil
local shadow: Shadow? = nil

local function assets(name: string): Instance?
	local folder = ReplicatedStorage:FindFirstChild("Assets")
	local fishing = folder and folder:FindFirstChild("Fishing")
	return fishing and fishing:FindFirstChild(name)
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Where the line leaves the rod: the Grip's "Tip" attachment, or 5 studs out along it.
local function tipPosition(): Vector3?
	local held = WeaponController.heldModel()
	local grip = held and held.PrimaryPart
	if not grip then
		local root = rootPart()
		return root and (root.Position + root.CFrame.LookVector * 2 + Vector3.new(0, 2, 0))
	end
	local tip = grip:FindFirstChild("Tip")
	if tip and tip:IsA("Attachment") then
		return tip.WorldPosition
	end
	return (grip.CFrame * CFrame.new(0, 0, -5)).Position
end

local function rodOut(): boolean
	local tool = WeaponController.tool()
	return tool ~= nil and tool.kind == "Rod"
end

local function popup(at: BasePart?, text: string)
	if at then
		deps.Util.DamagePopup.show(at, text, "Player", POPUP_HEIGHT)
	end
end

local function noCollide(model: Instance)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
end

-- ==================== the fish's shadow ====================

local function clearShadow()
	if shadow then
		shadow.model:Destroy()
		shadow = nil
	end
end

local function setShadowTransparency(model: Model, value: number)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = value
		end
	end
end

local function newShadow(): Model?
	local template = assets("FishShadow")
	if not (template and template:IsA("Model")) then
		return nil
	end
	local model = template:Clone()
	noCollide(model)
	setShadowTransparency(model, SHADOW_TRANSPARENCY)
	-- pressed flat across the model's X, which the roll stands upright
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part:SetAttribute("FullSize", part.Size)
			part.Size = Vector3.new(part.Size.X * SHADOW_FLAT, part.Size.Y, part.Size.Z)
		end
	end
	model.Parent = MapLayout.runtimeFolder()
	return model
end

-- The fish leaves the water: its full 3D shape, solid.
local function unflatten(model: Model)
	for _, part in model:GetDescendants() do
		local full = part:GetAttribute("FullSize")
		if part:IsA("BasePart") and typeof(full) == "Vector3" then
			part.Size = full
		end
	end
	setShadowTransparency(model, 0)
end

local function swimShadow(mode: string, to: Vector3, seconds: number)
	if not shadow then
		return
	end
	shadow.from = shadow.model:GetPivot().Position
	shadow.to = to
	shadow.start = os.clock()
	shadow.seconds = seconds
	shadow.mode = mode
end

-- ==================== the line ====================

local function clearLine()
	if line then
		line.bobber:Destroy()
		line.beam:Destroy()
		line.tip:Destroy()
		line.tail:Destroy()
		line = nil
	end
end

local function finishLocal()
	clearLine()
	clearShadow()
	phase = nil
	deps.UI.FishingRingUI.cancel()
end

local function send(payload: { [string]: any })
	if actionRemote then
		actionRemote:FireServer(payload)
	end
end

local function reelIn()
	if not line then
		phase = nil
		return
	end
	phase = "Reeling"
	line.mode = "reel"
	line.reelStart = os.clock()
	line.reelFrom = line.root.Position
end

-- The landing spot for a cast: the ground or water straight under a point the cast
-- distance ahead. Returns the point, whether it is fishing water, and its spot.
local function landingSpot(root: BasePart): (Vector3, boolean, Fishing.Spot?)
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local ahead = root.Position + flat * Fishing.castDistance
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Instance, MapLayout.runtimeFolder() }
	local hit = workspace:Raycast(ahead + Vector3.new(0, 12, 0), Vector3.new(0, -40, 0), params)
	if not hit then
		return ahead - Vector3.new(0, 3, 0), false, nil
	end
	local wet = CollectionService:HasTag(hit.Instance, Fishing.Tag)
	return hit.Position, wet, if wet then Fishing.spot(hit.Instance:GetAttribute("Spot")) else nil
end

local function launch()
	local root = rootPart()
	local template = assets("Bobber")
	local from = tipPosition()
	if not (root and from and template and template:IsA("Model") and template.PrimaryPart) then
		warn("[FishingController] missing ReplicatedStorage/Assets/Fishing/Bobber")
		return
	end
	clearLine()
	clearShadow()
	local to, wet, spot = landingSpot(root)
	-- a rod only fishes its own world's water or older
	local needs: number? = nil -- the rod tier this water needs, when the one in hand is too weak
	local rod = WeaponController.tool()
	if wet and spot and rod and (rod.tier or 1) < (spot.tier or 1) then
		wet = false
		needs = spot.tier or 1
	end
	local bobber = template:Clone()
	noCollide(bobber)
	bobber:PivotTo(CFrame.new(from))
	bobber.Parent = MapLayout.runtimeFolder()

	local tip = Instance.new("Attachment")
	tip.Name = "FishingTip"
	tip.Parent = workspace.Terrain
	local tail = Instance.new("Attachment")
	tail.Name = "FishingTail"
	tail.Parent = workspace.Terrain
	local beam = Instance.new("Beam")
	beam.Name = "FishingLine"
	beam.Attachment0 = tip
	beam.Attachment1 = tail
	beam.Color = ColorSequence.new(LINE_COLOR)
	beam.Width0 = LINE_WIDTH
	beam.Width1 = LINE_WIDTH
	beam.Segments = 12
	beam.FaceCamera = true
	beam.LightInfluence = 0.6
	beam.Transparency = NumberSequence.new(0.1)
	beam.Parent = workspace.Terrain

	line = {
		bobber = bobber,
		root = bobber.PrimaryPart :: BasePart,
		tip = tip,
		tail = tail,
		beam = beam,
		from = from,
		to = to,
		surface = to.Y,
		wet = wet,
		needs = needs,
		flyStart = os.clock(),
		mode = "fly",
		depth = 0,
		sink = 0,
		reelStart = 0,
		reelFrom = from,
	}
	phase = "Flying"
	if wet then
		send({ action = "cast", at = to })
	end
end

local function landed(current: Line)
	current.mode = "float"
	if current.wet then
		Effects.burst(current.to, "Splash")
		Effects.shockwave(current.to + Vector3.new(0, 0.05, 0), "Shockwave", { color = Color3.fromRGB(230, 245, 255), endSize = 4 })
		if phase == "Flying" then
			phase = "Waiting"
		end
	else
		if current.needs then
			-- water this rod can't fish: it splashes, the hint pops there, the line comes back in
			Effects.burst(current.to, "Splash")
			deps.Util.ToolHint.show(current.to + Vector3.new(0, 1.5, 0), "Rod", current.needs)
		else
			Effects.burst(current.to, "Dust", { count = 5 })
			popup(rootPart(), "Cast into the water!")
		end
		task.delay(0.5, function()
			if line == current then
				reelIn()
			end
		end)
	end
end

-- ==================== each frame ====================

local function bobberLine(current: Line): Vector3
	local tail = current.bobber:FindFirstChild("Line", true)
	return if tail and tail:IsA("Attachment") then tail.WorldPosition else current.root.Position + Vector3.new(0, 0.6, 0)
end

local function step(dt: number, now: number)
	local current = line
	if current then
		local pos: Vector3
		if current.mode == "fly" then
			local t = math.clamp((now - current.flyStart) / Fishing.flightSeconds, 0, 1)
			pos = current.from:Lerp(current.to, t) + Vector3.new(0, Fishing.castHeight * 4 * t * (1 - t), 0)
			if t >= 1 then
				landed(current)
			end
		elseif current.mode == "reel" then
			local t = math.clamp((now - current.reelStart) / REEL_SECONDS, 0, 1)
			local home = tipPosition() or current.reelFrom
			pos = current.reelFrom:Lerp(home, t) + Vector3.new(0, 2 * t * (1 - t), 0)
			if t >= 1 then
				clearLine()
				if phase == "Reeling" then
					phase = nil
				end
				current = nil
			end
		else
			-- floating: ride the water, eased toward the sink depth a bite pulls it to
			current.depth += (current.sink - current.depth) * math.min(1, dt * 9)
			local bob = if current.sink > 0 then 0 else math.sin(now * 2.4) * FLOAT_BOB
			-- a fish on the line tugs it about
			local tug = if phase == "Ring" then Vector3.new(math.sin(now * 13) * 0.18, 0, math.cos(now * 11) * 0.18) else Vector3.zero
			pos = Vector3.new(current.to.X, current.surface + bob - current.depth, current.to.Z) + tug
		end
		if current then
			current.bobber:PivotTo(CFrame.new(pos))
			local tip = tipPosition() or pos
			local tail = bobberLine(current)
			-- slack while waiting, pulled straight while flying in or fighting a fish
			local span = (tail - tip).Magnitude
			local sag = if current.mode == "float" and phase ~= "Ring" and phase ~= "Hooking" then math.min(span * 0.22, 4) else 0.15
			current.tip.WorldCFrame = CFrame.fromMatrix(tip, Vector3.new(0, -1, 0), Vector3.new(1, 0, 0))
			current.tail.WorldCFrame = CFrame.fromMatrix(tail, Vector3.new(0, 1, 0), Vector3.new(1, 0, 0))
			current.beam.CurveSize0 = sag
			current.beam.CurveSize1 = sag * 0.6
		end
	end

	local fish = shadow
	if fish then
		local t = math.clamp((now - fish.start) / math.max(fish.seconds, 1e-3), 0, 1)
		local cf: CFrame
		if fish.mode == "leap" then
			local pos = fish.from:Lerp(fish.to, t) + Vector3.new(0, LEAP_HEIGHT * 4 * t * (1 - t), 0)
			-- nose up out of the water, over the top, nose down at the end
			local heading = Vector3.new(fish.to.X - fish.from.X, 0, fish.to.Z - fish.from.Z)
			heading = if heading.Magnitude > 1e-3 then heading.Unit else Vector3.new(0, 0, -1)
			cf = CFrame.lookAt(pos, pos + heading) * CFrame.Angles(math.rad(70 - 140 * t), 0, math.rad(360 * t))
			if t >= 1 then
				fish.mode = "show"
				fish.start = now
				fish.seconds = SHOW_SECONDS
				fish.from = fish.to
			end
		elseif fish.mode == "show" then
			local root = rootPart()
			local over = if root then root.Position + Vector3.new(0, 4.2, 0) else fish.to
			cf = CFrame.new(over + Vector3.new(0, math.sin(t * math.pi) * 0.4, 0)) * CFrame.Angles(0, t * math.pi * 3, math.rad(-12))
			if t >= 1 then
				Effects.burst(over, "DeathPop", { count = 12 })
				clearShadow()
				if phase == "Landing" then
					phase = nil
				end
				return
			end
		else
			local ease = t * t * (3 - 2 * t)
			local pos = fish.from:Lerp(fish.to, if fish.mode == "flee" then t else ease)
			local heading = fish.to - fish.from
			heading = Vector3.new(heading.X, 0, heading.Z)
			if heading.Magnitude < 1e-3 then
				heading = fish.model:GetPivot().LookVector
			end
			-- a lazy swim wiggle, a thrash while hooked
			local wiggle = if phase == "Ring" or phase == "Hooking" then math.sin(now * 18) * 0.5 else math.sin(now * 6) * 0.18
			cf = CFrame.lookAt(pos, pos + heading.Unit) * CFrame.Angles(0, wiggle, 0) * SHADOW_ROLL
			if fish.mode == "flee" then
				setShadowTransparency(fish.model, SHADOW_TRANSPARENCY + (1 - SHADOW_TRANSPARENCY) * t)
				if t >= 1 then
					clearShadow()
					return
				end
			end
		end
		fish.model:PivotTo(cf)
	end
end

-- ==================== the server ====================

local function under(current: Line): Vector3
	return Vector3.new(current.to.X, current.surface + SHADOW_LIFT, current.to.Z)
end

-- A point `distance` from `centre` that is over open fishing water (nothing on top of
-- it), so the fish never swims in from under a bank; nearer in if no direction is clear.
local function openWaterNear(centre: Vector3, distance: number): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Instance, MapLayout.runtimeFolder() }
	for _, reach in { distance, distance * 0.6, distance * 0.35 } do
		local turn = math.random() * math.pi * 2
		for i = 0, 7 do
			local angle = turn + i * math.pi / 4
			local point = centre + Vector3.new(math.cos(angle), 0, math.sin(angle)) * reach
			local hit = workspace:Raycast(point + Vector3.new(0, 12, 0), Vector3.new(0, -14, 0), params)
			if hit and CollectionService:HasTag(hit.Instance, Fishing.Tag) then
				return point
			end
		end
	end
	return centre
end

local function onState(message: any)
	if type(message) ~= "table" then
		return
	end
	local state = message.state
	local current = line
	if state == "Approach" and current then
		phase = "Approach"
		clearShadow()
		local model = newShadow()
		if model then
			local start = openWaterNear(under(current), SHADOW_FROM)
			model:PivotTo(CFrame.new(start))
			shadow = { model = model, from = start, to = under(current), start = os.clock(), seconds = message.seconds or 1.5, mode = "swim", fade = false }
		end
	elseif state == "Bite" and current then
		phase = "Bite"
		current.sink = SINK_DEPTH
		Effects.burst(current.to, "Splash", { count = 8 })
		popup(current.root, "!")
	elseif state == "Surface" and current then
		phase = "Waiting"
		current.sink = 0
		if shadow then
			local away = shadow.model:GetPivot().LookVector * -SHADOW_FROM
			swimShadow("flee", under(current) + Vector3.new(away.X, 0, away.Z), 1.0)
		end
	elseif state == "Ring" and current then
		if phase ~= "Ring" then
			-- hooked: the bobber pops back up and the fight starts
			current.sink = 0.25
			Effects.burst(current.to, "Splash", { count = 10 })
			deps.UI.FishingRingUI.begin(message.of or Fishing.rings, current.root)
		end
		phase = "Ring"
		deps.UI.FishingRingUI.ring(message.n, message.delay or 0, message.closeSeconds, message.zone)
	elseif state == "Caught" then
		deps.UI.FishingRingUI.finish(true)
		phase = "Landing"
		WeaponController.playExtra("Reel", 0.8, 0.45)
		local root = rootPart()
		if current then
			Effects.burst(current.to, "Splash", { count = 16 })
			if not shadow then
				local model = newShadow()
				if model then
					shadow = { model = model, from = under(current), to = under(current), start = 0, seconds = 1, mode = "hold", fade = false }
				end
			end
			if shadow then
				-- out of the water it is the whole dark fish, solid
				unflatten(shadow.model)
				shadow.from = Vector3.new(current.to.X, current.surface, current.to.Z)
				shadow.to = if root then root.Position + Vector3.new(0, 4.2, 0) else shadow.from
				shadow.start = os.clock()
				shadow.seconds = LEAP_SECONDS
				shadow.mode = "leap"
			end
			reelIn()
			-- the leap clears "Landing" when it ends; with no fish model the reel does
			phase = if shadow then "Landing" else "Reeling"
		end
	elseif state == "Escaped" then
		deps.UI.FishingRingUI.finish(false)
		if current then
			phase = "Reeling"
			popup(current.root, "It got away!")
			if shadow then
				local away = (under(current) - (rootPart() and (rootPart() :: BasePart).Position or under(current)))
				away = Vector3.new(away.X, 0, away.Z)
				away = if away.Magnitude > 1e-3 then away.Unit * SHADOW_FROM else Vector3.new(SHADOW_FROM, 0, 0)
				swimShadow("flee", under(current) + away, 0.8)
			end
			task.delay(0.5, function()
				if line == current then
					reelIn()
				end
			end)
		else
			phase = nil
		end
	elseif state == "Reeled" then
		deps.UI.FishingRingUI.cancel()
		if phase ~= "Landing" then
			if shadow and current then
				swimShadow("flee", under(current) + Vector3.new(SHADOW_FROM, 0, 0), 0.8)
			end
			reelIn()
		end
	end
end

-- ==================== clicks ====================

-- Clicks with the rod out: only a click with no line out becomes a swing (the cast).
local function filter(def: any): boolean
	if def.kind ~= "Rod" then
		return false
	end
	if phase == nil then
		return false
	end
	if phase == "Bite" then
		phase = "Hooking"
		send({ action = "hook" })
	elseif phase == "Ring" then
		local n, ok = deps.UI.FishingRingUI.click()
		if n then
			send({ action = "ring", n = n, ok = ok })
		end
	elseif phase == "Waiting" or phase == "Approach" then
		send({ action = "reel" })
		if shadow and line then
			swimShadow("flee", under(line) + Vector3.new(0, 0, SHADOW_FROM), 0.8)
		end
		reelIn()
	end
	return true
end

-- ==================== lifecycle ====================

function FishingController.init(injected: any)
	deps = injected
	WeaponController = deps.Controllers.WeaponController
	actionRemote = deps.Remotes.getEvent("FishAction")
end

function FishingController.start()
	WeaponController.setClickFilter(filter)
	WeaponController.onSwingLanded(function(_root: BasePart, def: any)
		if def.kind == "Rod" and phase == nil then
			launch()
		end
	end)
	-- a ring that closed with no click is a miss
	deps.UI.FishingRingUI.onClosed(function(n: number)
		if phase == "Ring" then
			send({ action = "ring", n = n, ok = false })
		end
	end)
	-- the rod put away (or a respawn): the line goes
	WeaponController.onChanged(function()
		if phase ~= nil and phase ~= "Landing" and not rodOut() then
			finishLocal()
		end
	end)
	player.CharacterAdded:Connect(finishLocal)
	deps.Remotes.getEvent("FishState").OnClientEvent:Connect(onState)
	Animation.Scheduler.bind("Render", "Fishing", 40, step)
end

return FishingController
