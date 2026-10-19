--!strict
-- BoostHudUI: the running potions (timed boosts: Luck, Coins, EXP) stacked in
-- the bottom-right corner, each with its countdown (user's request, 2026-10-11).
--
-- Order: the first one bought sits at the bottom, the next above it, and so
-- on; when one runs out the ones above slide down (a bottom-aligned
-- UIListLayout does the moving). The order comes from the server's
-- "BoostOrder_<id>" stamps (ShopService), the time from "Boost_<id>" (seconds
-- left, ticked every second), so it survives rejoining.
--
-- Hand-built StarterGui/BoostHud: Stack (bottom-right, UIListLayout) and
-- Templates/BoostChip (Icon, Texts/BoostName, Texts/Timer). The chip's
-- attributes: Color_<id> (the pill), Icon_<id> (the potion art), LowSeconds /
-- LowColor (the timer turns red near the end). Wording: Config/Shop.BoostHud,
-- names: Config/Shop.Boosts. On touch screens the stack sits above the Attack
-- button.
--
-- Brewed potions (Config/Potions, 2026-10-19) share the stack: a chip named
-- "Potion_<kind>" per running potion, from PotionService's "Potion_<kind>" (seconds
-- left), "PotionTier_<kind>" and "PotionOrder_<kind>" (a stamp from the same counter
-- as the boosts', so the two kinds stack in the order they started). Its colour and
-- picture are the potion's own (`color`, `icon`), its name "Strength II".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Potions = require(Config:WaitForChild("Potions"))
local Shop = require(Config:WaitForChild("Shop"))

local BoostHudUI = {}

local player = Players.LocalPlayer
local deps: any = nil
local gui: ScreenGui? = nil

local function attr(inst: Instance, name: string, fallback: any): any
	local v = inst:GetAttribute(name)
	return if v ~= nil then v else fallback
end

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 3600 then
		return Shop.BoostHud.hourFormat:format(s // 3600, (s % 3600) // 60, s % 60)
	end
	return Shop.BoostHud.timeFormat:format(s // 60, s % 60)
end

-- One chip: made from the template if it isn't there yet, then placed and timed.
local function showChip(stack: Instance, template: Instance, name: string, look: { color: Color3?, icon: string?, title: string }, left: number, order: any)
	local chip = stack:FindFirstChild(name) :: any
	if not chip then
		chip = template:Clone()
		chip.Name = name
		chip.Visible = true
		if look.color then
			chip.BackgroundColor3 = look.color
		end
		local icon = chip:FindFirstChild("Icon")
		if icon and icon:IsA("ImageLabel") and look.icon then
			icon.Image = look.icon
		end
		local label = chip:FindFirstChild("BoostName", true)
		if label and label:IsA("TextLabel") then
			label.Text = look.title
		end
		chip.Parent = stack
	end
	-- bottom-aligned list, ascending top to bottom: the oldest (smallest
	-- stamp) gets the largest LayoutOrder, so it sits at the bottom
	chip.LayoutOrder = -(if type(order) == "number" then order else 0)
	local timer = chip:FindFirstChild("Timer", true)
	if timer and timer:IsA("TextLabel") then
		timer.Text = clock(left)
		local low = left <= attr(template, "LowSeconds", 60)
		timer.TextColor3 = if low then attr(template, "LowColor", Color3.new(1, 0.35, 0.35)) else Color3.new(1, 1, 1)
	end
end

local function renderPotions(stack: Instance, template: Instance)
	for _, kind in Potions.Kinds do
		local tier, left = Potions.running(player, kind)
		local def = tier and Potions.get(kind .. tier)
		local name = "Potion_" .. kind
		if not def then
			local chip = stack:FindFirstChild(name)
			if chip then
				chip:Destroy()
			end
			continue
		end
		-- a stronger tier replacing a weaker one gets a fresh chip (its name and picture)
		local chip = stack:FindFirstChild(name)
		if chip and chip:GetAttribute("Tier") ~= tier then
			chip:Destroy()
		end
		showChip(stack, template, name, { color = def.color, icon = def.icon, title = kind .. " " .. Potions.Numerals[def.tier] }, left, player:GetAttribute("PotionOrder_" .. kind))
		local shown = stack:FindFirstChild(name)
		if shown then
			shown:SetAttribute("Tier", tier)
		end
	end
end

local function render()
	local stack = gui and gui:FindFirstChild("Stack")
	local templates = gui and gui:FindFirstChild("Templates")
	local template = templates and templates:FindFirstChild("BoostChip")
	if not (stack and template) then
		return
	end
	renderPotions(stack, template)
	for id, boost in Shop.Boosts do
		local left = player:GetAttribute("Boost_" .. id)
		local order = player:GetAttribute("BoostOrder_" .. id)
		local running = type(left) == "number" and left > 0
		if not running then
			local chip = stack:FindFirstChild(id)
			if chip then
				chip:Destroy()
			end
			continue
		end
		showChip(stack, template, id, { color = attr(template, "Color_" .. id, nil), icon = attr(template, "Icon_" .. id, nil), title = boost.name }, left :: number, order)
	end
end

-- On touch screens the Attack button owns the corner: sit just above it.
local function place()
	local stack = gui and gui:FindFirstChild("Stack")
	if not (stack and stack:IsA("GuiObject")) then
		return
	end
	local base = stack:GetAttribute("BasePositionY")
	if type(base) ~= "number" then
		base = stack.Position.Y.Scale
		stack:SetAttribute("BasePositionY", base)
	end
	local hud = player.PlayerGui:FindFirstChild("WeaponHud")
	local attack = hud and hud:FindFirstChild("Attack")
	local y = base :: number
	if attack and attack:IsA("GuiObject") and attack.Visible and gui and gui.AbsoluteSize.Y > 0 then
		-- the top of the Attack button, as a share of the screen, less a small gap
		y = math.min(y, (attack.AbsolutePosition.Y - gui.AbsolutePosition.Y) / gui.AbsoluteSize.Y - 0.015)
	end
	stack.Position = UDim2.new(stack.Position.X.Scale, 0, y, 0)
end

function BoostHudUI.init(injected: any)
	deps = injected
end

function BoostHudUI.start()
	task.spawn(function()
		local found = player:WaitForChild("PlayerGui"):WaitForChild("BoostHud", 15)
		if not (found and found:IsA("ScreenGui")) then
			warn("[BoostHudUI] no StarterGui/BoostHud")
			return
		end
		gui = found
		deps.Util.FontDrop.watch(found)
		for id in Shop.Boosts do
			player:GetAttributeChangedSignal("Boost_" .. id):Connect(render)
			player:GetAttributeChangedSignal("BoostOrder_" .. id):Connect(render)
		end
		for _, kind in Potions.Kinds do
			for _, prefix in { "Potion_", "PotionTier_", "PotionOrder_" } do
				player:GetAttributeChangedSignal(prefix .. kind):Connect(render)
			end
		end
		render()
		place()
		found:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
		local hud = player.PlayerGui:WaitForChild("WeaponHud", 15)
		local attack = hud and hud:FindFirstChild("Attack")
		if attack then
			attack:GetPropertyChangedSignal("Visible"):Connect(place)
		end
		place()
	end)
end

return BoostHudUI
