--!strict
-- UpgradesUI: the upgrader's panel (2026-10-19, option B "list + detail" on
-- https://claude.ai/artifact/AxKfkGh2E8rdPAGwFEfDR1), hand-built as
-- StarterGui/UpgradesShop (Panel = "Upgrades", opened by every world's upgrader ring,
-- Station "Upgrades"). The upgrades and every word are in Config/Upgrades.
-- Since 2026-10-28 each world's upgrader sells only that world's three upgrades
-- (Upgrades.soldIn): the panel shows those (the player's CurrentWorld), each row's pips
-- are that world's set, the track shows the upgrade's two sets, and a second set waits
-- ("Finish Defense at World 1's upgrader") until the first is bought in its own world.
--
-- Names the code uses:
--   Window/List       a ScrollingFrame of Templates/UpgradeRow clones, one per upgrade,
--                     only this world's shown (Icon, UpgradeName, Pips/Pip1..3 for this
--                     world's three levels; IdleFill / SelectedFill / PipOn / PipOff
--                     attributes). Its canvas follows its layout (a one-column UIGridLayout
--                     since 2026-10-20, so a hovered or selected row grows round its own middle).
--   Window/World      Label: the world this upgrader is in
--   Window/Coins      Amount (deep): the player's coins
--   Window/Detail/Card/Stage/Preview   the selected upgrade's icon
--   .../Info          UpgradeName, LevelPill/Label "Lv 2 / 3", Note ("Level 2 of 3 in
--                     World 1"), NowCard / NextCard (Title, Value, StatIcon(+Shadow) =
--                     the icon), TrackLabel, Track (Templates/WorldTemplate clones, one
--                     per world, only the upgrade's two shown: Pips/Pip1..3, Label "W1";
--                     PipOn / PipOpen / PipLocked /
--                     LockedTransparency attributes), Cost (Amount, deep; MetColor /
--                     ShortColor), Buy (Skin, Label; SkinCraft / SkinLocked,
--                     StrokeCraft / StrokeLocked, TextBuy / TextCoins / TextCapped /
--                     TextMaxed attributes)
-- Buying asks Remotes.BuyUpgrade (UpgradeService checks it all again).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UiSound = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("UiSound"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Worlds = require(Config:WaitForChild("Worlds"))

local Util = script.Parent.Parent:WaitForChild("Util")
local Format = require(Util:WaitForChild("Format"))

local UpgradesUI = {}

local PANEL_ID = "Upgrades"
local GUI_TIMEOUT = 15
local player = Players.LocalPlayer

local PanelWindow: any = nil
local window: any = nil
local selected = "Sprint"
local busy = false
local built = false

local function number(name: string, fallback: number): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function highest(): number
	return math.clamp(number("HighestWorld", 1), 1, Upgrades.MAX_WORLD)
end

-- The world whose upgrader the player stands at (the stall is in their current world).
local function here(): number
	return math.clamp(number("CurrentWorld", 1), 1, Upgrades.MAX_WORLD)
end

local function setButton(button: any, look: string, words: string)
	button.Skin.Image = button:GetAttribute("Skin" .. look) or button.Skin.Image
	button.Label.Text = words
	local stroke = button.Label:FindFirstChildOfClass("UIStroke")
	local color = button:GetAttribute("Stroke" .. look)
	if stroke and typeof(color) == "Color3" then
		stroke.Color = color
	end
	-- a locked button can't be clicked, so it gets no hover or press (Util.ButtonFx)
	button.Active = look ~= "Locked"
end

-- Pips for the three levels a world holds: owned (On), still to buy (Open), out of reach (Locked).
local function paintPips(pips: Instance, from: number, level: number, open: boolean, template: Instance)
	for i = 1, Upgrades.LEVELS_PER_WORLD do
		local pip = pips:FindFirstChild("Pip" .. i) :: Frame?
		if pip then
			local n = from + i
			pip.BackgroundColor3 = template:GetAttribute(if n <= level then "PipOn" elseif open then (template:GetAttribute("PipOpen") and "PipOpen" or "PipOff") else (template:GetAttribute("PipLocked") and "PipLocked" or "PipOff"))
				or pip.BackgroundColor3
		end
	end
end

local function fitList()
	local list = window.List
	local layout = list:FindFirstChildWhichIsA("UIGridStyleLayout")
	local pad = list:FindFirstChildOfClass("UIPadding")
	local extra = if pad then pad.PaddingTop.Offset + pad.PaddingBottom.Offset else 0
	if layout then
		list.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + extra)
	end
