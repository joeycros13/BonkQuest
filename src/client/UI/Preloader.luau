--!strict
-- Preloader: loads everything the game shows before the player sees anything, so no
-- picture, mesh or panel appears piece by piece the first time it is used (2026-10-20,
-- the user: "all assets need to be loaded right away"; opening a panel, taking out a
-- weapon or wearing armour for the first time drew it in front of them).
--
-- On join the hand-built StarterGui/ScreenFade covers the screen: its "Black" frame
-- (authored clear, so Studio's Edit view isn't blacked out) turns opaque the moment the
-- gui reaches the player, and its "Loading" label shows while this runs. Then:
--   1. ContentProvider:PreloadAsync on every image, mesh and sound in the player's UI
--      (closed panels too), ReplicatedStorage/Assets (weapons, tools, effects, sounds,
--      the shared tiles), every "rbxassetid://" in the Shared.Config modules (icons,
--      portraits, world cards: the pictures code puts in at runtime; only image ids:
--      a bare content string is fetched as an image) and the armour models (ArmorService
--      copies them to ReplicatedStorage/Assets/ArmorModels for this). Also every
--      "rbxassetid://" kept in an attribute of the UI and Assets (2026-10-25, issue 22):
--      the pictures code swaps in by state, like the NEW popup's Banner_<Rarity>, the
--      tiles' Skin_<Rarity> or the guide button's IconOn / IconOff, which PreloadAsync on
--      the instance never sees (the first Rare popup drew its name before its banner).
--   2. Once the player's save has loaded ("DataLoaded"), every closed ScreenGui is
--      switched on for a few frames behind the cover with its PopScale at 1, so each
--      panel is laid out, its text measured and its pictures drawn once.
--   3. The cover fades away (ScreenFade attribute "RevealSeconds").
-- Everything has a time limit (ScreenFade "MaxSeconds", default 20) so a slow asset can
-- never leave the screen black. FadeController keeps using the same Black frame for
-- teleports.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Preloader = {}

local player = Players.LocalPlayer
local done = false
local doneEvent = Instance.new("BindableEvent")

local function number(inst: Instance, name: string, fallback: number): number
	local value = inst:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

-- Every asset id string in a Config table (icons, portraits, profiles...).
local function collectIds(value: any, out: { [string]: boolean }, depth: number)
	if depth > 8 then
		return
	end
	if type(value) == "string" then
		if value:find("rbxassetid://", 1, true) == 1 then
			out[value] = true
		end
	elseif type(value) == "table" then
		for k, v in value do
			collectIds(k, out, depth + 1)
			collectIds(v, out, depth + 1)
		end
	end
end

-- Every asset id kept in an attribute under these instances (state-swapped pictures).
local function attributeIds(roots: { any }, out: { [string]: boolean })
	for _, root in roots do
		if typeof(root) ~= "Instance" then
			continue
		end
		for _, inst in root:GetDescendants() do
			for _, value in inst:GetAttributes() do
				if type(value) == "string" and value:find("rbxassetid://", 1, true) == 1 then
					out[value] = true
				end
			end
		end
	end
end

local function configIds(): { string }
	local found: { [string]: boolean } = {}
	local config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
	for _, module in config:GetDescendants() do
		if module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok then
				collectIds(result, found, 0)
			end
		end
	end
	local list = {}
	for id in found do
		table.insert(list, id)
	end
	return list
end

-- Switch every closed ScreenGui on for a few frames, at full size, then back.
local function warmPanels(playerGui: PlayerGui, cover: ScreenGui)
	local restore: { () -> () } = {}
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") and gui ~= cover and not gui.Enabled then
			for _, d in gui:GetDescendants() do
				if d:IsA("UIScale") and d.Name == "PopScale" then
					local scale, was = d, d.Scale
					d.Scale = 1
					table.insert(restore, function()
						scale.Scale = was
					end)
				end
			end
			gui.Enabled = true
			table.insert(restore, function()
				gui.Enabled = false
			end)
		end
	end
	for _ = 1, 4 do
		RunService.RenderStepped:Wait()
	end
	for _, undo in restore do
		undo()
	end
end

-- Runs `f` in its own thread and waits for it, at most `seconds`.
local function within(seconds: number, f: () -> ())
	local finished = false
	task.spawn(function()
		pcall(f)
		finished = true
	end)
	local deadline = os.clock() + seconds
	while not finished and os.clock() < deadline do
		task.wait(0.05)
	end
end

-- True once the join cover has gone.
function Preloader.isDone(): boolean
	return done
end

-- Calls `callback` once the join cover has gone (at once if it already has).
function Preloader.whenDone(callback: () -> ())
	if done then
		task.spawn(callback)
	else
		doneEvent.Event:Once(callback)
	end
end

function Preloader.init(_injected: any) end

function Preloader.start()
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
		local cover = playerGui:WaitForChild("ScreenFade", 15)
		local black = cover and cover:FindFirstChild("Black")
		local label = cover and cover:FindFirstChild("Loading")
		if black and black:IsA("GuiObject") then
			black.BackgroundTransparency = 0
		end
		if label and label:IsA("GuiObject") then
			label.Visible = true
		end
		local started = os.clock()
		local limit = if cover then number(cover, "MaxSeconds", 20) else 20

		-- 1. every asset
		within(limit, function()
			local items: { any } = {}
			for _, gui in playerGui:GetChildren() do
				if gui:IsA("LayerCollector") then
					table.insert(items, gui)
				end
			end
			local assets = ReplicatedStorage:FindFirstChild("Assets")
			if assets then
				table.insert(items, assets)
			end
			for _, id in configIds() do
				table.insert(items, id)
			end
			local swapped: { [string]: boolean } = {}
			attributeIds(table.clone(items), swapped)
			for id in swapped do
				table.insert(items, id)
			end
			ContentProvider:PreloadAsync(items)
			-- PreloadAsync can return with a few still downloading: wait for the queue
			while ContentProvider.RequestQueueSize > 0 do
				task.wait(0.1)
			end
		end)

		-- 2. the player's own things in place, then every panel drawn once
		within(math.max(1, limit - (os.clock() - started)), function()
			if player:GetAttribute("DataLoaded") ~= true then
				player:GetAttributeChangedSignal("DataLoaded"):Wait()
			end
			task.wait(0.3) -- the panels' own renders (end of frame) catch up
		end)
		if cover and cover:IsA("ScreenGui") then
			warmPanels(playerGui, cover)
		end

		-- 3. reveal
		if label and label:IsA("GuiObject") then
			label.Visible = false
		end
		if black and black:IsA("GuiObject") then
			TweenService:Create(black, TweenInfo.new(if cover then number(cover, "RevealSeconds", 0.5) else 0.5), { BackgroundTransparency = 1 }):Play()
		end
		done = true
		doneEvent:Fire()
	end)
end

return Preloader
