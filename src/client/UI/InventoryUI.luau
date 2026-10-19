--!strict
-- InventoryUI: wires up the hand-built Inventory window and the HUD's touch
-- Attack button and hit flash. Nothing here creates UI from scratch.
--
-- Inventory (StarterGui/Inventory, a PanelWindow panel):
--   * Equipment (left): the Weapon and Armor sockets (Inventory B on the Crafting &
--     Armor canvas, 2026-10-12: armour is one item, so the Helmet / Chestplate /
--     Legs slots went), each showing what's equipped in Inner/Picture on its
--     rarity tile (Inner/RarityTile) or its placeholder SlotIcon, and
--     CharacterView, a WorldModel holding a live copy of the player that
--     PlayerAnimator idles and WeaponController poses with the weapon in hand. The
--     copy is rebuilt when the window opens, when the weapon changes and when the
--     worn armour model on the character changes.
--   * Items (right): shared WeaponTiles (Util.WeaponTile) for every owned weapon
--     (OwnedWeapons, MeleeService), owned armour set (OwnedArmor, ArmorService) and
--     material held (Materials, MaterialService), plus every gathering tool owned
--     (OwnedTools, ToolService; 2026-10-19), sorted by rarity (highest first),
--     then type (weapons, tools, armour, materials), then strength. The selected
--     weapon and the worn set get the EquippedBadge; clicking a weapon puts it in
--     hand, clicking a set wears it (again takes it off: Remotes.EquipArmor). Tool
--     tiles only show what is owned (the user's call): tools come out of their hotbar
--     slot, which always holds the best one of its kind.
--   * Damage / Health / Defense cards under the character.
--   * TopBar: the Filter dropdown (All / Weapons / Tools / Armor / Materials) and the
--     SearchBox (matches names) narrow the grid.
--   * BottomBar: Equip Best equips the highest-damage weapon and the highest-defense
--     set owned. Sell Mode makes clicks pick weapon tiles instead (SellMark + Sell*
--     rim); once one is picked the Sell button appears and sells them
--     (Remotes.SellItems). Armour and materials can't be sold.
-- Looks that change with state come from attributes on the template / buttons.
--
-- HUD (WeaponHud): "Attack" is shown on touch screens only; getting hit flashes
-- "HitFlash" (PeakTransparency / FadeSeconds) and pops the damage over the
-- player's head. The camera doesn't shake (the user's call, 2026-10-09).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Armor = require(Config:WaitForChild("Armor"))
local Materials = require(Config:WaitForChild("Materials"))
local Tools = require(Config:WaitForChild("Tools"))
local Weapons = require(Config:WaitForChild("Weapons"))

local InventoryUI = {}

local deps: any = nil
local DamagePopup: any = nil
local PanelWindow: any = nil
local WeaponController: any = nil
local PlayerAnimator: any = nil
local sellRemote: RemoteEvent? = nil
local armorRemote: RemoteEvent? = nil

local PANEL_ID = "Inventory"
local GUI_TIMEOUT = 15
local player = Players.LocalPlayer

-- What each filter option shows.
local FILTER_SHOWS: { [string]: { weapons: boolean?, tools: boolean?, armor: boolean?, materials: boolean? } } = {
	All = { weapons = true, tools = true, armor = true, materials = true },
	Weapons = { weapons = true },
	Tools = { tools = true },
	Armor = { armor = true },
	Materials = { materials = true },
}
local EMPTY_TEXT: { [string]: string } = {
	All = "Nothing here yet",
	Weapons = "No weapons",
	Tools = "No tools yet: buy them at the Weaponsmith",
	Armor = "No armor yet",
	Materials = "No materials yet",
}

local panel: ScreenGui? = nil
local hud: ScreenGui? = nil

local filter = "All"
local query = ""
local sellMode = false
local selected: { [string]: boolean } = {}

local preview: Model? = nil

-- ==================== helpers ====================

local function attribute(inst: Instance, name: string, fallback: any): any
	local value = inst:GetAttribute(name)
	return if value ~= nil then value else fallback
end

local function find(name: string, className: string): any
	local found = panel and panel:FindFirstChild(name, true)
	return if found and found:IsA(className) then found else nil
end

-- A button's visible text lives in its "Label" child (so the button's gradient
-- doesn't tint it); fall back to the button's own Text.
local function setButtonText(button: Instance?, value: string)
	if not button then
		return
	end
	local label = button:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = value
	elseif button:IsA("TextButton") then
		button.Text = value
	end
end

local WeaponTile = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("WeaponTile"))
local Format = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Format"))

local function ownedWeapons(): { Weapons.WeaponDef }
	local list: { Weapons.WeaponDef } = {}
	local owned = player:GetAttribute("OwnedWeapons")
	if type(owned) == "string" then
		for id in owned:gmatch("[^,]+") do
			local def = Weapons.get(id)
			if def and not def.unarmed then
				table.insert(list, def)
			end
		end
	end
	table.sort(list, function(a, b)
		return if a.damage == b.damage then a.order < b.order else a.damage > b.damage
	end)
	return list
end

-- Owned armour sets, best defense first.
local function ownedArmor(): { Armor.ArmorDef }
	local list: { Armor.ArmorDef } = {}
	local owned = player:GetAttribute("OwnedArmor")
	for id in (if type(owned) == "string" then owned else ""):gmatch("[^,]+") do
		local def = Armor.get(id)
		if def then
			table.insert(list, def)
		end
	end
	table.sort(list, function(a, b)
		return if a.defense == b.defense then a.order < b.order else a.defense > b.defense
	end)
	return list
end

local function wornArmor(): Armor.ArmorDef?
	return Armor.get(player:GetAttribute("EquippedArmor"))
end

-- ==================== items grid ====================

local renderGrid: () -> ()

type GridEntry = { kind: string, def: any, rank: number, typeRank: number, strength: number }

local function selectedCount(): number
	local n = 0
	for _ in selected do
		n += 1
	end
	return n
end

local function renderButtons()
	local sellButton = find("SellButton", "GuiButton")
	if sellButton then
		local count = selectedCount()
		sellButton.Visible = sellMode and count > 0
		setButtonText(sellButton, (attribute(sellButton, "TextFormat", "Sell (%d)") :: string):format(count))
	end
	local modeButton = find("SellMode", "GuiButton")
	if modeButton then
		setButtonText(modeButton, attribute(modeButton, if sellMode then "ActiveText" else "Text", "Sell Mode"))
	end
end

-- The Weapon / Armor sockets: the equipped item's icon, or the placeholder.
local function renderSockets()
	local equipment = find("Equipment", "GuiObject")
	local current = WeaponController.selected()
	local worn = wornArmor()
	for _, pair in { { "Weapon", current :: any }, { "Armor", worn :: any } } do
		local slot, def = pair[1], pair[2]
		local socket = equipment and equipment:FindFirstChild(slot)
		local inner = socket and socket:FindFirstChild("Inner")
		local picture = inner and inner:FindFirstChild("Picture")
		local placeholder = inner and inner:FindFirstChild("SlotIcon")
		local rarityTile = inner and inner:FindFirstChild("RarityTile")
		local icon = def and def.icon
		if rarityTile and rarityTile:IsA("ImageLabel") then
			rarityTile.Visible = def ~= nil
			rarityTile.Image = if def then WeaponTile.skin(def.rarity) else ""
		end
		if picture and picture:IsA("ImageLabel") then
			picture.Visible = icon ~= nil
			picture.Image = icon or ""
		end
		if placeholder and placeholder:IsA("GuiObject") then
			placeholder.Visible = icon == nil
		end
	end
end

-- The Damage / Health / Defense cards under the character, and the item count
-- in the header (its Max / Format attributes set the capacity and wording).
local function renderStats(count: number)
	local current = WeaponController.selected()
	local damage = find("DamageValue", "TextLabel")
	if damage then
		damage.Text = Format.commas(current and current.damage or 0)
	end
	local health = find("HealthValue", "TextLabel")
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if health then
		health.Text = Format.commas(math.floor((humanoid and humanoid.MaxHealth or 100) + 0.5))
	end
	local defense = find("DefenseValue", "TextLabel")
	if defense then
		local value = player:GetAttribute("ArmorDefense")
		defense.Text = math.floor((if type(value) == "number" then value else 0) * 100 + 0.5) .. "%"
	end
	renderSockets()
	local capacity = find("Capacity", "GuiObject")
	local capLabel = capacity and capacity:FindFirstChild("Label")
	if capLabel and capLabel:IsA("TextLabel") then
		capLabel.Text = (attribute(capacity, "Format", "%d / %d") :: string):format(count, attribute(capacity, "Max", 50))
	end
end

local Responsive = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Responsive"))

local function styleTile(tile: GuiObject, equipped: boolean, picked: boolean)
	local badge = tile:FindFirstChild("EquippedBadge")
	if badge and badge:IsA("GuiObject") then
		badge.Visible = equipped and not picked
	end
	local rim = tile:FindFirstChild("Rim") or tile:FindFirstChildOfClass("UIStroke")
	if rim and rim:IsA("UIStroke") then
		local prefix = if picked then "SellRim" elseif equipped then "EquippedRim" else "Rim"
		rim.Color = attribute(tile, prefix .. "Color", rim.Color)
		-- the attribute is in reference-screen pixels; Responsive sizes it for this screen
		-- the tile's Rim is a ScaledSize stroke, so <prefix>Thickness is a fraction
		-- of the tile's side (SellRimThickness 0.0238 ~ 4 px on a 1080-high screen)
		local authored = rim:GetAttribute("BaseThickness")
		Responsive.setStroke(rim, attribute(tile, prefix .. "Thickness", if type(authored) == "number" then authored else rim.Thickness))
	end
	local mark = tile:FindFirstChild("SellMark")
	if mark and mark:IsA("GuiObject") then
		mark.Visible = picked
	end
end

-- The grid's canvas follows its UIGridLayout (2026-10-19, user: the bottom row was cut
-- off): AutomaticCanvasSize ignores aspect-ratio cells, like the Index's rows. The gap
-- above the first row and below the last is the same as the gap at the sides (user,
-- 2026-10-19), measured from the tiles. Inside a ScrollingFrame a UIPadding's scale is a
-- share of the CANVAS, so the top / bottom padding is set as gap / canvas.
local function fitCanvas(grid: ScrollingFrame)
	local layout = grid:FindFirstChildOfClass("UIGridLayout")
	if not layout then
		return
	end
	-- the left gap: from the grid's edge to the leftmost tile
	local left = math.huge
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") and child.Visible then
			left = math.min(left, child.AbsolutePosition.X)
		end
	end
	local gap = if left < math.huge then math.max(0, left - grid.AbsolutePosition.X) else 0
	local height = math.ceil(layout.AbsoluteContentSize.Y + 2 * gap)
	grid.CanvasSize = UDim2.new(0, 0, 0, height)
	local padding = grid:FindFirstChildOfClass("UIPadding")
	if padding and height > 0 then
		padding.PaddingTop = UDim.new(gap / height, 0)
		padding.PaddingBottom = UDim.new(gap / height, 0)
	end
