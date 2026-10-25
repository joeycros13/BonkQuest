--!strict
-- Hurt: a character's recoil when an enemy's hit lands (2026-10-22, the user: the player
-- should "stumble back" the way enemies flinch). An additive keyframe clip at Override
-- priority, so it layers on whatever the body is doing (walking, a weapon hold, a swing)
-- and never fights it, like Clips.Enemies.flinch. HurtController plays it on the hit
-- player's character, and pushes the character back (the stumble) for the player who
-- was hit.
--
--   entry.animator:Play(Hurt.flinch())
--
-- Tuning (degrees, Animation.Pose's axes: pitch + tips the torso / head back, swings an
-- arm forward): Hurt.FLINCH. The recoil snaps in over SNAP seconds and settles over the
-- rest of LENGTH.

local Animation = script.Parent.Parent
local Clip = require(Animation.Clip)

local Hurt = {}

Hurt.LENGTH = 0.42
Hurt.SNAP = 0.07
Hurt.FLINCH = {
	lean = 14, -- the torso tips back
	head = 16, -- the head snaps back on top of it
	arms = 24, -- both arms fly forward a little
	armsOut = 10, -- and out from the body
}

-- The death pose (2026-10-25, the user: "basically just the idle animation but the arms
-- are out and the torso is more forward, so an ascending look"). A full-body clip at
-- Override that covers every joint, so nothing under it shows: not the walk, a weapon hold
-- or swing, nor Roblox's own Animate script, which is the base a character falls back to
-- once the humanoid is Dead (not a ground state, so Locomotion lets go). It eases in from
-- whatever the body was doing (the track's fade) and the arms keep rising a little while
-- the body floats up (DeathController lifts it), then holds.
Hurt.DEATH_LENGTH = 2 -- held well past the break-up (DeathController hides the body by then)
Hurt.DEATH_FADE = 0.25
Hurt.DEATH_RISE = 0.6 -- seconds the arms keep lifting, matching the float up
Hurt.DEATH = {
	lean = -16, -- the torso tips forward
	head = 10, -- the head tips back up, so the face looks ahead and up
	arms = -6, -- the arms a touch behind the body
	armsOut = 68, -- and spread wide
	armsOutTop = 76, -- the spread they lift to as the body rises
	legLeft = -4, -- the legs hang a little behind
	legRight = -10,
	legOut = 5,
}

local cached: any = nil
local cachedDeath: any = nil

function Hurt.death(): any
	if cachedDeath then
		return cachedDeath
	end
	local D = Hurt.DEATH
	local function held(from: { number }, to: { number }): { any }
		return {
			{ t = 0, rot = from },
			{ t = Hurt.DEATH_RISE, rot = to, ease = "Smooth" },
			{ t = Hurt.DEATH_LENGTH, rot = to },
		}
	end
	-- On R6 shoulders and hips a positive roll swings the LEFT limb in across the body
	-- (measured on a statue of the pose: +76 put both arms inside the torso), so out is
	-- negative on the left and positive on the right.
	local left = { D.arms, 0, -D.armsOut }
	local right = { D.arms, 0, D.armsOut }
	cachedDeath = Clip.new({
		name = "Player_death",
		priority = "Override",
		additive = false,
		length = Hurt.DEATH_LENGTH,
		fadeIn = Hurt.DEATH_FADE,
		fadeOut = 0,
		joints = {
			Root = held({ D.lean, 0, 0 }, { D.lean, 0, 0 }),
			Neck = held({ D.head, 0, 0 }, { D.head, 0, 0 }),
			LeftShoulder = held(left, { D.arms, 0, -D.armsOutTop }),
			RightShoulder = held(right, { D.arms, 0, D.armsOutTop }),
			LeftHip = held({ D.legLeft, 0, -D.legOut }, { D.legLeft, 0, -D.legOut }),
			RightHip = held({ D.legRight, 0, D.legOut }, { D.legRight, 0, D.legOut }),
		},
	})
	return cachedDeath
end

function Hurt.flinch(): any
	if cached then
		return cached
	end
	local F = Hurt.FLINCH
	local function key(rot: { number }): { any }
		return {
			{ t = 0 },
			{ t = Hurt.SNAP, rot = rot, ease = "QuadOut" },
			{ t = Hurt.LENGTH, ease = "Smooth" },
		}
	end
	cached = Clip.new({
		name = "Player_flinch",
		priority = "Override",
		additive = true,
		length = Hurt.LENGTH,
		fadeIn = 0,
		fadeOut = 0.05,
		joints = {
			Root = key({ F.lean, 0, 0 }),
			Neck = key({ F.head, 0, 0 }),
			LeftShoulder = key({ F.arms, 0, F.armsOut }),
			RightShoulder = key({ F.arms, 0, -F.armsOut }),
		},
	})
	return cached
end

return Hurt
