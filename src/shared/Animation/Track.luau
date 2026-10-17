--!strict
-- Track: one PLAYING instance of a Clip on an Animator -- like Roblox's
-- AnimationTrack. Created by Animator:Play(clip, options).
--
--   track:Stop(fade?)            -- fade out, then it is removed
--   track:AdjustSpeed(2)         -- playback speed (1 = clip speed)
--   track:AdjustWeight(0.5, 0.2) -- blend weight, optionally over a fade
--   track:GetMarkerReachedSignal("Hit"):Connect(fn)
--   track.Ended    -- reached its end (non-looped); it then fades out
--   track.Stopped  -- fully gone
--   track.Looped   -- wrapped around (looped clips)
--   track.params   -- free table procedural clips read their inputs from

local Animation = script.Parent
local Signal = require(Animation.Signal)
local Clip = require(Animation.Clip)

local Track = {}
Track.__index = Track

function Track.new(clip: any, opts: any?)
	local options = opts or {}
	local fadeIn = if options.fadeIn ~= nil then options.fadeIn else clip.fadeIn
	local weight = options.weight or 1
	return setmetatable({
		clip = clip,
		name = clip.name,
		time = options.startTime or 0,
		speed = options.speed or clip.speed,
		weight = if fadeIn > 0 then 0 else weight,
		targetWeight = weight,
		fadeTime = fadeIn,
		looped = if options.looped ~= nil then options.looped else clip.looped,
		priority = if options.priority ~= nil then Clip.priorityOf(options.priority) else clip.priority,
		additive = if options.additive ~= nil then options.additive else clip.additive,
		params = options.params or {},
		playing = true,
		stopping = false,
		sequence = 0, -- set by the Animator; keeps play order among equal priorities
		Ended = Signal.new(),
		Stopped = Signal.new(),
		Looped = Signal.new(),
		Marker = Signal.new(), -- fires (name) for every marker
		_markerSignals = {} :: { [string]: any },
	}, Track)
end

function Track:GetMarkerReachedSignal(name: string)
	local signal = self._markerSignals[name]
	if not signal then
		signal = Signal.new()
		self._markerSignals[name] = signal
	end
	return signal
end

function Track:Stop(fade: number?)
	if not self.playing then
		return
	end
	local time = if fade ~= nil then fade else self.clip.fadeOut
	self.stopping = true
	self.targetWeight = 0
	self.fadeTime = time
	if time <= 0 then
		self.weight = 0
	end
end

function Track:AdjustSpeed(speed: number)
	self.speed = speed
end

function Track:AdjustWeight(weight: number, fade: number?)
	self.targetWeight = weight
	self.fadeTime = fade or 0
	if self.fadeTime <= 0 then
		self.weight = weight
	end
end

function Track:IsPlaying(): boolean
	return self.playing and not self.stopping
end

local function fire(self: any, name: string)
	self.Marker:Fire(name)
	local signal = self._markerSignals[name]
	if signal then
		signal:Fire(name)
	end
end

-- Fire every marker in (from, to], plus t = 0 markers on the very first step.
local function fireMarkers(self: any, from: number, to: number)
	for _, marker in self.clip.markers do
		if (marker.t > from and marker.t <= to) or (from == 0 and marker.t == 0 and not self._started) then
			fire(self, marker.name)
		end
	end
end

-- Advance by dt. Returns false once the track is finished and can be dropped.
function Track:_step(dt: number): boolean
	if self.weight ~= self.targetWeight then
		if self.fadeTime <= 0 then
			self.weight = self.targetWeight
		else
			local step = dt / self.fadeTime
			if self.weight < self.targetWeight then
				self.weight = math.min(self.targetWeight, self.weight + step)
			else
				self.weight = math.max(self.targetWeight, self.weight - step)
			end
		end
	end
	if self.stopping and self.weight <= 0 then
		self.playing = false
		self.Stopped:Fire()
		return false
	end

	local length = self.clip.length
	local from = self.time
	local to = from + dt * self.speed
	local hasMarkers = #self.clip.markers > 0
	if to >= length then
		if self.looped then
			if hasMarkers then
				fireMarkers(self, from, length)
			end
			to %= length
			self.Looped:Fire()
			if hasMarkers then
				fireMarkers(self, -1, to)
			end
		else
			if hasMarkers then
				fireMarkers(self, from, length)
			end
			to = length
			if not self.stopping then
				-- Hold the last pose while it fades out.
				self.stopping = true
				self.targetWeight = 0
				self.fadeTime = self.clip.fadeOut
				if self.fadeTime <= 0 then
					self.weight = 0
				end
				self.Ended:Fire()
			end
		end
	elseif hasMarkers then
		fireMarkers(self, from, to)
	end
	self._started = true
	self.time = to
	return true
end

return Track
