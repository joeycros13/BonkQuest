--!strict
-- Easing: turns linear progress t (0..1) into eased progress.
--
-- Names are <Style><Direction>, e.g. "QuadOut", "BackInOut", "SineIn":
--   styles     Sine Quad Cubic Quart Quint Expo Circ Back Elastic Bounce
--   directions In (slow start) Out (slow end) InOut (both)
-- plus Linear, Constant (jumps at the end), Smooth and Smoother (smoothstep).
-- Anything that takes an ease accepts a name, a function, or nil (Linear).
--
--   Easing.get("BackOut")(0.5)
--   Easing.bezier(0.25, 0.1, 0.25, 1)   -- CSS-style cubic-bezier
--   Easing.fromEnum(pose.EasingStyle, pose.EasingDirection)

local Easing = {}

export type EaseFn = (number) -> number

local pi = math.pi
local BACK = 1.70158

local function linear(t: number): number
	return t
end

local function bounceOut(t: number): number
	local n, d = 7.5625, 2.75
	if t < 1 / d then
		return n * t * t
	elseif t < 2 / d then
		t -= 1.5 / d
		return n * t * t + 0.75
	elseif t < 2.5 / d then
		t -= 2.25 / d
		return n * t * t + 0.9375
	end
	t -= 2.625 / d
	return n * t * t + 0.984375
end

-- The "In" form of each style; Out and InOut are derived from it.
local IN: { [string]: EaseFn } = {
	Sine = function(t)
		return 1 - math.cos(t * pi / 2)
	end,
	Quad = function(t)
		return t * t
	end,
	Cubic = function(t)
		return t * t * t
	end,
	Quart = function(t)
		return t * t * t * t
	end,
	Quint = function(t)
		return t * t * t * t * t
	end,
	Expo = function(t)
		return if t <= 0 then 0 else 2 ^ (10 * (t - 1))
	end,
	Circ = function(t)
		return 1 - math.sqrt(math.max(0, 1 - t * t))
	end,
	Back = function(t)
		return t * t * ((BACK + 1) * t - BACK)
	end,
	Elastic = function(t)
		if t <= 0 or t >= 1 then
			return t
		end
		return -(2 ^ (10 * (t - 1))) * math.sin((t - 1.075) * (2 * pi) / 0.3)
	end,
	Bounce = function(t)
		return 1 - bounceOut(1 - t)
	end,
}

local styles: { [string]: EaseFn } = {
	Linear = linear,
	Constant = function(t)
		return if t >= 1 then 1 else 0
	end,
	Smooth = function(t)
		return t * t * (3 - 2 * t)
	end,
	Smoother = function(t)
		return t * t * t * (t * (t * 6 - 15) + 10)
	end,
}
for name, f in IN do
	styles[name .. "In"] = f
	styles[name .. "Out"] = function(t)
		return 1 - f(1 - t)
	end
	styles[name .. "InOut"] = function(t)
		if t < 0.5 then
			return f(t * 2) / 2
		end
		return 1 - f((1 - t) * 2) / 2
	end
end

Easing.styles = styles

local warned: { [string]: boolean } = {}

function Easing.get(ease: any): EaseFn
	if type(ease) == "function" then
		return ease
	end
	if type(ease) == "string" then
		local f = styles[ease]
		if f then
			return f
		end
		if not warned[ease] then
			warned[ease] = true
			warn(("[Animation.Easing] unknown ease %q; using Linear"):format(ease))
		end
	end
	return linear
end

-- Roblox's EasingStyle / PoseEasingStyle with an EasingDirection / PoseEasingDirection.
function Easing.fromEnum(style: EnumItem?, direction: EnumItem?): EaseFn
	local name = if style then style.Name else "Linear"
	if name == "CubicV2" then
		name = "Cubic"
	end
	if name == "Linear" or name == "Constant" then
		return styles[name]
	end
	local dir = if direction then direction.Name else "In"
	return styles[name .. dir] or linear
end

-- CSS-style cubic-bezier(x1, y1, x2, y2), solved with a few Newton steps.
function Easing.bezier(x1: number, y1: number, x2: number, y2: number): EaseFn
	local function curve(a: number, b: number, u: number): number
		return 3 * a * u * (1 - u) ^ 2 + 3 * b * u * u * (1 - u) + u * u * u
	end
	local function slope(a: number, b: number, u: number): number
		return 3 * a * (1 - u) ^ 2 + 6 * (b - a) * u * (1 - u) + 3 * (1 - b) * u * u
	end
	return function(t: number): number
		local u = t
		for _ = 1, 6 do
			local d = slope(x1, x2, u)
			if math.abs(d) < 1e-6 then
				break
			end
			u -= (curve(x1, x2, u) - t) / d
		end
		return curve(y1, y2, math.clamp(u, 0, 1))
	end
end

return Easing
