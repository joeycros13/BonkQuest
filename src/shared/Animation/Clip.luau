--!strict
-- Clip: an animation's DEFINITION -- like Roblox's Animation object. A playing
-- instance of it is a Track (Animator:Play returns one).
--
-- Keyframe clip:
--   Clip.new({
--     name = "Wave", length = 1.2, looped = false,
--     priority = "Action",          -- Core Idle Movement Hold Action Action2 Action3 Override
--     additive = false,             -- additive clips layer ON TOP of the blended pose
--     fadeIn = 0.1, fadeOut = 0.15, -- seconds
--     ease = "Smooth",              -- default ease for every key
--     joints = {
--       RightShoulder = {
--         { t = 0 },                                   -- rest
--         { t = 0.4, rot = { 150, 0, 20 }, ease = "BackOut" },  -- degrees (pitch, yaw, roll)
--         { t = 1.2 },
--       },
--       Root = { { t = 0 }, { t = 0.6, pos = { 0, 0.3, 0 } }, { t = 1.2 } },
--     },
--     markers = { { t = 0.4, name = "Wave" } },   -- Track:GetMarkerReachedSignal("Wave")
--   })
-- A key's ease is how the pose ARRIVES at it from the previous key.
-- Joint names are a rig's channel names: characters use Root Waist Neck
-- Left/RightShoulder Elbow Wrist Hip Knee Ankle and Grip (the held weapon);
-- part rigs (enemies) use their limb part names plus Body.
--
-- Procedural clip -- poses computed every frame by a function (walk cycles):
--   Clip.procedural({ name = "Bob", priority = "Idle",
--     evaluate = function(track, out, dt) out.Root = CFrame.new(0, math.sin(track.time), 0) end })
--   evaluate may return a number: a per-frame weight multiplier.
--
-- From Roblox's Animation Editor (no upload needed):
--   Clip.fromKeyframeSequence(ServerStorage.AnimSaves.MyAnim, { priority = "Action" })

local Animation = script.Parent
local Easing = require(Animation.Easing)
local Pose = require(Animation.Pose)

local Clip = {}
Clip.__index = Clip

Clip.Priority = {
	Core = 0,
	Idle = 1,
	Movement = 2,
	Hold = 3, -- a held weapon or item: above movement, below actions
	Action = 4,
	Action2 = 5,
	Action3 = 6,
	Override = 7,
}

function Clip.priorityOf(value: any): number
	if type(value) == "number" then
		return value
	end
	return Clip.Priority[value or "Action"] or Clip.Priority.Action
end

export type Channel = { times: { number }, poses: { CFrame }, eases: { (number) -> number } }

function Clip.new(def: any)
	local channels: { [string]: Channel } = {}
	local length = def.length or 0
	for joint, keys in def.joints or {} do
		local sorted = table.clone(keys)
		table.sort(sorted, function(a, b)
			return a.t < b.t
		end)
		local channel: Channel = { times = {}, poses = {}, eases = {} }
		for i, key in sorted do
			channel.times[i] = key.t
			channel.poses[i] = Pose.from(key)
			channel.eases[i] = Easing.get(key.ease or def.ease or "Smooth")
			if key.t > length then
				length = key.t
			end
		end
		channels[joint] = channel
	end
	local markers = table.clone(def.markers or {})
	table.sort(markers, function(a, b)
		return a.t < b.t
	end)
	return setmetatable({
		kind = "keyframe",
		name = def.name or "Clip",
		length = math.max(length, 1e-3),
		looped = def.looped == true,
		priority = Clip.priorityOf(def.priority),
		additive = def.additive == true,
		fadeIn = def.fadeIn or 0.1,
		fadeOut = def.fadeOut or 0.15,
		speed = def.speed or 1,
		-- "parent": poses are in the parent part's frame (everything written by hand);
		-- "joint": raw joint Transforms (clips from the Animation Editor).
		space = def.space or "parent",
		channels = channels,
		markers = markers,
		evaluate = nil,
	}, Clip)
end

function Clip.procedural(def: any)
	return setmetatable({
		kind = "procedural",
		name = def.name or "Procedural",
		length = def.length or 1,
		looped = def.looped ~= false,
		priority = Clip.priorityOf(def.priority),
		additive = def.additive == true,
		fadeIn = def.fadeIn or 0.2,
		fadeOut = def.fadeOut or 0.2,
		speed = def.speed or 1,
		space = "parent",
		channels = {},
		markers = def.markers or {},
		evaluate = def.evaluate,
	}, Clip)
