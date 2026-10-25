--!strict
-- HurtController: how a player feels a hit, low health and a healing potion
-- (2026-10-22, the user's requests).
--
--   * A hit (Remotes.PlayerHurt from MeleeService, sent to every client): the body glows
--     red (Effects.flash "PlayerHurt", as long as WeaponHud/HitFlash's red screen flash
--     fades, 0.45 s) and recoils (Animation.Clips.Hurt.flinch, additive, like an enemy's
--     flinch). That recoil is all: the stumble back that pushed the hit player's body
--     away from the enemy was removed with every other knockback (the user, 2026-10-24:
--     it threw off damage tests). InventoryUI still flashes the screen and pops the damage.
--   * Low health: ScreenGlow/LowHealth, a red glow round the screen's edge, shows below
--     the gui's StartBelow share of max health (0.5) and gets stronger (MinStrength ->
--     MaxStrength) and darker (ColorLight -> ColorDark) the lower health goes, with a
--     heartbeat pulse that quickens and deepens as it falls (PulseRate, PulseDepth). It
--     eases toward each new level over EaseSeconds. An Animation.Scheduler Render system.
--   * A healing potion (HurtController.healed, from InventoryUI on a drunk Health potion):
--     green + signs float off the body (EffectPresets "HealPlus") and ScreenGlow/HealGlow,
--     the same edge glow in green, comes in (InSeconds), holds (HoldSeconds) and fades
--     (OutSeconds) at its Strength.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Animation = require(Shared:WaitForChild("Animation"))
local Effects = Animation.Effects
local Character = Animation.Character
local Hurt = Animation.Clips.Hurt

local HurtController = {}

local GUI_TIMEOUT = 15
local player = Players.LocalPlayer

local deps: any = nil
local lowGlow: ImageLabel? = nil
local healGlow: ImageLabel? = nil
local shown = 0 -- the low-health glow's current strength, 0..1 of its range
local beat = 0 -- heartbeat phase

local function number(inst: Instance, name: string, fallback: number): number
	local value = inst:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function color(inst: Instance, name: string, fallback: Color3): Color3
	local value = inst:GetAttribute(name)
	return if typeof(value) == "Color3" then value else fallback
end

local function onHurt(data: any)
	local character = type(data) == "table" and data.character
	if not (typeof(character) == "Instance" and character:IsA("Model") and character.Parent) then
		return
	end
	Effects.flash(character, "PlayerHurt")
	local entry = Character.peek(character)
	if entry then
		entry.animator:Stop("Player_flinch", 0)
		entry.animator:Play(Hurt.flinch())
	end
end

-- The low-health edge glow, every frame.
local function stepLowHealth(dt: number)
	local glow = lowGlow
	if not glow then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local share = if humanoid and humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 1
	local start = number(glow, "StartBelow", 0.5)
	-- 0 at the threshold, 1 at no health (a dead body shows nothing)
	local target = if humanoid and humanoid.Health > 0 and share < start then 1 - share / start else 0
	shown += (target - shown) * math.min(1, dt / math.max(number(glow, "EaseSeconds", 0.35), 1e-3))
	if shown < 0.005 then
		glow.ImageTransparency = 1
		beat = 0
		return
	end
	beat = (beat + dt * number(glow, "PulseRate", 1.1) * (0.5 + 0.5 * shown) * 2 * math.pi) % (2 * math.pi)
	local strength = number(glow, "MinStrength", 0.3) + (number(glow, "MaxStrength", 0.92) - number(glow, "MinStrength", 0.3)) * shown
	strength *= 1 - number(glow, "PulseDepth", 0.25) * shown * (0.5 + 0.5 * math.sin(beat))
	glow.ImageTransparency = 1 - strength
	glow.ImageColor3 = color(glow, "ColorLight", Color3.fromRGB(255, 59, 48)):Lerp(color(glow, "ColorDark", Color3.fromRGB(138, 0, 0)), shown)
end

-- A healing potion was drunk: + signs off the body and a brief green edge glow.
function HurtController.healed()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		Effects.burst(root.Position + Vector3.new(0, 0.5, 0), "HealPlus")
	end
	local glow = healGlow
	if glow then
		local strength = number(glow, "Strength", 0.6)
		local into = TweenService:Create(glow, TweenInfo.new(number(glow, "InSeconds", 0.12), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			ImageTransparency = 1 - strength,
		})
		into.Completed:Once(function(state)
			if state ~= Enum.PlaybackState.Completed then
				return
			end
			task.delay(number(glow, "HoldSeconds", 0.25), function()
				TweenService:Create(glow, TweenInfo.new(number(glow, "OutSeconds", 0.6), Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					ImageTransparency = 1,
				}):Play()
			end)
		end)
		into:Play()
	end
end

function HurtController.init(injected: any)
	deps = injected
end

function HurtController.start()
	deps.Remotes.getEvent("PlayerHurt").OnClientEvent:Connect(onHurt)
	task.spawn(function()
		local gui = player:WaitForChild("PlayerGui"):WaitForChild("ScreenGlow", GUI_TIMEOUT)
		if not gui then
			warn("[HurtController] no StarterGui/ScreenGlow")
			return
		end
		local low = gui:FindFirstChild("LowHealth")
		local heal = gui:FindFirstChild("HealGlow")
		lowGlow = if low and low:IsA("ImageLabel") then low else nil
		healGlow = if heal and heal:IsA("ImageLabel") then heal else nil
		if healGlow then
			healGlow.ImageTransparency = 1
		end
		Animation.Scheduler.bind("Render", "LowHealthGlow", 70, stepLowHealth)
	end)
end

return HurtController
