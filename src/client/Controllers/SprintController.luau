--!strict
-- SprintController: hold Shift (gamepad: left stick) to sprint, at
-- Balance.Sprint.speedMultiplier x the walk speed, while moving. Sprinting is
-- unlimited: stamina and its HUD bar were removed on 2026-10-11 (user's call).
--
-- The sprint animation itself is PlayerAnimator's (it sees the extra speed);
-- this only adds a small camera FOV push, as an Animation.CameraFX zoom layer
-- ("Sprint") that eases in and out.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared:WaitForChild("Config"):WaitForChild("Balance"))
local CameraFX = require(Shared:WaitForChild("Animation")).CameraFX

local SprintController = {}

local SPRINT_KEYS = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3 }

local FOV_SPEED = 8 -- how fast the FOV push eases in and out
local FOV_PUSH = 8 -- degrees added while sprinting
local MOVING = 0.1 -- MoveDirection magnitude that counts as moving

local player = Players.LocalPlayer

local held = false -- a sprint key is down
local sprinting = false
local baseSpeed: number? = nil

local function canSprint(humanoid: Humanoid): boolean
	return held
		and humanoid.Health > 0
		and humanoid.MoveDirection.Magnitude > MOVING
		-- talking to an NPC (QuestController)
		and not player:GetAttribute("InputLocked")
end

local function step(dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) then
		return
	end

	local want = canSprint(humanoid)

	if want ~= sprinting then
		sprinting = want
		if sprinting then
			baseSpeed = humanoid.WalkSpeed
			humanoid.WalkSpeed = humanoid.WalkSpeed * Balance.Sprint.speedMultiplier
			CameraFX.zoom("Sprint", FOV_PUSH, FOV_SPEED)
		else
			if baseSpeed then
				humanoid.WalkSpeed = baseSpeed
				baseSpeed = nil
			end
			CameraFX.release("Sprint")
		end
	end
end

-- ==================== public ====================

function SprintController.isSprinting(): boolean
	return sprinting
end

-- ==================== lifecycle ====================

function SprintController.init(_injected: any) end

function SprintController.start()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not table.find(SPRINT_KEYS, input.KeyCode) then
			return
		end
		held = true
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if table.find(SPRINT_KEYS, input.KeyCode) then
			held = false
		end
	end)

	local function onCharacter(character: Model)
		sprinting = false
		baseSpeed = nil
		CameraFX.release("Sprint")
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	RunService.PreSimulation:Connect(step)
end

return SprintController
