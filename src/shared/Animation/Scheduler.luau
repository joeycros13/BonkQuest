--!strict
-- Scheduler: the animation system's ONLY frame hooks.
--
-- Everything that moves something each frame binds a "system" here instead of
-- connecting its own RunService event. Systems in a phase run in priority order
-- (lowest first), so writers that touch the same thing always run in a known
-- order -- two separate connections to one RunService event do not.
--
-- Phases:
--   Joints  RunService.PreSimulation: after Roblox's Animator, before physics.
--           Character joint Transforms must be written here.
--   Render  RunService.PreRender (server: Heartbeat): anchored parts, tweens,
--           motions, effects. Enemy wander (10) runs before animators (50),
--           tweens/motions (20-30) before the batched part move (100).
--   Camera  RenderStep right after Roblox's camera (client only): CameraFX.
--
--   local handle = Scheduler.bind("Render", "MySystem", 40, function(dt, now) ... end)
--   handle:Unbind()
--   Scheduler.profiling = true; print(Scheduler.stats())  -- average ms per system
--
-- Without code: during a playtest, tick the "Profiling" attribute on this
-- module (client side) and read the "Stats" attribute, refreshed every second.

local RunService = game:GetService("RunService")

local Scheduler = {}

export type Phase = "Joints" | "Render" | "Camera"

type System = {
	name: string,
	priority: number,
	fn: (number, number) -> (),
	cost: number,
	warned: boolean,
	removed: boolean,
}

type PhaseState = { systems: { System }, conn: any, dirty: boolean }

local IS_CLIENT = RunService:IsClient()
local CAMERA_STEP = "AnimationCameraPhase"

local phases: { [string]: PhaseState } = {
	Joints = { systems = {}, conn = nil, dirty = false },
	Render = { systems = {}, conn = nil, dirty = false },
	Camera = { systems = {}, conn = nil, dirty = false },
}

-- Set true to measure each system's average cost (shown by Scheduler.stats()).
Scheduler.profiling = false

local function run(phase: PhaseState, dt: number)
	local now = os.clock()
	local profiling = Scheduler.profiling
	for _, system in phase.systems do
		if system.removed then
			continue
		end
		local start = if profiling then os.clock() else 0
		local ok, err = pcall(system.fn, dt, now)
		if not ok and not system.warned then
			-- Reported once; a broken system must not flood the output every frame.
			system.warned = true
			warn(("[Animation.Scheduler] %s failed: %s"):format(system.name, tostring(err)))
		end
		if profiling then
			system.cost = system.cost * 0.95 + (os.clock() - start) * 0.05
		end
	end
	if phase.dirty then
		phase.dirty = false
		local kept = {}
		for _, system in phase.systems do
			if not system.removed then
				table.insert(kept, system)
			end
		end
		phase.systems = kept
	end
end

local function connect(name: string, phase: PhaseState)
	if phase.conn then
		return
	end
	local step = function(dt: number)
		run(phase, dt)
	end
	if name == "Joints" then
		phase.conn = RunService.PreSimulation:Connect(step)
	elseif name == "Render" then
		phase.conn = (if IS_CLIENT then RunService.PreRender else RunService.Heartbeat):Connect(step)
	elseif name == "Camera" and IS_CLIENT then
		RunService:BindToRenderStep(CAMERA_STEP, Enum.RenderPriority.Camera.Value + 1, step)
		phase.conn = {
			Disconnect = function()
				RunService:UnbindFromRenderStep(CAMERA_STEP)
			end,
		}
	end
end

function Scheduler.bind(phaseName: Phase, name: string, priority: number, fn: (number, number) -> ())
	local phase = phases[phaseName]
	assert(phase, "unknown Scheduler phase " .. tostring(phaseName))
	local system: System = { name = name, priority = priority, fn = fn, cost = 0, warned = false, removed = false }
	table.insert(phase.systems, system)
	table.sort(phase.systems, function(a, b)
		return a.priority < b.priority
	end)
	connect(phaseName, phase)
	return {
		Unbind = function(_self: any)
			if not system.removed then
				system.removed = true
				phase.dirty = true
			end
		end,
	}
end

-- Average cost of every system, in milliseconds (needs Scheduler.profiling).
function Scheduler.stats(): string
	local lines = {}
	local total = 0
	for phaseName, phase in phases do
		for _, system in phase.systems do
			total += system.cost
			table.insert(lines, ("%-7s %-28s %.3f ms"):format(phaseName, system.name, system.cost * 1000))
		end
	end
	table.sort(lines)
	table.insert(lines, ("total %.3f ms per frame"):format(total * 1000))
	return table.concat(lines, "\n")
end

-- The attribute switch (see the header).
local module = script
local function syncProfiling()
	Scheduler.profiling = module:GetAttribute("Profiling") == true
end
module:GetAttributeChangedSignal("Profiling"):Connect(syncProfiling)
syncProfiling()
task.spawn(function()
	while true do
		task.wait(1)
		if Scheduler.profiling then
			module:SetAttribute("Stats", Scheduler.stats())
		end
	end
end)

return Scheduler
