--!strict
-- FishingBarUI: the fishing fight's reel bar (issue 26, 2026-10-25, option A "rod handle" on
-- https://claude.ai/artifact/HVf9wMPrZdj5nLj6cVh8Dc, the user's pick; it replaced the
-- closing rings). FishingController starts it from the server's "Fight" message;
-- Config/Fishing has the rules and the marker's formula (Fishing.sliderAt), which the
-- server judges clicks by too.
--
-- The look is hand-built in Studio as `StarterGui/FishingBar`. This only shows it, moves
-- the marker, sizes the green, spins the reel, judges clicks for instant feedback and
-- shows the server's tally. Names the code uses:
--
--   Holder            the whole widget, middle of the right side, with a UIScale `PopScale`
--     Title/Content   "Reel it in!" with the fish (a CenterRow)
--     Handle/Track    the bar's cream window (clips the green)
--       Zone          the green; the code sets its Position and Size (centred in the Track)
--     Slide/Marker    the marker; the code sets its Position Y (0 top .. 1 bottom of Slide)
--     Reel            spun by the code (Rotation)
--     Pips/PipN       one per check, a `Tick` inside shown once it is ticked
--     Slip/Label      the forgiven miss: "1 slip left", then "Last chance!"
--   Hint              "Click when the marker is in the green", bottom of the screen
-- Attributes on the gui (colours as Color3, times in seconds, words as strings):
--   ZoneIdle / ZoneHit / ZoneMiss   the green, and its flash on a hit or a miss
--   PipIdle / PipDone               a pip before and after its check
--   SlipIdle / SlipLast             the slip pill before and after the free miss
--   SlipText / LastText             its words
--   CaughtText / EscapedText        the Hint's words when it ends
--   ReelSpin / ReelSpinHit          the reel's degrees a second, and right after a check
--   PopSeconds (0.18)               the pop in and out
--   FinishSeconds (0.6)             how long the result shows before it pops away
-- The quest tracker shares the right side of the screen, so it hides while the bar is up
-- and comes back as it was.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Fishing = require(Shared:WaitForChild("Config"):WaitForChild("Fishing"))
local Animation = require(Shared:WaitForChild("Animation"))
local Tween = Animation.Tween

local FishingBarUI = {}

local player = Players.LocalPlayer
local deps: any = nil

-- how long a hit or miss flash stays on the green
local FLASH_SECONDS = 0.25

