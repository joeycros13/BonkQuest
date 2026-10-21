--!strict
-- TelescopeController: the World 2 lookout telescope (user, 2026-10-12; memory
-- `secret-enemies`). It only ever looks at the fairy ring, with no hint text.
--
-- A model tagged "Telescope" gets a "Look" prompt (E, drawn by PromptController)
-- on its Mount part. Its attributes:
--   LookAt   Vector3  the point the view centres on (the ring)
--   ViewFov  number   the zoomed field of view (default 9)
-- Looking: the controls lock and the HUD hides; the camera glides to the eyecup,
-- then the hand-built StarterGui/TelescopeView lens (option A, brass rim) shows
-- and the camera pushes out past the railing while the FOV zooms onto LookAt.
-- E, gamepad B, a click or the lens's StepBack button steps back the same way.
-- Nothing blocks the view (2026-10-20, the user's pick after re-dressings grew trees into the
-- line): while looking, every decoration and gathering node of the telescope's world whose
-- bounding sphere enters the lens's view cone (eyecup to the ring, minus `CLEAR_NEAR` at the
-- far end) is hidden for this player only (LocalTransparencyModifier 1), the ring's own
-- `FairyRing` decorations excepted; stepping back puts each part's old value back (a broken
-- gathering node keeps its own).
-- The lookout itself and the player's own body are hidden the same way while the lens is up
-- (2026-10-20, the user: parts of the tower flashed by as the camera pushed out through the
-- railing): the lens comes up, and they go, just before the glide reaches the eyecup, and come
-- back just after the glide back leaves it, so the camera never shows the inside of the tube.
-- The tube is aimed so its eyecup -> lens line runs straight through LookAt, and the camera
-- moves along that line.
-- Nothing here builds UI; it only shows the lens and wires its button.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local TelescopeController = {}

local TAG = "Telescope"
local EXIT_ACTION = "TelescopeStepBack"
local TO_EYE, ZOOM, BACK = 0.45, 0.9, 0.5
local PUSH_OUT = 3 -- studs past the objective lens, clear of the railing
local CONE_TAN = math.tan(math.rad(6)) -- the lens shows ~4.5 degrees round the centre; a little margin
local CLEAR_NEAR = 10 -- studs short of LookAt where hiding stops (the ring itself stays)
local LENS_AT = 0.8 -- share of the glide to the eyecup after which the lens comes up

local player = Players.LocalPlayer
local busy = false
local viewing: { model: Model, prompt: ProximityPrompt, startCf: CFrame, startFov: number, huds: { [ScreenGui]: boolean }, died: RBXScriptConnection?, hidden: { [BasePart]: number }? }? = nil

local function lensGui(): ScreenGui?
	local g = player:WaitForChild("PlayerGui"):FindFirstChild("TelescopeView")
	return if g and g:IsA("ScreenGui") then g else nil
end

local function controls(): any?
	local ok, module = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: any)
	end)
	return if ok and module then module:GetControls() else nil
end

-- Glide the camera; `midway` (if given) runs once `at` of the way through, without a pause.
local function tweenCamera(cf: CFrame, fov: number, seconds: number, style: Enum.EasingStyle?, at: number?, midway: (() -> ())?)
	local cam = workspace.CurrentCamera
	local tween = TweenService:Create(cam, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = cf, FieldOfView = fov })
	tween:Play()
	if midway then
		task.wait(seconds * (at or 0.5))
		midway()
	end
	if tween.PlaybackState == Enum.PlaybackState.Playing then
		tween.Completed:Wait()
	end
end

-- Hide every part of `root` for this player, keeping the old values in `hidden`.
local function hideAll(root: Instance?, hidden: { [BasePart]: number })
	if not root then
		return
	end
	for _, part in root:GetDescendants() do
		if part:IsA("BasePart") and hidden[part] == nil then
			hidden[part] = part.LocalTransparencyModifier
			part.LocalTransparencyModifier = 1
		end
	end
end

local function poses(model: Model): (CFrame?, CFrame?)
	local lookAt = model:GetAttribute("LookAt")
	local glass = model:FindFirstChild("Glass")
	local eyecup = model:FindFirstChild("Eyecup")
	if typeof(lookAt) ~= "Vector3" or not (glass and glass:IsA("BasePart") and eyecup and eyecup:IsA("BasePart")) then
		return nil, nil
	end
	local dir = (lookAt - glass.Position).Unit
	return CFrame.lookAt(eyecup.Position, lookAt), CFrame.lookAt(glass.Position + dir * PUSH_OUT, lookAt)
end

-- Hide, for this player, whatever stands in the view cone from `from` to `lookAt`: the
-- decorations and gathering nodes of the telescope's world. Returns each part's old value.
local function hideBlockers(model: Model, from: Vector3, lookAt: Vector3): { [BasePart]: number }
	local hidden: { [BasePart]: number } = {}
	local world: Instance? = model
	while world and world.Parent ~= workspace:FindFirstChild("Worlds") do
		world = world.Parent
	end
	if not world then
		return hidden
	end
	local axis = lookAt - from
	local length = axis.Magnitude
	local dir = axis.Unit
	local function blocks(item: Model): boolean
		local cf, size = item:GetBoundingBox()
		local radius = size.Magnitude / 2 * 0.8
		local rel = cf.Position - from
		local t = rel:Dot(dir)
		if t < -radius or t > length - CLEAR_NEAR + radius then
			return false
		end
		local off = (rel - dir * t).Magnitude
		return off < math.max(t, 0) * CONE_TAN + radius
	end
	local function scan(folder: Instance?)
		if not folder then
			return
		end
		for _, item in folder:GetDescendants() do
			if item:IsA("Model") and item.Parent and not item.Parent:IsA("Model") and item.Name ~= "FairyRing" and not item:FindFirstAncestor("FairyRing") and blocks(item) then
				hideAll(item, hidden)
			end
		end
	end
	scan(world:FindFirstChild("Decorations"))
	scan(world:FindFirstChild("Gathering"))
	return hidden
