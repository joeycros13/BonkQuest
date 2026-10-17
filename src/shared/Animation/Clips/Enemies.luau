--!strict
-- Enemies: clips for part-built enemies (PartRig).
--
--   EnemyClips.walk                 procedural, priority Movement: idle sway and a
--                                   walk / trot cycle that fades in with speed.
--                                   Play with params = { rig = partRig }.
--   EnemyClips.move(name, hanging)  additive, priority Action: an attack move
--                                   layered ON the walk, so legs keep going.
--                                   Names: peck gore stab pounce charge slam stomp smash claw slash zap
--                                   swoop punch legstab rearslam
--                                   Marker "Strike" at the moment the blow lands.
--   EnemyClips.flinch(hanging)      additive, priority Override: a short recoil.
-- `hanging` = the rig has avatar-style hanging arms (ArmStyle = "Hanging");
-- otherwise arms are wings. Clips are built once and cached.
--
-- Moves are written as the old pulse functions over u = 0..1 and sampled into
-- keyframes. Pose fields (radians / studs):
--   lean (forward)  roll  lift  lunge (forward)  armUp  armFwd  leg  headYaw
--   headTilt (nose up)  rightFwd  leftFwd (one arm's extra forward swing)
--   rightPush (right arm jab, studs)  rightOut (hanging right arm out to the side)
--   rightSide (tips the right arm, as raised, out sideways: keeps a raised hand clear of the head)
--   fore (both front legs forward)  hind (both back legs back)  legL (left leg
--   forward)  kneeL / kneeR (knee bend, shin back)  crouch (both legs: thigh
--   forward, knee bent twice as far)  elbow (both forearms bend forward)
--   elbowL / elbowR (one forearm).
--   Knee and elbow fields only move rigs with lower limbs (PartRig CHAIN).

local Animation = script.Parent.Parent
local Clip = require(Animation.Clip)

local Enemies = {}

Enemies.MOVE_DURATION = {
	peck = 0.5,
	gore = 0.85,
	stab = 0.9,
	pounce = 0.8, -- Fox
	charge = 0.85, -- Wild Boar
	slam = 1.3, -- Grizzly Bear
	stomp = 1.2, -- Elder Treant
	smash = 1.2, -- Elder Treant (its second attack; lands on the same windup as stomp)
	claw = 0.9, -- (unused since the Corn Wraith moved to slash; kept for later enemies)
	slash = 0.8, -- Corn Wraith (secret): one-handed diagonal slash
	zap = 0.75, -- Fairy (secret): wand zap
	swoop = 0.75, -- Cave Bat: swoop-bite
	punch = 0.8, -- Pebble Golem: wind-up punch
	legstab = 1.2, -- Spider Queen: front-leg stab
	rearslam = 1.2, -- Spider Queen (second attack; lands on the same windup as legstab)
}

-- Where (fraction of the move) the "Strike" marker sits: the blow's peak.
Enemies.STRIKE = { peck = 0.55, gore = 0.68, stab = 0.6, pounce = 0.65, charge = 0.68, slam = 0.62, stomp = 0.62, smash = 0.62, claw = 0.62, slash = 0.6, zap = 0.6, swoop = 0.62, punch = 0.6, legstab = 0.62, rearslam = 0.62 }

-- Walk tuning.
Enemies.WALK = {
	speedForFull = 2.5, -- studs/s at which the walk reaches full strength
	blendRate = 6,
	strideRate = 1.8, -- cycles per second at full walk
	legSwing = math.rad(28),
	armFlap = math.rad(14),
	bodySway = math.rad(6),
	bodyBob = 0.14,
	hoverRate = 1.6, -- floating rigs (model attribute Hover = bob height in studs) bob at this rate
	wingRate = 7, -- rigs with LeftWing / RightWing flutter this many beats a second
	wingSwing = math.rad(28), -- how far each wing beats back and forth about the back
	-- rigs with model attribute WingStyle = "Flap" (the Cave Bat) beat their wings up
	-- and down instead, slower and wider, the body rising on each downstroke
	flapRate = 4,
	flapSwing = math.rad(35),
	flapBob = 0.08,
	hangingArmSwing = 0.8, -- hanging arms swing this fraction of the legs
	kneeBend = math.rad(25), -- rigs with knees bend each knee as its leg swings forward
	elbowRest = math.rad(10), -- rigs with elbows never hang dead straight
	elbowSwing = math.rad(20), -- extra bend as each arm swings forward
}

local SAMPLES = 16

local function pulse(u: number, a: number, b: number): number
	if u <= a or u >= b then
		return 0
	end
	return math.sin((u - a) / (b - a) * math.pi)
end

-- 0 before a, 1 after b, eased in between (holds a pose, unlike pulse)
local function smooth(u: number, a: number, b: number): number
	local t = math.clamp((u - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local function fields()
	return {
		lean = 0, roll = 0, lift = 0, lunge = 0, armUp = 0, armFwd = 0, armFlap = 0, leg = 0, headYaw = 0, headTilt = 0, rightFwd = 0, leftFwd = 0, rightPush = 0, rightOut = 0, rightSide = 0,
		fore = 0, hind = 0, legL = 0, kneeL = 0, kneeR = 0, crouch = 0, elbow = 0, elbowL = 0, elbowR = 0,
	}
end

-- Pose fields -> channels.
local function toChannels(p: any, hanging: boolean, out: { [string]: CFrame })
	out.Body = CFrame.new(0, p.lift, -p.lunge) * CFrame.Angles(-p.lean, 0, 0) * CFrame.Angles(0, 0, p.roll)
	out.Head = CFrame.Angles(p.headTilt, p.headYaw, 0)
	local push = CFrame.new(0, 0, -p.rightPush)
	if hanging then
		local swing = p.leg * Enemies.WALK.hangingArmSwing
		out.LeftArm = CFrame.Angles(p.armFwd + p.leftFwd - swing, 0, 0) * CFrame.Angles(0, 0, -p.armUp * 0.5)
		out.RightArm = push * CFrame.Angles(0, 0, -p.rightSide) * CFrame.Angles(p.armFwd + p.rightFwd + swing, 0, 0) * CFrame.Angles(0, 0, p.armUp * 0.5 + p.rightOut)
	else
		out.LeftArm = CFrame.Angles(0, -(p.armFwd + p.leftFwd), 0) * CFrame.Angles(0, 0, -(p.armUp + p.armFlap))
		out.RightArm = push * CFrame.Angles(0, p.armFwd + p.rightFwd, 0) * CFrame.Angles(0, 0, p.armUp - p.armFlap)
	end
	-- Trot pairs: each back leg swings with the diagonally opposite front leg.
	out.LeftLeg = CFrame.Angles(p.leg + p.fore + p.legL + p.crouch, 0, 0)
	out.RightBackLeg = CFrame.Angles(p.leg - p.hind, 0, 0)
	out.RightLeg = CFrame.Angles(-p.leg + p.fore + p.crouch, 0, 0)
	out.LeftBackLeg = CFrame.Angles(-p.leg - p.hind, 0, 0)
	-- Knees and elbows (only rigs that have lower limbs use these channels).
	out.LeftLowerLeg = CFrame.Angles(-(p.kneeL + 2 * p.crouch), 0, 0)
	out.RightLowerLeg = CFrame.Angles(-(p.kneeR + 2 * p.crouch), 0, 0)
	out.LeftLowerArm = CFrame.Angles(p.elbow + p.elbowL, 0, 0)
	out.RightLowerArm = CFrame.Angles(p.elbow + p.elbowR, 0, 0)
end

-- ==================== moves ====================

local MOVES: { [string]: (any, number) -> () } = {
	-- Rear back with the head up, then stab the beak down and forward.
	peck = function(p, u)
		local rear, strike = pulse(u, 0, 0.4), pulse(u, 0.3, 0.8)
		p.lean += -0.2 * rear + 0.55 * strike
		p.lunge += 0.9 * strike
		p.headTilt += 0.35 * rear - 0.95 * strike
		p.armUp += 0.5 * strike
	end,
	-- Step back with the head down, charge horns-first, toss the head at the end.
	gore = function(p, u)
		local back, strike = pulse(u, 0, 0.5), pulse(u, 0.4, 0.95)
		local lowered, toss = pulse(u, 0, 0.8), pulse(u, 0.65, 1)
		p.lunge += -0.6 * back + 2.4 * strike
		p.lean += -0.1 * back + 0.18 * strike
		p.headTilt += -0.6 * lowered + 0.7 * toss
		p.leg += 0.45 * math.sin(u * math.pi * 6) * strike
	end,
	-- Scarecrow King: a spear jab (user, 2026-10-11: "a jab instead of a bonk down",
	-- with the elbows and knees in it). He steps into a stance -- left leg forward
	-- with the knee bent, right leg back -- drawing the fork back in his right hand
	-- as the left hand comes up in front; then only the right arm thrusts straight
	-- out while the left arm swings back. The right forearm stays upright the whole
	-- time (rightFwd + elbowR = 0, and the walk's resting elbow bend is taken out),
	-- so the fork stays level instead of swinging down.
	stab = function(p, u)
		local stance = smooth(u, 0, 0.35) - smooth(u, 0.8, 1)
		local draw = smooth(u, 0, 0.4) - smooth(u, 0.45, 0.62)
		local thrust = smooth(u, 0.45, 0.62) - smooth(u, 0.78, 1)
		-- legs: step into the stance; the body drops a little so the feet stay down
		p.leg += 0.35 * stance
		p.kneeL += 0.4 * stance
		p.lift += -0.1 * stance
		-- `leg` also swings hanging arms like a walk would; take that back out
		local swing = 0.35 * stance * Enemies.WALK.hangingArmSwing
		p.rightFwd -= swing
		p.leftFwd += swing
		-- right arm: draw back level, then the jab
		p.rightPush += -1.3 * draw + 2.4 * thrust
		p.rightFwd += -0.45 * draw + 0.06 * thrust -- the 0.06 cancels the lean below
		p.elbowR += 0.45 * draw - Enemies.WALK.elbowRest * stance
		-- left arm: up in front on the draw, back on the jab
		p.leftFwd += 0.6 * draw - 0.65 * thrust
		p.elbowL += 0.55 * draw + 0.1 * thrust
		-- the body only rocks back and forward a touch: the arm does the jabbing
		p.lean += -0.04 * draw + 0.06 * thrust
		p.lunge += -0.15 * draw + 0.35 * thrust
	end,
	-- Fox: crouch low, spring forward with both forepaws reaching, snap at the end.
	pounce = function(p, u)
		local crouch, leap = pulse(u, 0, 0.45), pulse(u, 0.35, 0.9)
		local reach, bite = pulse(u, 0.35, 0.75), pulse(u, 0.5, 0.85)
		p.lift += -0.12 * crouch + 0.8 * leap
		p.lunge += -0.35 * crouch + 2.2 * leap
		p.lean += 0.12 * crouch - 0.25 * reach + 0.3 * bite
		p.fore += -0.3 * crouch + 0.9 * reach
		p.hind += 0.25 * crouch + 0.6 * reach
		p.headTilt += -0.2 * crouch + 0.15 * reach - 0.45 * bite
	end,
	-- Wild Boar: back up and dig in with the head low, charge tusks-first, rip the
	-- tusks up and to the side.
	charge = function(p, u)
		local back, strike = pulse(u, 0, 0.45), pulse(u, 0.35, 0.9)
		local low, rip = pulse(u, 0, 0.75), pulse(u, 0.6, 0.95)
		p.lunge += -0.5 * back + 2.6 * strike
		p.lean += 0.1 * back + 0.12 * strike
		p.headTilt += -0.5 * low + 0.8 * rip
		p.headYaw += 0.35 * rip
		p.hind += 0.3 * back
		p.leg += 0.5 * math.sin(u * math.pi * 8) * strike
	end,
	-- Grizzly Bear: rear up on the hind legs with the forepaws raised, hold, then
	-- slam down and forward. The body pivots on the hind feet, which stay planted
	-- (the bear's hips sit 2.16 up and 2.34 back from the feet line).
	slam = function(p, u)
		local up = smooth(u, 0, 0.4) - smooth(u, 0.5, 0.62)
		local hit = pulse(u, 0.56, 0.95)
		local a = 0.75 * up -- how far the body tips back
		p.lean += -a + 0.2 * hit
		p.lift += 2.16 * (1 - math.cos(a)) + 2.34 * math.sin(a) - 0.15 * hit
		p.lunge += 2.16 * math.sin(a) + 2.34 * math.cos(a) - 2.34 + 1.4 * hit
		p.hind += a
		p.fore += 0.6 * up - 0.3 * hit
		p.headTilt += -0.6 * up - 0.25 * hit
	end,
	-- Elder Treant: lift the left knee high with the arms spread for balance and the
	-- weight over the right foot, then stamp the foot down and sink into the blow.
	stomp = function(p, u)
		local up = smooth(u, 0, 0.42) - smooth(u, 0.5, 0.62)
		local hit = pulse(u, 0.56, 0.95)
		p.legL += 1.05 * up
		p.kneeL += 1.4 * up
		p.roll += -0.08 * up
		p.lift += 0.17 * up - 0.12 * hit
		p.lean += -0.1 * up + 0.16 * hit
		p.armUp += 0.7 * up - 0.2 * hit
		p.armFwd += 0.2 * up + 0.25 * hit
		p.elbow += 0.45 * up
		p.crouch += 0.18 * hit
		p.headTilt += 0.12 * up - 0.3 * hit
	end,
	-- Elder Treant: swing both arms up overhead with the elbows folded back and the
	-- body rearing, hold, then hammer both fists down in front while lunging into a
	-- crouch. Same length and strike as stomp, so one windup fits both.
	smash = function(p, u)
		local up = smooth(u, 0, 0.42)
		local down = smooth(u, 0.5, 0.62)
		local recover = smooth(u, 0.75, 1)
		local hit = pulse(u, 0.56, 1)
		p.armFwd += 2.6 * up - 2.8 * down + 0.2 * recover -- overhead, then fists down in front
		p.armUp += 0.35 * up - 0.35 * down -- spread a little going up, together for the blow
		p.elbow += 0.9 * up - 0.9 * down -- folded behind the head, straight on the blow
		p.lean += -0.12 * up + 0.57 * down - 0.45 * recover
		p.lift += 0.15 * up - 0.15 * down - 0.12 * hit
		p.crouch += 0.2 * hit
		p.headTilt += 0.3 * up - 0.2 * down
	end,
	-- Corn Wraith: rise and rear back with both leaf arms swept up high, then rake
	-- them down through the front while surging forward, head dipping into it.
	claw = function(p, u)
		local up = smooth(u, 0, 0.45) - smooth(u, 0.5, 0.64)
		local rake = smooth(u, 0.5, 0.64) - smooth(u, 0.78, 1)
		local hit = pulse(u, 0.52, 0.95)
		p.armFwd += 2.3 * up - 0.5 * rake
		p.armUp += 0.6 * up - 0.2 * rake
		p.lean += -0.18 * up + 0.3 * rake
		p.lift += 0.35 * up - 0.1 * hit
		p.lunge += -0.3 * up + 1.4 * hit
		p.headTilt += 0.2 * up - 0.3 * rake
	end,
	-- Corn Wraith (user, 2026-10-12: "a one handed slash diagonally"): the right leaf
	-- arm rises up and out to the right, the body leaning back and rolling right into
	-- the wind-up; then it slashes down and across to the lower left while the body
	-- surges forward. The left arm hangs back out of the way.
	slash = function(p, u)
		local up = smooth(u, 0, 0.42) - smooth(u, 0.5, 0.64)
		local cut = smooth(u, 0.5, 0.64) - smooth(u, 0.8, 1)
		local hit = pulse(u, 0.5, 0.95)
		p.rightFwd += 2.5 * up + 0.7 * cut      -- high over the shoulder, then down in front
		p.rightOut += 1.0 * up - 0.75 * cut     -- out to the right, then across to the left
		p.leftFwd += -0.25 * up - 0.15 * cut
		p.roll += 0.12 * up - 0.14 * cut
		p.lean += -0.12 * up + 0.22 * cut
		p.lift += 0.2 * up - 0.08 * hit
		p.lunge += -0.2 * up + 1.2 * hit
		p.headYaw += 0.25 * up - 0.3 * cut
	end,
	-- Fairy (user, 2026-10-12: "wand zap"): she rises a little and raises the wand
	-- high, then flicks it forward and down at you; the sparkles pop at the strike.
	zap = function(p, u)
		local up = smooth(u, 0, 0.45) - smooth(u, 0.5, 0.62)
		local flick = smooth(u, 0.5, 0.62) - smooth(u, 0.8, 1)
		local hit = pulse(u, 0.5, 0.95)
		-- her wand is held up in front already: lift it up and out to her right so the
		-- star shows beside her cap (straight up hid it behind the cap), then flick it
		-- forward and down past rest
		p.rightFwd += 0.75 * up - 0.55 * flick
		p.rightSide += 0.75 * up -- out past her right shoulder, clear of her head (user)
		p.lift += 0.35 * up - 0.1 * hit
		p.lean += -0.1 * up + 0.18 * flick
		p.lunge += -0.15 * up + 0.6 * hit
		p.headTilt += 0.15 * up - 0.15 * flick
	end,
	-- Cave Bat: rise up with the head back, then dive down and forward for a bite,
	-- the head snapping down into it.
	swoop = function(p, u)
		local rise = smooth(u, 0, 0.42) - smooth(u, 0.48, 0.62)
		local dive = pulse(u, 0.45, 0.95)
		p.lift += 1.1 * rise - 0.9 * dive
		p.lean += -0.3 * rise + 0.45 * dive
		p.lunge += -0.4 * rise + 2.0 * dive
		p.headTilt += 0.35 * rise - 0.55 * dive
	end,
	-- Pebble Golem: draw the right fist back with the elbow folded and the left fist
	-- up as a guard, then step in on the left foot and punch straight out.
	punch = function(p, u)
		local draw = smooth(u, 0, 0.42) - smooth(u, 0.48, 0.6)
		local jab = smooth(u, 0.48, 0.6) - smooth(u, 0.78, 1)
		local guard = smooth(u, 0, 0.3) - smooth(u, 0.8, 1)
		local hit = pulse(u, 0.48, 0.95)
		p.rightFwd += -0.5 * draw + 1.45 * jab
		p.elbowR += 1.1 * draw - Enemies.WALK.elbowRest * jab -- folded, then dead straight
		p.rightPush += 0.4 * jab
		p.leftFwd += 0.5 * guard
		p.elbowL += 1.0 * guard
		p.legL += 0.3 * jab
		p.kneeL += 0.25 * jab
		p.roll += 0.05 * draw - 0.06 * jab
		p.lean += -0.06 * draw + 0.14 * jab
		p.lunge += -0.2 * draw + 1.0 * hit
		p.headTilt += -0.1 * jab
	end,
	-- Spider Queen: rear the front of the body up with both front legs raised and
	-- spread, hold, then stab both legs down and forward as she lunges.
	legstab = function(p, u)
		local up = smooth(u, 0, 0.45) - smooth(u, 0.5, 0.62)
		local stab = smooth(u, 0.5, 0.62) - smooth(u, 0.8, 1)
		local hit = pulse(u, 0.52, 0.95)
		p.armUp += 0.7 * up - 0.25 * stab
		p.armFwd += 0.3 * up + 0.6 * stab
		-- only a small dip on the stab: her head and fangs sit low already
		p.lean += -0.18 * up + 0.07 * stab
		p.lift += 0.5 * up - 0.05 * hit
		p.lunge += -0.4 * up + 1.6 * hit
		p.headTilt += 0.25 * up - 0.12 * stab
	end,
	-- Spider Queen: rear right up on the back legs with the front legs high, hold,
	-- then crash down and forward; crystal shards burst out (EnemyAnimator).
	rearslam = function(p, u)
		local up = smooth(u, 0, 0.45) - smooth(u, 0.5, 0.62)
		local hit = pulse(u, 0.54, 0.95)
		p.lean += -0.45 * up + 0.07 * hit
		p.lift += 1.0 * up - 0.05 * hit
		p.lunge += -0.6 * up + 1.2 * hit
		p.armUp += 1.0 * up - 0.3 * hit
		p.armFwd += 0.2 * up + 0.4 * hit
		p.fore += -0.25 * up
		p.headTilt += 0.3 * up - 0.12 * hit
	end,
}
Enemies.MOVES = MOVES

local moveCache: { [string]: any } = {}

local function sampled(name: string, duration: number, hanging: boolean, shape: (any, number) -> (), opts: any)
	local joints: { [string]: { any } } = {}
	local scratch: { [string]: CFrame } = {}
	for i = 0, SAMPLES do
		local u = i / SAMPLES
		local p = fields()
		shape(p, u)
		table.clear(scratch)
		toChannels(p, hanging, scratch)
		for channel, cf in scratch do
			joints[channel] = joints[channel] or {}
			table.insert(joints[channel], { t = u * duration, cf = cf, ease = "Linear" })
		end
	end
	return Clip.new({
		name = name,
		length = duration,
		priority = opts.priority,
		additive = true,
		fadeIn = 0.03,
		fadeOut = 0.05,
		joints = joints,
		markers = opts.markers,
	})
end

function Enemies.move(name: string, hanging: boolean): any?
	local key = name .. (if hanging then "/hanging" else "/wings")
	local cached = moveCache[key]
	if cached then
		return cached
	end
	local shape = MOVES[name]
	local duration = Enemies.MOVE_DURATION[name]
	if not (shape and duration) then
		return nil
	end
	local strike = Enemies.STRIKE[name]
	local clip = sampled("Enemy_" .. name, duration, hanging, shape, {
		priority = "Action",
		markers = if strike then { { t = strike * duration, name = "Strike" } } else nil,
	})
	moveCache[key] = clip
	return clip
end

function Enemies.flinch(hanging: boolean): any
	local key = "flinch" .. (if hanging then "/hanging" else "/wings")
	local cached = moveCache[key]
	if cached then
		return cached
	end
	local clip = sampled("Enemy_flinch", 0.3, hanging, function(p, u)
		local k = pulse(u, 0, 1)
		p.lean -= 0.25 * k
		p.lunge -= 0.35 * k
		p.headTilt += 0.2 * k
		p.armUp += 0.2 * k
	end, { priority = "Override" })
	moveCache[key] = clip
	return clip
end

-- ==================== walk ====================

local function walkEvaluate(track: any, out: { [string]: CFrame }, dt: number): number
	local s = track.params
	local rig = s.rig
	if not rig then
		return 0
	end
	local W = Enemies.WALK
	local position = rig.root.Position
	local speed = 0
	if s.lastPos and dt > 0 then
		local d = position - s.lastPos
		speed = Vector3.new(d.X, 0, d.Z).Magnitude / dt
	end
	s.lastPos = position
	s.walk = s.walk or 0
	s.phase = s.phase or 0
	-- floating rigs (Hover) never walk: they drift along in their idle (user, 2026-10-12)
	local target = if rig.meta.hover then 0 else math.clamp(speed / W.speedForFull, 0, 1)
	s.walk += (target - s.walk) * math.min(1, dt * W.blendRate)
	s.phase = (s.phase + dt * W.strideRate * 2 * math.pi * s.walk) % (2 * math.pi)

	local w, sn, now = s.walk, math.sin(s.phase), os.clock()
	local p = fields()
	p.roll = W.bodySway * w * sn
	p.lift = W.bodyBob * w * math.abs(math.cos(s.phase)) + 0.04 * math.sin(now * 2) * (1 - w)
	local hover = rig.meta.hover
	if hover then
		-- floating rigs bob all the time and their "legs" (trailing leaves) drift
		p.lift += hover * math.sin(now * W.hoverRate)
		p.roll += 0.03 * math.sin(now * W.hoverRate * 0.5)
	end
	p.armUp = 0.05 * math.sin(now * 1.5) * (1 - w)
	p.armFlap = W.armFlap * w * sn
	p.leg = W.legSwing * w * sn + (if hover then 0.12 * math.sin(now * W.hoverRate * 0.8) * (1 - w) else 0)
	p.headTilt = 0.08 * w * math.sin(s.phase * 2)
	-- each knee bends while its leg swings forward
	p.kneeL = W.kneeBend * w * math.max(0, math.cos(s.phase))
	p.kneeR = W.kneeBend * w * math.max(0, -math.cos(s.phase))
	-- elbows: a little bend at rest, more as each arm swings forward (the left arm
	-- swings forward while sin(phase) < 0)
	p.elbowL = W.elbowRest + W.elbowSwing * w * math.max(0, -sn)
	p.elbowR = W.elbowRest + W.elbowSwing * w * math.max(0, sn)
	local flap = if rig.meta.wingFlap then math.sin(now * W.flapRate * 2 * math.pi) else nil
	if flap then
		-- the body rises as the wings come down
		p.lift += -W.flapBob * flap
	end
	toChannels(p, rig.meta.hangingArms, out)
	if flap and rig.channels.LeftWing then
		-- flapping wings beat up and down about the shoulders (the left wing is at -X)
		out.LeftWing = CFrame.Angles(0, 0, -flap * W.flapSwing)
		out.RightWing = CFrame.Angles(0, 0, flap * W.flapSwing)
	elseif rig.channels.LeftWing then
		-- wings flutter all the time, beating back and forth about the back
		local beat = math.sin(now * W.wingRate * 2 * math.pi) * W.wingSwing
		out.LeftWing = CFrame.Angles(0, beat, 0) * CFrame.Angles(0, 0, 0.25 * beat)
		out.RightWing = CFrame.Angles(0, -beat, 0) * CFrame.Angles(0, 0, -0.25 * beat)
	end
	return 1
end

Enemies.walk = Clip.procedural({
	name = "EnemyWalk",
	priority = "Movement",
	fadeIn = 0,
	evaluate = walkEvaluate,
})

return Enemies
