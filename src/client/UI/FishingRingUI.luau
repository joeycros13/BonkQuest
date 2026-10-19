--!strict
-- FishingRingUI: the fishing minigame's closing rings (2026-10-18; FishingController
-- starts them from the server's "Ring" messages, Config/Fishing has the rules).
--
-- The look is hand-built in Studio, either as a ScreenGui `StarterGui/FishingRing` or as
-- a BillboardGui `ReplicatedStorage/Assets/UI/FishingRing` that floats over the bobber
-- (a clone goes in PlayerGui, adorned to the bobber). This only shows it, sizes the
-- target zone for the fish, shrinks the closer and judges clicks. Names the code uses:
--
--   Ring          the round widget (any GuiObject, square), with a UIScale `PopScale`
--     Zone        the target band: a round Frame the size of the band's INSIDE, with a
--                 UIStroke `Band` (StrokeSizingMode ScaledSize) that draws the band
--                 outward. The code sets both from the fish's zone (Fishing.Difficulty):
--                 inside = 1 - zone of the Ring, band = 2 * zone of the Ring wide.
--                 Optional children: `Inner` (an outline the Zone's own size) and
--                 `Outer` (an outline the code sizes to the band's outside edge)
--     Closer      the closing ring: a round Frame the size of the Ring (1 = the middle
--                 of the zone) with a UIScale `Scale` the code shrinks
--     Pips        Pip1..PipN, one per ring (an optional `Check` child shows on a hit)
--     Hint        optional text ("Click when the ring is in the green")
-- Attributes on the gui (colours as Color3, times in seconds):
--   PipIdle / PipDone / PipMiss   a pip's BackgroundColor3 before, after a hit, after a miss
--   ZoneIdle / ZoneHit / ZoneMiss the Band's colour, and its flash on a hit or miss
--   PopSeconds (0.18)             the pop in and out
--   FinishSeconds (0.6)           how long the result shows before it pops away
--
-- click() judges against the closer's scale right now (the same maths the server uses,
-- Fishing.closerScale / zoneTimes) and returns the ring's number and whether it was in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Fishing = require(Shared:WaitForChild("Config"):WaitForChild("Fishing"))
local Animation = require(Shared:WaitForChild("Animation"))
local Tween = Animation.Tween

local FishingRingUI = {}

local player = Players.LocalPlayer
local deps: any = nil

type Ring = { n: number, startAt: number, difficulty: Fishing.Difficulty, done: boolean, started: boolean }

local gui: LayerCollector? = nil
local warned = false
local active: Ring? = nil
local closedEvent = Instance.new("BindableEvent")
local hideToken = 0

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

-- The gui, found (or cloned for the bobber) on first use.
local function ensure(): LayerCollector?
	if gui and gui.Parent then
		return gui
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local screen = playerGui and playerGui:FindFirstChild("FishingRing")
	if screen and screen:IsA("LayerCollector") then
		gui = screen
		-- Luckiest Guy draws high in its box: keep the title and hint centred
		deps.Util.FontDrop.watch(screen)
		return gui
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local ui = assets and assets:FindFirstChild("UI")
	local template = ui and ui:FindFirstChild("FishingRing")
	if template and template:IsA("BillboardGui") and playerGui then
		local copy = template:Clone()
		copy.Enabled = false
		copy.ResetOnSpawn = false
		copy.Parent = playerGui
		gui = copy
		deps.Util.FontDrop.watch(copy)
		return gui
	end
	if not warned then
		warned = true
		warn("[FishingRingUI] no StarterGui/FishingRing or Assets/UI/FishingRing yet: the rings can't show")
	end
	return nil
end

local function popScale(): UIScale?
	local scale = find({ "Ring", "PopScale" })
	return if scale and scale:IsA("UIScale") then scale else nil
end

local function setBand(color: Color3)
	local band = find({ "Ring", "Zone", "Band" })
	if band and band:IsA("UIStroke") then
		band.Color = color
	end
end

local function setPip(n: number, state: string)
	local pip = find({ "Ring", "Pips", "Pip" .. n })
	if not (pip and pip:IsA("GuiObject")) then
		return
	end
	local color = attr(if state == "done" then "PipDone" elseif state == "miss" then "PipMiss" else "PipIdle", nil)
	if typeof(color) == "Color3" then
		pip.BackgroundColor3 = color
	end
	local check = pip:FindFirstChild("Check")
	if check and check:IsA("GuiObject") then
		check.Visible = state == "done"
	end
end

local function closerScale(): UIScale?
	local scale = find({ "Ring", "Closer", "Scale" })
	return if scale and scale:IsA("UIScale") then scale else nil
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
		end
	end)
end

