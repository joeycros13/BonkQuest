--!strict
-- DialogueUI: plays an NPC conversation in the hand-built StarterGui/Dialogue
-- card (Dialogue B "Side card", picked on the Claude Design canvas).
--
-- QuestController drives it:
--   DialogueUI.open()          pop the card in
--   DialogueUI.say(conv)       yields until the player picks a choice; returns
--                              "accept" or "later"
--   DialogueUI.close()         pop it out
--   DialogueUI.cancel()        end the conversation now, as "later" (the player
--                              walked away from the giver)
-- A conversation is { lines, tag, objective = { text, icon }?, reward?,
-- accept = "label"?, later = "label"? }. Each line types out letter by letter
-- at the Dialogue's "CharsPerSecond" attribute (MaxVisibleGraphemes, so rich
-- text works mid-word). Clicking anywhere on screen (the full-screen "Catcher"
-- button behind the card, which also keeps the click from reaching the world)
-- or pressing E / Space / Enter finishes the
-- line, then moves to the next one. After the last line the Objective box,
-- Reward chips and the choice buttons the conversation names appear. In lines,
-- [square brackets] mark the objective, drawn bold in the Objective's red.
--
-- Pieces found by name inside Dialogue/Window: PopScale, NpcName,
-- Portrait/Photo, QuestTag (outlined text like the name), Text, Tap, NextHint,
-- Objective (Icon, Goal),
-- Reward (Coins, Exp, Weapon, Item, each with Amount; Item is a quest item from
-- Config/Materials), Choices (Accept, Later, each with Label).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Materials = require(Shared:WaitForChild("Config"):WaitForChild("Materials"))
local Weapons = require(Shared:WaitForChild("Config"):WaitForChild("Weapons"))

local DialogueUI = {}

export type Conversation = {
	lines: { string },
	tag: string?,
	objective: { text: string, icon: string }?,
	reward: { coins: number?, exp: number?, weapon: string?, item: string? }?,
	accept: string?,
	later: string?,
}

local ADVANCE_KEYS = {
	[Enum.KeyCode.E] = true,
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.Return] = true,
	[Enum.KeyCode.ButtonA] = true,
}

local gui: ScreenGui? = nil
local window: Frame? = nil
local popTween: Tween? = nil

-- the coroutine waiting in say(), and whether a click should finish typing
local waiting: thread? = nil
local typing = false
local skip = false
local choosing = false
local cancelled = false

local function find(name: string): any
	return (window :: Frame):FindFirstChild(name, true)
end

local function number(name: string, fallback: number): number
	local value = gui and gui:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function resume(value: string)
	local thread = waiting
	if thread then
		waiting = nil
		task.spawn(thread, value)
	end
end

local function advance()
	if not (gui and gui.Enabled) or choosing then
		return
	end
	if typing then
		skip = true
	else
		resume("next")
	end
end

-- "[defeat 5 chickens]" -> bold, in the Objective's red
local function markup(line: string): string
	local goal = find("Goal")
	local red = if goal then (goal :: TextLabel).TextColor3:ToHex() else "D9241B"
	return (line:gsub("%[(.-)%]", function(inner)
		return ('<b><font color="#%s">%s</font></b>'):format(red, inner)
	end))
end

local Format = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Format"))

local function setChip(name: string, text: string?)
	local chip = find(name)
	if not chip then
		return
	end
	chip.Visible = text ~= nil
	-- the icon and words sit in a centred row (Content, Util.CenterRow)
	local amount = chip:FindFirstChild("Amount", true)
	if text and amount then
		amount.Text = text
	end
end

local function showExtras(conv: Conversation?)
	local objective = find("Objective")
	local reward = find("Reward")
	local choices = find("Choices")
	objective.Visible = conv ~= nil and conv.objective ~= nil
	reward.Visible = conv ~= nil and conv.reward ~= nil
	choices.Visible = conv ~= nil and (conv.accept ~= nil or conv.later ~= nil)
	if not conv then
		return
	end
	if conv.objective then
		objective.Goal.Text = conv.objective.text
		objective.Icon.Image = conv.objective.icon
	end
	local r = conv.reward
	if r then
		setChip("Coins", if r.coins and r.coins > 0 then Format.coins(r.coins) .. " Coins" else nil)
		setChip("Exp", if r.exp and r.exp > 0 then Format.commas(r.exp) .. " EXP" else nil)
		local weapon = r.weapon and Weapons.get(r.weapon)
		setChip("Weapon", if weapon then weapon.name else nil)
		-- the weapon chip shows the weapon's own drawn icon (the template's sword
		-- stays for weapons without one)
		local chip = find("Weapon")
		local icon = chip and chip:FindFirstChild("Icon", true)
		if icon and icon:IsA("ImageLabel") then
			if icon:GetAttribute("DefaultImage") == nil then
				icon:SetAttribute("DefaultImage", icon.Image)
			end
			icon.Image = if weapon and weapon.icon then weapon.icon else icon:GetAttribute("DefaultImage")
		end
		-- a quest item shows its own icon once it has one; until then just its name
		local item = r.item and Materials.get(r.item)
		setChip("Item", if item then item.name else nil)
		local itemChip = find("Item")
		local itemIcon = itemChip and itemChip:FindFirstChild("Icon", true)
		if itemIcon and itemIcon:IsA("ImageLabel") then
			itemIcon.Visible = item ~= nil and item.icon ~= nil
			itemIcon.Image = if item and item.icon then item.icon else ""
		end
	end
	choices.Accept.Visible = conv.accept ~= nil
	choices.Accept.Label.Text = conv.accept or ""
	choices.Later.Visible = conv.later ~= nil
	choices.Later.Label.Text = conv.later or ""
