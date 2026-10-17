--!strict
-- PromptController: draws ProximityPrompts in the game's own style (Talk
-- prompt B "speech bubble", the user's pick on the gate & prompt canvas,
-- 2026-10-10) instead of Roblox's grey default.
--
-- Any prompt whose Style is Custom gets a clone of a hand-built BillboardGui
-- from ReplicatedStorage/Assets/UI -- the prompt's "Template" attribute names
-- it (default "TalkPrompt") -- adorned to the prompt's part while the prompt is
-- shown. The template holds:
--   Content (with a PopScale UIScale; pops in over the gui's PopSeconds)
--     Bubble/Label   the text: the gui's TextFormat ("Talk to %s") with the
--                    prompt's "ShortName" attribute, or its ObjectText; or just
--                    the ActionText when neither is set
--     Key/Label      the key to press: the keyboard key's name, the gamepad
--                    button, or "Tap" on touch
--     Hit            a full-size button: clicking or tapping the bubble works
--                    like pressing the key
-- Both labels have an empty UIPadding, so Util.FontDrop puts Luckiest Guy's
-- letters in the middle of their (centred) boxes.
-- Nothing here builds UI; it clones and fills the template.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local PromptController = {}

local player = Players.LocalPlayer
local DEFAULT_TEMPLATE = "TalkPrompt"

local FontDrop: any = nil

-- the gui shown for each prompt
local shown: { [ProximityPrompt]: BillboardGui } = {}

local function template(prompt: ProximityPrompt): BillboardGui?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local ui = assets and assets:FindFirstChild("UI")
	local name = prompt:GetAttribute("Template")
	local found = ui and ui:FindFirstChild(if type(name) == "string" then name else DEFAULT_TEMPLATE)
	return if found and found:IsA("BillboardGui") then found else nil
end

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "Tap"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		return (prompt.GamepadKeyCode.Name:gsub("^Button", ""))
	end
	return prompt.KeyboardKeyCode.Name
end

local function popTo(gui: BillboardGui, scale: number): Tween?
	local content = gui:FindFirstChild("Content")
	local pop = content and content:FindFirstChild("PopScale")
	if not (pop and pop:IsA("UIScale")) then
		return nil
	end
	local seconds = gui:GetAttribute("PopSeconds")
	local style = if scale > 0 then Enum.EasingStyle.Back else Enum.EasingStyle.Quad
	local direction = if scale > 0 then Enum.EasingDirection.Out else Enum.EasingDirection.In
	local tween = TweenService:Create(pop, TweenInfo.new(if type(seconds) == "number" then seconds else 0.18, style, direction), { Scale = scale })
	tween:Play()
	return tween
end

local function show(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom or shown[prompt] then
		return
	end
	local source = template(prompt)
	if not source then
		return
	end
	local gui = source:Clone()
	local content = gui:FindFirstChild("Content")
	local label = content and content:FindFirstChild("Label", true)
	if label and label:IsA("TextLabel") then
		local short = prompt:GetAttribute("ShortName")
		local who = if type(short) == "string" then short else prompt.ObjectText
		local format = gui:GetAttribute("TextFormat")
		label.Text = if who ~= "" and type(format) == "string" then format:format(who) else prompt.ActionText
	end
	local key = content and content:FindFirstChild("Key")
	local keyLabel = key and key:FindFirstChild("Label")
	if keyLabel and keyLabel:IsA("TextLabel") then
		keyLabel.Text = keyText(prompt, inputType)
	end
	local hit = content and content:FindFirstChild("Hit")
	if hit and hit:IsA("GuiButton") then
		hit.MouseButton1Down:Connect(function()
			prompt:InputHoldBegin()
		end)
		hit.MouseButton1Up:Connect(function()
			prompt:InputHoldEnd()
		end)
	end
	local pop = content and content:FindFirstChild("PopScale")
	if pop and pop:IsA("UIScale") then
		pop.Scale = 0
	end
	gui.Adornee = prompt.Parent :: any
	gui.Parent = player:WaitForChild("PlayerGui")
	if FontDrop then
		FontDrop.watch(gui)
	end
	shown[prompt] = gui
	popTo(gui, 1)
end

local function hide(prompt: ProximityPrompt)
	local gui = shown[prompt]
	if not gui then
		return
	end
	shown[prompt] = nil
	local tween = popTo(gui, 0)
	if tween then
		tween.Completed:Once(function()
			gui:Destroy()
		end)
	else
		gui:Destroy()
	end
end

function PromptController.init(injected: any)
	FontDrop = injected.Util.FontDrop
end

function PromptController.start()
	ProximityPromptService.PromptShown:Connect(show)
	ProximityPromptService.PromptHidden:Connect(hide)
end

return PromptController
