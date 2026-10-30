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
--   2. Flight: the camera glides along the world's hand-placed path,
--      Workspace.Worlds.<world>/Cinematic/Flyby/P1, P2... (invisible parts; move them in
--      Studio to change the route), at one speed with a gentle ease at both ends. The Flyby
--      folder's attributes: `Mode` "Straight" (one heading the whole way, the line from P1 to
--      the last P: World 2) or "Path" (it turns with the path: World 3's cave lanes), `Pitch`
--      (degrees it looks down), `Seconds` (the flight's length; else the gui's FlightSeconds),
--      `BossTurn` (the last share of the flight over which the view turns onto the boss).
--      A `Focus` part in the folder pulls the view toward it (World 4 circles its pyramid):
--      `FocusWeight` (0..1, how far toward it), up to `FocusUntil` (a share of the path),
--      then easing off over `FocusFade` (a share).
--      The view direction is filtered (LOOK_SMOOTH), so it never jitters (2026-10-25, the user:
--      World 2's first version was "too movey", it needed to be really smooth). The world's
--      banner (WorldBannerUI) shows its name as the camera crosses in.
--   3. Boss (BossSeconds): a soft fade through black to the path's `BossShot` (its CFrame is
--      the camera's: level with the boss's middle, aimed at its spawn point, the user's pick), which pushes
--      in PushStuds along its look while the boss plays its attack with its angry face
--      (EnemyAnimator.showOff) and its name card slams in ("ELDER TREANT" / "WORLD BOSS").
--   4. A fade to black, and the player is back where they were with the HUD.
-- A click (the gui's Skip button, after SkipAfter seconds) jumps to the fade. The player is
-- frozen meanwhile (InputLocked, anchored, controls off).
--
-- The look is hand-built: StarterGui/Cinematic -- TopBar / BottomBar (black, slid in and out;
-- BottomBar/SkipHint), Unlocked (PopScale; Rays, RaysInner, World / WorldShadow ("WORLD %d",
-- the gui's UnlockFormat), Label / Shadow "UNLOCKED!"), BossCard (PopScale; Rays, PlateLip,
-- Plate, Name, SubPill/Sub (BossSubtitle)) and Skip. Gui attributes: UnlockSeconds,
-- FlightSeconds, BossSeconds, BarSeconds, FadeSeconds (the end), CutSeconds (each half of the
-- fade to the boss shot), PushStuds, BarHeight, TitleAt (share of the flight when the title
-- shows), UnlockFormat, BossSubtitle, SkipAfter.
--
-- WorldFlybyController.play(world) is also the admin panel's "Play flyby" (2026-10-25: it
-- replays any world's flight for testing; players get it only when a gate opens).

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
local LOOK_AHEAD = 40 -- studs along the path a "Path" flight looks ahead to
-- seconds the view direction takes to follow a change: two exponential filters in a row, so
-- a turn starts and stops from rest (one filter started a turn at full rate); the start's view
-- eases into the flight's, and a path's turns come gently
local LOOK_SMOOTH = 0.35
-- the flight looks this far down at the world, whatever the path does (a climb looked at the
-- sky); a Flyby folder's own `Pitch` attribute (degrees) wins: a cave's is gentler
local FLIGHT_PITCH = -22
local SAMPLES = 400
-- a camera farther than this from P1 starts behind P1 instead of flying to it
local FAR_START = 120

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

-- an ease with zero speed and zero acceleration at both ends, for the flight
local function smoother(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * x * (x * (x * 6 - 15) + 10)
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

	local unlockSeconds = number(gui, "UnlockSeconds", 1.4)
	local flightSeconds = number(flyby, "Seconds", number(gui, "FlightSeconds", 7))
	local bossSeconds = number(gui, "BossSeconds", 2.6)
	local barSeconds = number(gui, "BarSeconds", 0.35)
	local fadeSeconds = number(gui, "FadeSeconds", 0.35)
	local cutSeconds = number(gui, "CutSeconds", 0.35)
	local pushStuds = number(gui, "PushStuds", 3)
	local barHeight = number(gui, "BarHeight", 0.11)

	local boss = bossOf(folder)
	local bossDef = boss and Enemies.get(boss:GetAttribute("Archetype") :: any)
	local pitchDegrees = flyby:GetAttribute("Pitch")
	local pitch = math.rad(if type(pitchDegrees) == "number" then pitchDegrees else FLIGHT_PITCH)
	local straight = flyby:GetAttribute("Mode") == "Straight"
	-- the last share of the flight that turns the view onto the boss (World 3's ends in the
	-- boss hall looking past her otherwise)
	local bossTurn = math.clamp(number(flyby, "BossTurn", 0), 0, 1)
	local focus = flyby:FindFirstChild("Focus")
	local focusWeight = math.clamp(number(flyby, "FocusWeight", 0), 0, 1)
	local focusUntil = math.clamp(number(flyby, "FocusUntil", 1), 0, 1)
	local focusFade = math.max(number(flyby, "FocusFade", 0.08), 1e-3)

	-- the boss goes back to its spawn point (the middle of its wander circle), where the
	-- boss shot is aimed, stops wandering and turns to the shot
	local bossAt: Vector3? = nil
	if boss then
		bossAt = deps.Controllers.WorldEnemyController.face(boss, shot.Position, unlockSeconds + flightSeconds + bossSeconds + 1)
	end

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

	-- the path: from the camera (lifted a little during the unlock) through P1, P2...
	local path: { Vector3 } = {}
	while true do
		local point = flyby:FindFirstChild("P" .. (#path + 1))
		if not (point and point:IsA("BasePart")) then
			break
		end
		table.insert(path, point.Position)
	end
	local startCFrame = camera.CFrame
	if #path >= 2 and (startCFrame.Position - path[1]).Magnitude > FAR_START then
		-- far from the path (the admin replay, pressed anywhere): start just behind P1 behind a
		-- quick fade, instead of flying across the map to it
		local d = path[2] - path[1]
		local heading = Vector3.new(d.X, 0, d.Z).Unit
		local from = path[1] - heading * 30 + Vector3.new(0, 6, 0)
		startCFrame = CFrame.lookAt(from, from + heading * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0))
		deps.Controllers.FadeController.fade("out", 0)
		deps.Controllers.FadeController.fade("in", fadeSeconds)
	end
	local lifted = startCFrame.Position + Vector3.new(0, 4, 0) - startCFrame.LookVector * 3
	local points: { Vector3 } = { lifted }
	for _, point in path do
		table.insert(points, point)
	end
	local raw, lengths = samplePath(points)
	local total = lengths[#lengths]
	-- a straight flight's one heading: from the first point to the last
	local lineHeading = Vector3.new(0, 0, -1)
	if #points >= 3 then
		local d = points[#points] - points[2]
		d = Vector3.new(d.X, 0, d.Z)
		if d.Magnitude > 1e-3 then
			lineHeading = d.Unit
		end
	end
	local function flightLook(s: number): Vector3
		local heading = lineHeading
		if not straight then
			local here, ahead = at(raw, lengths, s), at(raw, lengths, s + LOOK_AHEAD)
			local d = Vector3.new(ahead.X - here.X, 0, ahead.Z - here.Z)
			heading = if d.Magnitude > 1e-3 then d.Unit else lineHeading
		end
		local look = heading * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)
		if focus and focus:IsA("BasePart") and focusWeight > 0 then
			local w = focusWeight * (1 - smoother(math.clamp((s / total - focusUntil) / focusFade, 0, 1)))
			local toFocus = focus.Position - at(raw, lengths, s)
			if w > 0 and toFocus.Magnitude > 1e-3 then
				look = look:Lerp(toFocus.Unit, w).Unit
			end
		end
		local turnFrom = total * (1 - bossTurn)
		if bossAt and bossTurn > 0 and s > turnFrom then
			local toBoss = bossAt - at(raw, lengths, s)
			if toBoss.Magnitude > 1e-3 then
				look = look:Lerp(toBoss.Unit, smoother((s - turnFrom) / (total - turnFrom))).Unit
			end
		end
		return look
	end

	-- the world's banner shows under the top bar, not behind it
	local worldBanner = playerGui and playerGui:FindFirstChild("WorldBanner")
	local banner = worldBanner and worldBanner:FindFirstChild("Banner")
	local bannerPosition = if banner and banner:IsA("GuiObject") then banner.Position else nil
	if banner and banner:IsA("GuiObject") and bannerPosition then
		banner.Position = bannerPosition + UDim2.fromScale(0, barHeight)
	end

	local savedType = camera.CameraType
	local savedFov = camera.FieldOfView
	local started = os.clock()
	local finished = false
	local titleShown = false
	local bossShown = false
	local cutting = false
	local ending = false
	local look = startCFrame.LookVector
	local lookLead = startCFrame.LookVector

	local function finish()
		if ending then
			return
		end
		ending = true
		deps.Controllers.FadeController.fade("out", fadeSeconds)
		task.wait(fadeSeconds + 0.05)
		finished = true
	end

	local flightEnd = unlockSeconds + flightSeconds
	local system = Animation.Scheduler.bind("Camera", "WorldFlyby", 45, function(dt: number, now: number)
		if finished then
			return
		end
		camera.CameraType = Enum.CameraType.Scriptable
		local t = now - started
		if t < flightEnd then
			-- the unlock eases up and back from where the camera was; then the flight glides on
			local pos: Vector3
			local target: Vector3
			if t < unlockSeconds then
				pos = startCFrame.Position:Lerp(lifted, smoother(t / unlockSeconds))
				target = startCFrame.LookVector
			else
				local u = (t - unlockSeconds) / flightSeconds
				local s = smoother(u) * total
				pos = at(raw, lengths, s)
				target = flightLook(s)
				if not titleShown and u >= number(gui, "TitleAt", 0.12) then
					titleShown = true
					deps.UI.WorldBannerUI.show(world)
				end
			end
			-- the view follows its target through two filters, never in steps
			local blend = 1 - math.exp(-dt / LOOK_SMOOTH)
			lookLead = lookLead:Lerp(target, blend).Unit
			look = look:Lerp(lookLead, blend).Unit
			camera.CFrame = CFrame.lookAt(pos, pos + look)
			-- the soft cut to the boss: dark just as the flight ends
			if not cutting and t >= flightEnd - cutSeconds then
				cutting = true
				deps.Controllers.FadeController.fade("out", cutSeconds)
			end
		else
			-- the boss: a level shot, a slow push in, the attack, the name card
			local u = math.clamp((t - flightEnd) / bossSeconds, 0, 1)
			camera.CFrame = shot.CFrame + shot.CFrame.LookVector * (pushStuds * smoother(u))
			if not bossShown then
				bossShown = true
				deps.Controllers.FadeController.fade("in", cutSeconds)
				task.delay(cutSeconds * 0.6, function()
					if boss then
						deps.Controllers.EnemyAnimator.showOff(boss)
					end
					if card then
						popGroup(card, 2.2, bossSeconds - cutSeconds - 0.6)
					end
				end)
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
