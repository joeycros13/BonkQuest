--!strict
-- InfuserController: the Infuser altars (Config/Infuse, 2026-10-12).
--
-- Every model tagged "Infuser" gets an "Infuse" prompt (E, drawn by PromptController) on its Stone
-- part; it opens the altar's panel (InfuserUI). When the server accepts an infusion it fires
-- Remotes.CoreInfused { core, awakened, infuser } and this plays the reveal over that altar
-- (user's pick, ~3 s, no camera shake):
--   0.0  the blade (the Rusty Blade, or the Worldheart for a later core) rises out of the altar's
--        socket, tip up, its socket face turned to the camera
--   0.8  the core leaves the player and arcs into its socket, spinning
--   1.75 a violet flash and burst; when it awakens, flakes of rust fall away and the Worldheart
--        Blade takes the Rusty Blade's place, the core set in its guard
--   2.9  it fades out; the server then puts the blade in the hand and shows AWAKENED!
-- All of it is local copies (anchored, no collisions); nothing replicates.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Infuse = require(Config:WaitForChild("Infuse"))
local Effects = require(Shared:WaitForChild("Animation"):WaitForChild("Effects"))

local InfuserController = {}

local TAG = "Infuser"
local SOCKET_TOP = 2.62 -- the altar's socket ring above its pivot (the ground)
local HOVER = 1.4 -- the blade's grip this far above the socket ring
local FLASH_COLOR = Color3.fromHex("b98cff")
local RUST_COLORS = { Color3.fromHex("a9502a"), Color3.fromHex("74371c"), Color3.fromHex("c9763d") }

local player = Players.LocalPlayer
local deps: any = nil
local prompts: { [Instance]: ProximityPrompt } = {}
local playing = false

local function assets(): Instance
	return ReplicatedStorage:WaitForChild("Assets")
end

local function prepare(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		elseif d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
end

local function fade(model: Model, seconds: number)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			TweenService:Create(d, TweenInfo.new(seconds), { Transparency = 1 }):Play()
		end
	end
end

-- A core's gem, scaled and set into a socket attachment of a Worldheart copy.
local function setGem(blade: Model, core: string)
	local n = Infuse.socketOf(core)
	local grip = blade.PrimaryPart
	local socket = n and grip and grip:FindFirstChild("Socket" .. n)
	local template = assets():FindFirstChild("Cores") and assets().Cores:FindFirstChild(core)
	if socket and socket:IsA("Attachment") and template and template:IsA("Model") then
		local gem = template:Clone()
		local cf, scale = Infuse.gemCFrame(socket)
		gem:ScaleTo(scale)
		gem:PivotTo(cf)
		prepare(gem)
		gem.Parent = blade
	end
end

local function bladeCopy(id: string): Model?
	local template = assets():WaitForChild("Weapons"):FindFirstChild(id)
	if not (template and template:IsA("Model")) then
		return nil
	end
	local copy = template:Clone()
	prepare(copy)
	return copy
end

-- The altar display (user, 2026-10-15): each core the player has infused sits in its world's cup on
-- the altar top (cup 1 at the front, then clockwise seen from above), and once the blade has awoken
-- their Worldheart stands point-down in the centre cup, socket face to the front. Local copies only:
-- every player sees their own progress.

local CUP_RING = 0.92 -- the cups' distance from the altar's centre
local CUP_TOP = 2.445 -- the cups' floor above the altar's pivot (the ground)
local CENTRE_TOP = 2.54 -- the centre cup's floor
local TIP_SINK = 0.25 -- how far the blade's tip sinks into the centre cup

local displays: { [Instance]: Folder } = {}

local function clearDisplay(altar: Instance)
	local folder = displays[altar]
	if folder then
		folder:Destroy()
		displays[altar] = nil
	end
end

-- How far the blade's tip lies below its grip (the parts are lined up with the grip).
local function tipDepth(blade: Model): number
	local grip = blade.PrimaryPart
	local depth = 0
	for _, p in blade:GetDescendants() do
		if p:IsA("BasePart") and grip then
			local z = grip.CFrame:PointToObjectSpace(p.Position).Z - p.Size.Z / 2
			depth = math.max(depth, -z)
		end
	end
	return depth
end

local function refreshDisplay(altar: Instance)
	clearDisplay(altar)
	if not (altar:IsA("Model") and altar.Parent) then
		return
	end
	local cores = Infuse.infused(player)
	local folder = Instance.new("Folder")
	folder.Name = "AltarDisplay"
	local pivot = altar:GetPivot()
	local count = 0
	for id in cores do
		count += 1
		local n = Infuse.socketOf(id)
		local template = assets():FindFirstChild("Cores") and assets().Cores:FindFirstChild(id)
		if n and template and template:IsA("Model") then
			local a = math.rad((n - 1) * 45)
			local spot = Vector3.new(math.sin(a) * CUP_RING, CUP_TOP + Infuse.GIRDLE_LIFT, -math.cos(a) * CUP_RING)
			-- turned so the emblem points away from the front: it reads upright from in front of the altar
			local gem = template:Clone()
			gem:PivotTo(pivot * CFrame.new(spot) * CFrame.Angles(0, math.pi + Infuse.GEM_TURN, 0))
			prepare(gem)
			gem.Parent = folder
		end
	end
	if count > 0 then
		local blade = bladeCopy(Infuse.bladeOf(count))
		if blade then
			for id in cores do
				setGem(blade, id)
			end
			local front = pivot.LookVector
			local up = pivot.UpVector
			local at = pivot.Position + up * (CENTRE_TOP + tipDepth(blade) - TIP_SINK)
			blade:PivotTo(CFrame.fromMatrix(at, front, up:Cross(front)))
			blade.Parent = folder
		end
	end
	folder.Parent = workspace
	displays[altar] = folder
end

local function refreshAll()
	for _, altar in CollectionService:GetTagged(TAG) do
		refreshDisplay(altar)
	end
end

local function play(info: any)
	local altar = info.infuser
	if playing or not (altar and altar:IsA("Model") and altar.Parent) then
		return
	end
	playing = true
	clearDisplay(altar)
	local core: string = info.core
	local awakened: boolean = info.awakened == true
	local top = altar:GetPivot().Position + Vector3.new(0, SOCKET_TOP, 0)
	-- the blade stands tip up with its socket face (+X) toward the camera
	local cam = workspace.CurrentCamera
	local toCam = (cam.CFrame.Position - top) * Vector3.new(1, 0, 1)
	local yaw = if toCam.Magnitude > 0.01 then math.atan2(-toCam.Unit.Z, toCam.Unit.X) else 0
	local function pose(height: number): CFrame
		return CFrame.new(top + Vector3.new(0, height, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(90), 0, 0)
	end
	local blade = bladeCopy(if awakened then Infuse.BLADE else Infuse.AWAKENED)
	if not blade then
		playing = false
		return
	end
	if not awakened then
		-- the cores already in it
		for id in Infuse.infused(player) do
			if id ~= core then
				setGem(blade, id)
			end
		end
	end
	blade:PivotTo(pose(-1.2))
	blade.Parent = workspace
	-- rise
	local rise = Instance.new("CFrameValue")
	rise.Value = pose(-1.2)
	rise.Changed:Connect(function(v)
		if blade.Parent then
			blade:PivotTo(v)
		end
	end)
	TweenService:Create(rise, TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = pose(HOVER) }):Play()
	task.wait(0.8)

	-- the core flies in
	local target: Vector3
	local face = blade.PrimaryPart and blade.PrimaryPart.CFrame.RightVector or Vector3.xAxis
	if awakened then
		local socket = blade:FindFirstChild("Socket")
		target = (if socket and socket:IsA("BasePart") then socket.Position else top) + face * 0.2
	else
		local n = Infuse.socketOf(core)
		local att = n and blade.PrimaryPart and blade.PrimaryPart:FindFirstChild("Socket" .. n)
		target = if att and att:IsA("Attachment") then att.WorldPosition else top
	end
	local coreTemplate = assets():FindFirstChild("Cores") and assets().Cores:FindFirstChild(core)
	local gem: Model? = nil
	if coreTemplate and coreTemplate:IsA("Model") then
		gem = coreTemplate:Clone()
		local g = gem :: Model
		g:ScaleTo(1.7) -- the core model is socket size (0.3 across); about 0.5 across in flight
		prepare(g)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local from = if root and root:IsA("BasePart") then root.Position + Vector3.new(0, 1.5, 0) else top + Vector3.new(0, 4, 0)
		g:PivotTo(CFrame.new(from))
		g.Parent = workspace
		local t0 = os.clock()
		local FLY = 0.9
		while os.clock() - t0 < FLY do
			local f = (os.clock() - t0) / FLY
			local e = f * f * (3 - 2 * f)
			local p = from:Lerp(target, e) + Vector3.new(0, math.sin(f * math.pi) * 2.5, 0)
			g:PivotTo(CFrame.new(p) * CFrame.Angles(0, f * 9, 0) * CFrame.Angles(0, 0, -math.pi / 2 * e))
			task.wait()
		end
		g:Destroy()
		gem = nil
	end

	-- the flash
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = FLASH_COLOR
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.CastShadow = false
	flash.Size = Vector3.one * 0.6
	flash.Transparency = 0.15
	flash.Position = target
	flash.Parent = workspace
	TweenService:Create(flash, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 9, Transparency = 1 }):Play()
	Debris:AddItem(flash, 0.6)
	pcall(Effects.burst, CFrame.new(target), "DeathPop")
	pcall(Effects.burst, CFrame.new(target), "Poof")

	if awakened then
		-- rust flakes fall away and the Worldheart takes the Rusty Blade's place
		local at = blade:GetPivot()
		for i = 1, 14 do
			local flake = Instance.new("Part")
			flake.Size = Vector3.new(0.18, 0.06, 0.24)
			flake.Color = RUST_COLORS[(i % #RUST_COLORS) + 1]
			flake.Material = Enum.Material.SmoothPlastic
			flake.CanCollide = false
			flake.CanQuery = false
			flake.CanTouch = false
			flake.CFrame = at * CFrame.new((math.random() - 0.5) * 0.3, (math.random() - 0.5) * 0.4, -(0.6 + math.random() * 3.6))
			flake.Parent = workspace
			flake.AssemblyLinearVelocity = Vector3.new((math.random() - 0.5) * 8, 3 + math.random() * 4, (math.random() - 0.5) * 8)
			flake.AssemblyAngularVelocity = Vector3.new(math.random() * 10, math.random() * 10, math.random() * 10)
			Debris:AddItem(flake, 1.6)
		end
		blade:Destroy()
		local awake = bladeCopy(Infuse.AWAKENED)
		if not awake then
			playing = false
			return
		end
		blade = awake
		for id in Infuse.infused(player) do
			setGem(blade, id)
		end
		setGem(blade, Infuse.FIRST)
		blade:PivotTo(at)
		blade.Parent = workspace
	else
		setGem(blade, core)
	end

	-- hold, then fade away (the server puts the real one in the hand)
	local hold = pose(HOVER)
	local t1 = os.clock()
	while os.clock() - t1 < 1.0 do
		local f = (os.clock() - t1)
		if blade.Parent then
			blade:PivotTo(hold * CFrame.new(0, 0, -0.15 * math.sin(f * 4)))
		end
		task.wait()
	end
	fade(blade, 0.35)
	task.wait(0.4)
	blade:Destroy()
	rise:Destroy()
	playing = false
	refreshAll()
end

local function addPrompt(model: Instance)
	if prompts[model] or not model:IsA("Model") then
		return
	end
	local part = model:FindFirstChild("Stone") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not (part and part:IsA("BasePart")) then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "InfusePrompt"
	prompt.ActionText = "Infuse"
	prompt.ObjectText = ""
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.zero
	prompt.Triggered:Connect(function()
		if not playing then
			deps.UI.InfuserUI.open(model)
		end
	end)
	prompt.Parent = part
	prompts[model] = prompt
end

function InfuserController.init(injected: any)
	deps = injected
end

function InfuserController.start()
	for _, model in CollectionService:GetTagged(TAG) do
		addPrompt(model)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(addPrompt)
	refreshAll()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(refreshDisplay)
	player:GetAttributeChangedSignal("InfusedCores"):Connect(function()
		if not playing then
			refreshAll()
		end
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(model)
		clearDisplay(model)
		local prompt = prompts[model]
		if prompt then
			prompt:Destroy()
			prompts[model] = nil
		end
	end)
	deps.Remotes.getEvent("CoreInfused").OnClientEvent:Connect(function(info: any)
		if type(info) == "table" and type(info.core) == "string" then
			task.spawn(play, info)
		end
	end)
end

return InfuserController
