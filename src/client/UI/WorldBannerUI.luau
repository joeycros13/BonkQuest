--!strict
-- WorldBannerUI: shows the world's name across the top of the screen whenever
-- the player walks into a different world, and once when they join (user's
-- request, 2026-10-11).
--
-- Which world the player is in comes from the ground under their feet: a ray down from the
-- root into every world's Workspace.Worlds.<folder>/Ground (as WorldGuardService does on the
-- server). Over no ground (mid-air, a gate's doorway) or over a secret room's floor (a Ground
-- child marked `Secret`, far off its world; a player in one has no world) the last world holds.
-- (Until 2026-10-26 it used each world's X/Z box of its Ground parts, smallest first; World 4
-- is turned 45 degrees, so its box covered World 2's south-west corner and the other way round.)
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
local CHECK_EVERY = 0.4
local RAY_DOWN = 80 -- studs below the root the ground is looked for (WorldGuardService's)

local player = Players.LocalPlayer
local deps: any = nil
local gui: ScreenGui? = nil

type Ground = { folder: Instance, world: number, secret: { Instance } }
local grounds: { Ground } = {}
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include

local function number(name: string, fallback: number): number
	local value = gui and gui:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

-- Every world's Ground folder, with its secret rooms' floors (a Ground child with the Secret
-- attribute: the Corn Wraith cellar, the Fairy's stump room), which belong to no world.
local function measure()
	table.clear(grounds)
	local list = {}
	local root = workspace:FindFirstChild("Worlds")
	for _, id in Worlds.Order do
		local def = Worlds.get(id)
		local folder = def and root and root:FindFirstChild(def.folder)
		local ground = folder and folder:FindFirstChild("Ground")
		if not ground then
			continue
		end
		local secret = {}
		for _, child in ground:GetChildren() do
			if child:GetAttribute("Secret") then
				table.insert(secret, child)
			end
		end
		table.insert(grounds, { folder = ground, world = id, secret = secret })
		table.insert(list, ground)
	end
	params.FilterDescendantsInstances = list
end

-- a ray straight down an exact seam between two ground parts (World 4's corridor slabs meet
-- along the corridor's centre line) can slip between them, so a miss tries once more just aside
local NUDGE = Vector3.new(0.13, 0, 0.07)

local function worldAt(pos: Vector3): number?
	local hit = workspace:Raycast(pos, Vector3.new(0, -RAY_DOWN, 0), params)
		or workspace:Raycast(pos + NUDGE, Vector3.new(0, -RAY_DOWN, 0), params)
	if not hit then
		return nil
	end
	for _, g in grounds do
		if hit.Instance:IsDescendantOf(g.folder) then
			for _, room in g.secret do
				if hit.Instance:IsDescendantOf(room) then
					return nil
				end
			end
			return g.world
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

-- Show a world's banner now (the world unlock cinematic, issue 28).
function WorldBannerUI.show(id: number)
	show(id)
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
