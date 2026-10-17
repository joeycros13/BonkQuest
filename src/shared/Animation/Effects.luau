--!strict
-- Effects: one-shot and attached visual effects, looked up by preset name
-- (EffectPresets). Emitter parts and rings are pooled and reused, so effects
-- cost almost nothing after the first use.
--
--   Effects.burst(at, "HitSpark", { count = 20 })   -- at: Vector3 | CFrame | BasePart | Attachment | Model
--   Effects.shockwave(at, "Shockwave", { endSize = 14 })
--   Effects.flash(model, "HurtFlash")
--   local trail = Effects.trail(weaponModel, "SlashTrail")  trail:Enable(true)  trail:Destroy()
--   Effects.sound("rbxassetid://123", at, { volume = 0.6, pitch = 1.1 })
-- Overrides patch any preset field for one call. Effects are local to whoever
-- calls them -- call on each client that should see it.

local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Animation = script.Parent
local Presets = require(Animation.EffectPresets)
local Tween = require(Animation.Tween)

local Effects = {}

Effects.Presets = Presets

local POOL_LIMIT = 24

local container: Folder? = nil
local pools: { [string]: { BasePart } } = {}

local function folder(): Folder
	if container and container.Parent then
		return container
	end
	local runtime = Workspace:FindFirstChild("Runtime")
	if not runtime then
		runtime = Instance.new("Folder")
		runtime.Name = "Runtime"
		runtime.Parent = Workspace
	end
	local f = Instance.new("Folder")
	f.Name = "Effects"
	f.Parent = runtime
	container = f
	return f
end

local function cframeOf(at: any): CFrame
	local kind = typeof(at)
	if kind == "Vector3" then
		return CFrame.new(at)
	elseif kind == "CFrame" then
		return at
	elseif kind == "Instance" then
		if at:IsA("BasePart") then
			return at.CFrame
		elseif at:IsA("Attachment") then
			return at.WorldCFrame
		elseif at:IsA("Model") then
			return at:GetPivot()
		end
	end
	return CFrame.identity
end

local function merged(name: string, overrides: any?): any
	local preset = Presets[name]
	if not preset then
		warn(("[Animation.Effects] unknown preset %q"):format(name))
		return nil
	end
	if not overrides then
		return preset
	end
	local copy = table.clone(preset)
	for k, v in overrides do
		copy[k] = v
	end
	return copy
end

local function blankPart(name: string): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	return part
end

local function take(key: string, build: () -> BasePart): BasePart
	local pool = pools[key]
	if pool and #pool > 0 then
		return table.remove(pool) :: BasePart
	end
	local part = build()
	part.Parent = folder()
	return part
end

local function give(key: string, part: BasePart)
	local pool = pools[key]
	if not pool then
		pool = {}
		pools[key] = pool
	end
	if #pool < POOL_LIMIT and part.Parent then
		table.insert(pool, part)
	else
		part:Destroy()
	end
end

local function asSequence(value: any, kind: string): any
	if kind == "Color" and typeof(value) == "Color3" then
		return ColorSequence.new(value)
	elseif (kind == "Size" or kind == "Transparency") and type(value) == "number" then
		return NumberSequence.new(value)
	end
	return value
end

-- ==================== bursts ====================

function Effects.burst(at: any, presetName: string, overrides: any?)
	local preset = merged(presetName, overrides)
	if not preset then
		return
	end
	local key = "burst:" .. presetName
	local part = take(key, function()
		local p = blankPart("Burst_" .. presetName)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Enabled = false
		emitter.Parent = p
		local light = Instance.new("PointLight")
		light.Enabled = false
		light.Parent = p
		return p
	end)
	local emitter = part:FindFirstChildOfClass("ParticleEmitter") :: ParticleEmitter
	for prop, value in preset.emitter or {} do
		(emitter :: any)[prop] = asSequence(value, prop)
	end
	part.CFrame = cframeOf(at)
	emitter:Emit(preset.count or 10)

	local lightSpec = preset.light
	local light = part:FindFirstChildOfClass("PointLight") :: PointLight
	if lightSpec then
		light.Color = lightSpec.Color or Color3.new(1, 1, 1)
		light.Range = lightSpec.Range or 8
		light.Brightness = lightSpec.Brightness or 2
		light.Enabled = true
		Tween.to(light, { Brightness = 0 }, lightSpec.Time or 0.12, "QuadOut")
	end

	local lifetime = (preset.emitter and preset.emitter.Lifetime and preset.emitter.Lifetime.Max) or 1
	task.delay(lifetime + 0.1, function()
		light.Enabled = false
		give(key, part)
	end)
