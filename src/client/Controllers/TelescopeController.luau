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

local player = Players.LocalPlayer
local busy = false
local viewing: { model: Model, prompt: ProximityPrompt, startCf: CFrame, startFov: number, huds: { [ScreenGui]: boolean }, died: RBXScriptConnection? }? = nil

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

local function tweenCamera(cf: CFrame, fov: number, seconds: number, style: Enum.EasingStyle?)
	local cam = workspace.CurrentCamera
	local tween = TweenService:Create(cam, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = cf, FieldOfView = fov })
	tween:Play()
	tween.Completed:Wait()
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
	tweenCamera(eye :: CFrame, cam.FieldOfView, TO_EYE)
	gui.Enabled = true
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
	if gui then
		gui.Enabled = false
	end
	tweenCamera(v.startCf, v.startFov, TO_EYE)
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
