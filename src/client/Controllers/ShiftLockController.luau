--!strict
-- ShiftLockController: our own shift lock, toggled with Ctrl (the user, 2026-10-28).
-- Roblox's own is switched off (StarterPlayer.EnableMouseLockOption = false), so
-- Shift is only sprint.
--
-- While it is on the mouse is locked to the middle of the screen (so moving it
-- turns the camera, like Roblox's), the cursor is the locked-cursor dot, the
-- camera sits over the right shoulder (Humanoid.CameraOffset) and the body always
-- faces where the camera looks (AutoRotate off, the root turned every frame).
--
-- It lets go by itself, without forgetting it was on, whenever the mouse is
-- needed or the camera isn't the player's: a panel open (PanelWindow), talking or
-- a cinematic (InputLocked), a scripted camera (the telescope), or no living body.
--
-- The per-frame work is an Animation.Scheduler Camera system, so it runs right
-- after Roblox's camera has placed itself for the frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Animation = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Animation"))

local ShiftLockController = {}

local TOGGLE_KEYS = { Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl }
local SHOULDER = Vector3.new(1.75, 0, 0) -- Roblox's shift-lock offset
local CURSOR = "rbxasset://textures/MouseLockedCursor.png"

local player = Players.LocalPlayer

local wanted = false -- the player turned it on
local active = false -- it is applied this frame
local PanelWindow: any = nil

local function humanoidOf(): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

-- Whether the lock may hold right now (it is wanted, and nothing needs the mouse).
local function allowed(): boolean
	if not wanted or player:GetAttribute("InputLocked") or player:GetAttribute("Cinematic") then
		return false
	end
	local camera = workspace.CurrentCamera
	if not camera or camera.CameraType ~= Enum.CameraType.Custom then
		return false
	end
	if PanelWindow == nil then
		local ok, module = pcall(function()
			return require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PanelWindow") :: any)
		end)
		PanelWindow = if ok then module else false
	end
	if PanelWindow and PanelWindow.isPanelOpen() then
		return false
	end
	return humanoidOf() ~= nil
end

local function release()
	if not active then
		return
	end
	active = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIcon = ""
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = true
		humanoid.CameraOffset = Vector3.zero
	end
end

local function step()
	if not allowed() then
		release()
		return
	end
	local humanoid = humanoidOf() :: Humanoid
	local root = humanoid.RootPart
	local camera = workspace.CurrentCamera
	if not root then
		release()
		return
	end
	active = true
	-- Roblox's camera puts MouseBehavior back every frame, so it is set again here
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIcon = CURSOR
	humanoid.AutoRotate = false
	humanoid.CameraOffset = SHOULDER
	-- face where the camera looks, turning about the vertical only
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude > 1e-3 then
		local at = root.Position
		root.CFrame = CFrame.lookAt(at, at + flat.Unit)
	end
end

function ShiftLockController.isOn(): boolean
	return wanted
end

function ShiftLockController.init(_deps: any) end

function ShiftLockController.start()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not table.find(TOGGLE_KEYS, input.KeyCode) then
			return
		end
		wanted = not wanted
	end)
	player.CharacterAdded:Connect(function()
		active = false
	end)
	Animation.Scheduler.bind("Camera", "ShiftLock", 50, step)
end

return ShiftLockController
