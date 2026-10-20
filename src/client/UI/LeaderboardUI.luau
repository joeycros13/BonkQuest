--!strict
-- LeaderboardUI: the Leaderboards panel (2026-10-19, option A "tabs and podium" on
-- https://claude.ai/artifact/E7RQQXPYH2ZCKBB6V4YaWk), opened from the HUD's
-- WeaponHud/SideButtons/LeaderboardButton. Boards and rewards are Config/Leaderboards;
-- the numbers come from Remotes.GetLeaderboard (LeaderboardService).
--
-- Hand-built StarterGui/LeaderboardPanel (Panel = "Leaderboards"):
--   Window/Periods/<Daily|Weekly|All>   pills (Period attribute, Label)
--   Window/Tabs/<Coins|Levels|Kills>    stat tabs (Stat attribute, Icon, Label)
--   Window/Reset                        "Resets in 5h 12m" / "Never resets"
--   Window/Podium/Place1..3             PlayerName, Value, Block/Rank
--   Window/List                         a ScrollingFrame of Templates/Row clones (#4-50:
--                                       Rank, PlayerName, Value); Window/Empty when no one
--   Window/You                          your own place (Rank, PlayerName, Value)
--   Window/Rewards                      Title, Tiers (Templates/TierCard clones: Label, Chips
--                                       of Templates/Chip; Fill1..3 attributes), Note (all-time)
-- Colours: the gui's TabSelected / TabIdle / PillSelected / PillIdle / PillSelectedText /
-- PillIdleText attributes; a chip's TextScale is its text size as a share of its height.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Leaderboards = require(Shared:WaitForChild("Config"):WaitForChild("Leaderboards"))

local Util = script.Parent.Parent:WaitForChild("Util")
local Format = require(Util:WaitForChild("Format"))

local LeaderboardUI = {}

local PANEL = "Leaderboards"
local GUI_TIMEOUT = 15
local CACHE_SECONDS = 15
local player = Players.LocalPlayer

local deps: any = nil
local PanelWindow: any = nil
local gui: any = nil
local window: any = nil
local stat = "Coins"
local period = "Daily"
local boards: { [string]: { data: any, at: number } } = {}
local shownResetsAt: number? = nil

local Text = Leaderboards.Text

local function duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local d = seconds // 86400
	local h = (seconds % 86400) // 3600
	local m = (seconds % 3600) // 60
	if d > 0 then
		return ("%dd %dh"):format(d, h)
	elseif h > 0 then
		return ("%dh %dm"):format(h, m)
	end
	return ("%dm %ds"):format(m, seconds % 60)
end

local function valueText(value: number): string
	if stat == "Levels" and period == "All" then
		return Text.level:format(Format.commas(value))
	end
	return Format.commas(value)
end

local function fetch(): any
	local key = stat .. "_" .. period
	local hit = boards[key]
	if hit and os.clock() - hit.at < CACHE_SECONDS then
		return hit.data
	end
	local ok, data = pcall(function()
		return Remotes.getFunction("GetLeaderboard"):InvokeServer(stat, period)
	end)
	if not ok or type(data) ~= "table" then
		return hit and hit.data or nil
	end
	boards[key] = { data = data, at = os.clock() }
	return data
end

local function styleTabs()
	for _, b in window.Tabs:GetChildren() do
		if b:IsA("GuiButton") then
			b.BackgroundColor3 = gui:GetAttribute(if b:GetAttribute("Stat") == stat then "TabSelected" else "TabIdle") or b.BackgroundColor3
			b:SetAttribute("Selected", b:GetAttribute("Stat") == stat) -- stays grown (Util.ButtonFx)
		end
	end
	for _, b in window.Periods:GetChildren() do
		if b:IsA("GuiButton") then
			local on = b:GetAttribute("Period") == period
			b:SetAttribute("Selected", on) -- stays grown (Util.ButtonFx)
			b.BackgroundColor3 = gui:GetAttribute(if on then "PillSelected" else "PillIdle") or b.BackgroundColor3
			b.Label.TextColor3 = gui:GetAttribute(if on then "PillSelectedText" else "PillIdleText") or b.Label.TextColor3
		end
	end
end

local function chipSize(container: GuiObject, template: Instance): number
	return math.max(8, math.floor(container.AbsoluteSize.Y * 0.3 * (template:GetAttribute("TextScale") or 0.62)))
end

local function fillRewards()
	local card = window.Rewards
	for _, c in card.Tiers:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local tiers = Leaderboards.Rewards[period]
	card.Title.Text = if tiers then Text.rewards else Text.allTime
	card.Note.Text = Text.allTimeNote
	card.Note.Visible = tiers == nil
	for index, tier in tiers or {} do
		local tc = window.Templates.TierCard:Clone()
		tc.Name = "Tier" .. index
		tc.LayoutOrder = index
		tc.Visible = true
		tc.BackgroundColor3 = tc:GetAttribute("Fill" .. index) or tc.BackgroundColor3
		tc.Label.Text = tier.label
		tc.Parent = card.Tiers
		local size = chipSize(tc.Chips, window.Templates.Chip)
		for i, words in Leaderboards.describe(tier.reward) do
			local chip = window.Templates.Chip:Clone()
			chip.Name = "Chip" .. i
			chip.LayoutOrder = i
			chip.Visible = true
			chip.Text = words
			chip.TextSize = size
			chip.Parent = tc.Chips
		end
	end
end

local function fitList()
	local layout = window.List:FindFirstChildOfClass("UIListLayout")
	local pad = window.List:FindFirstChildOfClass("UIPadding")
	if layout then
		local extra = if pad then pad.PaddingTop.Offset + pad.PaddingBottom.Offset else 0
		window.List.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + extra)
	end
