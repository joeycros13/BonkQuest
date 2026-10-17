--!strict
-- SpinnerController: keeps decorative things turning, such as the windmill sails.
--
-- Anything tagged Spinner (a Model or a BasePart) spins around its pivot:
--   SpinSpeed  number   degrees per second (default 20; negative turns the other way)
--   SpinAxis   Vector3  axis in the target's own pivot space (default X)
-- Changing SpinSpeed during play takes effect straight away.
--
-- Purely decorative, so it runs on each player's client and nothing is
-- replicated. The turning is an Animation.Motion.spin, i.e. a Scheduler system,
-- never a RunService handler of its own.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Animation = require(Shared:WaitForChild("Animation"))
local Motion = Animation.Motion

local SpinnerController = {}

local TAG = "Spinner"
local DEFAULT_SPEED = 20

type Spin = { handle: any, baseSpeed: number }

local spinning: { [Instance]: Spin } = {}

local function speedOf(target: Instance): number
	local speed = target:GetAttribute("SpinSpeed")
	return if type(speed) == "number" then speed else DEFAULT_SPEED
end

local function adopt(target: Instance)
	if spinning[target] or not (target:IsA("Model") or target:IsA("BasePart")) then
		return
	end
	local axis = target:GetAttribute("SpinAxis")
	local unit = if typeof(axis) == "Vector3" and axis.Magnitude > 1e-3 then axis.Unit else Vector3.xAxis
	-- The handle spins at baseSpeed; SetSpeed scales it, so a later SpinSpeed
	-- change (even to the other direction) is a ratio of this one.
	local baseSpeed = speedOf(target)
	if baseSpeed == 0 then
		baseSpeed = DEFAULT_SPEED
	end
	local entry: Spin = { handle = Motion.spin(target, unit, baseSpeed), baseSpeed = baseSpeed }
	entry.handle:SetSpeed(speedOf(target) / baseSpeed)
	spinning[target] = entry
	target:GetAttributeChangedSignal("SpinSpeed"):Connect(function()
		local current = spinning[target]
		if current then
			current.handle:SetSpeed(speedOf(target) / current.baseSpeed)
		end
	end)
end

local function release(target: Instance)
	local entry = spinning[target]
	if entry then
		entry.handle:Stop()
		spinning[target] = nil
	end
end

function SpinnerController.init(_deps: any) end

function SpinnerController.start()
	for _, target in CollectionService:GetTagged(TAG) do
		adopt(target)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(adopt)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(release)
end

return SpinnerController