end

renderGrid = function()
	local grid = find("Grid", "ScrollingFrame")
	if not grid then
		return
	end
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	-- The hotbar's weapon counts as equipped, in hand or put away.
	local current = WeaponController.selected()
	local shown = 0
	local owned = ownedWeapons()
	local sets = ownedArmor()
	local shows = FILTER_SHOWS[filter] or FILTER_SHOWS.All
	local needle = query:lower()
	local function matches(name: string): boolean
		return needle == "" or name:lower():find(needle, 1, true) ~= nil
	end
	-- Everything shown, sorted by rarity (highest first), then type (weapons, armour,
	-- materials), then strength (user, 2026-10-12).
	local entries: { GridEntry } = {}
	local function rank(rarity: string?): number
		return table.find(Weapons.Rarities, rarity or "Common") or 1
	end
	if shows.weapons then
		for _, def in owned do
			if matches(def.name) then
				table.insert(entries, { kind = "weapon", def = def, rank = rank(def.rarity), typeRank = 1, strength = def.damage })
			end
		end
	end
	if shows.tools then
		for id in Tools.owned(player) do
			local def = Tools.get(id)
			if def and matches(def.name) then
				table.insert(entries, { kind = "tool", def = def, rank = rank(def.rarity), typeRank = 2, strength = def.tier })
			end
		end
	end
	if shows.armor then
		for _, def in sets do
			if matches(def.name) then
				table.insert(entries, { kind = "armor", def = def, rank = rank(def.rarity), typeRank = 3, strength = def.defense })
			end
		end
	end
	local counts = Materials.counts(player)
	if shows.materials then
		for _, def in Materials.list() do
			if (counts[def.id] or 0) > 0 and matches(def.name) then
				table.insert(entries, { kind = "material", def = def, rank = rank(def.rarity), typeRank = 4, strength = -(def.world * 100 + def.order) })
			end
		end
	end
	table.sort(entries, function(a, b)
		if a.rank ~= b.rank then
			return a.rank > b.rank
		end
		if a.typeRank ~= b.typeRank then
			return a.typeRank < b.typeRank
		end
		if a.strength ~= b.strength then
			return a.strength > b.strength
		end
		return a.def.name < b.def.name
	end)

	local worn = wornArmor()
	for order, entry in entries do
		local def = entry.def
		-- the shared tile (ReplicatedStorage/Assets/UI/WeaponTile, Util.WeaponTile): rarity
		-- skin, drawn icon, name and its pill ("50 Dmg", "10% Def", "×12")
		local tile: GuiObject? = nil
		if entry.kind == "weapon" then
			tile = WeaponTile.new(def)
		elseif entry.kind == "tool" then
			tile = WeaponTile.new(def, { statText = ("Tier %d"):format(def.tier) })
		elseif entry.kind == "armor" then
			tile = WeaponTile.new(def, { statText = math.floor(def.defense * 100 + 0.5) .. "% Def" })
		else
			tile = WeaponTile.new(def, { statText = "×" .. Format.commas(counts[def.id] or 0) })
		end
		if not tile then
			continue
		end
		shown += 1
		tile.LayoutOrder = order
		if entry.kind == "weapon" then
			styleTile(tile, current ~= nil and current.id == def.id, selected[def.id] == true)
			if tile:IsA("GuiButton") then
				tile.Activated:Connect(function()
					if sellMode then
						if def.starter or def.keep then
							return -- the starter weapon and key items (the Rusty Blade) can't be sold
						end
						selected[def.id] = if selected[def.id] then nil else true
						renderGrid()
						renderButtons()
					else
						WeaponController.equip(def.id)
					end
				end)
			end
		elseif entry.kind == "tool" then
			-- shown only (user, 2026-10-19): tools are taken out from their hotbar slot,
			-- which always holds the best one of its kind, so a tile does nothing
			styleTile(tile, false, false)
		elseif entry.kind == "armor" then
			-- the worn set is badged; clicking wears it, or takes it off
			styleTile(tile, worn ~= nil and worn.id == def.id, false)
			if tile:IsA("GuiButton") then
				tile.Activated:Connect(function()
					if not sellMode and armorRemote then
						armorRemote:FireServer(def.id)
					end
				end)
			end
		else
			styleTile(tile, false, false)
		end
		tile.Parent = grid
	end

	-- pad the grid with empty slots: at least MinSlots, and always whole rows
	local slotTemplate = panel and panel:FindFirstChild("Templates") and panel.Templates:FindFirstChild("EmptySlot")
	if slotTemplate and slotTemplate:IsA("GuiObject") then
		local columns = attribute(grid, "Columns", 5)
		local total = math.max(attribute(grid, "MinSlots", 15), math.ceil(shown / columns) * columns)
		for i = shown + 1, total do
			local filler = slotTemplate:Clone()
			filler.LayoutOrder = 10000 + i
			filler.Visible = true
			filler.Parent = grid
		end
	end
	renderStats(#owned + #sets)

	-- the hint line under the cards: its Text_<filter> attribute, else as authored
	local hint = find("Hint", "TextLabel")
	if hint then
		if hint:GetAttribute("DefaultText") == nil then
			hint:SetAttribute("DefaultText", hint.Text)
		end
		hint.Text = attribute(hint, "Text_" .. filter, hint:GetAttribute("DefaultText"))
	end

	local empty = find("Empty", "TextLabel")
	if empty then
		empty.Visible = shown == 0
		empty.Text = if query ~= "" then "No matches" else (EMPTY_TEXT[filter] or "Nothing here yet")
	end
end

local function setSellMode(on: boolean)
	sellMode = on
	table.clear(selected)
	renderGrid()
	renderButtons()
end

-- ==================== character preview ====================

local function clearPreview()
	if preview then
		PlayerAnimator.untrack(preview)
		WeaponController.untrack(preview)
		preview:Destroy()
		preview = nil
	end
end

-- A posed copy of the player, holding the current weapon, in CharacterView.
local function buildPreview()
	clearPreview()
	local view = find("CharacterView", "ViewportFrame")
	local world = view and view:FindFirstChildOfClass("WorldModel")
	local character = player.Character
	if not (view and world and character and character:FindFirstChild("HumanoidRootPart")) then
		return
	end
	local wasArchivable = character.Archivable
	character.Archivable = true
	local copy = character:Clone()
	character.Archivable = wasArchivable
	if not copy then
		return
	end
	for _, d in copy:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ForceField") then
			d:Destroy()
		end
	end
	local humanoid = copy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local root = copy:FindFirstChild("HumanoidRootPart") :: BasePart
	copy.PrimaryPart = root
	root.Anchored = true
	copy:PivotTo(CFrame.new(0, 0, 0))
	copy.Parent = world
	preview = copy

	local camera = view:FindFirstChildOfClass("Camera") or Instance.new("Camera")
	camera.FieldOfView = 38
	-- Front three-quarter view; characters face -Z.
	camera.CFrame = CFrame.lookAt(Vector3.new(-3.6, 0.5, -11.2), Vector3.new(0, -0.2, 0))
	camera.Parent = view
	view.CurrentCamera = camera

	PlayerAnimator.track(copy)
	WeaponController.track(copy)
end

-- ==================== wiring ====================

local function wirePanel(gui: ScreenGui)
	panel = gui

	local grid = find("Grid", "ScrollingFrame")
	local gridLayout = grid and grid:FindFirstChildOfClass("UIGridLayout")
	if grid and gridLayout then
		gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			fitCanvas(grid)
		end)
		grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			fitCanvas(grid)
		end)
	end

	-- Filter dropdown.
	local filterButton = find("Filter", "GuiButton")
	local options = find("Options", "GuiObject")
	if filterButton and options then
		options.Visible = false
		filterButton.Activated:Connect(function()
			options.Visible = not options.Visible
		end)
		for _, option in options:GetChildren() do
			local value = option:GetAttribute("Filter")
			if option:IsA("GuiButton") and type(value) == "string" then
				option.Activated:Connect(function()
					filter = value
					options.Visible = false
					setButtonText(filterButton, value)
					renderGrid()
				end)
			end
		end
	end

	local search = find("SearchBox", "TextBox")
	if search then
		search:GetPropertyChangedSignal("Text"):Connect(function()
			query = search.Text
			renderGrid()
		end)
	end

	local equipBest = find("EquipBest", "GuiButton")
	if equipBest then
		equipBest.Activated:Connect(function()
			local best = ownedWeapons()[1]
			if best then
				WeaponController.equip(best.id)
			end
			local bestSet = ownedArmor()[1]
			local worn = wornArmor()
			if bestSet and armorRemote and not (worn and worn.id == bestSet.id) then
				armorRemote:FireServer(bestSet.id)
			end
		end)
	end
	local modeButton = find("SellMode", "GuiButton")
	if modeButton then
		modeButton.Activated:Connect(function()
			setSellMode(not sellMode)
		end)
	end
	local sellButton = find("SellButton", "GuiButton")
	if sellButton then
		sellButton.Activated:Connect(function()
			local ids = {}
			for id in selected do
				table.insert(ids, id)
			end
			if #ids > 0 and sellRemote then
				sellRemote:FireServer(ids)
			end
			setSellMode(false)
		end)
	end

	-- The preview lives only while the window is open.
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Enabled then
			buildPreview()
			renderGrid()
		else
			clearPreview()
			if options then
				options.Visible = false
			end
			if sellMode then
				setSellMode(false)
			end
		end
	end)

	-- the Worldheart Blade's damage grows with each core infused
	player:GetAttributeChangedSignal("InfusedCores"):Connect(function()
		if gui.Enabled then
			renderGrid()
		end
	end)

	player:GetAttributeChangedSignal("OwnedWeapons"):Connect(function()
		-- Sold items can't stay picked.
		local owned = player:GetAttribute("OwnedWeapons")
		for id in selected do
			if type(owned) ~= "string" or not ("," .. owned .. ","):find("," .. id .. ",", 1, true) then
				selected[id] = nil
			end
		end
		renderGrid()
		renderButtons()
	end)
	for _, name in { "OwnedArmor", "EquippedArmor", "Materials", "OwnedTools" } do
		player:GetAttributeChangedSignal(name):Connect(renderGrid)
	end
	-- the max-health change lands just after the armour's own attributes
	player:GetAttributeChangedSignal("ArmorHealth"):Connect(function()
		task.delay(0.1, renderGrid)
	end)
	-- the preview copies the character, so rebuild it when the worn armour model
	-- (ArmorService puts it on as "Armor") arrives or goes. The model's pieces can
	-- reach the client over several frames, so wait until its "Pieces" count is
	-- all there (up to 2 s) before copying; a newer switch cancels an older wait
	-- (2026-10-12: switching sets sometimes showed a set with pieces missing).
	local armorToken = 0
	local function piecesIn(model: Instance): number
		local n = 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		return n
	end
	local function watchArmor(character: Model)
		local function changed(child: Instance)
			if child.Name ~= "Armor" or not gui.Enabled then
				return
			end
			armorToken += 1
			local token = armorToken
			task.spawn(function()
				local worn = character:FindFirstChild("Armor")
				local want = worn and worn:GetAttribute("Pieces")
				if worn and type(want) == "number" then
					local deadline = os.clock() + 2
					while token == armorToken and worn.Parent == character and piecesIn(worn) < want and os.clock() < deadline do
						task.wait()
					end
				end
				task.wait() -- one more frame for the welds to settle the pieces onto the limbs
				if token == armorToken and gui.Enabled then
					buildPreview()
				end
			end)
		end
		character.ChildAdded:Connect(changed)
		character.ChildRemoved:Connect(changed)
	end
	player.CharacterAdded:Connect(watchArmor)
	if player.Character then
		watchArmor(player.Character)
	end
	WeaponController.onChanged(function()
		renderGrid()
		if gui.Enabled then
			-- Wait a beat for the new weapon model to arrive on the character.
			task.delay(0.15, function()
				if gui.Enabled then
					buildPreview()
				end
			end)
		end
	end)

	renderGrid()
	renderButtons()
