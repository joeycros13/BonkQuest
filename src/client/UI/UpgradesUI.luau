--!strict
-- UpgradesUI: the upgrader's panel, hand-built as StarterGui/UpgradesShop (Panel = "Upgrades",
-- opened by every world's upgrader ring, Station "Upgrades"). The upgrades and every word are in
-- Config/Upgrades.
--
-- Each world's upgrader sells that world's three upgrades (Upgrades.soldIn, 2026-10-28), and
-- since the same day the panel is layout A "three cards" (the user's pick on
-- https://claude.ai/artifact/N4YdTkHbTWRqiNbyELMTDt): the three side by side, each with its
-- own Upgrade button, so nothing has to be selected first. The world is the player's
-- CurrentWorld (the stall stands in it).
--
-- Names the code uses:
--   Window/World      Label: the world this upgrader is in
--   Window/Coins      Amount (deep): the player's coins
--   Window/Cards      a UIGridLayout holding one Templates/UpgradeCard clone per upgrade sold
--                     here (the hand-placed Preview1..3 are Edit-mode previews, removed on start)
--   Templates/UpgradeCard   Face/Stage/Preview (the icon), Face/UpgradeName, Face/LevelPill/Label
--                     ("Lv 2 / 3", this world's set), Face/Pips/Pip1..6 (levels 1-6; the set
--                     sold elsewhere fades to the card's LockedTransparency; PipOn / PipOff /
--                     PipLocked attributes), Face/NowCard and Face/NextCard (Title, Value,
--                     StatIcon(+Shadow)), Face/Note (what's left elsewhere, or what comes
--                     first), Face/Costs/Coins (Content/Amount; MetColor / ShortColor),
--                     Face/Buy (Skin, Label; SkinCraft / SkinLocked, StrokeCraft /
--                     StrokeLocked, TextBuy / TextCoins / TextMaxed attributes)
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
local busy = false
-- one card per upgrade for the session, shown while its world's upgrader is open
local cards: { [string]: any } = {}

local function number(name: string, fallback: number): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else fallback
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

local function buy(id: string)
	if busy then
		return
	end
	busy = true
	local ok, result = pcall(function()
		return Remotes.getFunction("BuyUpgrade"):InvokeServer(id)
	end)
	busy = false
	if not ok then
		warn("[UpgradesUI] BuyUpgrade failed: " .. tostring(result))
	end
	UiSound.play(if ok and result == true then "Purchase" else "Refuse")
	UpgradesUI.refresh()
end

local function cardFor(def: Upgrades.UpgradeDef): any
	local card = cards[def.id]
	if card then
		return card
	end
	card = window.Templates.UpgradeCard:Clone()
	card.Name = def.id
	card.LayoutOrder = def.order
	local face = card.Face
	face.Stage.Preview.Image = def.icon
	face.UpgradeName.Text = def.name
	face.NowCard.Title.Text = Upgrades.Text.now
	face.NextCard.Title.Text = Upgrades.Text.next
	for _, cardName in { "NowCard", "NextCard" } do
		for _, iconName in { "StatIcon", "StatIconShadow" } do
			local icon = face[cardName]:FindFirstChild(iconName)
			if icon then
				icon.Image = def.icon
			end
		end
	end
	face.Buy.Activated:Connect(function()
		buy(def.id)
	end)
	card.Parent = window.Cards
	cards[def.id] = card
	return card
end

-- Pips for levels 1-6: owned (On), still to buy (Off); the set sold in another world fades.
local function paintPips(card: any, def: Upgrades.UpgradeDef, level: number, set: number)
	local template = window.Templates.UpgradeCard
	local fade = template:GetAttribute("LockedTransparency") or 0.55
	for i = 1, Upgrades.LEVELS_PER_WORLD * Upgrades.SETS do
		local pip = card.Face.Pips:FindFirstChild("Pip" .. i) :: Frame?
		if pip then
			local mine = Upgrades.setOf(i) == set
			local key = if i <= level then "PipOn" elseif mine then "PipOff" else "PipLocked"
			pip.BackgroundColor3 = template:GetAttribute(key) or pip.BackgroundColor3
			pip.BackgroundTransparency = if mine then 0 else fade
		end
	end
end

local function fill(card: any, def: Upgrades.UpgradeDef, world: number)
	local face = card.Face
	local level = Upgrades.level(player, def.id)
	local set = Upgrades.setIn(def, world) :: number
	local from = (set - 1) * Upgrades.LEVELS_PER_WORLD
	local inSet = math.clamp(level - from, 0, Upgrades.LEVELS_PER_WORLD)
	face.LevelPill.Label.Text = ("Lv %d / %d"):format(inSet, Upgrades.LEVELS_PER_WORLD)
	paintPips(card, def, level, set)
	face.NowCard.Value.Text = Upgrades.describe(def, level)

	local maxed = level >= Upgrades.maxLevel()
	-- this world's three are bought (more may come in the upgrade's other world)
	local doneHere = not maxed and inSet >= Upgrades.LEVELS_PER_WORLD
	-- the first set, sold in its own world, comes first
	local waiting = level < from
	local later = def.worlds[set + 1]
	-- what the next level gives, even when it's sold in another world (the Note says where)
	face.NextCard.Value.Text = if maxed then Upgrades.Text.maxAll else Upgrades.describe(def, level + 1)
	face.Note.Text = if maxed then ""
		elseif doneHere then (if later then Upgrades.Text.maxWorld:format(world, later) else Upgrades.Text.maxHere:format(world))
		elseif waiting then Upgrades.Text.finishFirst:format(def.name, def.worlds[1])
		elseif later then Upgrades.Text.moreLater:format(later)
		else ""

	local blocked = maxed or doneHere or waiting
	local cost = if blocked then 0 else Upgrades.cost(def, level + 1)
	local coins = face.Costs.Coins
	coins.Visible = not blocked
	local amount = coins:FindFirstChild("Amount", true)
	if amount then
		amount.Text = Format.coins(cost)
		amount.TextColor3 = coins:GetAttribute(if number("Coins", 0) >= cost then "MetColor" else "ShortColor") or amount.TextColor3
	end
	local button = face.Buy
	if maxed or doneHere then
		setButton(button, "Locked", button:GetAttribute("TextMaxed") or "Maxed")
	elseif waiting then
		setButton(button, "Locked", Upgrades.Text.finishShort:format(def.worlds[1]))
	elseif number("Coins", 0) < cost then
		setButton(button, "Locked", button:GetAttribute("TextCoins") or "Need Coins")
	else
		setButton(button, "Craft", button:GetAttribute("TextBuy") or "Upgrade")
	end
end

function UpgradesUI.refresh()
	if not window then
		return
	end
	local world = here()
	local info = Worlds.get(world)
	if info and window:FindFirstChild("World") then
		window.World.Label.Text = Upgrades.Text.worldPill:format(world, (info.name:gsub("^The ", "")))
	end
	local coinsAmount = window:FindFirstChild("Coins") and window.Coins:FindFirstChild("Amount", true)
	if coinsAmount then
		coinsAmount.Text = Format.coins(number("Coins", 0))
	end
	local soldHere: { [string]: boolean } = {}
	for _, def in Upgrades.soldIn(world) do
		soldHere[def.id] = true
		fill(cardFor(def), def, world)
	end
	for id, card in cards do
		card.Visible = soldHere[id] == true
	end
end

local function wire(found: ScreenGui)
	window = found:WaitForChild("Window")
	-- the Edit-mode previews go; real cards are cloned per upgrade
	for _, child in window.Cards:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
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
