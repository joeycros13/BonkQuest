--!strict
-- HealZoneController: shows a heal from a healing zone (the World 1 fountain,
-- Server.Services.HealZoneService): green sparkles round the player (the "Heal"
-- EffectPreset) and a "+45 HP" popup, or "Fountain ready in 12s" when stepping in
-- while it recharges. The words are the DamagePopup template's HealFormat /
-- CooldownFormat attributes; the colours its HealHitColor / InfoHitColor.

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
		DamagePopup.show(root, words("HealFormat", "+%s HP"):format(Format.commas(event.amount)), "Heal", 3)
	elseif event.kind == "cooldown" then
		DamagePopup.show(root, words("CooldownFormat", "Fountain ready in %ds"):format(event.seconds), "Info", 3)
	end
end

function HealZoneController.init(injected: any)
	deps = injected
end

function HealZoneController.start()
	deps.Remotes.getEvent("HealZone").OnClientEvent:Connect(onZone)
end

return HealZoneController