type Fight = {
	startAt: number, -- server time the marker starts
	difficulty: Fishing.Difficulty,
	checks: number, -- the checks needed
	slips: number,
	ticked: number, -- checks so far (local, then the server's)
	missed: number,
	over: boolean,
	lastClick: number,
}

local gui: ScreenGui? = nil
local warned = false
local fight: Fight? = nil
local hideToken = 0
local flashUntil = 0
local spinFast = 0
local trackerWas: ScreenGui? = nil -- the quest tracker, hidden while the bar is up

local function hideTracker()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local tracker = playerGui and playerGui:FindFirstChild("QuestTracker")
	if tracker and tracker:IsA("ScreenGui") and tracker.Enabled and not trackerWas then
		trackerWas = tracker
		tracker.Enabled = false
	end
end

local function showTracker()
	if trackerWas then
		trackerWas.Enabled = true
		trackerWas = nil
	end
end

local function attr(name: string, fallback: any): any
	local value = gui and gui:GetAttribute(name)
	return if value ~= nil then value else fallback
end

local function find(path: { string }): Instance?
	local node: Instance? = gui
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function ensure(): ScreenGui?
	if gui and gui.Parent then
		return gui
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local screen = playerGui and playerGui:FindFirstChild("FishingBar")
	if screen and screen:IsA("ScreenGui") then
		gui = screen
		-- Luckiest Guy draws high in its box: keep the hint centred
		deps.Util.FontDrop.watch(screen)
		return gui
	end
	if not warned then
		warned = true
		warn("[FishingBarUI] no StarterGui/FishingBar: the reel bar can't show")
	end
	return nil
end

local function popScale(): UIScale?
	local scale = find({ "Holder", "PopScale" })
	return if scale and scale:IsA("UIScale") then scale else nil
end

local function setZoneColor(color: Color3)
	local zone = find({ "Holder", "Handle", "Track", "Zone" })
	if zone and zone:IsA("GuiObject") then
		zone.BackgroundColor3 = color
	end
end

local function flash(name: string)
	local color = attr(name, nil)
	if typeof(color) == "Color3" then
		setZoneColor(color)
		flashUntil = os.clock() + FLASH_SECONDS
	end
end

local function setHint(text: string?)
	local hint = find({ "Hint" })
	if hint and hint:IsA("TextLabel") and text then
		hint.Text = text
	end
end

local function render(current: Fight)
	local pips = find({ "Holder", "Pips" })
	for i = 1, 8 do
		local pip = pips and pips:FindFirstChild("Pip" .. i)
		if pip and pip:IsA("GuiObject") then
			pip.Visible = i <= current.checks
			local done = i <= current.ticked
			local color = attr(if done then "PipDone" else "PipIdle", nil)
			if typeof(color) == "Color3" then
				pip.BackgroundColor3 = color
			end
			local tick = pip:FindFirstChild("Tick")
			if tick and tick:IsA("GuiObject") then
				tick.Visible = done
			end
		end
	end
	local slip = find({ "Holder", "Slip" })
	if slip and slip:IsA("GuiObject") then
		local last = current.missed >= current.slips
		local color = attr(if last then "SlipLast" else "SlipIdle", nil)
		if typeof(color) == "Color3" then
			slip.BackgroundColor3 = color
		end
		local label = slip:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			label.Text = if last then attr("LastText", "Last chance!") else attr("SlipText", "1 slip left")
		end
	end
	-- the green, centred in the bar, shrinking with each check
	local zone = find({ "Holder", "Handle", "Track", "Zone" })
	if zone and zone:IsA("GuiObject") then
		local size = Fishing.zoneSize(current.difficulty, current.ticked)
		zone.Position = UDim2.fromScale(0.5, 0.5)
		zone.Size = UDim2.fromScale(1, size)
	end
end

local function hide(seconds: number)
	hideToken += 1
	local token = hideToken
	local scale = popScale()
	local current = gui
	if scale and seconds > 0 then
		Tween.native(scale, { Scale = 0 }, seconds, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	end
	task.delay(seconds, function()
		if token == hideToken and current then
			current.Enabled = false
			showTracker()
		end
	end)
end

-- Show the bar for a fight: the marker starts at server time `startAt`.
function FishingBarUI.begin(message: { [string]: any })
	local current = ensure()
	if not current then
		return
	end
	hideToken += 1
	fight = {
		startAt = message.startAt or workspace:GetServerTimeNow(),
		difficulty = { speed = message.speed or 0.55, zone = message.zone or 0.3, jerk = message.jerk or 0 },
		checks = message.checks or Fishing.checks,
		slips = message.slips or Fishing.slips,
		ticked = 0,
		missed = 0,
		over = false,
		lastClick = 0,
	}
	setZoneColor(attr("ZoneIdle", Color3.fromRGB(79, 207, 92)))
	setHint(current:GetAttribute("HintText") :: string?)
	render(fight :: Fight)
	hideTracker()
	current.Enabled = true
	local scale = popScale()
	if scale then
		scale.Scale = 0
		Tween.native(scale, { Scale = 1 }, attr("PopSeconds", 0.18), Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
end

-- A click: (the server time it was made at, whether the marker was in the green), or nil
-- when it doesn't count (no fight, before the marker starts, a double click).
function FishingBarUI.click(): (number?, boolean)
	local current = fight
	if not current or current.over then
		return nil, false
	end
	local clock = os.clock()
	local now = workspace:GetServerTimeNow()
	local t = now - current.startAt
	if t < 0 or clock - current.lastClick < Fishing.clickGap then
		return nil, false
	end
	current.lastClick = clock
	local ok = Fishing.inZone(current.difficulty, current.ticked, t)
	if ok then
		current.ticked += 1
		spinFast = clock + 0.4
		flash("ZoneHit")
	else
		current.missed += 1
		flash("ZoneMiss")
	end
	render(current)
	return now, ok
end

-- The server's count after a click (it judged the same moment; this keeps them in step).
function FishingBarUI.tally(checks: number, misses: number)
	local current = fight
	if current then
		current.ticked = checks
		current.missed = misses
		render(current)
	end
end

-- The fight is over: show the result a moment, then pop away.
function FishingBarUI.finish(caught: boolean)
	local current = fight
	if not (current and gui and gui.Enabled) then
		fight = nil
		return
	end
	current.over = true
	if caught then
		current.ticked = current.checks
	end
	render(current)
	flash(if caught then "ZoneHit" else "ZoneMiss")
	flashUntil = math.huge
	setHint(if caught then attr("CaughtText", "Caught!") else attr("EscapedText", "It got away!"))
	task.delay(attr("FinishSeconds", 0.6), function()
		if fight == current then
			fight = nil
			hide(attr("PopSeconds", 0.18))
		end
	end)
end

-- Gone at once (the line came in).
function FishingBarUI.cancel()
	fight = nil
	if gui and gui.Enabled then
		hide(0)
	end
	showTracker()
end

function FishingBarUI.active(): boolean
	return fight ~= nil and not (fight :: Fight).over
end

function FishingBarUI.init(injected: any)
	deps = injected
end

function FishingBarUI.start()
	-- keep the Hint's authored words to put back on each new fight
	task.defer(function()
		local current = ensure()
		local hint = current and current:FindFirstChild("Hint")
		if current and hint and hint:IsA("TextLabel") and current:GetAttribute("HintText") == nil then
			current:SetAttribute("HintText", hint.Text)
		end
	end)
	Animation.Scheduler.bind("Render", "FishingBar", 70, function(dt: number, now: number)
		local current = fight
		if not current then
			return
		end
		if now >= flashUntil then
			flashUntil = math.huge
			setZoneColor(attr("ZoneIdle", Color3.fromRGB(79, 207, 92)))
		end
		local t = workspace:GetServerTimeNow() - current.startAt
		local marker = find({ "Holder", "Slide", "Marker" })
		if marker and marker:IsA("GuiObject") and not current.over then
			marker.Position = UDim2.fromScale(0.5, Fishing.sliderAt(current.difficulty, t))
		end
		local reel = find({ "Holder", "Reel" })
		if reel and reel:IsA("GuiObject") and not current.over and t > 0 then
			local speed = if now < spinFast then attr("ReelSpinHit", 1400) else attr("ReelSpin", 400)
			reel.Rotation = (reel.Rotation + speed * dt) % 360
		end
	end)
end

return FishingBarUI
