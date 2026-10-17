--!strict
-- Spring: a damped spring that chases a target -- smooth follow, camera kick,
-- FOV easing, wobble. Works for numbers, Vector2 and Vector3.
--
--   local s = Spring.new(0, 18, 1)   -- start, speed (higher = snappier), damping (1 = no overshoot)
--   s.target = 10                    -- every frame: local value = s:Update(dt)
--   s:Impulse(40)                    -- kick its velocity
--   s:Snap(0)                        -- jump straight to a value, at rest

local Spring = {}
Spring.__index = Spring

-- Substep size: keeps stiff springs stable at low frame rates.
local MAX_STEP = 1 / 120

function Spring.new(initial: any, speed: number?, damping: number?)
	local zero = initial * 0
	return setmetatable({
		position = initial,
		velocity = zero,
		target = initial,
		speed = speed or 15,
		damping = damping or 1,
		_zero = zero,
	}, Spring)
end

function Spring:Update(dt: number): any
	local steps = math.max(1, math.ceil(dt / MAX_STEP))
	local h = dt / steps
	local k = self.speed * self.speed
	local c = 2 * self.damping * self.speed
	for _ = 1, steps do
		local accel = (self.target - self.position) * k - self.velocity * c
		self.velocity += accel * h
		self.position += self.velocity * h
	end
	return self.position
end

function Spring:Impulse(velocity: any)
	self.velocity += velocity
end

function Spring:Snap(value: any)
	self.position = value
	self.target = value
	self.velocity = self._zero
end

-- True when it has (practically) stopped at its target.
function Spring:IsResting(epsilon: number?): boolean
	local e = epsilon or 1e-3
	local offset = self.target - self.position
	local function size(v: any): number
		return if type(v) == "number" then math.abs(v) else v.Magnitude
	end
	return size(offset) < e and size(self.velocity) < e
end

return Spring
