--!strict
-- AmbienceController: local lighting for special places (2026-10-12; first used for
-- World 2's secret stump room, whose open top shows a twilight sky).
--
-- A part tagged "AmbienceZone" is a box; while this player's character is inside
-- it, Lighting eases to the zone's attributes and eases back on leaving:
--   ClockTime       number  the time of day to show (18.7 = dusk)
--   Ambient         Color3  Lighting.Ambient (lifts the shadows indoors)
--   OutdoorAmbient  Color3  Lighting.OutdoorAmbient
--   Brightness      number  Lighting.Brightness
-- Any of them may be left out. Only this client's Lighting changes; nobody
-- else's sky moves.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local AmbienceController = {}

local TAG = "AmbienceZone"
local POLL, EASE = 0.25, 1.2

local PROPS = { "ClockTime", "Ambient", "OutdoorAmbient", "Brightness" }

local player = Players.LocalPlayer
local current: BasePart? = nil
local saved: { [string]: any }? = nil
local tween: Tween? = nil

local function inside(zone: BasePart, point: Vector3): boolean
	local p = zone.CFrame:PointToObjectSpace(point)
	local h = zone.Size / 2
	return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
end

local function ease(goal: { [string]: any }, seconds: number)
	if tween then
		tween:Cancel()
	end
	tween = TweenService:Create(Lighting, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), goal)
	;(tween :: Tween):Play()
end

local function goalOf(zone: BasePart): { [string]: any }
	local goal = {}
	for _, prop in PROPS do
		local v = zone:GetAttribute(prop)
		if v ~= nil then
			goal[prop] = v
		end
	end
	return goal
end

local function poll()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local found: BasePart? = nil
	if root and root:IsA("BasePart") then
		for _, zone in CollectionService:GetTagged(TAG) do
			if zone:IsA("BasePart") and zone:IsDescendantOf(workspace) and inside(zone, root.Position) then
				found = zone
				break
			end
		end
	end
	if found == current then
		return
	end
	if found then
		if not current then
			local s = {}
			for _, prop in PROPS do
				s[prop] = (Lighting :: any)[prop]
			end
			saved = s
		end
		-- arriving through a fade: snap, so the sky is already right when the screen clears
		ease(goalOf(found), if current then EASE else 0.05)
	elseif saved then
		ease(saved, 0.05)
		saved = nil
	end
	current = found
end

function AmbienceController.init(_injected: any) end

function AmbienceController.start()
	task.spawn(function()
		while true do
			poll()
			task.wait(POLL)
		end
	end)
end

return AmbienceController
