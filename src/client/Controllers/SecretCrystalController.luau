--!strict
-- SecretCrystalController: World 3's secret crystal puzzle, client side (2026-10-13).
--
-- Three floor crystals in the cave are tagged "SecretCrystal" (attribute SecretOrder 1..3:
-- Cyan, Pink, Lavender = Blue, Pink, Purple, the order the three hint crystals on the
-- entry tunnel's left wall show).
--   * Pulse: unlike every other crystal they breathe. Their Neon tips ease a little
--     whiter and their light a little brighter, then back, on a slow cycle, so only a
--     player who looks closely notices.
--   * Code: a weapon swing (WeaponController.onSwingLanded) that reaches one of them,
--     with the same reach and arc test enemies get, counts as a hit. The next crystal
--     in order chimes (rising pitch per step) and flashes; any other thuds and the code
--     starts over (the first crystal starts it again). The server (SecretService)
--     keeps its own count and checks the player is really there.
--   * Reward: when the server sets this player's SecretOpen_W3, the front mineshaft
--     opens for this player only: a rumble, the dark panel in its mouth fades away and
--     its invisible barrier stops blocking this player's character. It stays open for
--     the session (respawns included).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local SecretCrystalController = {}

local TAG = "SecretCrystal"
local ATTRIBUTE = "SecretOpen_W3"
local STEPS = 3
local PERIOD = 4 -- seconds per breath
local TIP_WHITE = 0.35 -- how far the tips ease toward white at the peak
local LIGHT_LOW, LIGHT_HIGH = 0.55, 1.45 -- light brightness multiplier over a breath
local FLASH_TIME = 0.6 -- a struck crystal's flash fades over this long
local CHIME_PITCH = { 1, 1.12, 1.26 } -- the chime climbs with each right step
local MAX_HEIGHT_GAP = 8
local OPEN_FADE = 1.5

local player = Players.LocalPlayer
local sounds = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds")

local hitRemote: RemoteEvent? = nil
local WeaponController: any = nil

type Entry = {
	model: Model,
	order: number,
	tips: BasePart?,
	base: Color3,
	light: PointLight?,
	lightBase: number,
	flashAt: number,
	flashColor: Color3,
}
local entries: { [Instance]: Entry } = {}
local step = 0 -- this player's place in the code (mirrors the server)

local function add(model: Instance)
	if entries[model] or not model:IsA("Model") then
		return
	end
	local tips = model:FindFirstChild("Tips")
	local light = model:FindFirstChildWhichIsA("PointLight", true)
	entries[model] = {
		model = model,
		order = model:GetAttribute("SecretOrder") or 0,
		tips = if tips and tips:IsA("BasePart") then tips else nil,
		base = if tips and tips:IsA("BasePart") then tips.Color else Color3.new(1, 1, 1),
		light = light,
		lightBase = if light then light.Brightness else 0,
		flashAt = -math.huge,
		flashColor = Color3.new(1, 1, 1),
	}
end

local function remove(model: Instance)
	entries[model] = nil
end

local function play(name: string, at: BasePart?, pitch: number?)
	local template = sounds:FindFirstChild(name)
	if not (template and template:IsA("Sound")) then
		return
	end
	local s = template:Clone()
	s.PlaybackSpeed = pitch or 1
	s.RollOffMaxDistance = 80
	s.Parent = at or workspace
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
end

-- ==================== the mine ====================

local function mineshaft(): Model?
	local worlds = workspace:FindFirstChild("Worlds")
	local w3 = worlds and worlds:FindFirstChild("W03_CrystalCaverns")
	local shafts = w3 and w3:FindFirstChild("Structures") and w3.Structures:FindFirstChild("Mineshafts")
	local m = shafts and shafts:FindFirstChild("EntryMineshaft")
	return if m and m:IsA("Model") then m else nil
end

local opened = false
local function openMine(instant: boolean)
	if opened then
		return
	end
	local shaft = mineshaft()
	if not shaft then
		return
	end
	opened = true
	for _, name in { "Opening", "Shadow" } do
		local panel = shaft:FindFirstChild(name)
		if panel and panel:IsA("BasePart") then
			if instant then
				panel.Transparency = 1
			else
				TweenService:Create(panel, TweenInfo.new(OPEN_FADE, Enum.EasingStyle.Sine), { Transparency = 1 }):Play()
			end
		end
	end
	-- only this client stops colliding with it, so only this player walks through
	local barrier = shaft:FindFirstChild("SecretBarrier")
	if barrier and barrier:IsA("BasePart") then
		barrier.CanCollide = false
	end
	if not instant then
		play("SecretRumble", shaft:FindFirstChild("Opening") :: BasePart?)
	end
end

-- ==================== striking ====================

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- The secret crystal this swing reached, if any (reach to its edge, arc widened by its size).
local function struck(root: BasePart, def: any): Entry?
	local look = flat(root.CFrame.LookVector)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local halfArc = math.rad((def.arc or 90) / 2)
	local best: Entry? = nil
	local bestDistance = math.huge
	for _, e in entries do
		local cf, size = e.model:GetBoundingBox()
		local offset = cf.Position - root.Position
		if math.abs(offset.Y) > MAX_HEIGHT_GAP + size.Y / 2 then
			continue
		end
		local radius = math.max(size.X, size.Z) / 2
		local toward = flat(offset)
		local distance = toward.Magnitude
		if distance - radius > (def.reach or 0) then
			continue
		end
		if (def.arc or 90) < 360 and distance > radius then
			local angle = math.acos(math.clamp(toward.Unit:Dot(look), -1, 1))
			if angle > halfArc + math.atan2(radius, distance) then
				continue
			end
		end
		if distance < bestDistance then
			best, bestDistance = e, distance
		end
	end
	return best
end

local function onSwingLanded(root: BasePart, def: any)
	if opened or player:GetAttribute(ATTRIBUTE) then
		return
	end
	local e = struck(root, def)
	if not e then
		return
	end
	if hitRemote then
		hitRemote:FireServer(e.order)
	end
	if e.order == step + 1 then
		step = e.order
		e.flashAt, e.flashColor = os.clock(), Color3.new(1, 1, 1)
		play("SecretChime", e.tips, CHIME_PITCH[step])
		if step >= STEPS then
			step = 0 -- the server opens the mine (SecretOpen_W3)
		end
	else
		step = if e.order == 1 then 1 else 0
		if step == 1 then
			-- the first crystal always starts the code afresh
			e.flashAt, e.flashColor = os.clock(), Color3.new(1, 1, 1)
			play("SecretChime", e.tips, CHIME_PITCH[1])
		else
			e.flashAt, e.flashColor = os.clock(), Color3.fromRGB(40, 36, 52)
			play("SecretThud", e.tips)
		end
	end
end

-- ==================== lifecycle ====================

function SecretCrystalController.init(injected: any)
	hitRemote = injected.Remotes.getEvent("SecretCrystalHit")
	WeaponController = injected.Controllers.WeaponController
end

function SecretCrystalController.start()
	for _, m in CollectionService:GetTagged(TAG) do
		add(m)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)
	if WeaponController then
		WeaponController.onSwingLanded(onSwingLanded)
	end
	if player:GetAttribute(ATTRIBUTE) then
		openMine(true)
	end
	player:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
		if player:GetAttribute(ATTRIBUTE) then
			openMine(false)
		end
	end)
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		-- 0 at rest, 1 at the peak of each breath (a smooth sine)
		local k = 0.5 - 0.5 * math.cos(now * 2 * math.pi / PERIOD)
		for _, e in entries do
			local f = math.clamp(1 - (now - e.flashAt) / FLASH_TIME, 0, 1)
			if e.tips then
				e.tips.Color = e.base:Lerp(Color3.new(1, 1, 1), TIP_WHITE * k):Lerp(e.flashColor, f)
			end
			if e.light then
				local glow = LIGHT_LOW + (LIGHT_HIGH - LIGHT_LOW) * k
				e.light.Brightness = e.lightBase * (if e.flashColor.R > 0.5 then glow + 2.5 * f else glow * (1 - 0.8 * f))
			end
		end
	end)
end

return SecretCrystalController
