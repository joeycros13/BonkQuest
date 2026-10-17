--!strict
-- Tween: animate any property over time -- numbers, Vector3, Vector2, CFrame,
-- Color3, UDim2, UDim -- plus two pseudo-properties:
--   Pivot  a Model's (or part's) pivot, moved with PivotTo
--   Scale  a Model's scale (Model:ScaleTo)
-- Anchored parts' CFrame tweens go through the batched part mover.
--
--   local t = Tween.to(door, { CFrame = openCF }, 0.6, "BackOut")
--   t.Completed:Connect(fn)   t:Pause()   t:Play()   t:Cancel()
--   Tween.new(model, { Pivot = cf, Scale = 1.5 }, { time = 1, ease = "SineInOut",
--     delay = 0.2, repeats = 2, reverses = true }):Play()
--   Tween.native(frame, { Size = UDim2.fromScale(1, 1) }, 0.3)  -- Roblox TweenService
--   Tween.chain({ tweenA, tweenB, function() ... end })        -- one after another
--
-- A new tween on the same property of the same target replaces the old one.

local TweenService = game:GetService("TweenService")

local Animation = script.Parent
local Easing = require(Animation.Easing)
local Scheduler = require(Animation.Scheduler)
local Signal = require(Animation.Signal)
local PartBatch = require(Animation.PartBatch)

local Tween = {}
Tween.__index = Tween

local active: { any } = {}

local function lerp(a: any, b: any, t: number): any
	local kind = typeof(a)
	if kind == "number" then
		return a + (b - a) * t
	elseif kind == "CFrame" or kind == "Vector3" or kind == "Vector2" or kind == "Color3" or kind == "UDim2" then
		return a:Lerp(b, t)
	elseif kind == "UDim" then
		return UDim.new(a.Scale + (b.Scale - a.Scale) * t, a.Offset + (b.Offset - a.Offset) * t)
	end
	return if t >= 1 then b else a
end

local function read(target: any, prop: string): any
	if prop == "Pivot" then
		return target:GetPivot()
	elseif prop == "Scale" then
		return target:GetScale()
	end
	return target[prop]
end

local function write(target: any, prop: string, value: any)
	if prop == "Pivot" then
		if target:IsA("BasePart") and target.Anchored then
			PartBatch.push(target, value)
		else
			target:PivotTo(value)
		end
	elseif prop == "Scale" then
		target:ScaleTo(value)
	elseif prop == "CFrame" and target:IsA("BasePart") and target.Anchored then
		PartBatch.push(target, value)
	else
		target[prop] = value
	end
end

function Tween.new(target: Instance, goals: { [string]: any }, info: any?)
	local options = info or {}
	return setmetatable({
		target = target,
		goals = goals,
		time = math.max(options.time or 0.25, 1e-3),
		ease = Easing.get(options.ease or "QuadOut"),
		delay = options.delay or 0,
		repeats = options.repeats or 0, -- extra plays after the first; -1 = forever
		reverses = options.reverses == true,
		state = "Idle", -- Idle Playing Paused Completed Cancelled
		elapsed = 0,
		starts = {} :: { [string]: any },
		Completed = Signal.new(),
	}, Tween)
end

function Tween:Play()
	if self.state == "Playing" then
		return self
	end
	if self.state ~= "Paused" then
		self.elapsed = 0
		for prop in self.goals do
			self.starts[prop] = read(self.target, prop)
		end
		-- Replace any running tween of the same property on the same target.
		for _, other in active do
			if other ~= self and other.target == self.target then
				for prop in self.goals do
					other.goals[prop] = nil
				end
				if next(other.goals) == nil then
					other:Cancel()
				end
			end
		end
	end
	self.state = "Playing"
	table.insert(active, self)
	return self
end

local function remove(self: any)
	local index = table.find(active, self)
	if index then
		table.remove(active, index)
	end
end

function Tween:Pause()
	if self.state == "Playing" then
		self.state = "Paused"
		remove(self)
	end
end

function Tween:Cancel()
	if self.state == "Playing" or self.state == "Paused" then
		self.state = "Cancelled"
		remove(self)
		self.Completed:Fire("Cancelled")
	end
end

-- Advance; returns false when finished.
function Tween:_step(dt: number): boolean
	if not self.target.Parent then
		self.state = "Cancelled"
		return false
	end
	self.elapsed += dt
	local t = self.elapsed - self.delay
	if t < 0 then
		return true
	end
	local cycle = math.floor(t / self.time)
	local finished = self.repeats >= 0 and cycle > self.repeats
	local u = if finished then 1 else (t - cycle * self.time) / self.time
	local backwards = self.reverses and (if finished then self.repeats % 2 == 1 else cycle % 2 == 1)
	local alpha = self.ease(if backwards then 1 - u else u)
	if finished and self.reverses and self.repeats % 2 == 1 then
		alpha = 0
	end
	for prop, goal in self.goals do
		write(self.target, prop, lerp(self.starts[prop], goal, alpha))
	end
	if finished then
		self.state = "Completed"
		self.Completed:Fire("Completed")
		return false
	end
	return true
end

function Tween.to(target: Instance, goals: { [string]: any }, time: number?, ease: any?, delay: number?)
	return Tween.new(target, goals, { time = time, ease = ease, delay = delay }):Play()
end

-- Roblox's TweenService, for simple GUI / property tweens that don't need this
-- system's extras (it runs natively and is the cheapest option).
function Tween.native(target: Instance, goals: { [string]: any }, time: number?, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local tween = TweenService:Create(target, TweenInfo.new(time or 0.25, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goals)
	tween:Play()
	return tween
end

-- Play tweens (or call functions) one after another. Returns { Cancel, Completed }.
function Tween.chain(steps: { any })
	local handle = { Completed = Signal.new(), cancelled = false, current = nil :: any }
	function handle.Cancel(_self: any)
		handle.cancelled = true
		if handle.current then
			handle.current:Cancel()
		end
	end
	task.spawn(function()
		for _, step in steps do
			if handle.cancelled then
				return
			end
			if type(step) == "function" then
				step()
			elseif type(step) == "number" then
				task.wait(step)
			else
				handle.current = step
				if step.state ~= "Playing" then
					step:Play()
				end
				if step.state == "Playing" then
					step.Completed:Wait()
				end
			end
		end
		handle.Completed:Fire()
	end)
	return handle
end

Scheduler.bind("Render", "Tween", 20, function(dt)
	local i = 1
	while i <= #active do
		local tween = active[i]
		if tween:_step(dt) then
			i += 1
		else
			table.remove(active, i)
		end
	end
end)

return Tween
