--!strict
-- WorldFlybyController: the short cinematic when a new world unlocks (issue 28, 2026-10-25,
-- the user's picks: a flight along the path ending on the boss's name card, the unlock burst at
-- the gate, letterbox bars with the world's title, a click to skip; about 8 seconds).
--
-- It plays when the local player's HighestWorld rises after their save has loaded (buying a
-- gate), for a world that has a flight path:
--   1. Unlock (UnlockSeconds): the gate bursts (DeathPop stars, a ring) as GateUI opens it,
--      the HUD hides, letterbox bars slide in and "WORLD 2 / UNLOCKED!" slams in over spinning
--      rays; the camera eases up from where it was.
--   2. Flight (FlightSeconds): the camera glides along the world's hand-placed path,
--      Workspace.Worlds.<world>/Cinematic/Flyby/P1, P2... (invisible parts; move them in
--      Studio to change the route; the folder's `Pitch` attribute is how far down it looks, in
--      degrees), turning to face where it is going, then toward the boss;
--      the world's banner (WorldBannerUI) shows its name as the camera crosses in.
--   3. Boss (BossSeconds): from the path's `BossShot` part (its CFrame is the camera's), the
--      camera pushes in (PushIn of the way) while the boss plays its attack with its angry
--      face (EnemyAnimator.showOff) and its name card slams in ("ELDER TREANT" / "WORLD BOSS").
--   4. A quick fade to black, and the player is back at the gate with the HUD.
-- A click (the gui's Skip button, after SkipAfter seconds) jumps to the fade. The player is
-- frozen meanwhile (InputLocked, anchored, controls off).
--
-- The look is hand-built: StarterGui/Cinematic -- TopBar / BottomBar (black, slid in and out;
-- BottomBar/SkipHint), Unlocked (PopScale; Rays, RaysInner, World / WorldShadow ("WORLD %d",
-- the gui's UnlockFormat), Label / Shadow "UNLOCKED!"), BossCard (PopScale; Rays, PlateLip,
-- Plate, Name, SubPill/Sub (BossSubtitle)) and Skip. Gui attributes: UnlockSeconds,
-- FlightSeconds, BossSeconds, BarSeconds, FadeSeconds, PushIn, BarHeight, TitleAt (share of
-- the flight when the title shows), UnlockFormat, BossSubtitle, SkipAfter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Worlds = require(Config:WaitForChild("Worlds"))
local Enemies = require(Config:WaitForChild("Enemies"))
local Gates = require(Config:WaitForChild("Gates"))
local Animation = require(Shared:WaitForChild("Animation"))
local Effects = Animation.Effects

local WorldFlybyController = {}

local player = Players.LocalPlayer
local deps: any = nil

-- guis left alone while the HUD hides
local KEEP_GUIS = { Cinematic = true, WorldBanner = true, ScreenFade = true }
local LOOK_AHEAD = 30 -- studs along the path the camera looks ahead to
local TURN_TO_BOSS = 0.35 -- the last share of the flight turns the camera toward the boss
-- the flight looks this far down at the world, whatever the path does (a climb looked at the
-- sky); a Flyby folder's own `Pitch` attribute (degrees) wins: a cave's is gentler
local FLIGHT_PITCH = -22
-- the boss shot aims this share of the boss's height below its middle, so the boss sits
-- above the name card
local SHOT_DROP = 0.25
local SAMPLES = 240

local playing = false

local function number(gui: Instance, name: string, fallback: number): number
	local value = gui:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

-- The path as evenly spaced samples, so the camera moves at one speed: (points, total length).
local function samplePath(points: { Vector3 }): ({ Vector3 }, { number })
	local raw: { Vector3 } = {}
	local segments = #points - 1
	for i = 1, segments do
		local p0, p1, p2, p3 = points[math.max(i - 1, 1)], points[i], points[i + 1], points[math.min(i + 2, #points)]
		local steps = math.ceil(SAMPLES / segments)
		for s = 0, steps - 1 do
			table.insert(raw, catmull(p0, p1, p2, p3, s / steps))
		end
	end
	table.insert(raw, points[#points])
	local lengths = { 0 }
	for i = 2, #raw do
		lengths[i] = lengths[i - 1] + (raw[i] - raw[i - 1]).Magnitude
	end
	return raw, lengths
end

local function at(raw: { Vector3 }, lengths: { number }, distance: number): Vector3
	local total = lengths[#lengths]
	distance = math.clamp(distance, 0, total)
	local lo, hi = 1, #lengths
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if lengths[mid] <= distance then
			lo = mid
		else
			hi = mid
		end
	end
	local span = lengths[hi] - lengths[lo]
	local f = if span > 1e-6 then (distance - lengths[lo]) / span else 0
	return raw[lo]:Lerp(raw[hi], f)
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function controls(): any
	local ok, module = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript) :: any
	end)
	return if ok and module then module:GetControls() else nil
end

local function setFrozen(frozen: boolean)
	player:SetAttribute("InputLocked", if frozen then true else nil)
	-- the guide arrow hides meanwhile (GuideController)
	player:SetAttribute("Cinematic", if frozen then true else nil)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		root.Anchored = frozen
	end
end

-- Hide every gui but the cinematic's own; returns a function that brings them back.
local function hideHud(): () -> ()
	local saved: { [ScreenGui]: boolean } = {}
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	for _, gui in if playerGui then playerGui:GetChildren() else {} do
		if gui:IsA("ScreenGui") and not KEEP_GUIS[gui.Name] and gui.Enabled then
			saved[gui] = true
			gui.Enabled = false
		end
	end
	return function()
		for gui in saved do
			if gui.Parent then
				gui.Enabled = true
			end
		end
	end
end

local function setText(parent: Instance, names: { string }, text: string)
	for _, name in names do
		local label = parent:FindFirstChild(name, true)
		if label and label:IsA("TextLabel") then
			label.Text = text
		end
	end
end

local function spin(image: Instance?, degrees: number, seconds: number)
	if image and image:IsA("ImageLabel") then
		TweenService:Create(image, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Rotation = image.Rotation + degrees }):Play()
	end
end

-- Pop a group (its PopScale) in with an overshoot from `from`, hold, and away.
local function popGroup(group: GuiObject, from: number, hold: number)
	local scale = group:FindFirstChild("PopScale")
	if not (scale and scale:IsA("UIScale")) then
		group.Visible = true
		return
	end
	group.Visible = true
	scale.Scale = from
	TweenService:Create(scale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	spin(group:FindFirstChild("Rays"), 60, hold + 0.6)
	spin(group:FindFirstChild("RaysInner"), -90, hold + 0.6)
	task.delay(0.32 + hold, function()
		if scale.Parent then
			TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		end
	end)
end

local function gateModel(world: number): Model?
	local folder = workspace:FindFirstChild("Shared")
	local gates = folder and folder:FindFirstChild("Gates")
	for _, gate in Gates.list do
		if gate.world == world and gates then
			local model = gates:FindFirstChild((gate :: any).model or (gate.id .. "Gate"))
			if model and model:IsA("Model") then
				return model
			end
		end
	end
	local model = gates and gates:FindFirstChild("World" .. world .. "Gate")
	return if model and model:IsA("Model") then model else nil
end

local function bossOf(folder: Instance): Model?
	local bosses = folder:FindFirstChild("Bosses")
	for _, model in if bosses then bosses:GetChildren() else {} do
		if model:IsA("Model") and model:GetAttribute("IsBoss") == true then
			return model
		end
	end
	return nil
end

function WorldFlybyController.play(world: number)
	if playing then
		return
	end
	local def = Worlds.get(world :: any)
	local worlds = workspace:FindFirstChild("Worlds")
	local folder = def and worlds and worlds:FindFirstChild((def :: any).folder)
	local cinematic = folder and folder:FindFirstChild("Cinematic")
	local flyby = cinematic and cinematic:FindFirstChild("Flyby")
	local shot = flyby and flyby:FindFirstChild("BossShot")
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local gui = playerGui and playerGui:FindFirstChild("Cinematic")
	local camera = workspace.CurrentCamera
	if not (folder and flyby and shot and shot:IsA("BasePart") and gui and gui:IsA("ScreenGui") and camera) then
		return
	end
	playing = true

	local unlockSeconds = number(gui, "UnlockSeconds", 1.6)
	local flightSeconds = number(gui, "FlightSeconds", 5)
	local bossSeconds = number(gui, "BossSeconds", 2)
	local barSeconds = number(gui, "BarSeconds", 0.35)
	local fadeSeconds = number(gui, "FadeSeconds", 0.25)
	local pushIn = number(gui, "PushIn", 0.18)
	local barHeight = number(gui, "BarHeight", 0.11)

	-- the boss and where the camera looks at it
	local boss = bossOf(folder)
	local bossDef = boss and Enemies.get(boss:GetAttribute("Archetype") :: any)
	local focus = shot.CFrame.Position + shot.CFrame.LookVector * 25
	local aim = focus
	if boss then
		local size = boss:GetExtentsSize()
		focus = boss:GetPivot().Position + Vector3.new(0, size.Y * 0.1, 0)
		aim = focus - Vector3.new(0, size.Y * SHOT_DROP, 0)
	end
	local pitchDegrees = flyby:GetAttribute("Pitch")
	local pitch = math.rad(if type(pitchDegrees) == "number" then pitchDegrees else FLIGHT_PITCH)

	-- the cinematic's pieces
	local top = gui:FindFirstChild("TopBar") :: GuiObject?
	local bottom = gui:FindFirstChild("BottomBar") :: GuiObject?
	local unlocked = gui:FindFirstChild("Unlocked") :: GuiObject?
	local card = gui:FindFirstChild("BossCard") :: GuiObject?
	local skip = gui:FindFirstChild("Skip") :: GuiButton?
	if unlocked then
		unlocked.Visible = false
		setText(unlocked, { "World", "WorldShadow" }, string.format(tostring(gui:GetAttribute("UnlockFormat") or "WORLD %d"), world))
	end
	if card then
		card.Visible = false
		setText(card, { "Name" }, string.upper(if bossDef then (bossDef :: any).name else "BOSS"))
		setText(card, { "Sub" }, tostring(gui:GetAttribute("BossSubtitle") or "WORLD BOSS"))
	end
	if top then
		top.Position = UDim2.fromScale(0.5, -barHeight)
	end
	if bottom then
		bottom.Position = UDim2.fromScale(0.5, 1 + barHeight)
	end
	deps.Util.FontDrop.watch(gui)
	gui.Enabled = true
	local barInfo = TweenInfo.new(barSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if top then
		TweenService:Create(top, barInfo, { Position = UDim2.fromScale(0.5, 0) }):Play()
	end
	if bottom then
		TweenService:Create(bottom, barInfo, { Position = UDim2.fromScale(0.5, 1) }):Play()
	end

	-- the player waits; the HUD goes
	local showHud = hideHud()
	local control = controls()
	if control then
		control:Disable()
	end
	setFrozen(true)

	-- the burst at the gate, as GateUI opens it
	local gate = gateModel(world)
	if gate then
		local pivot = gate:GetPivot().Position + Vector3.new(0, 14, 0)
		Effects.burst(pivot, "DeathPop", { count = 40 })
		Effects.burst(pivot, "Poof", { count = 24 })
		Effects.shockwave(gate:GetPivot().Position + Vector3.new(0, 0.3, 0), "Shockwave", { endSize = 40, color = Color3.fromRGB(255, 226, 120) })
	end
	if unlocked then
		popGroup(unlocked, 0.2, unlockSeconds - 0.6)
	end

	-- the path: from the camera (lifted a little during the unlock) through P1, P2... to the boss shot
	local startCFrame = camera.CFrame
	local lifted = startCFrame.Position + Vector3.new(0, 4, 0) - startCFrame.LookVector * 3
	local points: { Vector3 } = { lifted }
	local index = 1
	while true do
		local point = flyby:FindFirstChild("P" .. index)
		if not (point and point:IsA("BasePart")) then
			break
		end
		table.insert(points, point.Position)
		index += 1
	end
	table.insert(points, shot.Position)
	local raw, lengths = samplePath(points)
	local total = lengths[#lengths]

	-- the world's banner shows under the top bar, not behind it
	local worldBanner = playerGui and playerGui:FindFirstChild("WorldBanner")
	local banner = worldBanner and worldBanner:FindFirstChild("Banner")
	local bannerPosition = if banner and banner:IsA("GuiObject") then banner.Position else nil
	if banner and banner:IsA("GuiObject") and bannerPosition then
		banner.Position = bannerPosition + UDim2.fromScale(0, barHeight)
	end

	-- the boss stops wandering and turns to where the camera will be
	if boss then
		deps.Controllers.WorldEnemyController.face(boss, shot.Position, unlockSeconds + flightSeconds + bossSeconds + 1)
	end

	local savedType = camera.CameraType
	local savedFov = camera.FieldOfView
	local started = os.clock()
	local finished = false
	local titleShown = false
	local bossShown = false
	local ending = false

	local function finish()
		if ending then
			return
		end
		ending = true
		deps.Controllers.FadeController.fade("out", fadeSeconds)
		task.wait(fadeSeconds + 0.05)
		finished = true
	end

	local system = Animation.Scheduler.bind("Camera", "WorldFlyby", 45, function(_dt: number, now: number)
		if finished then
			return
		end
		camera.CameraType = Enum.CameraType.Scriptable
		local t = now - started
		if t < unlockSeconds then
			-- the unlock: ease up and back from where the camera was
			local u = smooth(t / unlockSeconds)
			local pos = startCFrame.Position:Lerp(lifted, u)
			camera.CFrame = CFrame.lookAt(pos, pos + startCFrame.LookVector)
		elseif t < unlockSeconds + flightSeconds then
			-- the flight: one speed along the path, eased at both ends
			local u = (t - unlockSeconds) / flightSeconds
			local s = smooth(u) * total
			local pos = at(raw, lengths, s)
			local ahead = at(raw, lengths, s + LOOK_AHEAD)
			if (ahead - pos).Magnitude < 1 then
				ahead = pos + shot.CFrame.LookVector
			end
			-- the way the path heads, tipped down to look over the world
			local heading = Vector3.new(ahead.X - pos.X, 0, ahead.Z - pos.Z)
			heading = if heading.Magnitude > 1e-3 then heading.Unit else Vector3.new(0, 0, -1)
			local look = heading * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)
			-- out of the start's view at first, toward the boss at the end
			look = startCFrame.LookVector:Lerp(look, smooth(u / 0.15))
			local toBoss = (aim - pos)
			if toBoss.Magnitude > 1 then
				look = look:Lerp(toBoss.Unit, smooth((u - (1 - TURN_TO_BOSS)) / TURN_TO_BOSS))
			end
			camera.CFrame = CFrame.lookAt(pos, pos + look)
			if not titleShown and u >= number(gui, "TitleAt", 0.12) then
				titleShown = true
				deps.UI.WorldBannerUI.show(world)
			end
		else
			-- the boss: push in, the attack, the name card
			local u = math.clamp((t - unlockSeconds - flightSeconds) / bossSeconds, 0, 1)
			local from = shot.Position
			local pos = from:Lerp(focus, pushIn * (1 - (1 - u) * (1 - u)))
			camera.CFrame = CFrame.lookAt(pos, aim)
			if not bossShown then
				bossShown = true
				if boss then
					deps.Controllers.EnemyAnimator.showOff(boss)
				end
				if card then
					task.delay(0.15, popGroup, card, 2.2, bossSeconds - 0.7)
				end
			end
			if u >= 1 then
				task.spawn(finish)
			end
		end
	end)

	local skipConn: RBXScriptConnection? = nil
	if skip then
		skipConn = skip.Activated:Connect(function()
			if os.clock() - started >= number(gui, "SkipAfter", 0.5) then
				task.spawn(finish)
			end
		end)
	end
	local deathConn = player.CharacterRemoving:Connect(function()
		task.spawn(finish)
	end)

	while not finished do
		task.wait()
	end

	-- back to the player
	system:Unbind()
	if skipConn then
		skipConn:Disconnect()
	end
	deathConn:Disconnect()
	camera.CameraType = if savedType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else savedType
	camera.FieldOfView = savedFov
	camera.CFrame = startCFrame
	if unlocked then
		unlocked.Visible = false
	end
	if card then
		card.Visible = false
	end
	if top then
		top.Position = UDim2.fromScale(0.5, -barHeight)
	end
	if bottom then
		bottom.Position = UDim2.fromScale(0.5, 1 + barHeight)
	end
	gui.Enabled = false
	if banner and banner:IsA("GuiObject") and bannerPosition then
		banner.Position = bannerPosition
	end
	setFrozen(false)
	if control then
		control:Enable()
	end
	showHud()
	deps.Controllers.FadeController.fade("in", fadeSeconds)
	playing = false
end

function WorldFlybyController.init(injected: any)
	deps = injected
end

function WorldFlybyController.start()
	task.spawn(function()
		if player:GetAttribute("DataLoaded") ~= true then
			player:GetAttributeChangedSignal("DataLoaded"):Wait()
		end
		local highest = tonumber(player:GetAttribute("HighestWorld")) or 1
		player:GetAttributeChangedSignal("HighestWorld"):Connect(function()
			local now = tonumber(player:GetAttribute("HighestWorld")) or 1
			if now > highest then
				highest = now
				task.spawn(WorldFlybyController.play, now)
			else
				highest = now
			end
		end)
	end)
end

return WorldFlybyController
