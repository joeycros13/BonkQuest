--!strict
-- StatsUI: the Stats panel (2026-10-19, option A "stat sheet" on
-- https://claude.ai/artifact/E7RQQXPYH2ZCKBB6V4YaWk), opened from the HUD's
-- WeaponHud/SideButtons/StatsButton. Every stat shows as its total MULTIPLIER, never a
-- percentage (the user's rule), with a chip for each thing that feeds it:
--   Max Health    the number: (level's HP + armour) x the Health upgrade
--   Luck / Coins / EXP   the shop's passes and boosts (LuckBoost / CoinBoost / ExpBoost,
--                 ShopService) x the upgrade
--   Damage        the Strength potion x the Attack upgrade
--   Defense       how much tougher: 1 / (armour's damage x Stoneskin x the Defense upgrade)
--   Attack Speed, Regen, Gathering   the upgrade (Upgrades.multiplier)
--   Sprint        the Sprint upgrade x a Swiftness potion ("Locked" before Sprint 1)
-- Hand-built StarterGui/StatsPanel (Panel = "Stats"): Window/World/Label, Window/Sheet
-- (a UIGridLayout) filled with Templates/StatRow clones (Tile/Icon, StatName, Parts,
-- Total; UpColor / SameColor attributes), each Parts holding Templates/PartChip clones
-- (TextScale attribute: the chip's text size as a share of its height).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Potions = require(Config:WaitForChild("Potions"))
local Leveling = require(Config:WaitForChild("Leveling"))

local Util = script.Parent.Parent:WaitForChild("Util")
local Format = require(Util:WaitForChild("Format"))

local StatsUI = {}

local PANEL = "Stats"
local GUI_TIMEOUT = 15
local TICK = 0.5
local player = Players.LocalPlayer

-- Every word the panel shows.
local Text = {
	pill = "Level %s · all your multipliers",
	locked = "Locked",
	noBonus = "No bonus yet",
	level = "Level HP %s",
	armour = "Armour +%s",
	upgrade = "Upgrade %s",
	shop = "Passes & boosts %s",
	potion = "%s %s",
	armourDefense = "Armour %s",
	base = "Base 1%% a second",
	names = {
		Health = "Max Health", Luck = "Luck", Attack = "Damage", Coins = "Coins", Defense = "Defense",
		Exp = "EXP", AttackSpeed = "Attack Speed", Regen = "Regen", Sprint = "Sprint", Gathering = "Gathering",
	},
}
local ORDER = { "Health", "Luck", "Attack", "Coins", "Defense", "Exp", "AttackSpeed", "Regen", "Sprint", "Gathering" }

local PanelWindow: any = nil
local FontDrop: any = nil
local deps: any = nil
local window: any = nil
local rows: { [string]: any } = {}

local function number(name: string, fallback: number): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local times = Upgrades.times

local function upgradeX(id: string): number
	local def = Upgrades.get(id)
	return if def then Upgrades.multiplier(def, Upgrades.level(player, id)) else 1
end

-- A potion's name for a chip ("Strength II"), or nil while none runs.
local function potionName(kind: string): string?
	local tier = Potions.running(player, kind)
	local def = tier and Potions.get(kind .. tier)
	return def and def.name or nil
end

-- One stat's total and its source chips.
local function measure(id: string): (string, { string }, boolean)
	local parts = {}
	local up = Upgrades.level(player, id) > 0
	if id == "Health" then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local level = number("Level", 1)
		table.insert(parts, Text.level:format(Format.commas(Leveling.maxHealth(level))))
		local armour = number("ArmorHealth", 0)
		if armour > 0 then
			table.insert(parts, Text.armour:format(Format.commas(armour)))
		end
		if up then
			table.insert(parts, Text.upgrade:format(times(upgradeX(id))))
		end
		local max = if humanoid then humanoid.MaxHealth else Leveling.maxHealth(level)
		return Format.commas(math.floor(max + 0.5)), parts, armour > 0 or up
	elseif id == "Luck" or id == "Coins" or id == "Exp" then
		local shop = number(({ Luck = "LuckBoost", Coins = "CoinBoost", Exp = "ExpBoost" })[id], 1)
		if shop ~= 1 then
			table.insert(parts, Text.shop:format(times(shop)))
		end
		if up then
			table.insert(parts, Text.upgrade:format(times(upgradeX(id))))
		end
		local total = shop * upgradeX(id)
		return times(total), parts, total > 1.0001
	elseif id == "Attack" then
		local strength = Potions.multiplier(player, "Strength")
		local name = potionName("Strength")
		if name then
			table.insert(parts, Text.potion:format(name, times(strength)))
		end
		if up then
			table.insert(parts, Text.upgrade:format(times(upgradeX(id))))
		end
		local total = strength * upgradeX(id)
		return times(total), parts, total > 1.0001
	elseif id == "Defense" then
		local armour = 1 - math.clamp(number("ArmorDefense", 0), 0, 0.9)
		local skin = Potions.multiplier(player, "Stoneskin")
		if armour < 1 then
			table.insert(parts, Text.armourDefense:format(times(1 / armour)))
		end
		local name = potionName("Stoneskin")
		if name then
			table.insert(parts, Text.potion:format(name, times(1 / skin)))
		end
		if up then
			table.insert(parts, Text.upgrade:format(times(upgradeX(id))))
		end
		local total = 1 / (armour * skin * Upgrades.value(player, "Defense"))
		return times(total), parts, total > 1.0001
	elseif id == "Sprint" then
		if not up then
			return Text.locked, { Text.noBonus }, false
		end
		table.insert(parts, Text.upgrade:format(times(upgradeX(id))))
		local swift = Potions.multiplier(player, "Swiftness")
		local name = potionName("Swiftness")
		if name then
			table.insert(parts, Text.potion:format(name, times(swift)))
		end
		return times(upgradeX(id) * swift), parts, true
	elseif id == "Regen" then
		table.insert(parts, Text.base)
		if up then
			table.insert(parts, Text.upgrade:format(times(upgradeX(id))))
		end
		return times(upgradeX(id)), parts, up
	end
	-- Attack Speed, Gathering: the upgrade alone
	if up then
		table.insert(parts, Text.upgrade:format(times(upgradeX(id))))
	end
	return times(upgradeX(id)), parts, up
end

local function build()
	local sheet = window.Sheet
	for index, id in ORDER do
		local row = window.Templates.StatRow:Clone()
		row.Name = id
		row.LayoutOrder = index
		row.Visible = true
		local def = Upgrades.get(id)
		row.Tile.Icon.Image = if def then def.icon else ""
		row.StatName.Text = Text.names[id] or id
		row.Parent = sheet
		rows[id] = row
	end
end

local function fillChips(row: any, parts: { string })
	for _, child in row.Parts:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	if #parts == 0 then
		parts = { Text.noBonus }
	end
	local template = window.Templates.PartChip
	local size = math.max(8, math.floor(row.Parts.AbsoluteSize.Y * (template:GetAttribute("TextScale") or 0.62)))
	for index, words in parts do
		local chip = template:Clone()
		chip.Name = "Chip" .. index
		chip.LayoutOrder = index
		chip.Visible = true
		chip.Text = words
		chip.TextSize = size
		chip.Parent = row.Parts
	end
end

function StatsUI.refresh()
	if not window then
		return
	end
	if window:FindFirstChild("World") then
		window.World.Label.Text = Text.pill:format(Format.commas(number("Level", 1)))
	end
	for id, row in rows do
		local total, parts, raised = measure(id)
		row.Total.Text = total
		row.Total.TextColor3 = row:GetAttribute(if raised then "UpColor" else "SameColor") or row.Total.TextColor3
		fillChips(row, parts)
	end
end

function StatsUI.toggle()
	if PanelWindow.isPanelOpen(PANEL) then
		PanelWindow.hidePanel()
	else
		PanelWindow.showPanel(PANEL)
		StatsUI.refresh()
	end
end

function StatsUI.init(injected: any)
	deps = injected
	PanelWindow = injected.UI.PanelWindow
	FontDrop = injected.Util.FontDrop
end

function StatsUI.start()
	task.spawn(function()
		local found = PanelWindow.getPanel(PANEL, GUI_TIMEOUT)
		if not found then
			warn("[StatsUI] no Stats panel (StarterGui/StatsPanel)")
			return
		end
		window = found:WaitForChild("Window")
		build()
		if FontDrop then
			FontDrop.watch(found)
		end
		local hud = player:WaitForChild("PlayerGui"):WaitForChild("WeaponHud", GUI_TIMEOUT)
		local button = hud and hud:FindFirstChild("StatsButton", true)
		if button and button:IsA("GuiButton") then
			if deps.UI.HotbarUI and deps.UI.HotbarUI.wireHover then
				deps.UI.HotbarUI.wireHover(button)
			end
			button.Activated:Connect(StatsUI.toggle)
		end
		-- live while open: boost and potion timers run out, health changes
		while true do
			task.wait(TICK)
			if found.Enabled then
				StatsUI.refresh()
			end
		end
	end)
end

return StatsUI
