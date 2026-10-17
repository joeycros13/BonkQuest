--!strict
-- HotbarUI: wires the hand-built hotbar, StarterGui/WeaponHud/Hotbar, and the
-- Inventory button beside it, StarterGui/WeaponHud/InventoryButton.
--
--   * InventoryButton (left side of the screen): opens and closes the Inventory.
--   * Slot1 (key 1): the one weapon in the hotbar -- the selected weapon (the
--     Dagger at first, then whatever was last picked in the Inventory). It looks
--     like the weapon's Inventory tile: its "Skin" takes the rarity's tile image
--     (from the shared weapon tile, Util.WeaponTile), and
--     "Picture" shows the weapon's drawn icon (def.icon), bigger than the slot so
--     it pokes out. A weapon without an icon falls back to the "Icon" viewport.
--     Clicking it or pressing 1 takes the weapon out or puts it away
--     (WeaponController.toggleHolster).
--   * The slot isn't highlighted while the weapon is out (the user's call).
--   * The side buttons (Inventory, Index, Shop) are bubbly drawn icons with no
--     circle behind them, and a Label (plus a LabelShadow) centred on the
--     drawing's bottom edge; Util.FontDrop centres the Luckiest Guy text.
--   * Hovering a slot or the Inventory button quickly grows it: its visuals sit
--     in a "Content" frame whose "HoverScale" UIScale is tweened, so the row
--     never reflows. The Hotbar's HoverScale / HoverGrowTime / HoverShrinkTime
--     attributes tune it.
-- Roblox's own backpack hotbar is switched off: it reserves the number keys and
-- this one replaces it.
-- Everything visual is authored; this only fills in the weapon previews.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local HotbarUI = {}

local PanelWindow: any = nil
local WeaponController: any = nil
local FontDrop: any = nil

local SIDE_BUTTONS = { "InventoryButton", "IndexButton", "ShopButton", "AdminButton" }

local GUI_TIMEOUT = 15
local INVENTORY = "Inventory"
local player = Players.LocalPlayer

local hotbar: Instance? = nil
-- The weapon the slot's viewport currently shows.
local shownWeapon: string? = nil

local function slot(name: string): GuiButton?
	local found = hotbar and hotbar:FindFirstChild(name)
	return if found and found:IsA("GuiButton") then found else nil
end

local function iconOf(button: Instance?): ViewportFrame?
	local icon = button and button:FindFirstChild("Icon", true)
	return if icon and icon:IsA("ViewportFrame") then icon else nil
end

local WeaponTile = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("WeaponTile"))
-- the 3D view of a weapon (shared with every screen: Util.WeaponTile)
local showWeapon = WeaponTile.showModel

local function refresh()
	local selected = WeaponController.selected()
	local button = slot("Slot1")
	if not (button and selected) or selected.id == shownWeapon then
		return
	end
	shownWeapon = selected.id
	-- the rarity skin comes from the shared weapon tile (Util.WeaponTile), so the
	-- slot always matches the Inventory and the Index
	local skin = button:FindFirstChild("Skin", true)
	if skin and skin:IsA("ImageLabel") then
		skin.Image = WeaponTile.skin(selected.rarity)
	end
	local picture = button:FindFirstChild("Picture", true)
	local icon = iconOf(button)
	local drawn = selected.icon ~= nil and picture ~= nil and picture:IsA("ImageLabel")
	if picture and picture:IsA("ImageLabel") then
		picture.Visible = drawn
		picture.Image = selected.icon or ""
	end
	if icon then
		icon.Visible = not drawn
		if not drawn then
			showWeapon(icon, selected.id)
		end
	end
end

local function tuning(name: string, fallback: number): number
	local value = hotbar and hotbar:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

-- Grow a slot while the pointer is over it, and ease it back after.
local function wireHover(button: GuiButton)
	local content = button:FindFirstChild("Content")
	local scale = content and content:FindFirstChild("HoverScale")
	if not (scale and scale:IsA("UIScale")) then
		return
	end
	local tween: Tween? = nil
	local function to(target: number, time: number)
		if tween then
			tween:Cancel()
		end
		tween = TweenService:Create(scale, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = target })
		;(tween :: Tween):Play()
	end
	button.MouseEnter:Connect(function()
		to(tuning("HoverScale", 1.15), tuning("HoverGrowTime", 0.12))
	end)
	button.MouseLeave:Connect(function()
		to(1, tuning("HoverShrinkTime", 0.1))
	end)
end

-- the side buttons' grow-on-hover, for the modules that own the other buttons
HotbarUI.wireHover = wireHover

function HotbarUI.init(injected: any)
	PanelWindow = injected.UI.PanelWindow
	WeaponController = injected.Controllers.WeaponController
	FontDrop = injected.Util.FontDrop
end

function HotbarUI.start()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	task.spawn(function()
		local hud = player:WaitForChild("PlayerGui"):WaitForChild("WeaponHud", GUI_TIMEOUT)
		local found = hud and hud:FindFirstChild("Hotbar")
		if not found then
			warn("[HotbarUI] no WeaponHud/Hotbar in StarterGui")
			return
		end
		hotbar = found
		-- the side buttons stack in WeaponHud/SideButtons (a UIListLayout), so look deep
		for _, name in SIDE_BUTTONS do
			local button = hud:FindFirstChild(name, true)
			if button then
				FontDrop.watch(button)
			end
		end

		local inventory = hud:FindFirstChild("InventoryButton", true)
		if inventory and inventory:IsA("GuiButton") then
			wireHover(inventory)
			inventory.Activated:Connect(function()
				if PanelWindow.isPanelOpen(INVENTORY) then
					PanelWindow.hidePanel()
				else
					PanelWindow.showPanel(INVENTORY)
				end
			end)
		end
		local weaponSlot = slot("Slot1")
		if weaponSlot then
			wireHover(weaponSlot)
			weaponSlot.Activated:Connect(WeaponController.toggleHolster)
		end

		WeaponController.onChanged(refresh)
		refresh()
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		-- InputLocked: talking to an NPC (QuestController)
		if processed or Players.LocalPlayer:GetAttribute("InputLocked") then
			return
		end
		if input.KeyCode == Enum.KeyCode.One then
			WeaponController.toggleHolster()
		end
	end)
end

return HotbarUI
