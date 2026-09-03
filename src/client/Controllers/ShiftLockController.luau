--!strict
-- ShiftLockController: custom shift lock (mouse-lock) for the walking avatar.
-- When enabled it locks the cursor to screen center, makes the character face
-- the camera's look direction, and applies a slight over-the-shoulder camera
-- offset -- matching Roblox's built-in shift lock behavior. Works with the
-- default camera because forcing MouseBehavior = LockCenter makes the default
-- camera treat mouse movement as camera rotation.
--
-- Toggle with LeftShift (ignored while typing in a TextBox), or drive it from
-- other UI via the public setEnabled/toggle API (useful for a mobile button).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local ShiftLockController = {}

-- ==================== config ====================

local TOGGLE_KEY = Enum.KeyCode.LeftShift
-- Over-the-shoulder offset in head-space (+X = right). Set to Vector3.zero for
-- a centered lock.
local SHOULDER_OFFSET = Vector3.new(1.75, 0, 0)
local RENDER_BIND_NAME = "ShiftLockCharacterUpdate"

-- ==================== state ====================

local deps: any = nil
local player = Players.LocalPlayer

local enabled = false
local bound = false

local character: Model? = nil
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil

local changedEvent: BindableEvent = Instance.new("BindableEvent")

function ShiftLockController.init(injected: any)
	deps = injected
end

-- ==================== character wiring ====================

-- Apply or clear the shift-lock character properties (rotation lock + offset).
local function applyCharacterState()
	local hum = humanoid
	if not hum then
		return
	end
	if enabled then
		hum.AutoRotate = false
		hum.CameraOffset = SHOULDER_OFFSET
	else
		hum.AutoRotate = true
		hum.CameraOffset = Vector3.zero
	end
end

local function onCharacterAdded(char: Model)
	character = char
	humanoid = char:WaitForChild("Humanoid") :: Humanoid
	rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart
	-- Reapply state to the fresh character if shift lock was on across a respawn.
	applyCharacterState()
end

-- ==================== per-frame update ====================

-- Rotate the character to face the camera's flattened look vector, and keep the
-- cursor locked to center so the default camera rotates on mouse movement.
local function onRenderStep()
	if not enabled then
		return
	end

	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

	local hum = humanoid
	local root = rootPart
	local camera = workspace.CurrentCamera
	if not (hum and root and camera) then
		return
	end
	if hum.Health <= 0 then
		return
	end

	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-4 then
		return
	end
	flat = flat.Unit

	local pos = root.Position
	root.CFrame = CFrame.lookAt(pos, pos + flat)
end

local function bindRenderStep()
	if bound then
		return
	end
	RunService:BindToRenderStep(RENDER_BIND_NAME, Enum.RenderPriority.Character.Value + 1, onRenderStep)
	bound = true
end

local function unbindRenderStep()
	if not bound then
		return
	end
	RunService:UnbindFromRenderStep(RENDER_BIND_NAME)
	bound = false
end

-- ==================== public API ====================

-- Enable/disable shift lock. Idempotent; fires the `changed` event on a flip.
function ShiftLockController.setEnabled(value: boolean)
	if enabled == value then
		return
	end
	enabled = value

	if enabled then
		bindRenderStep()
	else
		unbindRenderStep()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end

	applyCharacterState()
	changedEvent:Fire(enabled)
end

function ShiftLockController.toggle()
	ShiftLockController.setEnabled(not enabled)
end

function ShiftLockController.isEnabled(): boolean
	return enabled
end

-- Subscribe to on/off changes; callback receives the new boolean state.
function ShiftLockController.onChanged(callback: (boolean) -> ()): RBXScriptConnection
	return changedEvent.Event:Connect(callback)
end

-- ==================== lifecycle ====================

function ShiftLockController.start()
	-- Disable Roblox's built-in shift-lock switch so the two systems don't fight.
	pcall(function()
		player.DevEnableMouseLock = false
	end)

	-- Wire the current + future characters.
	if player.Character then
		onCharacterAdded(player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(function()
		humanoid = nil
		rootPart = nil
		character = nil
	end)

	-- Keyboard toggle (gameProcessed is true when a TextBox/CoreGui consumes it).
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == TOGGLE_KEY then
			ShiftLockController.toggle()
		end
	end)
end

return ShiftLockController