end

-- ==================== shockwave ====================

function Effects.shockwave(at: any, presetName: string?, overrides: any?)
	local name = presetName or "Shockwave"
	local preset = merged(name, overrides)
	if not preset then
		return
	end
	local key = "ring"
	local ring = take(key, function()
		local p = blankPart("Shockwave")
		p.Shape = Enum.PartType.Cylinder
		p.Material = Enum.Material.Neon
		return p
	end)
	local base = cframeOf(at)
	-- A cylinder's axis is X; tip it so the disc lies flat.
	ring.CFrame = CFrame.new(base.Position) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Color = preset.color or Color3.new(1, 1, 1)
	ring.Transparency = preset.transparency or 0.3
	local thickness = preset.thickness or 0.15
	ring.Size = Vector3.new(thickness, preset.startSize or 1, preset.startSize or 1)
	local tween = Tween.to(ring, {
		Size = Vector3.new(thickness, preset.endSize or 8, preset.endSize or 8),
		Transparency = 1,
	}, preset.time or 0.35, "QuadOut")
	tween.Completed:Once(function()
		give(key, ring)
	end)
end

-- ==================== flash ====================

function Effects.flash(model: Instance, presetName: string?, overrides: any?)
	local preset = merged(presetName or "HurtFlash", overrides)
	if not preset then
		return
	end
	local highlight = model:FindFirstChild("AnimationFlash")
	if not (highlight and highlight:IsA("Highlight")) then
		local h = Instance.new("Highlight")
		h.Name = "AnimationFlash"
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.OutlineTransparency = 1
		h.Adornee = model
		h.Parent = model
		highlight = h
	end
	local h = highlight :: Highlight
	h.FillColor = preset.color or Color3.new(1, 1, 1)
	h.FillTransparency = preset.fillTransparency or 0.4
	h.Enabled = true
	local tween = Tween.to(h, { FillTransparency = 1 }, preset.time or 0.15, "QuadIn")
	tween.Completed:Once(function(state)
		if state == "Completed" then
			h.Enabled = false
		end
	end)
end

-- ==================== trails ====================

-- A trail along a held model, from its PrimaryPart (the grip) toward its
-- far end along -Z. Returns a handle with :Enable(bool) and :Destroy().
function Effects.trail(model: Model, presetName: string?, overrides: any?)
	local preset = merged(presetName or "SlashTrail", overrides)
	local grip = model.PrimaryPart
	if not (preset and grip) then
		return nil
	end
	-- How far the model reaches forward (-Z) from the grip.
	local reach = 0
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= grip then
			local offset = grip.CFrame:PointToObjectSpace(part.Position)
			reach = math.max(reach, -offset.Z + part.Size.Z / 2)
		end
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailStart"
	a0.Position = Vector3.new(0, 0, -reach * (preset.from or 0.35))
	a0.Parent = grip
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailEnd"
	a1.Position = Vector3.new(0, 0, -reach * (preset.to or 1))
	a1.Parent = grip
	local trail = Instance.new("Trail")
	trail.Name = "AnimationTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Enabled = false
	for prop, value in preset do
		if prop ~= "kind" and prop ~= "from" and prop ~= "to" then
			pcall(function()
				(trail :: any)[prop] = asSequence(value, prop)
			end)
		end
	end
	trail.Parent = grip
	local handle = { trail = trail }
	function handle.Enable(_self: any, on: boolean)
		if trail.Parent then
			trail.Enabled = on
		end
	end
	function handle.Destroy(_self: any)
		trail:Destroy()
		a0:Destroy()
		a1:Destroy()
	end
	return handle
end

-- ==================== sound ====================

function Effects.sound(sound: any, at: any?, opts: any?)
	local options = opts or {}
	local s: Sound
	if typeof(sound) == "Instance" and sound:IsA("Sound") then
		s = sound:Clone()
	else
		s = Instance.new("Sound")
		s.SoundId = tostring(sound)
	end
	s.Volume = options.volume or s.Volume
	s.PlaybackSpeed = options.pitch or s.PlaybackSpeed
	if at then
		local holder = blankPart("SoundEmitter")
		holder.CFrame = cframeOf(at)
		holder.Parent = folder()
		s.Parent = holder
		Debris:AddItem(holder, 10)
	else
		s.Parent = folder()
		Debris:AddItem(s, 10)
	end
	s:Play()
	return s
end

return Effects
