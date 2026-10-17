--!strict
-- PanelWindow: shows and hides the hand-built panels.
--
-- A panel is a ScreenGui designed in StarterGui and given a "Panel" attribute
-- naming it ("Weapons", "Crafting", "Inventory"). Everything about how it looks
-- -- size, layout, colours, the items in a shop -- is authored there in Studio;
-- this module only switches panels on and off, one at a time, and closes the
-- open one when any button named "Close" inside it is pressed.
--
-- Walking into a stall's ring (InteractionController) opens that stall's panel;
-- the HUD's Inventory button (InventoryUI) opens the Inventory.
--
-- Opening pops the panel out of its centre: a UIScale named "PopScale" (on
-- the panel's Window, authored) grows from 0 with a little overshoot over the
-- panel's "OpenSeconds". Closing shrinks it back to 0 over "CloseSeconds",
-- and only then turns the panel off. Switching straight to another panel
-- closes the old one at once, so two windows never overlap. A panel without a
-- PopScale just appears and disappears.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local PanelWindow = {}

local panels: { [string]: ScreenGui } = {}
local openPanel: string? = nil
local popTweens: { [ScreenGui]: Tween } = {}

local function number(gui: Instance, name: string, fallback: number): number
	local value = gui:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function popScale(gui: ScreenGui): UIScale?
	local scale = gui:FindFirstChild("PopScale", true)
	return if scale and scale:IsA("UIScale") then scale else nil
end

-- Animate a panel's PopScale; `done` runs if the tween finishes uninterrupted.
local function pop(gui: ScreenGui, target: number, info: TweenInfo, done: (() -> ())?)
	local running = popTweens[gui]
	if running then
		running:Cancel()
		popTweens[gui] = nil
	end
	local scale = popScale(gui)
	if not scale then
		if done then
			done()
		end
		return
	end
	local tween = TweenService:Create(scale, info, { Scale = target })
	popTweens[gui] = tween
	tween.Completed:Connect(function(state)
		if popTweens[gui] == tween then
			popTweens[gui] = nil
		end
		if state == Enum.PlaybackState.Completed and done then
			done()
		end
	end)
	tween:Play()
end

local function openNow(gui: ScreenGui)
	-- reopened while still shrinking: grow back from where it is
	local scale = popScale(gui)
	if scale and not gui.Enabled then
		scale.Scale = 0
	end
	gui.Enabled = true
	pop(gui, 1, TweenInfo.new(number(gui, "OpenSeconds", 0.22), Enum.EasingStyle.Back, Enum.EasingDirection.Out))
end

local function closeNow(gui: ScreenGui, animate: boolean)
	if not gui.Enabled then
		return
	end
	if not animate then
		pop(gui, 1, TweenInfo.new(0))
		gui.Enabled = false
		return
	end
	pop(gui, 0, TweenInfo.new(number(gui, "CloseSeconds", 0.14), Enum.EasingStyle.Back, Enum.EasingDirection.In), function()
		gui.Enabled = false
	end)
end

function PanelWindow.init(_injected: any) end

local function adopt(gui: Instance)
	if not gui:IsA("ScreenGui") then
		return
	end
	local id = gui:GetAttribute("Panel")
	if type(id) ~= "string" or panels[id] == gui then
		return
	end
	panels[id] = gui
	gui.Enabled = false
	for _, descendant in gui:GetDescendants() do
		if descendant.Name == "Close" and descendant:IsA("GuiButton") then
			descendant.Activated:Connect(function()
				if openPanel == id then
					PanelWindow.hidePanel()
				end
			end)
			-- every panel's X is the admin panel's (2026-10-12): it dips while pressed
			-- (its PressScale). A panel whose own code already does this (AdminUI,
			-- RobuxShopUI) just runs the same tween twice.
			local press = descendant:FindFirstChild("PressScale")
			if press and press:IsA("UIScale") then
				local function dip(to: number)
					TweenService:Create(press, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = to }):Play()
				end
				descendant.MouseButton1Down:Connect(function()
					dip(0.88)
				end)
				descendant.MouseButton1Up:Connect(function()
					dip(1)
				end)
				descendant.MouseLeave:Connect(function()
					dip(1)
				end)
			end
		end
	end
end

function PanelWindow.start()
	-- StarterGui's copies arrive in PlayerGui on the first spawn; the authored
	-- panels have ResetOnSpawn off, so they are never replaced after that.
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, gui in playerGui:GetChildren() do
		adopt(gui)
	end
	playerGui.ChildAdded:Connect(adopt)
end

-- True if a hand-built panel with that id exists.
function PanelWindow.hasPanel(panelId: string): boolean
	return PanelWindow.getPanel(panelId) ~= nil
end

-- The panel's ScreenGui, for modules that fill in live values. Waits up to
-- `timeout` seconds for it to arrive from StarterGui (default: no wait).
function PanelWindow.getPanel(panelId: string, timeout: number?): ScreenGui?
	local deadline = os.clock() + (timeout or 0)
	repeat
		if panels[panelId] then
			return panels[panelId]
		end
		local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if playerGui then
			for _, gui in playerGui:GetChildren() do
				adopt(gui)
			end
		end
		if panels[panelId] or os.clock() >= deadline then
			break
		end
		task.wait(0.1)
	until false
	return panels[panelId]
end

-- Open a panel, replacing whichever one was showing.
function PanelWindow.showPanel(panelId: string)
	local gui = panels[panelId]
	if not gui then
		return
	end
	for id, other in panels do
		if id ~= panelId then
			closeNow(other, false)
		end
	end
	openPanel = panelId
	openNow(gui)
end

function PanelWindow.hidePanel()
	local id = openPanel
	openPanel = nil
	if id and panels[id] then
		closeNow(panels[id], true)
	end
end

-- True when `panelId` (or any panel, if omitted) is showing.
function PanelWindow.isPanelOpen(panelId: string?): boolean
	if not openPanel then
		return false
	end
	return panelId == nil or openPanel == panelId
end

return PanelWindow
