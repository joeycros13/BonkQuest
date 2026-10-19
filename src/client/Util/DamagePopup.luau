--!strict
-- DamagePopup: a number that pops out above something that just took damage,
-- drifts up and fades. Purely local; each client draws its own.
--
-- The look is hand-built: ReplicatedStorage/Assets/UI/DamagePopup, a BillboardGui
-- with a "Label". Its attributes set the colours per kind of hit (EnemyHitColor,
-- PlayerHitColor, HealHitColor, InfoHitColor) and the motion (Lifetime, Rise, Spread). This only copies it
-- and animates it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local DamagePopup = {}

-- Heal / Info: the healing fountain's "+HP" and "ready in" notes (HealZoneController)
export type Kind = "Enemy" | "Player" | "Heal" | "Info"

local template: BillboardGui? = nil

function DamagePopup.init(_injected: any) end

function DamagePopup.start()
	local assets = ReplicatedStorage:WaitForChild("Assets", 10)
	local ui = assets and assets:WaitForChild("UI", 10)
	local found = ui and ui:WaitForChild("DamagePopup", 10)
	if found and found:IsA("BillboardGui") then
		template = found
	else
		warn("[DamagePopup] missing ReplicatedStorage/Assets/UI/DamagePopup")
	end
end

local function number(inst: Instance, name: string, fallback: number): number
	local value = inst:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

-- Show `text` above `adornee`, `height` studs over its centre. `kind` picks the
-- colour authored on the template.
function DamagePopup.show(adornee: BasePart, text: string, kind: Kind, height: number)
	local source = template
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not (source and playerGui) then
		return
	end
	local lifetime = number(source, "Lifetime", 0.9)
	local rise = number(source, "Rise", 2.2)
	local spread = number(source, "Spread", 1.2)

	local billboard = source:Clone()
	local start = Vector3.new((math.random() - 0.5) * spread, height, (math.random() - 0.5) * spread)
	billboard.Adornee = adornee
	billboard.StudsOffsetWorldSpace = start
	local label = billboard:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = text
		local color = source:GetAttribute(kind .. "HitColor")
		if typeof(color) == "Color3" then
			label.TextColor3 = color
		end
		TweenService:Create(label, TweenInfo.new(lifetime * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, lifetime * 0.5), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
	end
	billboard.Parent = playerGui
	TweenService:Create(billboard, TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = start + Vector3.new(0, rise, 0),
	}):Play()
	task.delay(lifetime + 0.05, function()
		billboard:Destroy()
	end)
end

return DamagePopup
