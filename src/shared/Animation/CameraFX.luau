--!strict
-- CameraFX: layered FOV zooms (client only; every call is a no-op on the server).
--
--   CameraFX.zoom("Sprint", 8)      -- FOV offset under an id; layers add up
--   CameraFX.release("Sprint")      -- ease that layer back out
--   CameraFX.reset()                -- ease every layer out
--   CameraFX.settings               -- tuning (see below)
--
-- Applied right after Roblox's camera each frame. Nothing is written while every
-- layer is at rest, so other camera scripts are never disturbed.
--
-- There is no screen shake or camera kick, on purpose: the user had every shake
-- removed on 2026-10-09 ("a huge hassle"), and the unused shake / kick code went
-- on 2026-10-11. Give a heavy hit dust, sparks or a flash instead.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Animation = script.Parent
local Scheduler = require(Animation.Scheduler)
local Spring = require(Animation.Spring)

local CameraFX = {}

CameraFX.settings = {
	zoomSpeed = 9, -- FOV spring stiffness
}

local IS_CLIENT = RunService:IsClient()

local layers: { [string]: { target: number, spring: any } } = {}
local baseFov: number? = nil

function CameraFX.zoom(id: string, fovOffset: number, speed: number?)
	if not IS_CLIENT then
		return
	end
	local layer = layers[id]
	if not layer then
		layer = { target = 0, spring = Spring.new(0, speed or CameraFX.settings.zoomSpeed, 1) }
		layers[id] = layer
	end
	layer.target = fovOffset
	if speed then
		layer.spring.speed = speed
	end
end

function CameraFX.release(id: string)
	local layer = layers[id]
	if layer then
		layer.target = 0
	end
end

function CameraFX.reset()
	for _, layer in layers do
		layer.target = 0
	end
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local total, any = 0, false
	for id, layer in layers do
		layer.spring.target = layer.target
		total += layer.spring:Update(dt)
		if layer.target == 0 and layer.spring:IsResting(0.02) then
			layers[id] = nil
		else
			any = true
		end
	end
	if any then
		baseFov = baseFov or camera.FieldOfView
		camera.FieldOfView = (baseFov :: number) + total
	elseif baseFov then
		camera.FieldOfView = baseFov
		baseFov = nil
	end
end

if IS_CLIENT then
	Scheduler.bind("Camera", "CameraFX", 50, step)
	-- A new camera (respawn) starts clean.
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		baseFov = nil
	end)
end

return CameraFX