end

function LeaderboardUI.refresh()
	if not window then
		return
	end
	styleTabs()
	fillRewards()
	local data = fetch()
	local rows = if data then data.rows or {} else {}
	for rank = 1, 3 do
		local place = window.Podium:FindFirstChild("Place" .. rank)
		local row = rows[rank]
		if place then
			place.PlayerName.Text = if row then row.name else "—"
			place.Value.Text = if row then valueText(row.value) else ""
			place.Block.Rank.Text = tostring(rank)
		end
	end
	for _, c in window.List:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	for i = 4, #rows do
		local row = rows[i]
		local r = window.Templates.Row:Clone()
		r.Name = "Rank" .. row.rank
		r.LayoutOrder = row.rank
		r.Visible = true
		r.Rank.Text = "#" .. row.rank
		r.PlayerName.Text = row.name
		r.Value.Text = valueText(row.value)
		r.Parent = window.List
	end
	window.Empty.Text = Text.empty
	window.Empty.Visible = #rows == 0
	fitList()
	local you = if data then data.you else nil
	window.You.Rank.Text = if you and you.rank then Text.you:format(you.rank) else Text.youUnranked
	window.You.PlayerName.Text = player.Name
	window.You.Value.Text = valueText(if you then you.value or 0 else 0)
	shownResetsAt = if data then data.resetsAt else nil
end

-- the countdown ticks every second while open
local function tickReset()
	if not window then
		return
	end
	window.Reset.Text = if shownResetsAt
		then Text.resetsIn:format(duration(shownResetsAt - Workspace:GetServerTimeNow()))
		else Text.never
end

function LeaderboardUI.toggle()
	if PanelWindow.isPanelOpen(PANEL) then
		PanelWindow.hidePanel()
	else
		PanelWindow.showPanel(PANEL)
		LeaderboardUI.refresh()
		tickReset()
	end
end

local function wire(found: ScreenGui)
	gui = found
	window = found:WaitForChild("Window")
	for _, b in window.Tabs:GetChildren() do
		local s = b:GetAttribute("Stat")
		if b:IsA("GuiButton") and type(s) == "string" then
			b.Label.Text = Text.stat[s] or s
			b.Activated:Connect(function()
				stat = s
				LeaderboardUI.refresh()
			end)
		end
	end
	for _, b in window.Periods:GetChildren() do
		local p = b:GetAttribute("Period")
		if b:IsA("GuiButton") and type(p) == "string" then
			b.Label.Text = Text.period[p] or p
			b.Activated:Connect(function()
				period = p
				LeaderboardUI.refresh()
				tickReset()
			end)
		end
	end
	if window:FindFirstChild("Title") then
		window.Title.Text = Text.title
	end
	if deps.Util.FontDrop then
		deps.Util.FontDrop.watch(found)
	end
	local hud = player:WaitForChild("PlayerGui"):WaitForChild("WeaponHud", GUI_TIMEOUT)
	local button = hud and hud:FindFirstChild("LeaderboardButton", true)
	if button and button:IsA("GuiButton") then
		if deps.UI.HotbarUI and deps.UI.HotbarUI.wireHover then
			deps.UI.HotbarUI.wireHover(button)
		end
		button.Activated:Connect(LeaderboardUI.toggle)
	end
	task.spawn(function()
		local since = 0
		while true do
			task.wait(1)
			if found.Enabled then
				tickReset()
				since += 1
				if since >= CACHE_SECONDS then
					since = 0
					LeaderboardUI.refresh()
				end
			end
		end
	end)
end

function LeaderboardUI.init(injected: any)
	deps = injected
	PanelWindow = injected.UI.PanelWindow
end

function LeaderboardUI.start()
	task.spawn(function()
		local found = PanelWindow.getPanel(PANEL, GUI_TIMEOUT)
		if found then
			wire(found)
		else
			warn("[LeaderboardUI] no Leaderboards panel (StarterGui/LeaderboardPanel)")
		end
	end)
end

return LeaderboardUI
