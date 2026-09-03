--!strict
-- HudToggle: a single always-on-screen button that shows/hides the entire game
-- display (all our ScreenGuis in PlayerGui). The UI starts hidden so only this
-- button is visible; pressing it toggles everything back on. Prior Enabled state
-- of each ScreenGui is remembered so restoring never force-shows overlays (e.g.
-- CombatUI) that were meant to stay hidden.

local Players = game:GetService("Players")

local HudToggle = {}

local deps: any = nil
local UIFactory: any = nil
local Responsive: any = nil

local toggleGui: ScreenGui? = nil
local button: TextButton? = nil

local hidden = true
-- Remembers each managed ScreenGui's Enabled value while hidden, so we can
-- restore exactly on show. Keyed by the ScreenGui instance.
local savedStates: { [ScreenGui]: boolean } = {}
local childAddedConn: RBXScriptConnection? = nil

function HudToggle.init(injected: any)
	deps = injected
	UIFactory = deps.Util.UIFactory
	Responsive = deps.Util.Responsive
end

-- Every ScreenGui in PlayerGui that we manage (all of ours except this button).
local function managedGuis(): { ScreenGui }
	local player = Players.LocalPlayer
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local result: { ScreenGui } = {}
	if not playerGui then
		return result
	end
	for _, child in playerGui:GetChildren() do
		if child:IsA("ScreenGui") and child ~= toggleGui then
			table.insert(result, child)
		end
	end
	return result
end

local function refreshButton()
	if not button then
		return
	end
	local Theme = UIFactory.Theme
	;(button :: TextButton).Text = hidden and "Show UI" or "Hide UI"
	;(button :: TextButton).BackgroundColor3 = hidden and Theme.Positive or Theme.Negative
end

-- Disable a newly-added ScreenGui while we're in the hidden state, remembering
-- its prior Enabled value for restore.
local function handleChildAdded(child: Instance)
	if not hidden then
		return
	end
	if child:IsA("ScreenGui") and child ~= toggleGui then
		local gui = child :: ScreenGui
		savedStates[gui] = gui.Enabled
		gui.Enabled = false
	end
end

local function applyHidden(nowHidden: boolean)
	hidden = nowHidden
	local player = Players.LocalPlayer
	local playerGui = player:FindFirstChildOfClass("PlayerGui")

	if hidden then
		-- Snapshot + disable every managed ScreenGui.
		savedStates = {}
		for _, gui in managedGuis() do
			savedStates[gui] = gui.Enabled
			gui.Enabled = false
		end
		-- Keep new GUIs hidden too while in this state.
		if playerGui and not childAddedConn then
			childAddedConn = playerGui.ChildAdded:Connect(handleChildAdded)
		end
	else
		-- Restore each managed ScreenGui to its remembered state.
		for _, gui in managedGuis() do
			local prior = savedStates[gui]
			gui.Enabled = if prior == nil then true else prior
		end
		savedStates = {}
		if childAddedConn then
			childAddedConn:Disconnect()
			childAddedConn = nil
		end
	end

	refreshButton()
end

local function relayout()
	if not button then
		return
	end
	local w = Responsive.scaled(96)
	local h = Responsive.scaled(36)
	local margin = Responsive.scaled(12)
	;(button :: TextButton).Size = UDim2.fromOffset(w, h)
	;(button :: TextButton).Position = UDim2.new(1, -margin, 0, margin)
	;(button :: TextButton).TextSize = Responsive.scaled(16)
end

function HudToggle.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = UIFactory.create("ScreenGui", {
		Name = "HudToggle",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		-- Above all other UI so the button is never covered.
		DisplayOrder = 1000,
	})
	toggleGui = gui

	local btn = UIFactory.textButton({
		Name = "ToggleButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Responsive.scaled(12), 0, Responsive.scaled(12)),
		Size = UDim2.fromOffset(Responsive.scaled(96), Responsive.scaled(36)),
		TextSize = Responsive.scaled(16),
		Text = "Show UI",
	})
	UIFactory.corner(Responsive.scaled(8)).Parent = btn
	UIFactory.stroke({ Color = UIFactory.Theme.Stroke }).Parent = btn
	btn.Parent = gui
	button = btn

	btn.Activated:Connect(function()
		applyHidden(not hidden)
	end)

	gui.Parent = playerGui

	Responsive.onChanged(relayout)

	-- Start with the whole display turned off; only this button shows.
	applyHidden(true)
end

return HudToggle
