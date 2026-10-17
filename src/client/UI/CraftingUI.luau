--!strict
-- CraftingUI: wires the hand-built Crafting stall, StarterGui/CraftingShop (the
-- "Recipe book" layout, option B on the Crafting & Armor canvas, 2026-10-12).
-- Nothing here builds UI: the set buttons and recipe rows are clones of the
-- hand-built Window/Templates/SetTemplate and IngredientTemplate (authored
-- hidden, shown on the clone).
--
--   Window/Sets      one SetTemplate per armour set of the world the player
--                    stands in (their "CurrentWorld"): Tile (rarity skin from
--                    Util.WeaponTile), Icon, Lock ("Lv N" while their level is
--                    short), Check (owned), SetName. The selected set is full
--                    size with a Pointer toward the details; the others shrink
--                    (Tile/SelectScale to IdleScale) and dim (IdleColor /
--                    IdleTextColor), the user's call after a white box looked off
--   Window/Detail    the selected set: Stage/Preview, Info/SetName, Rarity
--                    (colour from its Color_<Rarity> attributes), Blurb,
--                    DefenseCard / HealthCard (Value), Ingredients (one row per
--                    recipe material: Slot/Icon, ItemName, Count "have / need",
--                    Bar/Fill), Level, Cost, Craft
--   Craft            Craft when everything is met; otherwise locked with why
--                    (level, then materials, then coins); an owned set shows
--                    Wear, or Wearing while it's worn. Looks and words come from
--                    the button's Skin* / Stroke* / Text* attributes.
-- Crafting asks Remotes.CraftArmor (StallService checks it all again and
-- puts the set on); Wear fires Remotes.EquipArmor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Armor = require(Config:WaitForChild("Armor"))
local Materials = require(Config:WaitForChild("Materials"))
local Worlds = require(Config:WaitForChild("Worlds"))

local Util = script.Parent.Parent:WaitForChild("Util")
local Format = require(Util:WaitForChild("Format"))
local WeaponTile = require(Util:WaitForChild("WeaponTile"))

local CraftingUI = {}

local PANEL_ID = "Crafting"
local GUI_TIMEOUT = 15
local player = Players.LocalPlayer

local PanelWindow: any = nil
local window: any = nil
local selected: string? = nil
local shownWorld: number? = nil
local busy = false

local function number(name: string, fallback: number): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function world(): number
	return number("CurrentWorld", 1)
end

local function owns(id: string): boolean
	local owned = player:GetAttribute("OwnedArmor")
	return type(owned) == "string" and ("," .. owned .. ","):find("," .. id .. ",", 1, true) ~= nil
end

local function setsHere(): { Armor.ArmorDef }
	local out = {}
	for _, def in Armor.list() do
		if def.world == world() then
			table.insert(out, def)
		end
	end
	return out
end

-- Why the set can't be crafted yet ("level" / "materials" / "coins"), or nil.
local function blocker(def: Armor.ArmorDef, counts: { [string]: number }): string?
	if number("Level", 1) < def.level then
		return "level"
	end
	for _, item in def.recipe do
		if (counts[item.id] or 0) < item.count then
			return "materials"
		end
	end
	if number("Coins", 0) < def.coins then
		return "coins"
	end
	return nil
end

local function setButton(button: any, look: string, words: string)
	button.Skin.Image = button:GetAttribute("Skin" .. look) or button.Skin.Image
	button.Label.Text = words
	local stroke = button.Label:FindFirstChildOfClass("UIStroke")
	local color = button:GetAttribute("Stroke" .. look)
	if stroke and typeof(color) == "Color3" then
		stroke.Color = color
	end
end

local function rebuildSets()
	local list = window.Sets
	for _, child in list:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	for index, def in setsHere() do
		local button = window.Templates.SetTemplate:Clone()
		button.Name = def.id
		button.LayoutOrder = index
		button.Visible = true
		button.Tile.Image = WeaponTile.skin(def.rarity)
		button.Tile.Icon.Image = def.icon or ""
		button.SetName.Text = def.name
		button.Activated:Connect(function()
			selected = def.id
			CraftingUI.refresh()
		end)
		button.Parent = list
	end
end

