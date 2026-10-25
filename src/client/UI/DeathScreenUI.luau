--!strict
-- DeathScreenUI: the BONKED! screen while you're dead (2026-10-25, the user's pick: option A
-- on https://claude.ai/artifact/MX1sY6kYn9VhiDJ4d7DDM1).
--
-- Hand-built StarterGui/DeathScreen (DisplayOrder 190, under ScreenFade): `Vignette` (the
-- low-health edge glow image in red, shown at its Strength), `Popup` (PopScale; the BOSS
-- BONK's `Rays`, `RaysInner`, `BurstShadow`, orange `Burst`, `Label` / `Shadow` "BONKED!",
-- and `Pill/Label` from the pill's `Format`, "Respawning in 3"). On a death
-- (DeathController.died): the world turns grey (a copy of Assets/Effects/DeathGrey in the
-- camera, eased to the gui's GreySaturation / GreyBrightness / GreyContrast over
-- GreySeconds), the red edge comes in, and after PopDelay the popup slams in from PopFrom.
-- The pill counts down to the fade, which starts FadeSeconds before Players.RespawnTime
-- (4 s) is up, so the screen is black when the new body appears; the new body
-- (respawned) clears it all and fades back in over InSeconds.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local DeathScreenUI = {}

local GUI_TIMEOUT = 15
local player = Players.LocalPlayer

local deps: any = nil
local gui: ScreenGui? = nil
local token = 0 -- bumped by every death and respawn, so a stale countdown stops
local dead = false
local grey: ColorCorrectionEffect? = nil
local raysTweens: { Tween } = {}

local function number(inst: Instance, name: string, fallback: number): number
	local value = inst:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function setCount(n: number)
	local root = gui
	local pill = root and root:FindFirstChild("Pill", true)
	local label = pill and pill:FindFirstChild("Label")
	if pill and label and label:IsA("TextLabel") then
		local format = pill:GetAttribute("Format")
		label.Text = string.format(if type(format) == "string" then format else "Respawning in %d", n)
	end
end

local function spinRays(popup: Instance, on: boolean)
	for _, tween in raysTweens do
		tween:Cancel()
	end
	table.clear(raysTweens)
	if not on then
		return
	end
	local root = gui :: ScreenGui
	local period = 360 / math.max(number(root, "RaysSpin", 40), 1)
	for i, name in { "Rays", "RaysInner" } do
		local rays = popup:FindFirstChild(name)
		if rays and rays:IsA("GuiObject") then
			rays.Rotation = 0
			local tween = TweenService:Create(rays, TweenInfo.new(period * i, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
				Rotation = if i == 1 then 360 else -360,
			})
			tween:Play()
			table.insert(raysTweens, tween)
		end
	end
end

local function clear()
	local root = gui
	if not root then
		return
	end
	local popup = root:FindFirstChild("Popup")
	if popup and popup:IsA("GuiObject") then
		popup.Visible = false
		spinRays(popup, false)
	end
	local vignette = root:FindFirstChild("Vignette")
	if vignette and vignette:IsA("ImageLabel") then
		vignette.ImageTransparency = 1
	end
	if grey then
		grey:Destroy()
		grey = nil
	end
end

-- The local player died: grey, red edge, BONKED!, countdown, fade to black.
function DeathScreenUI.died()
	local root = gui
	if not root then
		return
	end
	token += 1
	dead = true
	local mine = token
	local diedAt = os.clock()
	local fadeSeconds = number(root, "FadeSeconds", 0.5)
	local fadeAt = diedAt + Players.RespawnTime - fadeSeconds - 0.05

	-- the grey
	if grey then
		grey:Destroy()
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local effects = assets and assets:FindFirstChild("Effects")
	local template = effects and effects:FindFirstChild("DeathGrey")
	if template and template:IsA("ColorCorrectionEffect") and workspace.CurrentCamera then
		local effect = template:Clone()
		effect.Parent = workspace.CurrentCamera
		grey = effect
		TweenService:Create(effect, TweenInfo.new(number(root, "GreySeconds", 0.5), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Saturation = number(root, "GreySaturation", -0.85),
			Brightness = number(root, "GreyBrightness", -0.12),
			Contrast = number(root, "GreyContrast", 0.05),
		}):Play()
	end
	-- the red edge
	local vignette = root:FindFirstChild("Vignette")
	if vignette and vignette:IsA("ImageLabel") then
		TweenService:Create(vignette, TweenInfo.new(number(root, "GreySeconds", 0.5)), {
			ImageTransparency = 1 - number(vignette, "Strength", 0.55),
		}):Play()
	end
	-- BONKED!
	setCount(math.max(1, math.ceil(fadeAt - os.clock())))
	task.delay(number(root, "PopDelay", 0.7), function()
		if token ~= mine then
			return
		end
		local popup = root:FindFirstChild("Popup")
		local scale = popup and popup:FindFirstChild("PopScale")
		if popup and popup:IsA("GuiObject") and scale and scale:IsA("UIScale") then
			scale.Scale = number(root, "PopFrom", 0.2)
			popup.Visible = true
			spinRays(popup, true)
			TweenService:Create(scale, TweenInfo.new(number(root, "PopSeconds", 0.35), Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
		end
	end)
	-- the countdown, then the fade to black just before the respawn
	task.spawn(function()
		while token == mine do
			local left = fadeAt - os.clock()
			if left <= 0 then
				deps.Controllers.FadeController.fade("out", fadeSeconds)
				return
			end
			setCount(math.max(1, math.ceil(left)))
			task.wait(math.min(0.1, left))
		end
	end)
end

-- A new body: clear the screen and fade back in (only after a death on this screen).
function DeathScreenUI.respawned()
	local root = gui
	if not root then
		return
	end
	local wasDead = dead
	dead = false
	token += 1
	clear()
	if wasDead then
		deps.Controllers.FadeController.fade("in", number(root, "InSeconds", 0.5))
	end
end

function DeathScreenUI.init(injected: any)
	deps = injected
end

function DeathScreenUI.start()
	task.spawn(function()
		local found = player:WaitForChild("PlayerGui"):WaitForChild("DeathScreen", GUI_TIMEOUT)
		if not (found and found:IsA("ScreenGui")) then
			warn("[DeathScreenUI] no StarterGui/DeathScreen")
			return
		end
		gui = found
		clear()
		local popup = found:FindFirstChild("Popup")
		if popup then
			deps.Util.FontDrop.watch(popup)
		end
	end)
end

return DeathScreenUI