-- Show the widget for a fight of `of` rings, over `adornee` if it floats in the world.
function FishingRingUI.begin(of: number, adornee: BasePart?)
	local current = ensure()
	if not current then
		return
	end
	hideToken += 1
	active = nil
	if current:IsA("BillboardGui") then
		current.Adornee = adornee
	end
	local pips = find({ "Ring", "Pips" })
	for i = 1, 8 do
		local pip = pips and pips:FindFirstChild("Pip" .. i)
		if pip and pip:IsA("GuiObject") then
			pip.Visible = i <= of
			setPip(i, "idle")
		end
	end
	local closer = find({ "Ring", "Closer" })
	if closer and closer:IsA("GuiObject") then
		closer.Visible = false
	end
	setBand(attr("ZoneIdle", Color3.fromRGB(91, 191, 74)))
	current.Enabled = true
	local scale = popScale()
	if scale then
		scale.Scale = 0
		Tween.native(scale, { Scale = 1 }, attr("PopSeconds", 0.18), Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
end

-- Start ring `n` after `delay` seconds, closing over `closeSeconds`, the zone 1 +- `zone`.
-- Until then the last ring's hit stays on screen (the yellow band, the closer where it was
-- clicked): the user wanted a clear half second between a hit and the next ring (2026-10-19).
function FishingRingUI.ring(n: number, delay: number, closeSeconds: number, zone: number)
	if not ensure() then
		return
	end
	local difficulty = { closeSeconds = closeSeconds, zone = zone }
	local first = active == nil
	active = { n = n, startAt = os.clock() + delay, difficulty = difficulty, done = false, started = false }
	local inside = 1 - zone
	local band = find({ "Ring", "Zone", "Band" })
	local zoneFrame = find({ "Ring", "Zone" })
	if zoneFrame and zoneFrame:IsA("GuiObject") then
		zoneFrame.Size = UDim2.fromScale(inside, inside)
	end
	if band and band:IsA("UIStroke") then
		-- ScaledSize: a fraction of the Zone frame's own size, drawn outward from its edge
		band.Thickness = zone / inside
	end
	local outer = find({ "Ring", "Zone", "Outer" })
	if outer and outer:IsA("GuiObject") then
		outer.Size = UDim2.fromScale((1 + zone) / inside, (1 + zone) / inside)
	end
	if first then
		setBand(attr("ZoneIdle", Color3.fromRGB(91, 191, 74)))
		local closer = find({ "Ring", "Closer" })
		if closer and closer:IsA("GuiObject") then
			closer.Visible = false
		end
	end
end

-- A click: (ring number, whether the closer was inside the zone), or nil between rings.
function FishingRingUI.click(): (number?, boolean)
	local ring = active
	local now = os.clock()
	if not ring or ring.done or now < ring.startAt then
		return nil, false
	end
	ring.done = true
	local s = Fishing.closerScale(ring.difficulty, now - ring.startAt)
	local ok = math.abs(s - 1) <= ring.difficulty.zone
	setPip(ring.n, if ok then "done" else "miss")
	local flash = attr(if ok then "ZoneHit" else "ZoneMiss", nil)
	if typeof(flash) == "Color3" then
		setBand(flash)
	end
	return ring.n, ok
end

-- The fight is over: show the result a moment, then pop away.
function FishingRingUI.finish(caught: boolean)
	local ring = active
	active = nil
	if not (gui and gui.Enabled) then
		return
	end
	if not caught and ring and not ring.done then
		setPip(ring.n, "miss")
	end
	local flash = attr(if caught then "ZoneHit" else "ZoneMiss", nil)
	if typeof(flash) == "Color3" then
		setBand(flash)
	end
	task.delay(attr("FinishSeconds", 0.6), function()
		if active == nil then
			hide(attr("PopSeconds", 0.18))
		end
	end)
end

-- Gone at once (the line came in).
function FishingRingUI.cancel()
	active = nil
	if gui and gui.Enabled then
		hide(0)
	end
end

-- Fires (n) when a ring closes with no click.
function FishingRingUI.onClosed(callback: (number) -> ()): RBXScriptConnection
	return closedEvent.Event:Connect(callback)
end

function FishingRingUI.init(injected: any)
	deps = injected
end

function FishingRingUI.start()
	Animation.Scheduler.bind("Render", "FishingRing", 70, function(_dt: number, now: number)
		local ring = active
		if not ring or ring.done then
			return
		end
		local closer = find({ "Ring", "Closer" })
		local scale = closerScale()
		if now < ring.startAt then
			return
		end
		if not ring.started then
			-- the gap is over: back to the idle band and a fresh closer
			ring.started = true
			setBand(attr("ZoneIdle", Color3.fromRGB(91, 191, 74)))
		end
		if closer and closer:IsA("GuiObject") then
			closer.Visible = true
		end
		local t = now - ring.startAt
		if scale then
			scale.Scale = Fishing.closerScale(ring.difficulty, t)
		end
		if t >= ring.difficulty.closeSeconds then
			ring.done = true
			setPip(ring.n, "miss")
			local flash = attr("ZoneMiss", nil)
			if typeof(flash) == "Color3" then
				setBand(flash)
			end
			closedEvent:Fire(ring.n)
		end
	end)
end

return FishingRingUI