end

-- Write this clip's pose at `time` into `out`. Returns a weight multiplier.
function Clip:sample(time: number, out: { [string]: CFrame }, track: any, dt: number): number
	if self.kind == "procedural" then
		local w = self.evaluate(track, out, dt)
		return if type(w) == "number" then w else 1
	end
	for joint, channel in self.channels do
		local times = channel.times
		local n = #times
		if n == 1 or time <= times[1] then
			out[joint] = channel.poses[1]
		elseif time >= times[n] then
			out[joint] = channel.poses[n]
		else
			local i = 1
			while times[i + 1] < time do
				i += 1
			end
			local t0, t1 = times[i], times[i + 1]
			local alpha = channel.eases[i + 1]((time - t0) / (t1 - t0))
			out[joint] = channel.poses[i]:Lerp(channel.poses[i + 1], alpha)
		end
	end
	return 1
end

-- ==================== Animation Editor import ====================

-- Animation Editor poses are named after the part each joint moves.
local EDITOR_JOINTS: { [string]: string } = {
	-- R6
	Torso = "Root",
	Head = "Neck",
	["Right Arm"] = "RightShoulder",
	["Left Arm"] = "LeftShoulder",
	["Right Leg"] = "RightHip",
	["Left Leg"] = "LeftHip",
	-- R15
	LowerTorso = "Root",
	UpperTorso = "Waist",
	RightUpperArm = "RightShoulder",
	RightLowerArm = "RightElbow",
	RightHand = "RightWrist",
	LeftUpperArm = "LeftShoulder",
	LeftLowerArm = "LeftElbow",
	LeftHand = "LeftWrist",
	RightUpperLeg = "RightHip",
	RightLowerLeg = "RightKnee",
	RightFoot = "RightAnkle",
	LeftUpperLeg = "LeftHip",
	LeftLowerLeg = "LeftKnee",
	LeftFoot = "LeftAnkle",
}

local EDITOR_PRIORITY: { [string]: string } = {
	Core = "Core",
	Idle = "Idle",
	Movement = "Movement",
	Action = "Action",
	Action2 = "Action2",
	Action3 = "Action3",
	Action4 = "Override",
}

-- Build a clip from a KeyframeSequence saved by Roblox's Animation Editor
-- (ServerStorage.AnimSaves). opts: priority, looped, fadeIn, fadeOut, jointMap.
function Clip.fromKeyframeSequence(sequence: KeyframeSequence, opts: any?)
	local options = opts or {}
	local joints: { [string]: { any } } = {}
	local markers = {}
	local length = 0
	for _, keyframe in sequence:GetKeyframes() do
		local kf = keyframe :: Keyframe
		length = math.max(length, kf.Time)
		for _, pose in kf:GetDescendants() do
			if pose:IsA("Pose") and pose.Weight > 0 then
				local joint = (options.jointMap and options.jointMap[pose.Name]) or EDITOR_JOINTS[pose.Name]
				if joint then
					joints[joint] = joints[joint] or {}
					table.insert(joints[joint], {
						t = kf.Time,
						cf = pose.CFrame,
						-- The editor stores how a pose LEAVES its keyframe.
						leave = Easing.fromEnum(pose.EasingStyle, pose.EasingDirection),
					})
				end
			end
		end
		for _, marker in kf:GetMarkers() do
			table.insert(markers, { t = kf.Time, name = marker.Name })
		end
	end
	-- Convert to this system's convention: the ease belongs to the key it arrives at.
	for _, keys in joints do
		table.sort(keys, function(a, b)
			return a.t < b.t
		end)
		for i = #keys, 2, -1 do
			keys[i].ease = keys[i - 1].leave
		end
	end
	return Clip.new({
		name = sequence.Name,
		length = length,
		looped = if options.looped ~= nil then options.looped else sequence.Loop,
		priority = options.priority or EDITOR_PRIORITY[sequence.Priority.Name] or "Action",
		fadeIn = options.fadeIn,
		fadeOut = options.fadeOut,
		space = "joint",
		joints = joints,
		markers = markers,
	})
end

return Clip