end

local function build()
	if built then
		return
	end
	built = true
	local list = window.List
	local template = window.Templates.UpgradeRow
	for index, def in Upgrades.list() do
		local row = template:Clone()
		row.Name = def.id
		row.LayoutOrder = index
		row.Visible = true
		row.Icon.Image = def.icon
		row.UpgradeName.Text = def.name
		row.Activated:Connect(function()
			selected = def.id
			UpgradesUI.refresh()
		end)
		row.Parent = list
	end
	local layout = list:FindFirstChildWhichIsA("UIGridStyleLayout")
	if layout then
		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitList)
	end
	fitList()
	local track = window.Detail.Card.Info.Track
	local worldTemplate = window.Templates.WorldTemplate
	for w = 1, Upgrades.MAX_WORLD do
		local group = worldTemplate:Clone()
		group.Name = "W" .. w
		group.LayoutOrder = w
		group.Visible = true
		group.Label.Text = Upgrades.Text.worldShort:format(w)
		group.Parent = track
	end
end

function UpgradesUI.refresh()
	if not window then
		return
	end
	build()
	-- the stall stands in the player's world: it sells that world's three upgrades
	local world = here()
	local top = highest()
	local info = Worlds.get(world)
	if info and window:FindFirstChild("World") then
		window.World.Label.Text = Upgrades.Text.worldPill:format(world, (info.name:gsub("^The ", "")))
	end
	local coinsAmount = window:FindFirstChild("Coins") and window.Coins:FindFirstChild("Amount", true)
	if coinsAmount then
		coinsAmount.Text = Format.coins(number("Coins", 0))
	end

	local sold = Upgrades.soldIn(world)
	local soldHere: { [string]: boolean } = {}
	for _, d in sold do
		soldHere[d.id] = true
	end
	if not soldHere[selected] and sold[1] then
		selected = sold[1].id
	end

	-- the rows: this world's upgrades, each with this world's set of three levels
	for _, row in window.List:GetChildren() do
		local def = Upgrades.get(row.Name)
		if def and row:IsA("GuiButton") then
			row.Visible = soldHere[def.id] == true
			if row.Visible then
				local level = Upgrades.level(player, def.id)
				local set = Upgrades.setIn(def, world) :: number
				row.BackgroundColor3 = row:GetAttribute(if def.id == selected then "SelectedFill" else "IdleFill") or row.BackgroundColor3
				row:SetAttribute("Selected", def.id == selected) -- stays grown (Util.ButtonFx)
				paintPips(row.Pips, (set - 1) * Upgrades.LEVELS_PER_WORLD, level, true, row)
			end
		end
	end

	local def = Upgrades.get(selected)
	if not (def and soldHere[def.id]) then
		return
	end
	local level = Upgrades.level(player, def.id)
	local set = Upgrades.setIn(def, world) :: number
	local from = (set - 1) * Upgrades.LEVELS_PER_WORLD
	local inSet = math.clamp(level - from, 0, Upgrades.LEVELS_PER_WORLD)
	local card = window.Detail.Card
	local detail = card.Info
	card.Stage.Preview.Image = def.icon
	detail.UpgradeName.Text = def.name
	detail.LevelPill.Label.Text = ("Lv %d / %d"):format(inSet, Upgrades.LEVELS_PER_WORLD)
	detail.Note.Text = Upgrades.Text.levelOf:format(inSet, Upgrades.LEVELS_PER_WORLD, world)
	detail.NowCard.Title.Text = Upgrades.Text.now
	detail.NowCard.Value.Text = Upgrades.describe(def, level)
	detail.NextCard.Title.Text = Upgrades.Text.next
	local maxed = level >= Upgrades.maxLevel()
	-- this world's three are bought (more may come in the upgrade's other world)
	local doneHere = not maxed and inSet >= Upgrades.LEVELS_PER_WORLD
	-- the first set, sold in its own world, comes first
	local waiting = level < from
	local later = def.worlds[set + 1]
	detail.NextCard.Value.Text = if maxed then Upgrades.Text.maxAll
		elseif doneHere then (if later then Upgrades.Text.maxWorld:format(world, later) else Upgrades.Text.maxHere:format(world))
		elseif waiting then Upgrades.Text.finishFirst:format(def.name, def.worlds[1])
		else Upgrades.describe(def, level + 1)
	for _, cardName in { "NowCard", "NextCard" } do
		for _, iconName in { "StatIcon", "StatIconShadow" } do
			local icon = detail[cardName]:FindFirstChild(iconName)
			if icon then
				icon.Image = def.icon
			end
		end
	end
	-- the track: the upgrade's two sets, in the two worlds that sell them
	detail.TrackLabel.Text = Upgrades.Text.allLevels
	for _, group in detail.Track:GetChildren() do
		local w = tonumber((group.Name:match("^W(%d+)$")))
		if w and group:IsA("GuiObject") then
			local index = Upgrades.setIn(def, w)
			group.Visible = index ~= nil
			if index then
				local open = w <= top
				paintPips(group.Pips, (index - 1) * Upgrades.LEVELS_PER_WORLD, level, open, window.Templates.WorldTemplate)
				local fade = if open then 0 else (window.Templates.WorldTemplate:GetAttribute("LockedTransparency") or 0.5)
				group.Label.TextTransparency = fade
			end
		end
	end

	local buy = detail.Buy
	local blocked = maxed or doneHere or waiting
	local cost = if blocked then 0 else Upgrades.cost(def, level + 1)
	local amount = detail.Cost:FindFirstChild("Amount", true)
	detail.Cost.Visible = not blocked
	if amount then
		amount.Text = Format.coins(cost)
		amount.TextColor3 = detail.Cost:GetAttribute(if number("Coins", 0) >= cost then "MetColor" else "ShortColor") or amount.TextColor3
	end
	if maxed or doneHere then
		setButton(buy, "Locked", buy:GetAttribute("TextMaxed") or "Maxed")
	elseif waiting then
		setButton(buy, "Locked", Upgrades.Text.finishShort:format(def.worlds[1]))
	elseif number("Coins", 0) < cost then
		setButton(buy, "Locked", buy:GetAttribute("TextCoins") or "Need Coins")
	else
		setButton(buy, "Craft", buy:GetAttribute("TextBuy") or "Upgrade")
	end
