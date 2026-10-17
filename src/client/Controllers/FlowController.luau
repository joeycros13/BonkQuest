--!strict
-- FlowController: makes water details look like they are moving -- the dashes
-- running down the waterfall and the streaks drifting along the stream.
--
-- Any BasePart tagged Flow slides from where it was placed along a direction,
-- then starts again, fading out at both ends so the jump back is never seen:
--   FlowDir     Vector3  world direction of travel (default straight down)
--   FlowSpeed   number   studs per second (default 6)
--   FlowRange   number   studs travelled before it loops (default 8)
--   FlowOffset  number   studs already travelled at time 0, to stagger copies
--   FlowFade    number   share of the range spent fading in and out (default 0.2)
-- The part's own Transparency is its most visible state.
--
-- Purely decorative, so it runs on each player's client and nothing is
-- replicated. It is one Scheduler system that hands its moves to PartBatch, so
-- every flowing part moves in the same BulkMoveTo as the rest of the frame.
-- Parts far from the camera are left alone.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Animation = require(Shared:WaitForChild("Animation"))
local Scheduler = Animation.Scheduler
local PartBatch = Animation.PartBatch

local FlowController = {}

local TAG = "Flow"
local FAR = 320 -- studs from the camera beyond which nothing is updated

type Flow = {
	part: BasePart,
	origin: CFrame,
	dir: Vector3,
	speed: number,
	range: number,
	offset: number,
	fade: number,
	alpha: number,
}

local flows: { Flow } = {}
local byPart: { [Instance]: Flow } = {}

local function number(part: Instance, name: string, default: number): number
	local v = part:GetAttribute(name)
	return if type(v) == "number" then v else default
end

local function adopt(part: Instance)
	if byPart[part] or not part:IsA("BasePart") then
		return
	end
	local dir = part:GetAttribute("FlowDir")
	local flow: Flow = {
		part = part,
		origin = part.CFrame,
		dir = if typeof(dir) == "Vector3" and dir.Magnitude > 1e-3 then dir.Unit else -Vector3.yAxis,
		speed = number(part, "FlowSpeed", 6),
		range = math.max(number(part, "FlowRange", 8), 0.1),
		offset = number(part, "FlowOffset", 0),
		fade = math.clamp(number(part, "FlowFade", 0.2), 0.01, 0.5),
		alpha = part.Transparency,
	}
	byPart[part] = flow
	table.insert(flows, flow)
end

local function release(part: Instance)
	local flow = byPart[part]
	if not flow then
		return
	end
	byPart[part] = nil
	local i = table.find(flows, flow)
	if i then
		table.remove(flows, i)
	end
end

local function step(_dt: number, now: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	for _, flow in flows do
		if (flow.origin.Position - eye).Magnitude > FAR then
			continue
		end
		local travelled = (now * flow.speed + flow.offset) % flow.range
		local u = travelled / flow.range
		-- 0 at either end of the run, 1 in the middle: fades in, flows, fades out.
		local edge = math.clamp(math.min(u, 1 - u) / flow.fade, 0, 1)
		edge = edge * edge * (3 - 2 * edge)
		flow.part.Transparency = 1 - (1 - flow.alpha) * edge
		PartBatch.push(flow.part, flow.origin + flow.dir * travelled)
	end
end

function FlowController.init(_deps: any) end

function FlowController.start()
	for _, part in CollectionService:GetTagged(TAG) do
		adopt(part)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(adopt)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(release)
	-- Before Motion (30) and the PartBatch flush (100).
	Scheduler.bind("Render", "FlowController", 25, step)
end

return FlowController
