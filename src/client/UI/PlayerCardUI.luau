--!strict
-- PlayerCardUI: wires the hand-built player card, StarterGui/WeaponHud/TopLeft/PlayerCard
-- (found with a deep FindFirstChild, so it can move inside the HUD's layouts).
--
-- Live today:
--   * PlayerName: the player's display name,
--   * Avatar/AvatarImage: the player's Roblox headshot (the striped circle shows
--     until it loads, or if it can't),
--   * Health: Fill width and the Amount text, from the character's Humanoid.
--     The fill colour comes from the bar's HealthyColor / LowColor / LowFraction
--     attributes.
--   * Stamina: removed (user, 2026-10-11: sprinting is unlimited). The bar was
--     deleted; Health and XP sit in Panel/Info's UIListLayout, which spaces them.
--   * Every number reads with commas (Util.Format), like the shop.
--   * XP bar ("EXP" Label, Amount "x / y") and the LevelBadge: from the
--     player's "ExpTotal" attribute (ExpService) through Config/Leveling. Like
--     the coin counter it counts up over the XP bar's CountSeconds, rolling
--     over into the next level as it passes one.
--   * PlayerCardUI.Exp is the EXP stars' landing spot for LootController
--     (beginSpill / collect / endSpill, the same shape as CoinsUI): each star
--     flies to the XP bar (FlyingStar template, FlySeconds) and bumps it
--     (BumpScale); the count starts when the first one lands.
--   * PlayerCardUI.Exp.shownLevel() / onShown() give the level the badge shows
--     right now, for the quest tracker to follow.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Leveling = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Leveling"))

local PlayerCardUI = {}

local GUI_TIMEOUT = 15
local player = Players.LocalPlayer

local card: Instance? = nil
local hud: ScreenGui? = nil
local HudFly: any = nil
local Format: any = nil

local function attribute(inst: Instance, name: string, fallback: any): any
	local value = inst:GetAttribute(name)
	return if value ~= nil then value else fallback
end

local function find(name: string, className: string): any
	local found = card and card:FindFirstChild(name, true)
	return if found and found:IsA(className) then found else nil
end

local function showHealth(humanoid: Humanoid)
	local bar = find("Health", "GuiObject")
	if not bar then
		return
	end
	local ratio = if humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0
	local fill = bar:FindFirstChild("Fill", true)
	if fill and fill:IsA("GuiObject") then
		fill.Size = UDim2.fromScale(ratio, fill.Size.Y.Scale)
		local low = ratio <= attribute(bar, "LowFraction", 0.3)
		fill.BackgroundColor3 = attribute(bar, if low then "LowColor" else "HealthyColor", fill.BackgroundColor3)
	end
	local amount = bar:FindFirstChild("Amount", true)
	if amount and amount:IsA("TextLabel") then
		amount.Text = Format.ratio(math.ceil(humanoid.Health), humanoid.MaxHealth)
	end
end

-- ==================== EXP ====================

local expShown = 0 -- the total EXP the bar shows right now
local expValue: NumberValue? = nil
local expTween: Tween? = nil
local expPending = 0 -- star spills still on their way
local shownLevel = Leveling.START
local levelEvent = Instance.new("BindableEvent")

local function expTotal(): number
	local value = player:GetAttribute("ExpTotal")
	return if type(value) == "number" then value else 0
end

local function xpNumber(name: string, fallback: number): number
	local bar = find("XP", "GuiObject")
	local value = bar and bar:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function showExp(total: number)
	expShown = total
	local level, into, need = Leveling.fromTotal(math.floor(total + 0.5))
	local bar = find("XP", "GuiObject")
	if bar then
		local fill = bar:FindFirstChild("Fill", true)
		if fill and fill:IsA("GuiObject") then
			fill.Size = UDim2.fromScale(math.clamp(into / need, 0, 1), fill.Size.Y.Scale)
		end
		local amount = bar:FindFirstChild("Amount", true)
		if amount and amount:IsA("TextLabel") then
			amount.Text = Format.ratio(into, need)
		end
	end
	local badge = find("Level", "TextLabel")
	if badge then
		badge.Text = Format.commas(level)
	end
	if level ~= shownLevel then
		shownLevel = level
		levelEvent:Fire(level)
	end
end

-- Count the bar from what it shows now up to `target` total EXP.
local function countExp(target: number)
	if expTween then
		expTween:Cancel()
	end
	if not expValue then
		local value = Instance.new("NumberValue")
		value.Changed:Connect(showExp)
		expValue = value
	end
	local value = expValue :: NumberValue
	value.Value = expShown
	if target == expShown then
		return
	end
	expTween = TweenService:Create(value, TweenInfo.new(xpNumber("CountSeconds", 1), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = target })
	;(expTween :: Tween):Play()
end

-- Where LootController sends EXP stars.
PlayerCardUI.Exp = {}

function PlayerCardUI.Exp.beginSpill()
	expPending += 1
end

function PlayerCardUI.Exp.endSpill()
	expPending = math.max(0, expPending - 1)
	countExp(expTotal())
end

function PlayerCardUI.Exp.collect(from: Vector2, landed: (() -> ())?)
	local bar = find("XP", "GuiObject")
	local templates = hud and hud:FindFirstChild("Templates")
	local template = templates and templates:FindFirstChild("FlyingStar")
	if not (hud and bar and template and template:IsA("GuiObject")) then
		if landed then
			landed()
		end
		return
	end
	HudFly.fly(hud :: ScreenGui, template, from, bar, xpNumber("FlySeconds", 0.55), function()
		HudFly.bump(bar, xpNumber("BumpScale", 1.08))
		if landed then
			landed()
		end
	end)
end

-- The level the badge shows right now (it trails the real level while stars
-- fly in and the bar counts up).
function PlayerCardUI.Exp.shownLevel(): number
	return shownLevel
end

function PlayerCardUI.Exp.onShown(callback: (number) -> ()): RBXScriptConnection
	return levelEvent.Event:Connect(callback)
end

function PlayerCardUI.Exp.flyStagger(): number
	return xpNumber("FlyStagger", 0.08)
end

local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	showHealth(humanoid)
	humanoid.HealthChanged:Connect(function()
		showHealth(humanoid)
	end)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		showHealth(humanoid)
	end)
