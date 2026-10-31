--!strict
-- FlailController: the Firefly Lantern's lantern swings on its chain (2026-10-29). A first
-- version simulated the chain (Verlet under gravity); the user found it messy and asked
-- for a fixed path instead, so the chain now follows hand-set keys: it hangs straight
-- down at rest with a slow sway, and on a swing follows PATHS[swing name], keyed over the
-- swing's length, in the holder's torso frame (so it turns with the body).
--
-- A held weapon (a character's EquippedWeapon) is a flail when its Grip has a `FlailPivot`
-- attachment, where the chain hangs from. Its pieces with a `FlailLink` attribute (1..n,
-- counted from the handle) are the chain's links; those with `FlailBob` hang from the last
-- link (the lantern). On each player's client, for every character holding one near the
-- camera, those pieces are hidden (LocalTransparencyModifier, their lights switched off)
-- and anchored copies of them are placed every frame along a straight chain from the
-- pivot toward the path's direction. The chain is kept out of the holder's body and
-- above the ground. Purely for looks: the server's hit check is the swing's, unchanged.
--
-- One Scheduler Render system (priority 90: after the joints have placed the handle, before
-- the PartBatch flush), moving the copies through PartBatch.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Animation = require(Shared:WaitForChild("Animation"))
local Scheduler = Animation.Scheduler
local PartBatch = Animation.PartBatch

local FlailController = {}

local HELD_NAME = "EquippedWeapon"
local FAR = 150 -- studs from the camera beyond which a flail is left rigid
local GROUND_REACH = 12 -- studs looked down from the pivot for the ground
local BOB_CLEAR = 0.8 -- the lantern's centre kept over the ground (its half height and a little)
-- the holder's body, a standing cylinder round the root the lantern is kept out of
local BODY_CLEAR = 1.45
local BODY_BELOW = 3.2 -- studs under the root the cylinder reaches (the feet)
local BODY_ABOVE = 2.6 -- and over it (the head)
-- the rest sway: a slow drift, in the torso's sideways and forward directions
local SWAY_SIDE, SWAY_SIDE_RATE = 0.06, 1.6
local SWAY_FWD, SWAY_FWD_RATE = 0.05, 1.1

-- Where the lantern hangs from the pivot over a swing, in the torso's frame (+X right,
-- +Y up, +Z back), at points through the swing (u 0..1, the swing's own clock), joined
-- by a Catmull-Rom curve. FlailWhirl (Animation.Clips.Weapons) draws the handle back
-- over the right shoulder (u 0.32), smashes it down in front (hit u 0.56) and follows
-- through to the left (u 0.74): the lantern lags behind on the windup, swings up over
-- the top and comes down in front on the hit, stays in front while the arm follows
-- through (swinging it back under the body dragged it across the feet), and is lifted
-- back to hanging as the arm comes home.
type Key = { u: number, dir: Vector3 }
local PATHS: { [string]: { Key } } = {
	FlailWhirl = {
		{ u = 0, dir = Vector3.new(0, -1, 0) },
		{ u = 0.18, dir = Vector3.new(0.05, -0.85, 0.5) },
		{ u = 0.32, dir = Vector3.new(0.15, -0.45, 0.88) },
		{ u = 0.44, dir = Vector3.new(0.1, 0.55, 0.83) },
		{ u = 0.5, dir = Vector3.new(0.05, 1, 0.05) },
		{ u = 0.56, dir = Vector3.new(0, -0.2, -1) },
		{ u = 0.66, dir = Vector3.new(-0.05, -0.6, -0.8) },
		{ u = 0.8, dir = Vector3.new(0, -0.72, -0.7) },
		{ u = 0.92, dir = Vector3.new(0, -0.93, -0.36) },
		{ u = 1, dir = Vector3.new(0, -1, 0) },
	},
}

type Piece = { part: BasePart, copy: BasePart, rest: CFrame, lights: { Light } }
type Flail = {
	model: Model,
	grip: BasePart,
	pivot: Vector3, -- in the grip's space
	links: { Piece }, -- link k lies between node k and node k + 1
	bob: { Piece }, -- lies between node n + 1 and node n + 2
	lengths: { number }, -- each stretch's length, from the pivot down
	restNodes: { Vector3 }, -- the nodes laid out straight, in the grip's space
}
type Swing = { path: { Key }, start: number, seconds: number }

local flails: { [Model]: Flail } = {} -- by character
local swings: { [Model]: Swing } = {} -- a swing under way, by character
local folder: Folder? = nil
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function copiesFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local runtime = Workspace:FindFirstChild("Runtime") or Workspace
	local f = Instance.new("Folder")
	f.Name = "FlailCopies"
	f.Parent = runtime
	folder = f
	return f
end

local function fromTo(a: Vector3, b: Vector3): CFrame
	local d = math.clamp(a:Dot(b), -1, 1)
	local axis = a:Cross(b)
	if axis.Magnitude < 1e-6 then
		if d > 0 then
			return CFrame.identity
		end
		local perp = if math.abs(a.X) < 0.9 then Vector3.xAxis else Vector3.zAxis
		return CFrame.fromAxisAngle(a:Cross(perp).Unit, math.pi)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(d))