end

-- ==================== HUD ====================

local function flashHit()
	local flash = hud and hud:FindFirstChild("HitFlash")
	if not (flash and flash:IsA("GuiObject")) then
		return
	end
	flash.BackgroundTransparency = attribute(flash, "PeakTransparency", 0.45)
	TweenService:Create(flash, TweenInfo.new(attribute(flash, "FadeSeconds", 0.45), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
end

local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	local head = character:WaitForChild("Head", 5)
	local last = humanoid.Health
	humanoid.HealthChanged:Connect(function(health: number)
		local lost = last - health
		last = health
		-- Ignore the slow natural regen ticking the other way, and tiny changes.
		if lost >= 1 then
			flashHit()
			if head and head:IsA("BasePart") then
				DamagePopup.show(head, "-" .. math.floor(lost + 0.5), "Player", 1.5)
			end
		end
	end)
end

local function wireHud(gui: ScreenGui)
	local attack = gui:FindFirstChild("Attack")
	if attack and attack:IsA("GuiButton") then
		-- A tap on the screen is already camera and movement, so touch gets a button.
		attack.Visible = UserInputService.TouchEnabled
		attack.Activated:Connect(function()
			WeaponController.swing()
		end)
	end
end

-- ==================== lifecycle ====================

function InventoryUI.init(injected: any)
	deps = injected
	DamagePopup = deps.Util.DamagePopup
	PanelWindow = deps.UI.PanelWindow
	WeaponController = deps.Controllers.WeaponController
	PlayerAnimator = deps.Controllers.PlayerAnimator
	sellRemote = deps.Remotes.getEvent("SellItems")
	armorRemote = deps.Remotes.getEvent("EquipArmor")
end

function InventoryUI.start()
	-- One health bar, not two.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)

	-- StarterGui's copies can land in PlayerGui after this starts, so wait for
	-- them on a thread of their own rather than holding up the loader.
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		local hudGui = playerGui:WaitForChild("WeaponHud", GUI_TIMEOUT)
		if hudGui and hudGui:IsA("ScreenGui") then
			hud = hudGui
			wireHud(hudGui)
		else
			warn("[InventoryUI] no WeaponHud ScreenGui in StarterGui")
		end
		local found = PanelWindow.getPanel(PANEL_ID, GUI_TIMEOUT)
		if found then
			wirePanel(found)
		else
			warn('[InventoryUI] no ScreenGui in StarterGui has Panel = "Inventory"')
		end
	end)

	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
end

return InventoryUI
