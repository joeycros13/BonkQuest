--!strict
-- Critters: clips for World 2's ambient animals on PartRig -- deer, squirrels and the owl.
--
--   Critters.clip(kind)   procedural, priority Movement, one per kind ("Deer" / "Squirrel" /
--                         "Owl"), cached. Play with params = state (below).
--
-- CritterController is the brain: it decides what each animal does and writes TARGETS into
-- state.target. This clip eases every value toward its target (state.rate[field], else the
-- kind's RATE) and turns the result into channels, so all motion is smooth.
-- Fields (radians / studs / 0..1):
--   headYaw  headTilt (nose up)  headRoll  lean (forward)  lift  lunge
--   sit (squirrel up on its haunches)  arms  legs  tail  wing (owl wings out)
--   earL earR (deer ears flicked back)  chew (grazing deer)
-- Not eased: state.hop = 0..1 through the current hop (squirrels; nil between hops) and
-- state.shuffle = 0..1 (a deer stepping round on the spot).
--
-- Deer ears are the rig's arms: their channel carries the head's motion too, so they stay
-- on the head when it dips to graze, with the flick on top. The squirrel's tail is its
-- LeftBackLeg slot (attribute Role = "Tail"), so it can flick on its own.

local Animation = script.Parent.Parent
local Clip = require(Animation.Clip)

local Critters = {}

Critters.FIELDS = { "headYaw", "headTilt", "headRoll", "lean", "lift", "lunge", "sit", "arms", "legs", "tail", "wing", "earL", "earR", "chew" }

-- Default easing rate per kind (higher = snappier): squirrels twitch, deer and the owl glide.
Critters.RATE = { Deer = 2.5, Squirrel = 12, Owl = 6 }

-- A squirrel sitting up tips back this far about a pivot at its hind feet (relative to the
-- feet line's centre), with the hind legs counter-turned so the feet stay down, the front
-- paws raised to the chest and the head tipped forward to keep looking ahead.
Critters.SIT = { angle = math.rad(55), pivot = Vector3.new(0, 0.1, 0.3), paws = 1.3, head = 0.85 }

local function pulse(u: number, a: number, b: number): number
	if u <= a or u >= b then
		return 0
	end
	return math.sin((u - a) / (b - a) * math.pi)
end

local function ease(s: any, dt: number, default: number): { [string]: number }
	local cur, target, rate = s.cur, s.target, s.rate
	for _, k in Critters.FIELDS do
		local c = cur[k] or 0
		cur[k] = c + ((target[k] or 0) - c) * (1 - math.exp(-(rate[k] or default) * dt))
	end
	return cur
end

-- ==================== deer ====================

local function deer(track: any, out: { [string]: CFrame }, dt: number): number
	local s = track.params
	local c = ease(s, dt, Critters.RATE.Deer)
	local now = os.clock()
	out.Body = CFrame.new(0, c.lift + 0.02 * math.sin(now * 1.3 + s.seed), -c.lunge) * CFrame.Angles(-c.lean, 0, 0)
	local head = CFrame.Angles(0, c.headYaw, 0) * CFrame.Angles(c.headTilt + c.chew * 0.05 * math.sin(now * 7), 0, c.headRoll)
	out.Head = head
	-- the ears ride on the head (its motion about the neck), then flick back about their own base
	local joints = s.rig.channels
	local jh = joints.Head
	local carried = CFrame.new(jh) * head * CFrame.new(-jh)
	local jl, jr = joints.LeftArm, joints.RightArm
	out.LeftArm = CFrame.new(-jl) * carried * CFrame.new(jl) * CFrame.Angles(0, c.earL, 0)
	out.RightArm = CFrame.new(-jr) * carried * CFrame.new(jr) * CFrame.Angles(0, -c.earR, 0)
	-- stepping round on the spot: diagonal pairs, like the enemy trot
	local step = (s.shuffle or 0) * 0.2 * math.sin(now * 9)
	out.LeftLeg = CFrame.Angles(step, 0, 0)
	out.RightBackLeg = CFrame.Angles(step, 0, 0)
	out.RightLeg = CFrame.Angles(-step, 0, 0)
	out.LeftBackLeg = CFrame.Angles(-step, 0, 0)
	return 1
end

-- ==================== squirrel ====================

local function squirrel(track: any, out: { [string]: CFrame }, dt: number): number
	local s = track.params
	local c = ease(s, dt, Critters.RATE.Squirrel)
	local now = os.clock()
	local lift, lean, legs, arms, tail = c.lift, c.lean, c.legs, c.arms, c.tail
	local u = s.hop
	if u then
		lift += 0.42 * math.sin(math.pi * u)
		lean += 0.22 * math.sin(2 * math.pi * u) -- nose down taking off, nose up landing
		legs += -0.7 * pulse(u, 0, 0.55) + 0.3 * pulse(u, 0.5, 1) -- push off, then tuck
		arms += 0.7 * pulse(u, 0.35, 0.95) -- reach for the landing
		tail += 0.35 * math.sin(math.pi * u) -- streams out behind
	end
	local SIT = Critters.SIT
	local sit = c.sit
	local P = SIT.pivot
	lift += 0.012 * math.sin(now * 5 + s.seed)
	out.Body = CFrame.new(0, lift, -c.lunge) * CFrame.new(P) * CFrame.Angles(-lean + SIT.angle * sit, 0, 0) * CFrame.new(-P)
	out.Head = CFrame.Angles(0, c.headYaw, 0)
		* CFrame.Angles(c.headTilt - SIT.head * sit + sit * 0.06 * math.sin(now * 14), 0, c.headRoll)
	out.LeftLeg = CFrame.Angles(legs - SIT.angle * sit, 0, 0)
	out.RightLeg = CFrame.Angles(legs - SIT.angle * sit, 0, 0)
	out.LeftArm = CFrame.Angles(arms + SIT.paws * sit, 0, 0)
	out.RightArm = CFrame.Angles(arms + SIT.paws * sit, 0, 0)
	out.LeftBackLeg = CFrame.Angles(tail, 0, 0) -- the tail
	return 1
end

-- ==================== owl ====================

local function owl(track: any, out: { [string]: CFrame }, dt: number): number
	local s = track.params
	local c = ease(s, dt, Critters.RATE.Owl)
	local now = os.clock()
	out.Body = CFrame.new(0, c.lift + 0.015 * math.sin(now * 1.6 + s.seed), 0) * CFrame.Angles(-c.lean, 0, 0)
	out.Head = CFrame.Angles(0, c.headYaw, 0) * CFrame.Angles(c.headTilt, 0, c.headRoll)
	out.LeftArm = CFrame.Angles(0, 0, -c.wing)
	out.RightArm = CFrame.Angles(0, 0, c.wing)
	return 1
end

local EVALUATE: { [string]: (any, { [string]: CFrame }, number) -> number } = { Deer = deer, Squirrel = squirrel, Owl = owl }
local cache: { [string]: any } = {}

function Critters.clip(kind: string): any?
	local cached = cache[kind]
	if cached then
		return cached
	end
	local evaluate = EVALUATE[kind]
	if not evaluate then
		return nil
	end
	local clip = Clip.procedural({ name = "Critter_" .. kind, priority = "Movement", fadeIn = 0, evaluate = evaluate })
	cache[kind] = clip
	return clip
end

return Critters
