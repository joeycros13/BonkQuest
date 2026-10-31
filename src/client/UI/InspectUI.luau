--!strict
-- InspectUI: the peek card for another player (2026-10-23, option C on
-- https://claude.ai/artifact/MkJ7Xobg1XbSe6zZ8gJxfp): their headshot, level, name,
-- title and world, health, weekly medal, and the weapon (with their DPS) and armour they
-- wear. Full Profile and Inventory open their full card (ProfileUI) on that tab.
-- InspectUI.show(who) opens it. The press-E "Inspect" prompt on other players'
-- characters is gone (2026-10-28, the user: players fighting the same enemy clicked it
-- by accident); players are inspected from the player list (PlayerListUI's row opens
-- their profile card).
-- Everything comes from their published attributes, as on the profile card.
-- Hand-built StarterGui/InspectPeek (Panel = "Inspect"; gui attribute TitleFormat
-- "%s · World %d"): Window (PopScale, Blocker, Close), Avatar/Photo,
-- Avatar/LevelBadge/Level, PlayerName, TitleLine, Health, Medal, WeaponMini /
-- ArmorMini (TileSlot, ItemName, Stat; ArmorMini's EmptyName), ProfileButton,
-- InventoryButton.
-- Testing alone in Studio: with the Studio-only DevInspectSelf attribute on your own
-- player, InspectUI.show(yourself) works.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Index = require(Config:WaitForChild("Index"))
local Leaderboards = require(Config:WaitForChild("Leaderboards"))

local InspectUI = {}

local PANEL = "Inspect"
local GUI_TIMEOUT = 15
local TICK = 0.5
local player = Players.LocalPlayer

-- Every word the card shows itself.
local Text = {
	world = "World %d",
}

local PanelWindow: any = nil
local FontDrop: any = nil
local deps: any = nil
local gui: ScreenGui? = nil
local window: any = nil
local target: Player? = nil

local function number(who: Player, name: string, fallback: number): number
	local value = who:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

function InspectUI.refresh()
	local who = target
	if not (window and who) then
		return
	end
	if not who.Parent then
		PanelWindow.hidePanel()
		return
	end
	local profile = deps.UI.ProfileUI
	profile.fillIdentity(window, who)
	local title = Index.titleOf(who:GetAttribute("Title"))
	local world = math.max(1, number(who, "CurrentWorld", number(who, "HighestWorld", 1)))
	local format = gui and gui:GetAttribute("TitleFormat")
	window.TitleLine.Text = if title and type(format) == "string"
		then format:format(title.name, world)
		else Text.world:format(world)
	local tier = who:GetAttribute("LeaderMedal")
	local medal = if type(tier) == "string" then Leaderboards.Medals[tier] else nil
	window.Medal.Visible = medal ~= nil
	if medal then
		window.Medal.Image = medal.medal
	end
	profile.fillGear(window.WeaponMini, window.ArmorMini, who, "Inspect")
end

-- Open the peek card for `who`.
local function selfTest(): boolean
	return RunService:IsStudio() and player:GetAttribute("DevInspectSelf") == true
end

function InspectUI.show(who: Player)
	if not window or (who == player and not selfTest()) then
		return
	end
	target = who
	PanelWindow.showPanel(PANEL)
	InspectUI.refresh()
end

function InspectUI.init(injected: any)
	deps = injected
	PanelWindow = injected.UI.PanelWindow
	FontDrop = injected.Util.FontDrop
end

function InspectUI.start()
	task.spawn(function()
		local found = PanelWindow.getPanel(PANEL, GUI_TIMEOUT)
		if not found then
			warn("[InspectUI] no Inspect panel (StarterGui/InspectPeek)")
			return
		end
		gui = found
		window = found:WaitForChild("Window")
		window.ProfileButton.Activated:Connect(function()
			if target then
				deps.UI.ProfileUI.show(target, "Stats")
			end
		end)
		window.InventoryButton.Activated:Connect(function()
			if target then
				deps.UI.ProfileUI.show(target, "Inventory")
			end
		end)
		if FontDrop then
			FontDrop.watch(found)
		end
		local card = deps.UI.PlayerCardUI
		local badge = window:FindFirstChild("Level", true)
		if card and card.watchBadge and badge then
			card.watchBadge(badge)
		end
		while true do
			task.wait(TICK)
			if found.Enabled then
				InspectUI.refresh()
			end
		end
	end)
end

return InspectUI