end

local function unhide(hidden: { [BasePart]: number }?)
	for part, old in hidden or {} do
		if part.Parent then
			part.LocalTransparencyModifier = old
		end
	end
end

local stepBack: () -> ()

local function look(model: Model, prompt: ProximityPrompt)
	if busy or viewing then
		return
	end
	local eye, view = poses(model)
	local gui = lensGui()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (eye and view and gui and humanoid) then
		return
	end
	busy = true
	prompt.Enabled = false
	local ctl = controls()
	if ctl then
		ctl:Disable()
	end
	local huds = {}
	for _, g in player.PlayerGui:GetChildren() do
		if g:IsA("ScreenGui") and g ~= gui and g.Name ~= "ScreenFade" and g.Enabled then
			huds[g] = true
			g.Enabled = false
		end
	end
	local cam = workspace.CurrentCamera
	viewing = { model = model, prompt = prompt, startCf = cam.CFrame, startFov = cam.FieldOfView, huds = huds, died = nil }
	;(viewing :: any).died = humanoid.Died:Connect(function()
		stepBack()
	end)
	cam.CameraType = Enum.CameraType.Scriptable
	local lookAt = model:GetAttribute("LookAt") :: Vector3
	tweenCamera(eye :: CFrame, cam.FieldOfView, TO_EYE, nil, LENS_AT, function()
		gui.Enabled = true
		local hidden = hideBlockers(model, (view :: CFrame).Position, lookAt)
		-- the lookout the telescope stands on (or the telescope alone), and the player's body
		local tower = if model.Parent and model.Parent:IsA("Model") then model.Parent else model
		hideAll(tower, hidden)
		hideAll(character, hidden)
		;(viewing :: any).hidden = hidden
	end)
	local fov = model:GetAttribute("ViewFov")
	tweenCamera(view :: CFrame, if type(fov) == "number" then fov else 9, ZOOM, Enum.EasingStyle.Quart)
	ContextActionService:BindActionAtPriority(EXIT_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			task.spawn(stepBack)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 10, Enum.KeyCode.E, Enum.KeyCode.ButtonB, Enum.UserInputType.MouseButton1)
	busy = false
end

stepBack = function()
	local v = viewing
	if busy or not v then
		return
	end
	busy = true
	ContextActionService:UnbindAction(EXIT_ACTION)
	if v.died then
		v.died:Disconnect()
	end
	local gui = lensGui()
	local eye = poses(v.model)
	local cam = workspace.CurrentCamera
	if eye then
		tweenCamera(eye, v.startFov, BACK, Enum.EasingStyle.Quart)
	end
	tweenCamera(v.startCf, v.startFov, TO_EYE, nil, 1 - LENS_AT, function()
		if gui then
			gui.Enabled = false
		end
		unhide(v.hidden)
	end)
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = v.startFov
	for g in v.huds do
		if g.Parent then
			g.Enabled = true
		end
	end
	local ctl = controls()
	if ctl then
		ctl:Enable()
	end
	v.prompt.Enabled = true
	viewing = nil
	busy = false
end

local function adopt(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local mount = model:FindFirstChild("Mount")
	if not (mount and mount:IsA("BasePart")) or mount:FindFirstChild("LookPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LookPrompt"
	prompt.ActionText = "Look"
	prompt.ObjectText = ""
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Parent = mount
	prompt.Triggered:Connect(function()
		task.spawn(look, model, prompt)
	end)
end

local deps: any = nil

function TelescopeController.init(injected: any)
	deps = injected
end

function TelescopeController.start()
	-- the lens is copied into PlayerGui after controllers start, so wait for it
	task.spawn(function()
		local found = player:WaitForChild("PlayerGui"):WaitForChild("TelescopeView", 30)
		local gui = if found and found:IsA("ScreenGui") then found else nil
		if not gui then
			return
		end
		gui.Enabled = false
		-- Luckiest Guy sits high in its box: drop the E key's letter to its middle
		if deps and deps.Util and deps.Util.FontDrop then
			deps.Util.FontDrop.watch(gui)
		end
		local button = gui:FindFirstChild("StepBack")
		if button and button:IsA("GuiButton") then
			button.Activated:Connect(function()
				task.spawn(stepBack)
			end)
			-- the E key chip is for keyboards; touch players just tap the button
			local key = button:FindFirstChild("Key", true)
			if key and key:IsA("GuiObject") then
				key.Visible = UserInputService.KeyboardEnabled
			end
		end
	end)
	for _, model in CollectionService:GetTagged(TAG) do
		adopt(model)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(adopt)
end

return TelescopeController