end

local function onBuy()
	if busy then
		return
	end
	busy = true
	local ok, result = pcall(function()
		return Remotes.getFunction("BuyUpgrade"):InvokeServer(selected)
	end)
	busy = false
	if not ok then
		warn("[UpgradesUI] BuyUpgrade failed: " .. tostring(result))
	end
	UiSound.play(if ok and result == true then "Purchase" else "Refuse")
	UpgradesUI.refresh()
end

local function wire(found: ScreenGui)
	window = found:WaitForChild("Window")
	window.Detail.Card.Info.Buy.Activated:Connect(onBuy)
	local names = { "Coins", "HighestWorld", "CurrentWorld" }
	for _, def in Upgrades.list() do
		table.insert(names, Upgrades.attr(def.id))
	end
	for _, name in names do
		player:GetAttributeChangedSignal(name):Connect(UpgradesUI.refresh)
	end
	found:GetPropertyChangedSignal("Enabled"):Connect(UpgradesUI.refresh)
	UpgradesUI.refresh()
end

function UpgradesUI.init(injected: any)
	PanelWindow = injected.UI.PanelWindow
end

function UpgradesUI.start()
	task.spawn(function()
		local found = PanelWindow.getPanel(PANEL_ID, GUI_TIMEOUT)
		if found then
			wire(found)
		else
			warn("[UpgradesUI] no Upgrades panel (StarterGui/UpgradesShop)")
		end
	end)
end

return UpgradesUI