end

local function showIdentity()
	local name = find("PlayerName", "TextLabel")
	if name then
		name.Text = player.DisplayName
	end
	local image = find("AvatarImage", "ImageLabel")
	if image and player.UserId > 0 then
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and content then
			image.Image = content
		end
	end
end

function PlayerCardUI.init(injected: any)
	HudFly = injected.Util.HudFly
	Format = injected.Util.Format
end

function PlayerCardUI.start()
	-- StarterGui's copy can land in PlayerGui after this starts.
	task.spawn(function()
		local gui = player:WaitForChild("PlayerGui"):WaitForChild("WeaponHud", GUI_TIMEOUT)
		-- the card stacks in WeaponHud/TopLeft with the coin counter
		local found = gui and gui:FindFirstChild("PlayerCard", true)
		if not found then
			warn("[PlayerCardUI] no WeaponHud/PlayerCard in StarterGui")
			return
		end
		card = found
		hud = gui :: any
		showIdentity()
		showExp(expTotal())
		player:GetAttributeChangedSignal("ExpTotal"):Connect(function()
			-- stars on their way count up when they land; anything else counts
			-- after a beat (in case its spill is announced a moment later)
			task.delay(0.2, function()
				if expPending == 0 then
					countExp(expTotal())
				end
			end)
		end)
		player.CharacterAdded:Connect(watchCharacter)
		if player.Character then
			watchCharacter(player.Character)
		end
	end)
end

return PlayerCardUI
