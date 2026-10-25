--!strict
-- HealZoneController: shows a heal from a healing zone (the World 1 fountain,
-- Server.Services.HealZoneService): green sparkles round the player (the "Heal"
-- EffectPreset) and a "+45 HP" popup, or "Fountain ready in 12s" when stepping in
-- while it recharges. The words are the DamagePopup template's HealFormat /
-- CooldownFormat attributes; the colours its HealHitColor / InfoHitColor. A heal also
-- plays the potions' + signs and green screen glow (HurtController.healed, 2026-10-25).
--
-- The Fountain of Life's label (2026-10-25, the user): each zone's hand-built BillboardGui
-- `Label` (Plate with Label / LabelShadow "Fountain of Life"; Status with Bar and Text) shows
-- this player's own cooldown: while their HealZoneReady (server time) is ahead, Text reads the
-- gui's CooldownFormat ("Ready in %ds") and Bar fills back up over the zone's Cooldown in its
-- CooldownFill colour; otherwise Text is ReadyText ("Step in to heal") on a full ReadyFill bar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animation = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Animation"))
local Effects = Animation.Effects
local Util = script.Parent.Parent:WaitForChild("Util")
local DamagePopup = require(Util:WaitForChild("DamagePopup"))
local Format = require(Util:WaitForChild("Format"))

local HealZoneController = {}

local deps: any = nil
local player = Players.LocalPlayer
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local LABEL_EVERY = 0.2

local function words(name: string, fallback: string): string
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local ui = assets and assets:FindFirstChild("UI")
	local template = ui and ui:FindFirstChild("DamagePopup")
	local value = template and template:GetAttribute(name)
	return if type(value) == "string" then value else fallback
end

local function onZone(event: any)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	if event.kind == "healed" then
		Effects.burst(root.Position, "Heal", { count = 28 })
		if deps.Controllers.HurtController then
			deps.Controllers.HurtController.healed()
		end
		DamagePopup.show(root, words("HealFormat", "+%s HP"):format(Format.commas(event.amount)), "Heal", 3)
	elseif event.kind == "cooldown" then
		DamagePopup.show(root, words("CooldownFormat", "Fountain ready in %ds"):format(event.seconds), "Info", 3)
	end
end

function HealZoneController.init(injected: any)
	deps = injected
end

-- Every zone label shows this player's own cooldown.
local function refreshLabels()
	local readyAt = player:GetAttribute("HealZoneReady")
	local left = if type(readyAt) == "number" then readyAt - Workspace:GetServerTimeNow() else 0
	for _, zone in CollectionService:GetTagged("HealZone") do
		local gui = zone:IsDescendantOf(Workspace) and zone:FindFirstChild("Label")
		local status = gui and gui:FindFirstChild("Status")
		local bar = status and status:FindFirstChild("Bar")
		local text = status and status:FindFirstChild("Text")
		if not (gui and bar and bar:IsA("GuiObject") and text and text:IsA("TextLabel")) then
			continue
		end
		local cooldown = zone:GetAttribute("Cooldown")
		local total = if type(cooldown) == "number" and cooldown > 0 then cooldown else 30
		local cooling = left > 0
		local fill = if cooling then math.clamp(1 - left / total, 0, 1) else 1
		local colour = gui:GetAttribute(if cooling then "CooldownFill" else "ReadyFill")
		local words = if cooling
			then (gui:GetAttribute("CooldownFormat") or "Ready in %ds"):format(math.ceil(left))
			else gui:GetAttribute("ReadyText") or "Step in to heal"
		bar.Size = UDim2.fromScale(fill, 1)
		if typeof(colour) == "Color3" then
			bar.BackgroundColor3 = colour
		end
		if text.Text ~= words then
			text.Text = words
		end
	end
end

function HealZoneController.start()
	deps.Remotes.getEvent("HealZone").OnClientEvent:Connect(onZone)
	-- the labels' Luckiest Guy titles centred like every other (FontDrop)
	local FontDrop = deps.Util.FontDrop
	for _, zone in CollectionService:GetTagged("HealZone") do
		local gui = zone:FindFirstChild("Label")
		if gui and FontDrop then
			FontDrop.watch(gui)
		end
	end
	task.spawn(function()
		while true do
			refreshLabels()
			task.wait(LABEL_EVERY)
		end
	end)
end

return HealZoneController
