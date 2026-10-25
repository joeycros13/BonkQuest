--!strict
-- FishingController: the local player's fishing (2026-10-18, the user's design; rules and
-- numbers in Config/Fishing, the server's side in FishingService). Reworked for issue 26
-- (2026-10-25, the user: it was "very boring"): the reel bar, a struggle, a swimming fish.
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
--     bobber's "Line" attachment, sagging while slack and pulled straight and trembling
--     while a fish fights. Both ends are attachments in Terrain, moved every frame, so the
--     sag always hangs down whatever the rod is doing.
--   * The fish (one dark FishShadow model for every fish, the user's rule; a rarer fish is
--     a bigger shadow, the server's "Approach" `size`): it swims in on a curve that spirals
--     round the bobber, speeding and slowing in little darts, its tail swinging side to side
--     (the body turns about a point near its head) and ripples spreading behind it. Then it
--     nibbles (the server's `nibbles`): pokes the bobber, which dips with a ripple. Then
--     "Bite": the bobber is yanked under with a splash and "BITE!" pops at it
--     (Util.BonkPop.bite). While nothing bites, a click reels the line in.
--   * Hooked: a click while the bobber is under hooks the fish; the server starts the
--     fight ("Fight") and FishingBarUI shows the reel bar. Each click is judged there
--     (with the server time it was made at) and sent; a check heaves the rod (the Heave
--     swing) and drags the bobber a little closer, a miss lurches the player forward
--     (Lurch). In between the player struggles (the Struggle swing on a loop), the line is
--     tight and trembles, the fish thrashes and the camera eases in a little
--     (CameraFX "Fishing"; never a shake).
--   * Caught: the rod yanks back (the Reel swing), the bobber comes home and the fish
--     leaps out of the water in an arc to just over the player's head, spins and pops,
--     with "CAUGHT!" and its name (Util.BonkPop.caught). The fish itself arrives as a
--     material (the side toast). Escaped: the line snaps, the shadow darts off.
-- Clicks with the rod out go through WeaponController.setClickFilter: only the cast
-- itself is a swing. Everything here is local; other players see the swings only.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Fishing = require(Shared:WaitForChild("Config"):WaitForChild("Fishing"))
local Materials = require(Shared:WaitForChild("Config"):WaitForChild("Materials"))
local MapLayout = require(Shared:WaitForChild("Config"):WaitForChild("MapLayout"))
local Animation = require(Shared:WaitForChild("Animation"))
local Effects = Animation.Effects
local CameraFX = Animation.CameraFX

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
local NIBBLE_DEPTH = 0.35 -- how far a nibble dips it
local NIBBLE_POKE = 0.6 -- studs the fish darts forward on a nibble
local NIBBLE_POKE_SECONDS = 0.28
-- In the water the fish is the same model laid on its side and pressed flat (its side
-- profile, the shape on the minigame's icon) just on top of the surface: the pond water
-- is too opaque for a real fish under it to show. It gets its full shape back to leap out.
local SHADOW_FLAT = 0.08 -- its thickness, as a fraction of the model's
local SHADOW_LIFT = 0.1 -- studs over the surface
local SHADOW_ROLL = CFrame.Angles(0, 0, math.pi / 2)
local SHADOW_FROM = 7 -- studs away the fish starts its approach
local SPIRAL_TURN = math.pi * 1.25 -- how far round the bobber it swims on the way in
local SWIM_WAG = 0.32 -- radians the tail swings each way while swimming
local SWIM_WAG_RATE = 9 -- radians a second of the swing
local SWIM_PIVOT = 0.35 -- the body turns about a point this far ahead of its middle (x length)
local WAKE_EVERY = 0.4 -- seconds between ripples behind a swimming fish
-- solid: two see-through surfaces (the fish and the pond) sort badly and washed it out
local SHADOW_TRANSPARENCY = 0
local REEL_SECONDS = 0.35 -- the bobber flying back to the rod
local LEAP_SECONDS = 0.7 -- the caught fish's arc out of the water to the player
local LEAP_HEIGHT = 7
local SHOW_SECONDS = 0.7 -- it spins over the player's head this long, then pops
local POPUP_HEIGHT = 2.5
-- the fight
local STRUGGLE_SECONDS = 1.3 -- one loop of the Struggle swing
local HEAVE_SECONDS = 0.45
local LURCH_SECONDS = 0.5
local PULL_PER_CHECK = 1.6 -- studs each check drags the bobber toward the player
local FIGHT_ZOOM = -6 -- FOV offset while fighting (a small push in)

-- nil = no line out | "Flying" | "Waiting" | "Approach" | "Bite" | "Hooking" | "Fight" | "Landing" | "Reeling"
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
	dipUntil: number, -- a nibble holds the bobber dipped until then
	pull: number, -- studs dragged toward the player in the fight (eased toward pullTo)
	pullTo: number,
	reelStart: number,
	reelFrom: Vector3,
}

type Shadow = {
	model: Model,
	length: number, -- the fish's length in studs
	from: Vector3,
	to: Vector3,
	start: number,
	seconds: number,
	mode: string, -- "spiral" | "hold" | "fight" | "flee" | "leap" | "show"
	angle: number, -- spiral: the start angle round the bobber
	radius: number, -- spiral: the start distance
	poke: number, -- os.clock() of the last nibble
	wake: number, -- os.clock() of the last ripple
	fish: string?, -- the caught fish's id, for the CAUGHT! pop
}

local line: Line? = nil
local shadow: Shadow? = nil
local nextStruggle = 0

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

local function ripple(at: Vector3, size: number)
	Effects.shockwave(at + Vector3.new(0, 0.05, 0), "Shockwave", { color = Color3.fromRGB(230, 245, 255), endSize = size, transparency = 0.55 })
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

-- A new shadow, `size` times the model (a rarer fish is bigger), and its length.
local function newShadow(size: number?): (Model?, number)
	local template = assets("FishShadow")
	if not (template and template:IsA("Model")) then
		return nil, 2
	end
	local model = template:Clone()
	noCollide(model)
	setShadowTransparency(model, SHADOW_TRANSPARENCY)
	if size and size ~= 1 then
		model:ScaleTo(size)
	end
	local extents = model:GetExtentsSize()
	local length = math.max(extents.X, extents.Y, extents.Z)
	-- pressed flat across the model's X, which the roll stands upright
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part:SetAttribute("FullSize", part.Size)
			part.Size = Vector3.new(part.Size.X * SHADOW_FLAT, part.Size.Y, part.Size.Z)
		end
	end
	model.Parent = MapLayout.runtimeFolder()
	return model, length
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

local function endFight()
	CameraFX.release("Fishing")
	deps.UI.FishingBarUI.cancel()
end

local function finishLocal()
	clearLine()
	clearShadow()
	phase = nil
	endFight()
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
		dipUntil = 0,
		pull = 0,
		pullTo = 0,
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
		ripple(current.to, 4)
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
			local rod = WeaponController.tool()
			deps.Util.ToolHint.castHere(current.to + Vector3.new(0, 1.5, 0), rod and rod.icon)
		end
		task.delay(0.5, function()
			if line == current then
				reelIn()
			end
		end)
	end
end

-- Where the bobber floats now (the fight drags it toward the player).
local function floatPoint(current: Line): Vector3
	local root = rootPart()
	local spot = Vector3.new(current.to.X, current.surface, current.to.Z)
	if root and current.pull > 0 then
		local toward = Vector3.new(root.Position.X - spot.X, 0, root.Position.Z - spot.Z)
		if toward.Magnitude > 1e-3 then
			spot += toward.Unit * math.min(current.pull, toward.Magnitude - 3)
		end
	end
	return spot
end

-- The point on the water under the bobber, where the fish noses in.
local function under(current: Line): Vector3
	return floatPoint(current) + Vector3.new(0, SHADOW_LIFT, 0)
end

-- ==================== each frame ====================

local function bobberLine(current: Line): Vector3
	local tail = current.bobber:FindFirstChild("Line", true)
	return if tail and tail:IsA("Attachment") then tail.WorldPosition else current.root.Position + Vector3.new(0, 0.6, 0)
end

-- A swimming fish's CFrame: facing `heading`, its tail swinging (the body turns about a
-- point near its head, so the tail moves most).
local function swimFrame(fish: Shadow, pos: Vector3, heading: Vector3, wag: number): CFrame
	local flat = Vector3.new(heading.X, 0, heading.Z)
	if flat.Magnitude < 1e-3 then
		flat = fish.model:GetPivot().LookVector
		flat = Vector3.new(flat.X, 0, flat.Z)
	end
	local pivot = fish.length * SWIM_PIVOT
	return CFrame.lookAt(pos, pos + flat.Unit) * CFrame.new(0, 0, -pivot) * CFrame.Angles(0, wag, 0) * CFrame.new(0, 0, pivot) * SHADOW_ROLL
end

local function stepFish(fish: Shadow, now: number, current: Line?)
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
			-- CAUGHT! over the player's head, with the fish's name and picture
			local character = player.Character
			local head = character and character:FindFirstChild("Head")
			local def = fish.fish and Materials.get(fish.fish)
			if head and head:IsA("BasePart") and def then
				deps.Util.BonkPop.caught(head, def.name, def.icon)
			end
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
	elseif fish.mode == "spiral" and current then
		-- in on a curve round the bobber, in little darts (the speed swells and drops)
		local u = math.clamp(t + 0.05 * math.sin(t * math.pi * 6), 0, 1)
		local centre = under(current)
		local stop = fish.length * 0.5 -- its nose ends at the bobber
		local function at(v: number): Vector3
			local radius = fish.radius + (stop - fish.radius) * (v * v * (3 - 2 * v))
			local angle = fish.angle + SPIRAL_TURN * v
			return centre + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
		end
		local pos = at(u)
		local heading = if u >= 0.999 then centre - pos else at(math.min(u + 0.02, 1)) - pos
		local wag = math.sin(now * SWIM_WAG_RATE) * SWIM_WAG
		cf = swimFrame(fish, pos, heading, wag)
		if now - fish.wake > WAKE_EVERY and t < 0.95 then
			fish.wake = now
			ripple(pos, 2 + fish.length * 0.4)
		end
		if t >= 1 then
			fish.mode = "hold"
			fish.from = pos
		end
	elseif (fish.mode == "hold" or fish.mode == "fight") and current then
		-- nose at the bobber; a nibble darts it forward and back; hooked, it thrashes about
		local centre = under(current)
		local back = fish.from - centre
		back = Vector3.new(back.X, 0, back.Z)
		back = if back.Magnitude > 1e-3 then back.Unit else Vector3.new(1, 0, 0)
		local heading = -back
		local poke = math.clamp((now - fish.poke) / NIBBLE_POKE_SECONDS, 0, 1)
		local forward = math.sin(poke * math.pi) * NIBBLE_POKE
		local pos = centre + back * (fish.length * 0.5 - forward)
		local wag = math.sin(now * SWIM_WAG_RATE * 0.5) * SWIM_WAG * 0.4
		if fish.mode == "fight" then
			local side = Vector3.new(-heading.Z, 0, heading.X)
			pos += side * math.sin(now * 5.3) * 0.7 + back * (0.4 + math.sin(now * 3.1) * 0.3)
			wag = math.sin(now * 22) * SWIM_WAG * 1.4
		end
		cf = swimFrame(fish, pos, heading, wag)
	else
		-- "flee": darts off and fades
		local pos = fish.from:Lerp(fish.to, t)
		local wag = math.sin(now * SWIM_WAG_RATE * 2) * SWIM_WAG
		cf = swimFrame(fish, pos, fish.to - fish.from, wag)
		setShadowTransparency(fish.model, SHADOW_TRANSPARENCY + (1 - SHADOW_TRANSPARENCY) * t)
		if t >= 1 then
			clearShadow()
			return
		end
	end
	fish.model:PivotTo(cf)
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
			-- floating: ride the water, eased toward the sink depth a bite (or a nibble) pulls it to
			local sink = if now < current.dipUntil then math.max(current.sink, NIBBLE_DEPTH) else current.sink
			current.depth += (sink - current.depth) * math.min(1, dt * 14)
			current.pull += (current.pullTo - current.pull) * math.min(1, dt * 6)
			local bob = if sink > 0 then 0 else math.sin(now * 2.4) * FLOAT_BOB
			-- a fish on the line tugs it about
			local fighting = phase == "Fight"
			local tug = if fighting then Vector3.new(math.sin(now * 13) * 0.25, 0, math.cos(now * 11) * 0.25) else Vector3.zero
			pos = floatPoint(current) + Vector3.new(0, bob - current.depth, 0) + tug
		end
		if current then
			current.bobber:PivotTo(CFrame.new(pos))
			local tip = tipPosition() or pos
			local tail = bobberLine(current)
			-- slack while waiting, pulled straight (and trembling) while fighting a fish
			local tight = phase == "Fight" or phase == "Hooking"
			local span = (tail - tip).Magnitude
			local sag = if current.mode == "float" and not tight then math.min(span * 0.22, 4) else 0.15
			if tight then
				sag = math.sin(now * 37) * 0.12
			end
			current.tip.WorldCFrame = CFrame.fromMatrix(tip, Vector3.new(0, -1, 0), Vector3.new(1, 0, 0))
			current.tail.WorldCFrame = CFrame.fromMatrix(tail, Vector3.new(0, 1, 0), Vector3.new(1, 0, 0))
			current.beam.CurveSize0 = sag
			current.beam.CurveSize1 = sag * 0.6
		end
	end

	-- the struggle loops while the fight goes on
	if phase == "Fight" and now >= nextStruggle then
		nextStruggle = now + STRUGGLE_SECONDS
		WeaponController.playExtra("Struggle", STRUGGLE_SECONDS, 0.5)
	end

	local fish = shadow
	if fish then
		stepFish(fish, now, line)
	end
end

-- ==================== the server ====================

-- A point `distance` from `centre` that is over open fishing water (nothing on top of
-- it), so the fish never swims in from under a bank; nearer in if no direction is clear.
-- Returns the point and its angle round the centre.
local function openWaterNear(centre: Vector3, distance: number): (Vector3, number)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Instance, MapLayout.runtimeFolder() }
	for _, reach in { distance, distance * 0.6, distance * 0.35 } do
		local turn = math.random() * math.pi * 2
		for i = 0, 7 do
			local angle = turn + i * math.pi / 4
			local point = centre + Vector3.new(math.cos(angle), 0, math.sin(angle)) * reach
			-- the spiral's path must be over water too: check its middle as well
			local mid = centre + Vector3.new(math.cos(angle + SPIRAL_TURN / 2), 0, math.sin(angle + SPIRAL_TURN / 2)) * reach * 0.6
			local hit = workspace:Raycast(point + Vector3.new(0, 12, 0), Vector3.new(0, -14, 0), params)
			local midHit = workspace:Raycast(mid + Vector3.new(0, 12, 0), Vector3.new(0, -14, 0), params)
			if hit and CollectionService:HasTag(hit.Instance, Fishing.Tag) and midHit and CollectionService:HasTag(midHit.Instance, Fishing.Tag) then
				return point, angle
			end
		end
	end
	return centre + Vector3.new(1, 0, 0), 0
