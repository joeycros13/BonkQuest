--!strict
-- Pose: the one place angles become CFrames, so every clip agrees on axes.
--
-- Angles are DEGREES as (pitch, yaw, roll), applied yaw, then roll, then pitch,
-- in the parent part's frame (a character's torso, an enemy's root):
--   pitch +  tips forward-facing things up / swings a hanging limb forward
--   yaw   +  turns toward the left (-X)
--   roll  +  tilts toward the left
-- Offsets are studs in the same frame (-Z is forward).
--
-- A keyframe or pose spec can be a CFrame, or a table { rot = {p, y, r},
-- pos = {x, y, z} } with either part optional.

local Pose = {}

local rad = math.rad

function Pose.angles(pitch: number?, yaw: number?, roll: number?): CFrame
	return CFrame.Angles(0, rad(yaw or 0), 0) * CFrame.Angles(0, 0, rad(roll or 0)) * CFrame.Angles(rad(pitch or 0), 0, 0)
end

function Pose.offset(x: number?, y: number?, z: number?): CFrame
	return CFrame.new(x or 0, y or 0, z or 0)
end

function Pose.from(spec: any): CFrame
	if typeof(spec) == "CFrame" then
		return spec
	end
	if type(spec) ~= "table" then
		return CFrame.identity
	end
	if typeof(spec.cf) == "CFrame" then
		return spec.cf
	end
	local cf = CFrame.identity
	if spec.pos then
		cf = CFrame.new(spec.pos[1] or 0, spec.pos[2] or 0, spec.pos[3] or 0)
	end
	if spec.rot then
		cf *= Pose.angles(spec.rot[1], spec.rot[2], spec.rot[3])
	end
	return cf
end

return Pose