end

-- Type one line out; returns once it is fully shown.
local function typeLine(line: string)
	local text = find("Text") :: TextLabel
	text.Text = markup(line)
	text.MaxVisibleGraphemes = 0
	local total = utf8.len(text.ContentText) or #text.ContentText
	local speed = number("CharsPerSecond", 60)
	local shown = 0
	typing, skip = true, false
	while shown < total and not skip do
		shown += RunService.Heartbeat:Wait() * speed
		text.MaxVisibleGraphemes = math.floor(shown)
	end
	text.MaxVisibleGraphemes = -1
	typing = false
end

function DialogueUI.say(conv: Conversation): string
	assert(window, "DialogueUI: no Dialogue/Window")
	local tag = find("QuestTag")
	tag.Visible = conv.tag ~= nil
	tag.Text = conv.tag or ""
	showExtras(nil)
	for index, line in conv.lines do
		local last = index == #conv.lines
		find("NextHint").Visible = false
		typeLine(line)
		if cancelled then
			return "later"
		end
		if last then
			break
		end
		find("NextHint").Visible = true
		waiting = coroutine.running()
		coroutine.yield()
		if cancelled then
			return "later"
		end
	end
	showExtras(conv)
	choosing = true
	waiting = coroutine.running()
	local choice = coroutine.yield()
	choosing = false
	return if cancelled then "later" else choice
end

-- Who is talking, set before the card opens so it never shows the last speaker for a
-- moment (user, 2026-10-11 for the name and photo; 2026-10-19 for the tag, which used to
-- wait for say() and showed the last NPC's "Quest 3 of 10" / "Fishing Lesson").
function DialogueUI.setSpeaker(name: string, portrait: string, tag: string?)
	if window then
		find("NpcName").Text = name
		find("Photo").Image = portrait
		local label = find("QuestTag")
		label.Visible = tag ~= nil
		label.Text = tag or ""
	end
end

local function pop(target: number, seconds: number, style: Enum.EasingDirection, done: (() -> ())?)
	local scale = window and window:FindFirstChild("PopScale")
	if popTween then
		popTween:Cancel()
	end
	if not (scale and scale:IsA("UIScale")) then
		if done then
			done()
		end
		return
	end
	local tween = TweenService:Create(scale, TweenInfo.new(seconds, Enum.EasingStyle.Back, style), { Scale = target })
	popTween = tween
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and done then
			done()
		end
	end)
	tween:Play()
end

-- The player left (walked too far from the giver): finish any typing and answer
-- whatever say() is waiting on with "later", so the conversation ends at once.
function DialogueUI.cancel()
	cancelled = true
	skip = true
	resume("later")
end

function DialogueUI.open()
	if not (gui and window) then
		return
	end
	cancelled = false
	local text = find("Text") :: TextLabel
	text.Text = ""
	showExtras(nil)
	find("NextHint").Visible = false
	local scale = window:FindFirstChild("PopScale")
	if scale and scale:IsA("UIScale") then
		scale.Scale = 0
	end
	gui.Enabled = true
	pop(1, number("OpenSeconds", 0.25), Enum.EasingDirection.Out)
end

function DialogueUI.close()
	if not gui then
		return
	end
	choosing, typing = false, false
	local target = gui
	pop(0, number("CloseSeconds", 0.15), Enum.EasingDirection.In, function()
		target.Enabled = false
	end)
end

function DialogueUI.isOpen(): boolean
	return gui ~= nil and gui.Enabled
end

function DialogueUI.init(_injected: any) end

function DialogueUI.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local found = playerGui:WaitForChild("Dialogue", 30)
	if not (found and found:IsA("ScreenGui")) then
		warn("[DialogueUI] StarterGui has no Dialogue ScreenGui")
		return
	end
	gui = found
	window = found:FindFirstChild("Window") :: Frame
	found.Enabled = false
	find("Tap").Activated:Connect(advance)
	local catcher = found:FindFirstChild("Catcher")
	if catcher and catcher:IsA("GuiButton") then
		catcher.Activated:Connect(advance)
	end
	find("Accept").Activated:Connect(function()
		if choosing then
			resume("accept")
		end
	end)
	find("Later").Activated:Connect(function()
		if choosing then
			resume("later")
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and ADVANCE_KEYS[input.KeyCode] then
			advance()
		end
	end)
end

return DialogueUI
