--!strict
-- QuestMarkerController: the marker over a quest giver's head (issue 20, 2026-10-24; option A
-- "Puffy ! and ?" on https://claude.ai/artifact/8uGcAD5RK5ZGwK3jeGXnw1, the user's pick):
--   * a gold ! while the giver's line has a step on offer for this player (QuestState "Offer"),
--   * a green ? while a step is ready to hand in (QuestState "Ready"),
--   * nothing while a step is under way, once the line is done, or while talking (InputLocked).
-- For the line the quest tracker follows, "ready" waits for the tracker too (QuestShownState,
-- which stays Active until the coin / EXP counters on the HUD catch up), so the ? never shows
-- before the tracker turns green.
--
-- Every model tagged QuestGiver gets a clone of the hand-built ReplicatedStorage/Assets/UI/
-- QuestMarker BillboardGui on its Head (client-only, so each player sees their own progress).
-- The template's attributes: IconAvailable / IconReady (the images), Height (studs above the
-- top of the head), BobHeight / BobSeconds (a gentle bob, looped by TweenService), PopSeconds
-- (the pop in and out of its Content's PopScale).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Quests = require(Shared:WaitForChild("Config"):WaitForChild("Quests"))
local MapLayout = require(Shared:WaitForChild("Config"):WaitForChild("MapLayout"))

local QuestMarkerController = {}

local TEMPLATE = "QuestMarker"
local player = Players.LocalPlayer

type Marker = {
	gui: BillboardGui,
	icon: ImageLabel,
	pop: UIScale,
	line: string,
	shown: string?, -- "Available" / "Ready" / nil
	popTween: Tween?,
}

local template: BillboardGui? = nil
local markers: { [Model]: Marker } = {}

local function number(name: string, fallback: number): number
	local value = template and template:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

-- What this giver's marker should show for the local player.
local function wanted(line: string): string?
	if player:GetAttribute("InputLocked") then
		return nil
	end
	local state = player:GetAttribute(Quests.attr("State", line))
	if state == "Offer" then
		return "Available"
	elseif state == "Ready" then
		-- the tracked line turns ready only once the tracker has caught up
		if player:GetAttribute("QuestShownLine") == line and player:GetAttribute("QuestShownState") ~= "Ready" then
			return nil
		end
		return "Ready"
	end
	return nil
end

local function popTo(marker: Marker, scale: number, done: (() -> ())?)
	if marker.popTween then
		marker.popTween:Cancel()
	end
	local seconds = number("PopSeconds", 0.3)
	local tween = TweenService:Create(marker.pop, TweenInfo.new(seconds, if scale > 0 then Enum.EasingStyle.Back else Enum.EasingStyle.Quad, if scale > 0 then Enum.EasingDirection.Out else Enum.EasingDirection.In), { Scale = scale })
	marker.popTween = tween
	if done then
		tween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed then
				done()
			end
		end)
	end
	tween:Play()
end

local function refresh(giver: Model)
	local marker = markers[giver]
	if not marker then
		return
	end
	local want = wanted(marker.line)
	if want == marker.shown then
		return
	end
	marker.shown = want
	if want then
		local image = template and template:GetAttribute("Icon" .. want)
		if type(image) == "string" then
			marker.icon.Image = image
		end
		if not marker.gui.Enabled then
			marker.pop.Scale = 0
			marker.gui.Enabled = true
		else
			-- swapping ! for ? (or back): a quick dip and pop
			marker.pop.Scale = 0.4
		end
		popTo(marker, 1)
	else
		popTo(marker, 0, function()
			if not marker.shown then
				marker.gui.Enabled = false
			end
		end)
	end
end

local function refreshAll()
	for giver in markers do
		refresh(giver)
	end
end

local function adopt(giver: Instance)
	if not giver:IsA("Model") or markers[giver] or not template then
		return
	end
	local line = giver:GetAttribute("QuestLine")
	if type(line) ~= "string" or not Quests.get(line) then
		return
	end
	-- only givers in the world, never backups parked in ServerStorage
	if not giver:IsDescendantOf(workspace) then
		return
	end
	local head = giver:FindFirstChild("Head") or giver.PrimaryPart
	if not (head and head:IsA("BasePart")) then
		return
	end
	local gui = template:Clone()
	local content = gui:FindFirstChild("Content")
	local icon = content and content:FindFirstChild("Icon")
	local pop = content and content:FindFirstChild("PopScale")
	if not (icon and icon:IsA("ImageLabel") and pop and pop:IsA("UIScale")) then
		gui:Destroy()
		return
	end
	local base = Vector3.new(0, head.Size.Y / 2 + number("Height", 3.45), 0)
	gui.StudsOffset = base
	gui.Adornee = head
	gui.Enabled = false
	gui.Parent = head
	-- the bob runs for good; it costs nothing while the gui is off
	local bob = TweenService:Create(gui, TweenInfo.new(number("BobSeconds", 1.2), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		StudsOffset = base + Vector3.new(0, number("BobHeight", 0.35), 0),
	})
	bob:Play()
	markers[giver] = { gui = gui, icon = icon, pop = pop, line = line, shown = nil }
	giver.AncestryChanged:Connect(function()
		if not giver:IsDescendantOf(workspace) then
			local marker = markers[giver]
			markers[giver] = nil
			bob:Cancel()
			if marker then
				marker.gui:Destroy()
			end
		end
	end)
	refresh(giver)
end

function QuestMarkerController.init(_deps: any)
	local ui = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("UI")
	local t = ui:WaitForChild(TEMPLATE, 10)
	template = if t and t:IsA("BillboardGui") then t else nil
	if not template then
		warn("[QuestMarkerController] no ReplicatedStorage/Assets/UI/" .. TEMPLATE)
	end
end

function QuestMarkerController.start()
	player.AttributeChanged:Connect(function(name)
		if name:match("^QuestState_") or name == "QuestShownState" or name == "QuestShownLine" or name == "InputLocked" then
			refreshAll()
		end
	end)
	for _, giver in CollectionService:GetTagged(MapLayout.Tags.QuestGiver) do
		adopt(giver)
	end
	CollectionService:GetInstanceAddedSignal(MapLayout.Tags.QuestGiver):Connect(adopt)
end

return QuestMarkerController
