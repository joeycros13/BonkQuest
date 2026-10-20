--!strict
-- WorldBannerUI: shows the world's name across the top of the screen whenever
-- the player walks into a different world, and once when they join (user's
-- request, 2026-10-11).
--
-- Which world the player is in comes from where they stand: each world's
-- footprint is the X/Z box of its Workspace.Worlds.<folder>/Ground parts
-- (ignoring huge base plates like World 1's 2048-stud Baseplate), checked
-- smallest box first. Outside every box (a gate's doorway) the last world holds.
-- The world is also published on the local player as "CurrentWorld" (client-only;
-- Config/Quests' Quests.tracked picks the tracker's questline by it).
--
-- Hand-built pieces (StarterGui/WorldBanner): Banner (a CanvasGroup, faded in
-- and out with GroupTransparency, popped by its PopScale) holding Subtitle
-- ("World 2"), Title (the world's name from Config/Worlds) and TitleShadow (a
-- dark copy just below Title). Timing attributes on the gui: InSeconds,
-- HoldSeconds, OutSeconds, PopFrom. Labels have UIPaddings for Util.FontDrop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Worlds = require(Config:WaitForChild("Worlds"))

local WorldBannerUI = {}

-- the words above the name (UI text lives in code)
local SUBTITLE = "World %d"
-- ground parts wider than this are base plates, not the world's footprint
local BASEPLATE = 400
local CHECK_EVERY = 0.4

local player = Players.LocalPlayer
local deps: any = nil
local gui: ScreenGui? = nil

type Area = { id: number, minX: number, maxX: number, minZ: number, maxZ: number, size: number }
local areas: { Area } = {}

local function number(name: string, fallback: number): number
	local value = gui and gui:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function measure()
	areas = {}
	local root = workspace:FindFirstChild("Worlds")
	for _, id in Worlds.Order do
		local def = Worlds.get(id)
		local folder = def and root and root:FindFirstChild(def.folder)
		local ground = folder and folder:FindFirstChild("Ground")
		if not ground then
			continue
		end
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		for _, part in ground:GetDescendants() do
			if part:IsA("BasePart") and part.Size.X < BASEPLATE and part.Size.Z < BASEPLATE then
				local p, h = part.Position, part.Size / 2
				minX, maxX = math.min(minX, p.X - h.X), math.max(maxX, p.X + h.X)
				minZ, maxZ = math.min(minZ, p.Z - h.Z), math.max(maxZ, p.Z + h.Z)
			end
		end
		if minX < maxX then
			table.insert(areas, { id = id, minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ, size = (maxX - minX) * (maxZ - minZ) })
		end
	end
	-- the smallest box wins where two overlap
	table.sort(areas, function(a, b)
		return a.size < b.size
	end)
end

local function worldAt(pos: Vector3): number?
	for _, area in areas do
		if pos.X >= area.minX and pos.X <= area.maxX and pos.Z >= area.minZ and pos.Z <= area.maxZ then
			return area.id
		end
	end
	return nil
end

local showing = 0
local function show(id: number)
	local def = Worlds.get(id)
	local banner = gui and gui:FindFirstChild("Banner")
	if not (def and banner and banner:IsA("CanvasGroup")) then
		return
	end
	showing += 1
	local ticket = showing
	for _, name in { "Title", "TitleShadow" } do
		local label = banner:FindFirstChild(name)
		if label and label:IsA("TextLabel") then
			label.Text = def.name
		end
	end
	local sub = banner:FindFirstChild("Subtitle")
	if sub and sub:IsA("TextLabel") then
		sub.Text = SUBTITLE:format(id)
	end
	local pop = banner:FindFirstChild("PopScale")
	if pop and pop:IsA("UIScale") then
		pop.Scale = number("PopFrom", 0.82)
		TweenService:Create(pop, TweenInfo.new(number("InSeconds", 0.35) * 1.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	banner.GroupTransparency = 1
	TweenService:Create(banner, TweenInfo.new(number("InSeconds", 0.35), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 0 }):Play()
	task.delay(number("InSeconds", 0.35) + number("HoldSeconds", 2.4), function()
		if ticket == showing then
			TweenService:Create(banner, TweenInfo.new(number("OutSeconds", 0.6), Enum.EasingStyle.Quad, Enum.EasingDirection.In), { GroupTransparency = 1 }):Play()
		end
	end)
end

function WorldBannerUI.init(injected: any)
	deps = injected
end

function WorldBannerUI.start()
	local found = player:WaitForChild("PlayerGui"):WaitForChild("WorldBanner", 10)
	if not (found and found:IsA("ScreenGui")) then
		warn("[WorldBannerUI] no StarterGui/WorldBanner")
		return
	end
	gui = found
	local banner = found:FindFirstChild("Banner")
	if banner and banner:IsA("CanvasGroup") then
		banner.GroupTransparency = 1
	end
	deps.Util.FontDrop.watch(found)
	measure()

	local current: number? = nil
	task.spawn(function()
		while true do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local id = worldAt(root.Position)
				if id and id ~= current then
					current = id
					player:SetAttribute("CurrentWorld", id)
					-- on join it waits until the loading cover has gone (UI.Preloader)
					local shownId = id
					deps.UI.Preloader.whenDone(function()
						if current == shownId then
							show(shownId)
						end
					end)
				end
			end
			task.wait(CHECK_EVERY)
		end
	end)
end

return WorldBannerUI
