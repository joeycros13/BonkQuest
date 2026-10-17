--!strict
-- Animator: plays Clips on a rig and blends them -- like Roblox's Animator.
--
--   local animator = Animator.new(rig, { cull = true })
--   local track = animator:Play(clip, { speed = 1, weight = 1, fadeIn = 0.1, looped = nil, params = {} })
--   animator:Stop("Wave", 0.2)   animator:StopAll(0.2)   animator:Destroy()
--
-- Blending, per channel, each frame:
--   1. Normal tracks, lowest priority first (ties: older first): each lerps the
--      running pose toward its own by its weight, so higher priorities win.
--      "Coverage" tracks how much of the channel they claim (0..1).
--   2. The rig blends from its base (rest, or Roblox's Animator for characters)
--      to that pose by the coverage.
--   3. Additive tracks multiply on top, scaled by their weight.
--
-- Cost control (all automatic):
--   * Every animator is stepped by one Scheduler system per phase.
--   * Level of detail: rigs farther from the camera are evaluated every 2nd /
--     4th frame (in between, the last pose is re-applied), and part rigs that are
--     off-screen skip moving their parts at all. Set cull = false to always run
--     at full rate (the local player, UI previews).
--   * Scratch tables are reused; nothing is allocated per frame except the
--     CFrames themselves.
--
-- Debugging poses: during a playtest, set the number attribute "PinTime" (0..1)
-- on this module (client side). Every one-shot track then holds at that
-- fraction of its clip -- start a swing or an enemy move and screenshot it.
-- Remove the attribute to resume.

local Workspace = game:GetService("Workspace")

local Animation = script.Parent
local Scheduler = require(Animation.Scheduler)
local Track = require(Animation.Track)

local Animator = {}
Animator.__index = Animator

-- Distances (studs from the camera) for the level-of-detail steps.
Animator.LOD = {
	full = 60, -- every frame within this
	half = 120, -- every 2nd frame within this
	quarter = 260, -- every 4th frame within this; beyond, frozen in place
	nearAlwaysVisible = 25, -- treated as on-screen when this close
	screenMargin = 0.3, -- fraction of the screen beyond its edges that still counts as on-screen
}

local registry: { [string]: { any } } = { Joints = {}, Render = {} }

function Animator.new(rig: any, opts: any?)
	local options = opts or {}
	local self = setmetatable({
		rig = rig,
		tracks = {} :: { any },
		cull = options.cull ~= false,
		alive = true,
		_pending = 0,
		_frame = math.random(0, 3), -- spread skipped frames across rigs
		_sequence = 0,
		_pose = {} :: { [string]: CFrame },
		_cover = {} :: { [string]: number },
		_add = {} :: { [string]: CFrame },
		_scratch = {} :: { [string]: CFrame },
	}, Animator)
	table.insert(registry[rig.phase], self)
	return self
end

function Animator:Play(clip: any, opts: any?)
	local track = Track.new(clip, opts)
	self._sequence += 1
	track.sequence = self._sequence
	local tracks = self.tracks
	table.insert(tracks, track)
	table.sort(tracks, function(a, b)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		return a.sequence < b.sequence
	end)
	return track
end

-- Stop tracks of a clip (or clip name). Returns how many.
function Animator:Stop(clipOrName: any, fade: number?): number
	local n = 0
	for _, track in self.tracks do
		if track.clip == clipOrName or track.name == clipOrName then
			track:Stop(fade)
			n += 1
		end
	end
	return n
end

function Animator:StopAll(fade: number?)
	for _, track in self.tracks do
		track:Stop(fade)
	end
end

function Animator:GetPlayingTracks(): { any }
	local list = {}
	for _, track in self.tracks do
		if track:IsPlaying() then
			table.insert(list, track)
		end
	end
	return list
end

function Animator:Destroy()
	if not self.alive then
		return
	end
	self.alive = false
	local list = registry[self.rig.phase]
	local index = table.find(list, self)
	if index then
		table.remove(list, index)
	end
	self.rig:Release()
	table.clear(self.tracks)
end

local identity = CFrame.identity

local pinTime: number? = nil

function Animator:Step(dt: number)
	local tracks = self.tracks
	local i = 1
	while i <= #tracks do
		local track = tracks[i]
		local step = dt
		if pinTime and not track.looped and not track.stopping then
			track.time = pinTime * track.clip.length
			track.weight = 1
			step = 0
		end
		if track:_step(step) then
			i += 1
		else
			table.remove(tracks, i)
		end
	end

	local pose, cover, add, scratch = self._pose, self._cover, self._add, self._scratch
	table.clear(pose)
	table.clear(cover)
	table.clear(add)
	local rig = self.rig
	for _, track in tracks do
		if track.weight <= 0 then
			continue
		end
		table.clear(scratch)
		local w = track.weight * track.clip:sample(track.time, scratch, track, dt)
		if w <= 0 then
			continue
		end
		local jointSpace = track.clip.space == "joint"
		for channel, cf in scratch do
			if jointSpace then
				cf = rig:FromJointSpace(channel, cf)
			end
			if track.additive then
				local piece = if w >= 1 then cf else identity:Lerp(cf, w)
				local existing = add[channel]
				add[channel] = if existing then existing * piece else piece
			else
				local c = cover[channel]
				if c then
					pose[channel] = pose[channel]:Lerp(cf, w)
					cover[channel] = c + (1 - c) * w
				else
					pose[channel] = cf
					cover[channel] = w
				end
			end
		end
	end
	rig:Apply(pose, cover, add)
end

-- ==================== the shared runner ====================

local function stepAll(list: { any }, dt: number)
	local camera = Workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position
	local lod = Animator.LOD
	local i = 1
	while i <= #list do
		local animator = list[i]
		local rig = animator.rig
		if not rig:IsAlive() then
			animator:Destroy() -- removes itself from the list
			continue
		end
		i += 1
		local interval = 1
		if animator.cull and camPos then
			local position = rig:GetPosition()
			if position then
				local distance = (position - camPos).Magnitude
				interval = if distance < lod.full
					then 1
					elseif distance < lod.half then 2
					elseif distance < lod.quarter then 4
					else 0
				if rig.kind == "part" then
					-- Judged by the root, with a margin so a big body whose centre is
					-- just off the edge still moves its visible end.
					local onScreen = distance < lod.nearAlwaysVisible
					if not onScreen and interval ~= 0 then
						local point = camera:WorldToViewportPoint(position)
						local size = camera.ViewportSize
						local mx, my = size.X * lod.screenMargin, size.Y * lod.screenMargin
						onScreen = point.Z > 0
							and point.X > -mx and point.X < size.X + mx
							and point.Y > -my and point.Y < size.Y + my
					end
					rig.visible = interval ~= 0 and onScreen
				end
			end
		end
		animator._frame += 1
		animator._pending += dt
		if interval == 0 or animator._frame % interval ~= 0 then
			rig:Follow()
		else
			local elapsed = animator._pending
			animator._pending = 0
			animator:Step(elapsed)
		end
	end
end

local module = script
Scheduler.bind("Joints", "Animator.joints", 50, function(dt)
	local pin = module:GetAttribute("PinTime")
	pinTime = if type(pin) == "number" then math.clamp(pin, 0, 0.999) else nil
	stepAll(registry.Joints, dt)
end)
Scheduler.bind("Render", "Animator.parts", 50, function(dt)
	stepAll(registry.Render, dt)
end)

-- How many animators are running, per phase (for tuning).
function Animator.count(): (number, number)
	return #registry.Joints, #registry.Render
end

return Animator