end

local function nibble(current: Line)
	if line ~= current or phase ~= "Approach" then
		return
	end
	current.dipUntil = os.clock() + 0.22
	ripple(current.to, 2.5)
	if shadow then
		shadow.poke = os.clock()
	end
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
		local model, length = newShadow(message.size)
		local seconds = message.seconds or 1.5
		if model then
			local centre = under(current)
			local start, angle = openWaterNear(centre, SHADOW_FROM)
			local radius = (start - centre).Magnitude
			model:PivotTo(CFrame.new(start))
			shadow = {
				model = model,
				length = length,
				from = start,
				to = centre,
				start = os.clock(),
				seconds = seconds,
				mode = "spiral",
				angle = angle,
				radius = radius,
				poke = 0,
				wake = 0,
				fish = nil,
			}
		end
		-- the nibbles, after it arrives
		local each = message.nibbleSeconds or Fishing.nibbleSeconds
		for i = 1, (message.nibbles or 0) do
			task.delay(seconds + (i - 1) * each + each * 0.3, nibble, current)
		end
	elseif state == "Bite" and current then
		phase = "Bite"
		current.sink = SINK_DEPTH
		Effects.burst(current.to, "Splash", { count = 10 })
		ripple(current.to, 5)
		deps.Util.BonkPop.bite(current.to + Vector3.new(0, 0.8, 0))
		if shadow then
			shadow.poke = os.clock()
		end
	elseif state == "Surface" and current then
		phase = "Waiting"
		current.sink = 0
		if shadow then
			local away = shadow.model:GetPivot().LookVector * -SHADOW_FROM
			swimShadow("flee", under(current) + Vector3.new(away.X, 0, away.Z), 1.0)
		end
	elseif state == "Fight" and current then
		-- hooked: the bobber pops back up, the line goes tight and the fight starts
		phase = "Fight"
		current.sink = 0.25
		current.pullTo = 0
		Effects.burst(current.to, "Splash", { count = 12 })
		ripple(current.to, 6)
		if shadow then
			shadow.mode = "fight"
		end
		CameraFX.zoom("Fishing", FIGHT_ZOOM)
		nextStruggle = 0
		deps.UI.FishingBarUI.begin(message)
	elseif state == "Tally" and current then
		deps.UI.FishingBarUI.tally(message.checks or 0, message.misses or 0)
		current.pullTo = (message.checks or 0) * PULL_PER_CHECK
	elseif state == "Caught" then
		deps.UI.FishingBarUI.finish(true)
		CameraFX.release("Fishing")
		phase = "Landing"
		WeaponController.playExtra("Reel", 0.8, 0.45)
		local root = rootPart()
		if current then
			Effects.burst(floatPoint(current), "Splash", { count = 16 })
			ripple(floatPoint(current), 7)
			if not shadow then
				local model, length = newShadow(1)
				if model then
					local spot = under(current)
					shadow = { model = model, length = length, from = spot, to = spot, start = 0, seconds = 1, mode = "hold", angle = 0, radius = 0, poke = 0, wake = 0, fish = nil }
				end
			end
			if shadow then
				-- out of the water it is the whole dark fish, solid
				unflatten(shadow.model)
				local spot = floatPoint(current)
				shadow.fish = message.fish
				shadow.from = spot
				shadow.to = if root then root.Position + Vector3.new(0, 4.2, 0) else spot
				shadow.start = os.clock()
				shadow.seconds = LEAP_SECONDS
				shadow.mode = "leap"
			end
			reelIn()
			-- the leap clears "Landing" when it ends; with no fish model the reel does
			phase = if shadow then "Landing" else "Reeling"
		end
	elseif state == "Escaped" then
		deps.UI.FishingBarUI.finish(false)
		CameraFX.release("Fishing")
		if current then
			phase = "Reeling"
			-- the line snaps: it goes at once, the bobber bobs up and is gone a moment later
			current.beam.Enabled = false
			current.sink = 0
			current.pullTo = 0
			Effects.burst(floatPoint(current), "Splash", { count = 8 })
			if shadow then
				local away = (under(current) - (rootPart() and (rootPart() :: BasePart).Position or under(current)))
				away = Vector3.new(away.X, 0, away.Z)
				away = if away.Magnitude > 1e-3 then away.Unit * SHADOW_FROM else Vector3.new(SHADOW_FROM, 0, 0)
				swimShadow("flee", under(current) + away, 0.6)
			end
			task.delay(0.6, function()
				if line == current then
					clearLine()
					if phase == "Reeling" then
						phase = nil
					end
				end
			end)
		else
			phase = nil
		end
	elseif state == "Reeled" then
		endFight()
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
	elseif phase == "Fight" then
		local at, ok = deps.UI.FishingBarUI.click()
		if at then
			send({ action = "click", at = at })
			local seconds = if ok then HEAVE_SECONDS else LURCH_SECONDS
			WeaponController.playExtra(if ok then "Heave" else "Lurch", seconds, 0.35)
			nextStruggle = os.clock() + seconds
			if line then
				if ok then
					ripple(floatPoint(line), 3)
				else
					Effects.burst(floatPoint(line), "Splash", { count = 6 })
				end
			end
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