local function fillDetail(def: Armor.ArmorDef, counts: { [string]: number })
	local info = window.Detail.Card.Info
	window.Detail.Card.Stage.Preview.Image = def.icon or ""
	info.SetName.Text = def.name
	info.Blurb.Text = def.blurb
	local color = info.Rarity:GetAttribute("Color_" .. def.rarity)
	if typeof(color) == "Color3" then
		info.Rarity.BackgroundColor3 = color
	end
	info.Rarity.Label.Text = def.rarity
	info.DefenseCard.Value.Text = math.floor(def.defense * 100 + 0.5) .. "%"
	info.HealthCard.Value.Text = "+" .. Format.commas(def.health)

	local rows = info.Ingredients
	for _, child in rows:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	-- an owned set's recipe reads as done: just what it took
	local crafted = owns(def.id)
	for index, item in def.recipe do
		local mat = Materials.get(item.id)
		local row = window.Templates.IngredientTemplate:Clone()
		row.Name = item.id
		row.LayoutOrder = index
		row.Visible = true
		local have = if crafted then item.count else counts[item.id] or 0
		local done = have >= item.count
		-- the material on its rarity's tile, like the Inventory
		row.Slot.Image = WeaponTile.skin(mat and mat.rarity)
		row.Slot.Icon.Image = mat and mat.icon or ""
		row.ItemName.Text = mat and mat.name or item.id
		row.Count.Text = if crafted
			then "×" .. Format.commas(item.count)
			else Format.commas(have) .. " / " .. Format.commas(item.count)
		row.Count.TextColor3 = row:GetAttribute(if done then "DoneColor" else "ShortColor")
		row.Bar.Fill.Size = UDim2.fromScale(math.clamp(have / item.count, 0, 1), 1)
		row.Bar.Fill.Visible = have > 0
		row.Bar.Fill.Gradient.Color = ColorSequence.new(
			row:GetAttribute(if done then "DoneTop" else "ShortTop"),
			row:GetAttribute(if done then "DoneBottom" else "ShortBottom")
		)
		row.Parent = rows
	end

	local levelMet = crafted or number("Level", 1) >= def.level
	info.Level.Label.Text = "Level " .. def.level
	info.Level.BackgroundColor3 = info.Level:GetAttribute(if levelMet then "MetColor" else "ShortColor")
	local costAmount = info.Cost:FindFirstChild("Amount", true)
	costAmount.Text = Format.commas(def.coins)
	costAmount.TextColor3 = info.Cost:GetAttribute(if crafted or number("Coins", 0) >= def.coins then "MetColor" else "ShortColor")

	local craft = info.Craft
	if owns(def.id) then
		local worn = player:GetAttribute("EquippedArmor") == def.id
		setButton(craft, if worn then "Owned" else "Craft", craft:GetAttribute(if worn then "TextWearing" else "TextWear"))
	else
		local why = blocker(def, counts)
		if why == "level" then
			setButton(craft, "Locked", (craft:GetAttribute("TextLevel") or "Need Level %d"):format(def.level))
		elseif why == "materials" then
			setButton(craft, "Locked", craft:GetAttribute("TextMaterials"))
		elseif why == "coins" then
			setButton(craft, "Locked", craft:GetAttribute("TextCoins"))
		else
			setButton(craft, "Craft", craft:GetAttribute("TextCraft"))
		end
	end
end

function CraftingUI.refresh()
	if not window then
		return
	end
	if shownWorld ~= world() then
		shownWorld = world()
		selected = nil
		rebuildSets()
	end
	local def = Armor.get(selected)
	if not def or def.world ~= world() then
		-- start on the first set they don't own yet
		def = nil
		for _, candidate in setsHere() do
			if not owns(candidate.id) then
				def = candidate
				break
			end
		end
		def = def or setsHere()[1]
		selected = def and def.id
	end

	local info = Worlds.get(world())
	if info and window:FindFirstChild("World") then
		window.World.Label.Text = ("World %d · %s"):format(info.id, (info.name:gsub("^The ", "")))
	end
	local coinsPill = window:FindFirstChild("Coins")
	local coinsAmount = coinsPill and coinsPill:FindFirstChild("Amount", true)
	if coinsAmount then
		coinsAmount.Text = Format.commas(number("Coins", 0))
	end

	local counts = Materials.counts(player)
	for _, button in window.Sets:GetChildren() do
		local set = Armor.get(button.Name)
		if set and button:IsA("GuiButton") then
			local tile = button:FindFirstChild("Tile") :: any
			local on = set.id == selected
			button.Pointer.Visible = on
			tile.SelectScale.Scale = if on then 1 else button:GetAttribute("IdleScale") or 0.86
			local dim = button:GetAttribute("IdleColor") or Color3.new(0.8, 0.8, 0.8)
			tile.ImageColor3 = if on then Color3.new(1, 1, 1) else dim
			tile.Icon.ImageColor3 = if on then Color3.new(1, 1, 1) else dim
			button.SetName.TextColor3 = button:GetAttribute(if on then "SelectedTextColor" else "IdleTextColor") or button.SetName.TextColor3
			tile.Check.Visible = owns(set.id)
			tile.Lock.Visible = not owns(set.id) and number("Level", 1) < set.level
			tile.Lock.Label.Text = "Lv " .. set.level
		end
	end
	window.Detail.Visible = def ~= nil
	if def then
		fillDetail(def, counts)
	end
end

local function onCraft()
	local def = Armor.get(selected)
	if busy or not def then
		return
	end
	if owns(def.id) then
		if player:GetAttribute("EquippedArmor") ~= def.id then
			Remotes.getEvent("EquipArmor"):FireServer(def.id)
		end
		return
	end
	if blocker(def, Materials.counts(player)) then
		return
	end
	busy = true
	local ok, result = pcall(function()
		return Remotes.getFunction("CraftArmor"):InvokeServer(def.id)
	end)
	busy = false
	if not ok then
		warn("[CraftingUI] CraftArmor failed: " .. tostring(result))
	end
	CraftingUI.refresh()
end

local function wire(gui: ScreenGui)
	window = gui:WaitForChild("Window")
	window.Detail.Card.Info.Craft.Activated:Connect(onCraft)
	for _, name in { "Coins", "Level", "Materials", "OwnedArmor", "EquippedArmor", "CurrentWorld" } do
		player:GetAttributeChangedSignal(name):Connect(CraftingUI.refresh)
	end
	gui:GetPropertyChangedSignal("Enabled"):Connect(CraftingUI.refresh)
	CraftingUI.refresh()
end

function CraftingUI.init(injected: any)
	PanelWindow = injected.UI.PanelWindow
end

function CraftingUI.start()
	task.spawn(function()
		local gui = PanelWindow.getPanel(PANEL_ID, GUI_TIMEOUT)
		if gui then
			wire(gui)
		else
			warn("[CraftingUI] no Crafting panel (StarterGui/CraftingShop)")
		end
	end)
end

return CraftingUI
