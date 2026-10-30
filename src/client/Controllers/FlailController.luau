--!strict
-- FlailController: a flail's head swings on its chain (2026-10-29, the user: "if there is any
-- chance to give the flail actual physics"). The Lantern Flail's lantern hangs from five
-- links under the handle, trails behind the whirl over the head and whips through the blow.
--
-- A held weapon (a character's EquippedWeapon) is a flail when its Grip has a `FlailPivot`
-- attachment, where the chain hangs from. Its pieces with a `FlailLink` attribute (1..n,
-- counted from the handle) are the chain's links; those with `FlailBob` hang from the last
-- link (the lantern). On each player's client, for every character holding one near the
-- camera, those pieces are hidden (LocalTransparencyModifier, their lights switched off) and
-- anchored copies of them are moved every frame along a chain simulated with Verlet steps
-- under the place's gravity, pinned to the pivot. Purely for looks: the server's hit check
-- is the swing's, unchanged.
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
local DAMPING = 0.985 -- share of its speed a node keeps each frame (air drag)
local ITERATIONS = 8 -- passes holding the links to their lengths
local BOB_WEIGHT = 4 -- the lantern is this much heavier than a link: the links give way to it
local SNAP = 25 -- studs the pivot may jump in a frame before the chain is laid out again (a teleport)
local MAX_DT = 1 / 30

type Piece = { part: BasePart, copy: BasePart, rest: CFrame, lights: { Light } }
type Flail = {
	model: Model,
	grip: BasePart,
	pivot: Vector3, -- in the grip's space
	links: { Piece }, -- link k hangs between node k-1 and node k
	bob: { Piece }, -- hangs between node n and node n+1
	nodes: { Vector3 },
	last: { Vector3 },
	lengths: { number },
	restNodes: { Vector3 }, -- the nodes laid out straight, in the grip's space
	lastPivot: Vector3?,
}

local flails: { [Model]: Flail } = {} -- by character
local folder: Folder? = nil

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

-- The nodes laid out straight down the weapon from the pivot, in the grip's space.
local function layOut(flail: Flail)
	local cf = flail.grip.CFrame
	for i, point in flail.restNodes do
		flail.nodes[i] = cf * point
		flail.last[i] = flail.nodes[i]
	end
	flail.lastPivot = cf * flail.pivot
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
		nodes = {},
		last = {},
		lengths = lengths,
		restNodes = restNodes,
		lastPivot = nil,
	}
	layOut(flail)
	for _, list in { links, bob } do
		for _, piece in list do
			hide(piece, true)
		end
	end
	flails[character] = flail
	return flail
end

local function simulate(flail: Flail, dt: number)
	local cf = flail.grip.CFrame
	local pivot = cf * flail.pivot
	if not flail.lastPivot or (pivot - flail.lastPivot).Magnitude > SNAP then
		layOut(flail)
	end
	flail.lastPivot = pivot
	local nodes, last = flail.nodes, flail.last
	local gravity = Vector3.new(0, -Workspace.Gravity, 0) * dt * dt
	nodes[1], last[1] = pivot, pivot
	for i = 2, #nodes do
		local now = nodes[i]
		local moved = (now - last[i]) * DAMPING
		last[i] = now
		nodes[i] = now + moved + gravity
	end
	local bobNode = if #flail.bob > 0 then #nodes else -1
	for _ = 1, ITERATIONS do
		for i = 1, #nodes - 1 do
			local a, b = nodes[i], nodes[i + 1]
			local delta = b - a
			local dist = delta.Magnitude
			if dist < 1e-6 then
				continue
			end
			local fix = delta * ((dist - flail.lengths[i]) / dist)
			if i == 1 then
				nodes[i + 1] = b - fix -- the pivot is held by the hand
			else
				local wa, wb = 1, if i + 1 == bobNode then 1 / BOB_WEIGHT else 1
				local share = wa / (wa + wb)
				nodes[i] = a + fix * (1 - share)
				nodes[i + 1] = b - fix * share
			end
		end
	end
	-- place the copies: each turned from lying straight down the weapon to its stretch
	local along = cf.LookVector
	local turn = cf.Rotation
	for k, piece in flail.links do
		local from, to = nodes[k], nodes[k + 1]
		local dir = to - from
		local frame = CFrame.new(from) * (if dir.Magnitude > 1e-6 then fromTo(along, dir.Unit) else CFrame.identity) * turn
		PartBatch.push(piece.copy, frame * piece.rest)
	end
	if #flail.bob > 0 then
		local hang = nodes[#nodes] - nodes[#nodes - 1]
		local frame = CFrame.new(nodes[#nodes - 1]) * (if hang.Magnitude > 1e-6 then fromTo(along, hang.Unit) else CFrame.identity) * turn
		for _, piece in flail.bob do
			PartBatch.push(piece.copy, frame * piece.rest)
		end
	end
end

local function step(dt: number, _now: number)
	dt = math.min(dt, MAX_DT)
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
			simulate(flail, dt)
		end
	end
	for character in flails do
		if not seen[character] then
			release(character)
		end
	end
end

function FlailController.init(_deps: any) end

function FlailController.start()
	-- after the joints (the handle is where the hand put it), before the PartBatch flush (100)
	Scheduler.bind("Render", "FlailController", 90, step)
end

return FlailController
