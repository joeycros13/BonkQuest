--!strict
-- BonkPop: the comic "BONK!" that bursts out where an enemy is defeated (user,
-- 2026-10-17, after naming the game Bonk Quest). It slams in from small with
-- an overshoot, tilted a little at random over spinning orange rays, holds a
-- moment, then floats up, shrinks and fades. Purely local; each client draws
-- its own.
--
-- The look is hand-built: ReplicatedStorage/Assets/UI/BonkPop, a BillboardGui
-- holding `Content` (with its `PopScale` UIScale), and in it `Rays` (orange,
-- big), `RaysInner` (yellow, turning the other way), `Shadow` and `Label`. Its attributes set the motion: Words (comma list, one picked
-- per pop), Lifetime, PopSeconds, PopFrom, Hold, Rise, Height, TiltMax,
-- RaysSpin (degrees over the life), ShrinkTo, SizeMin / SizeMax and BossScale.
-- This only copies it and animates it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BonkPop = {}

local template: BillboardGui? = nil
local FontDrop: any = nil

function BonkPop.init(injected: any)
	FontDrop = injected.Util.FontDrop
end

function BonkPop.start()
	local assets = ReplicatedStorage:WaitForChild("Assets", 10)
	local ui = assets and assets:WaitForChild("UI", 10)
	local found = ui and ui:WaitForChild("BonkPop", 10)
	if found and found:IsA("BillboardGui") then
		template = found
	else
		warn("[BonkPop] missing ReplicatedStorage/Assets/UI/BonkPop")
	end
end

local function number(inst: Instance, name: string, fallback: number): number
	local value = inst:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function pickWord(source: Instance): string
	local words = {}
	for word in string.gmatch(tostring(source:GetAttribute("Words") or ""), "[^,]+") do
		table.insert(words, (string.gsub(word, "^%s+", "")))
	end
	return if #words > 0 then words[math.random(#words)] else "BONK!"
end

-- Pop the word at `position` (the top of the body; the template's Height is
-- added). `size` is how big the body is, about 1 for a chicken; it's clamped to
-- SizeMin..SizeMax, and bosses get BossScale on top.
function BonkPop.show(position: Vector3, size: number, isBoss: boolean?)
	local source = template
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not (source and playerGui) then
		return
	end
	local lifetime = number(source, "Lifetime", 1.05)
	local popSeconds = number(source, "PopSeconds", 0.2)
	local hold = number(source, "Hold", 0.45)
	local fadeSeconds = math.max(lifetime - popSeconds - hold, 0.1)
	local scale = math.clamp(size, number(source, "SizeMin", 0.85), number(source, "SizeMax", 1.6))
		* (if isBoss then number(source, "BossScale", 1.35) else 1)

	-- An attachment in Terrain holds the spot, so the pop stays put while the
	-- body hides or respawns.
	local spot = Instance.new("Attachment")
	spot.WorldPosition = position + Vector3.new(0, number(source, "Height", 1.2), 0)
	spot.Parent = workspace.Terrain

	local billboard = source:Clone()
	billboard.Adornee = spot
	local content = billboard:FindFirstChild("Content") :: GuiObject?
	local popScale = content and content:FindFirstChild("PopScale") :: UIScale?
	local rays: { ImageLabel } = {}
	for _, name in { "Rays", "RaysInner" } do
		local image = content and content:FindFirstChild(name)
		if image and image:IsA("ImageLabel") then
			table.insert(rays, image)
		end
	end
	local labels: { TextLabel } = {}
	local tilt = (math.random() * 2 - 1) * number(source, "TiltMax", 12)
	local word = pickWord(source)
	for _, name in { "Shadow", "Label" } do
		local label = content and content:FindFirstChild(name)
		if label and label:IsA("TextLabel") then
			label.Text = word
			label.Rotation = tilt
			table.insert(labels, label)
		end
	end
	billboard.Parent = playerGui
	if FontDrop then
		FontDrop.watch(billboard)
	end

	-- In: slam up from small with an overshoot.
	if popScale then
		popScale.Scale = scale * number(source, "PopFrom", 0.25)
		TweenService:Create(popScale, TweenInfo.new(popSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = scale,
		}):Play()
	end
	local spin = number(source, "RaysSpin", 70)
	for i, image in rays do
		local turn = if i % 2 == 1 then spin else -spin
		image.Rotation = math.random(0, 359)
		TweenService:Create(image, TweenInfo.new(lifetime, Enum.EasingStyle.Linear), {
			Rotation = image.Rotation + turn,
		}):Play()
	end

	-- Out: after the hold, float up, shrink and fade. Started by a task.delay,
	-- not a tween DelayTime: playing a delayed tween on PopScale.Scale cancels
	-- the pop-in at once, so the word sat at its PopFrom size (found 2026-10-17).
	task.delay(popSeconds + hold, function()
		if not billboard.Parent then
			return
		end
		local outInfo = TweenInfo.new(fadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(billboard, outInfo, {
			StudsOffsetWorldSpace = Vector3.new(0, number(source, "Rise", 2.5), 0),
		}):Play()
		if popScale then
			TweenService:Create(popScale, outInfo, { Scale = scale * number(source, "ShrinkTo", 0.75) }):Play()
		end
		for _, image in rays do
			TweenService:Create(image, outInfo, { ImageTransparency = 1 }):Play()
		end
		for _, label in labels do
			TweenService:Create(label, outInfo, { TextTransparency = 1 }):Play()
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				TweenService:Create(stroke, outInfo, { Transparency = 1 }):Play()
			end
		end
	end)
	task.delay(lifetime + 0.05, function()
		billboard:Destroy()
		spot:Destroy()
	end)
end

return BonkPop
