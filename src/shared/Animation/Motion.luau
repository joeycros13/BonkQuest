--!strict
-- Motion: ready-made movement for parts, models and attachments.
--
-- One-shot (return a Tween):
--   Motion.moveTo(target, cframe, time, ease)
--   Motion.moveBy(target, Vector3 | CFrame, time, ease)    -- world offset / local CFrame
--   Motion.rotate(target, Vector3.new(pitch, yaw, roll), time, ease)  -- degrees, around its pivot
--   Motion.path(target, { points }, time, ease, { face = true })      -- smooth curve through points
-- Continuous (return a handle with :Stop() and :SetSpeed(k)):
--   Motion.spin(target, axis, degreesPerSecond)
--   Motion.bob(target, amplitude, period, axis?)      -- up and down
--   Motion.sway(target, degrees, period, axis?)       -- rock back and forth
--   Motion.follow(target, getCFrame, sharpness?)      -- glide after a moving goal
-- Continuous motions start from the target's pose when created, so don't run
-- two on the same target or move it some other way at the same time.

local Animation = script.Parent
local Easing = require(Animation.Easing)
local Pose = require(Animation.Pose)
local Scheduler = require(Animation.Scheduler)
local Signal = require(Animation.Signal)
local Tween = require(Animation.Tween)
local PartBatch = require(Animation.PartBatch)

local Motion = {}

local running: { any } = {}

local function getCFrame(target: any): CFrame
	if target:IsA("Model") then
		return target:GetPivot()
	elseif target:IsA("BasePart") or target:IsA("Attachment") then
		return target.CFrame
	end
	error("Motion target must be a Model, BasePart or Attachment")
end

local function setCFrame(target: any, cframe: CFrame)
	if target:IsA("Model") then
		target:PivotTo(cframe)
	elseif target:IsA("BasePart") and target.Anchored then
		PartBatch.push(target, cframe)
	else
		target.CFrame = cframe
	end
end

local function propOf(target: any): string
	return if target:IsA("Model") then "Pivot" else "CFrame"
end

-- ==================== one-shot ====================

function Motion.moveTo(target: Instance, cframe: CFrame, time: number?, ease: any?)
	return Tween.to(target, { [propOf(target)] = cframe }, time, ease)
end

function Motion.moveBy(target: Instance, offset: any, time: number?, ease: any?)
	local current = getCFrame(target)
	local goal = if typeof(offset) == "Vector3" then current + offset else current * offset
	return Motion.moveTo(target, goal, time, ease)
end

function Motion.rotate(target: Instance, degrees: Vector3, time: number?, ease: any?)
	local goal = getCFrame(target) * Pose.angles(degrees.X, degrees.Y, degrees.Z)
	return Motion.moveTo(target, goal, time, ease)
end

-- Catmull-Rom point on the curve through p0..p3, between p1 and p2.
local function catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

-- ==================== continuous ====================

local function continuous(target: Instance, update: (CFrame, number) -> CFrame)
	local handle = { target = target, base = getCFrame(target), time = 0, speed = 1, alive = true, update = update }
	function handle.Stop(_self: any, restore: boolean?)
		handle.alive = false
		if restore and target.Parent then
			setCFrame(target, handle.base)
		end
	end
	function handle.SetSpeed(_self: any, k: number)
		handle.speed = k
	end
	table.insert(running, handle)
	return handle
end

-- Travel a smooth curve from where the target is through each point. The
-- handle also has .Completed (fires on arrival).
function Motion.path(target: Instance, points: { any }, time: number?, ease: any?, opts: any?)
	local options = opts or {}
	local duration = math.max(time or 1, 1e-3)
	local easeFn = Easing.get(ease or "Linear")
	local start = getCFrame(target)
	local positions: { Vector3 } = { start.Position }
	for _, point in points do
		table.insert(positions, if typeof(point) == "CFrame" then point.Position else point)
	end
	local segments = #positions - 1
	local handle
	handle = continuous(target, function(_base, elapsed)
		local u = easeFn(math.clamp(elapsed / duration, 0, 1))
		local scaled = u * segments
		local i = math.clamp(math.floor(scaled) + 1, 1, segments)
		local t = scaled - (i - 1)
		local p0 = positions[math.max(i - 1, 1)]
		local p1, p2 = positions[i], positions[i + 1]
		local p3 = positions[math.min(i + 2, #positions)]
		local position = catmull(p0, p1, p2, p3, t)
		local rotation = start.Rotation
		if options.face ~= false then
			local ahead = catmull(p0, p1, p2, p3, math.min(t + 0.02, 1))
			if (ahead - position).Magnitude > 1e-3 then
				rotation = CFrame.lookAt(position, ahead).Rotation
			end
		end
		if elapsed >= duration then
			handle.alive = false
			task.defer(function()
				handle.Completed:Fire()
			end)
		end
		return CFrame.new(position) * rotation
	end)
	handle.Completed = Signal.new()
	if segments < 1 then
		handle.alive = false
	end
	return handle
end

function Motion.spin(target: Instance, axis: Vector3, degreesPerSecond: number)
	local unit = axis.Unit
	return continuous(target, function(base, t)
		return base * CFrame.fromAxisAngle(unit, math.rad(degreesPerSecond * t))
	end)
end

function Motion.bob(target: Instance, amplitude: number, period: number, axis: Vector3?)
	local direction = axis or Vector3.yAxis
	return continuous(target, function(base, t)
		return base + direction * (amplitude * math.sin(t * 2 * math.pi / period))
	end)
end

function Motion.sway(target: Instance, degrees: number, period: number, axis: Vector3?)
	local unit = (axis or Vector3.zAxis).Unit
	return continuous(target, function(base, t)
		return base * CFrame.fromAxisAngle(unit, math.rad(degrees * math.sin(t * 2 * math.pi / period)))
	end)
end

-- Glide toward getCFrame() every frame; sharpness ~ how quickly it catches up.
function Motion.follow(target: Instance, getGoal: () -> CFrame, sharpness: number?)
	local k = sharpness or 12
	local handle
	handle = continuous(target, function(_base, _t)
		local current = getCFrame(target)
		return current:Lerp(getGoal(), 1 - math.exp(-k * handle.lastDt))
	end)
	handle.lastDt = 0
	return handle
end

Scheduler.bind("Render", "Motion", 30, function(dt)
	local i = 1
	while i <= #running do
		local handle = running[i]
		if not handle.alive or not handle.target.Parent then
			table.remove(running, i)
			continue
		end
		i += 1
		handle.time += dt * handle.speed
		handle.lastDt = dt
		setCFrame(handle.target, handle.update(handle.base, handle.time))
	end
end)

-- Re-export so `Motion.ease("QuadOut")` is at hand for custom motions.
Motion.ease = Easing.get

return Motion
