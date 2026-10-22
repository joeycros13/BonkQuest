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
--
-- The same pop shows every weapon hit's damage (2026-10-21, the user: the hit
-- number should appear like the BONK, in a comic burst bubble): `BonkPop.hit`
-- copies ReplicatedStorage/Assets/UI/HitPop instead -- `Content` with `PopScale`,
-- red `Rays`, the white ink-outlined `Burst` (art/tools/ui/hit_burst.py) and
-- `Shadow` / `Label` for the number -- with the same motion attributes plus
-- `Format` (the number's text, "%s") and `Spread` (studs it lands off-centre at
-- random, sideways on screen, so quick hits don't stack). `Pull` (both templates)
-- moves a pop that many studs toward the camera: billboards drawn on top are
-- sorted by distance, so a pop level with the enemy's health bar sometimes drew
-- behind it (the user, 2026-10-22); pulled in front, it always draws over it. Every image in `Content` fades out; only
-- the `Rays*` ones turn. A critical hit (Balance.Melee.critChance) pops bigger
-- (`CritScale`), tints the white `Burst` and the `Rays` (`CritBurstColor` /
-- `CritRaysColor`) and shows the hand-built `CritTag` ("CRIT!", hidden otherwise).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BonkPop = {}

local template: BillboardGui? = nil
local hitTemplate: BillboardGui? = nil
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
	local hit = ui and ui:FindFirstChild("HitPop")
	if hit and hit:IsA("BillboardGui") then
		hitTemplate = hit
	else
		warn("[BonkPop] missing ReplicatedStorage/Assets/UI/HitPop")
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

-- Pop a copy of `source` showing `word` at `position` (the template's Height is
-- added). `size` is how big the body is, about 1 for a chicken; it's clamped to
-- SizeMin..SizeMax, and bosses get BossScale on top.
local function play(source: BillboardGui, position: Vector3, size: number, isBoss: boolean?, word: string, crit: boolean?)
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local lifetime = number(source, "Lifetime", 1.05)
	local popSeconds = number(source, "PopSeconds", 0.2)
	local hold = number(source, "Hold", 0.45)
	local fadeSeconds = math.max(lifetime - popSeconds - hold, 0.1)
	local scale = math.clamp(size, number(source, "SizeMin", 0.85), number(source, "SizeMax", 1.6))
		* (if isBoss then number(source, "BossScale", 1.35) else 1)
		* (if crit then number(source, "CritScale", 1) else 1)

	-- An attachment in Terrain holds the spot, so the pop stays put while the
	-- body hides or respawns.
	local spot = Instance.new("Attachment")
	local base = position + Vector3.new(0, number(source, "Height", 1.2), 0)
	local right, toward = Vector3.xAxis, Vector3.zero
	local camera = workspace.CurrentCamera
	if camera then
		local back = camera.CFrame.Position - base
		right = camera.CFrame.RightVector
		toward = if back.Magnitude > 1e-3 then back.Unit else Vector3.zero
	end
	local aside = right * (math.random() * 2 - 1) * number(source, "Spread", 0)
	spot.WorldPosition = base + aside + toward * number(source, "Pull", 0)
	spot.Parent = workspace.Terrain

	local billboard = source:Clone()
	billboard.Adornee = spot
	local content = billboard:FindFirstChild("Content") :: GuiObject?
	local popScale = content and content:FindFirstChild("PopScale") :: UIScale?
	local images: { ImageLabel } = {}
	local rays: { ImageLabel } = {}
	for _, image in if content then content:GetChildren() else {} do
		if image:IsA("ImageLabel") then
			table.insert(images, image)
			if string.sub(image.Name, 1, 4) == "Rays" then
				table.insert(rays, image)
			end
		end
	end
	local labels: { TextLabel } = {}
	local tilt = (math.random() * 2 - 1) * number(source, "TiltMax", 12)
	for _, name in { "Shadow", "Label" } do
		local label = content and content:FindFirstChild(name)
		if label and label:IsA("TextLabel") then
			label.Text = word
			label.Rotation = tilt
			table.insert(labels, label)
		end
	end
	local critTag = content and content:FindFirstChild("CritTag")
	if crit and content then
		for _, look in { { "Burst", "CritBurstColor" }, { "Rays", "CritRaysColor" } } do
			local image = content:FindFirstChild(look[1])
			local color = source:GetAttribute(look[2])
			if image and image:IsA("ImageLabel") and typeof(color) == "Color3" then
				image.ImageColor3 = color
			end
		end
		if critTag and critTag:IsA("TextLabel") then
			critTag.Visible = true
			critTag.Rotation = tilt
			table.insert(labels, critTag)
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
		for _, image in images do
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

-- The defeat's word (one of the template's Words) over the top of the body.
function BonkPop.show(position: Vector3, size: number, isBoss: boolean?)
	if template then
		play(template, position, size, isBoss, pickWord(template))
	end
end

-- A hit's damage in the comic burst bubble (gold and bigger for a crit).
function BonkPop.hit(position: Vector3, size: number, amount: number, isBoss: boolean?, crit: boolean?)
	if hitTemplate then
		local format = hitTemplate:GetAttribute("Format")
		play(hitTemplate, position, size, isBoss, string.format(if type(format) == "string" then format else "%s", tostring(amount)), crit)
	end
end

return BonkPop