end

local function hide(piece: Piece, hidden: boolean)
	piece.part.LocalTransparencyModifier = if hidden then 1 else 0
	for _, light in piece.lights do
		light.Enabled = not hidden
	end
end

-- Roblox's camera (the PlayerModule's TransparencyController) rewrites the
-- LocalTransparencyModifier of every part in the character, the held weapon included,
-- when the camera zooms in or out, which showed the rigid originals beside the copies
-- (the user's screenshot, 2026-10-29); so they are hidden again every frame.
local function keepHidden(flail: Flail)
	for _, list in { flail.links, flail.bob } do
		for _, piece in list do
			if piece.part.LocalTransparencyModifier ~= 1 then
				piece.part.LocalTransparencyModifier = 1
			end
		end
	end
end

local function release(character: Model)
	local flail = flails[character]
	if not flail then
		return
	end
	flails[character] = nil
	for _, list in { flail.links, flail.bob } do
		for _, piece in list do
			if piece.part.Parent then
				hide(piece, false)
			end
			piece.copy:Destroy()
		end
	end
end

local function adopt(character: Model, model: Model): Flail?
	local grip = model.PrimaryPart
	local pivot = grip and grip:FindFirstChild("FlailPivot")
	if not (grip and pivot and pivot:IsA("Attachment")) then
		return nil
	end
	local links: { Piece } = {}
	local bob: { Piece } = {}
	local order: { [Piece]: number } = {}
	local bobCentre = Vector3.zero
	local bobCount = 0
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		local index = part:GetAttribute("FlailLink")
		local isBob = part:GetAttribute("FlailBob") == true
		if type(index) ~= "number" and not isBob then
			continue
		end
		local copy = part:Clone()
		for _, child in copy:GetDescendants() do
			if child:IsA("JointInstance") or child:IsA("WeldConstraint") then
				child:Destroy()
			end
		end
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanQuery = false
		copy.CanTouch = false
		copy.Massless = true
		copy.Parent = copiesFolder()
		local lights = {}
		for _, child in part:GetDescendants() do
			if child:IsA("Light") and child.Enabled then
				table.insert(lights, child)
			end
		end
		local piece: Piece = { part = part, copy = copy, rest = grip.CFrame:ToObjectSpace(part.CFrame), lights = lights }
		if type(index) == "number" then
			table.insert(links, piece)
			order[piece] = index
		else
			table.insert(bob, piece)
			bobCentre += piece.rest.Position
			bobCount += 1
		end
	end
	if #links == 0 then
		return nil
	end
	table.sort(links, function(a, b)
		return order[a] < order[b]
	end)
	-- the bob hangs from the bottom of the last link, its weight at its centre
	local lastLink = links[#links]
	local attach = Vector3.new(pivot.Position.X, pivot.Position.Y, lastLink.rest.Position.Z - lastLink.part.Size.Z / 2)
	local n = #links
	local restNodes: { Vector3 } = {}
	for k = 0, n do
		restNodes[k + 1] = pivot.Position:Lerp(attach, k / n)
	end
	if bobCount > 0 then
		local centre = bobCentre / bobCount
		restNodes[n + 2] = Vector3.new(attach.X, attach.Y, math.min(centre.Z, attach.Z - 0.2))
	end
	-- each piece's place in its stretch's own frame (at the stretch's start, the grip's turn)
	for k, piece in links do
		piece.rest = CFrame.new(restNodes[k]):Inverse() * piece.rest
	end
	for _, piece in bob do
		piece.rest = CFrame.new(restNodes[n + 1]):Inverse() * piece.rest
	end
	local lengths = {}
	for i = 1, #restNodes - 1 do
		lengths[i] = (restNodes[i + 1] - restNodes[i]).Magnitude
	end
	local flail: Flail = {
		model = model,
		grip = grip,
		pivot = pivot.Position,
		links = links,
		bob = bob,
		lengths = lengths,
		restNodes = restNodes,
	}
	for _, list in { links, bob } do
		for _, piece in list do
			hide(piece, true)
		end
	end
	flails[character] = flail
	return flail
end

-- The path's direction at u: a Catmull-Rom curve through the keys' directions.
local function pathAt(path: { Key }, u: number): Vector3
	u = math.clamp(u, 0, 1)
	local i = 1
	while i < #path - 1 and path[i + 1].u <= u do
		i += 1
	end
	local a, b = path[i], path[i + 1]
	local t = if b.u > a.u then (u - a.u) / (b.u - a.u) else 1
	local p0 = (path[i - 1] or a).dir
	local p1, p2 = a.dir, b.dir
	local p3 = (path[i + 2] or b).dir
	local t2, t3 = t * t, t * t * t
	local v = 0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3)
	return if v.Magnitude > 1e-4 then v.Unit else Vector3.new(0, -1, 0)
end

local function groundUnder(character: Model, at: Vector3): number?
	groundParams.FilterDescendantsInstances = { character, copiesFolder() }
	local hit = Workspace:Raycast(at, Vector3.new(0, -GROUND_REACH, 0), groundParams)
	return if hit then hit.Position.Y else nil
end

local function place(character: Model, flail: Flail, now: number)
	local cf = flail.grip.CFrame
	local pivot = cf * flail.pivot
	local torso = character:FindFirstChild("Torso") :: BasePart?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local frame = if torso then torso.CFrame else cf
	-- where the lantern hangs, in the torso's frame
	local dir: Vector3
	local swing = swings[character]
	if swing and now - swing.start < swing.seconds then
		dir = pathAt(swing.path, (now - swing.start) / swing.seconds)
	else
		swings[character] = nil
		dir = Vector3.new(math.sin(now * SWAY_SIDE_RATE) * SWAY_SIDE, -1, math.sin(now * SWAY_FWD_RATE) * SWAY_FWD).Unit
	end
	local world = frame:VectorToWorldSpace(dir)
	-- the whole chain's length, the pivot to the lantern's centre
	local total = 0
	for _, length in flail.lengths do
		total += length
	end
	local tip = pivot + world * total
	-- kept out of the holder's body and above the ground (the chain then runs to it)
	if root then
		local body = root.Position
		if tip.Y > body.Y - BODY_BELOW and tip.Y < body.Y + BODY_ABOVE then
			local flat = Vector3.new(tip.X - body.X, 0, tip.Z - body.Z)
			if flat.Magnitude < BODY_CLEAR then
				local out = if flat.Magnitude > 1e-4 then flat.Unit else frame.RightVector
				tip = Vector3.new(body.X, tip.Y, body.Z) + out * BODY_CLEAR
			end
		end
	end
	local ground = groundUnder(character, pivot)
	if ground and tip.Y < ground + BOB_CLEAR then
		-- lifted to the floor, the chain keeping its length by reaching out sideways
		local drop = pivot.Y - (ground + BOB_CLEAR)
		local flat = Vector3.new(tip.X - pivot.X, 0, tip.Z - pivot.Z)
		local reach = math.sqrt(math.max(total * total - drop * drop, 0))
		local out = if flat.Magnitude > 1e-4 then flat.Unit else frame.LookVector
		tip = Vector3.new(pivot.X, ground + BOB_CLEAR, pivot.Z) + out * reach
	end
	local along = (tip - pivot)
	along = if along.Magnitude > 1e-4 then along.Unit else world
	-- the copies: each turned from lying straight down the weapon to the chain's line
	local turn = fromTo(cf.LookVector, along) * cf.Rotation
	local at = 0
	for k, piece in flail.links do
		PartBatch.push(piece.copy, CFrame.new(pivot + along * at) * turn * piece.rest)
		at += flail.lengths[k]
	end
	for _, piece in flail.bob do
		PartBatch.push(piece.copy, CFrame.new(pivot + along * at) * turn * piece.rest)
	end
end

local function step(_dt: number, _now: number)
	local now = os.clock() -- the clock onSwingStarted stamps swings with
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local seen: { [Model]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end
		local held = character:FindFirstChild(HELD_NAME)
		local flail = flails[character]
		if flail and flail.model ~= held then
			release(character)
			flail = nil
		end
		if not (held and held:IsA("Model") and held.PrimaryPart) then
			continue
		end
		if (held.PrimaryPart.Position - eye).Magnitude > FAR then
			if flail then
				release(character)
			end
			continue
		end
		if not flail then
			flail = adopt(character, held)
		end
		if flail then
			seen[character] = true
			keepHidden(flail)
			place(character, flail, now)
		end
	end
	for character in flails do
		if not seen[character] then
			release(character)
		end
	end
end

function FlailController.init(deps: any)
	local weapons = deps.Controllers and deps.Controllers.WeaponController
	if weapons and weapons.onSwingStarted then
		weapons.onSwingStarted(function(model: Model, def: any, seconds: number)
			local path = PATHS[def.swing]
			if path then
				swings[model] = { path = path, start = os.clock(), seconds = seconds }
			end
		end)
	end
end

function FlailController.start()
	-- after the joints (the handle is where the hand put it), before the PartBatch flush (100)
	Scheduler.bind("Render", "FlailController", 90, step)
end

return FlailController
