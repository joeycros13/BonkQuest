--!strict
-- ToolHint: the wrong-tool hint (issue 23, 2026-10-25), shared by everything a tool works on:
-- trees and rocks (GatherController) and fishing water (FishingController, a rod too weak for
-- the spot). It pops BonkPop.need where the thing was struck -- the needed tool's picture,
-- "Needs an Axe" and a line saying what to do -- and nudges the hotbar slot (HotbarUI.nudge)
-- for as long as the pop shows.
--
--   * Owns a tool of the kind that works: "Needs an Axe" and how to take it out, by the input
--     the player is using (the user: phones have no 2 key): "Press 2 for your Axe" on a
--     keyboard, "Tap your Axe" on a touch screen, "Equip your Axe" on a gamepad. Its slot
--     shakes and flashes white.
--   * Owns the kind but too weak: "Needs a Stone Axe / Upgrade it at the Weaponsmith"; its slot
--     shakes in orange-red (also when it is the one in hand).
--   * Owns none: "Needs a Wooden Axe / Buy one at the Weaponsmith", or "Craft it at the
--     Weaponsmith" when the needed tool is made from a recipe (World 2's tools and up; the
--     user: they're crafted, not bought).
-- Every word is an attribute on ReplicatedStorage/Assets/UI/NeedPop: NeedsFormat, PressFormat,
-- TapFormat, EquipFormat, UpgradeText, BuyText, CraftText.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Tools = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tools"))

local ToolHint = {}

local deps: any = nil

local function template(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local ui = assets and assets:FindFirstChild("UI")
	return ui and ui:FindFirstChild("NeedPop")
end

local function words(name: string, fallback: string): string
	local t = template()
	local value = t and t:GetAttribute(name)
	return if type(value) == "string" then value else fallback
end

-- How long the pop shows (its Lifetime): the hotbar nudge lasts as long.
local function popSeconds(): number
	local t = template()
	local value = t and t:GetAttribute("Lifetime")
	return if type(value) == "number" then value else 1.9
end

local function withArticle(name: string): string
	return (if name:match("^[AEIOUaeiou]") then "an " else "a ") .. name
end

-- The input the player is using: "Keyboard", "Touch" or "Gamepad".
local function device(): string
	local ok, preferred = pcall(function()
		return (UserInputService :: any).PreferredInput
	end)
	if ok and preferred ~= nil then
		local name = tostring(preferred)
		if name:find("Touch") then
			return "Touch"
		elseif name:find("Gamepad") then
			return "Gamepad"
		end
		return "Keyboard"
	end
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "Touch"
	elseif tostring(last):find("Gamepad") then
		return "Gamepad"
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	return "Keyboard"
end

-- The weakest tool of `kind` that reaches `tier`.
local function toolFor(kind: string, tier: number): Tools.ToolDef?
	local best: Tools.ToolDef? = nil
	for _, def in Tools.Defs do
		if def.kind == kind and def.tier >= tier and (best == nil or def.tier < best.tier) then
			best = def
		end
	end
	return best
end

-- Show the hint at `at` for something that needs a `kind` tool of at least `tier`.
function ToolHint.show(at: Vector3, kind: string, tier: number)
	local kindName = Tools.KindNames[kind] or kind
	local best = Tools.bestOf(Tools.owned(Players.LocalPlayer), kind)
	local needed = toolFor(kind, tier)
	local needs = words("NeedsFormat", "Needs %s")
	local HotbarUI = deps and deps.UI and deps.UI.HotbarUI
	local top, hint, icon
	if best and best.tier >= tier then
		-- they have one that works: how to take it out
		local using = device()
		top = needs:format(withArticle(kindName))
		hint = if using == "Touch"
			then words("TapFormat", "Tap your %s"):format(kindName)
			elseif using == "Gamepad" then words("EquipFormat", "Equip your %s"):format(kindName)
			else words("PressFormat", "Press %s for your %s"):format(tostring(Tools.slotOf(kind) or ""), kindName)
		icon = best.icon
		if HotbarUI then
			HotbarUI.nudge(kind, false, popSeconds())
		end
	elseif best then
		top = needs:format(withArticle(if needed then needed.name else kindName))
		hint = words("UpgradeText", "Upgrade it at the Weaponsmith")
		icon = if needed then needed.icon else best.icon
		if HotbarUI then
			HotbarUI.nudge(kind, true, popSeconds())
		end
	else
		top = needs:format(withArticle(if needed then needed.name else kindName))
		hint = if needed and needed.recipe
			then words("CraftText", "Craft it at the Weaponsmith")
			else words("BuyText", "Buy one at the Weaponsmith")
		icon = needed and needed.icon
	end
	deps.Util.BonkPop.need(at, top, hint, icon)
end

-- A rod cast that landed on dry ground (2026-10-25, the user: the same pop): NeedPop at the
-- landing spot with CastText ("Cast into the water!"), CastHint under it and the rod's picture.
-- No hotbar nudge: the rod in hand is the right tool.
function ToolHint.castHere(at: Vector3, icon: string?)
	deps.Util.BonkPop.need(at, words("CastText", "Cast into the water!"), words("CastHint", "Aim your bobber at the water"), icon)
end

function ToolHint.init(injected: any)
	deps = injected
end

return ToolHint
