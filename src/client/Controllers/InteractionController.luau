--!strict
-- InteractionController: walk-in rings that open a panel -- the Weapons and
-- Crafting market stalls in the hub.
--
-- A ring is a part built by hand in Studio, tagged Interactable, with a
-- "Station" attribute naming the panel it opens (a hand-built ScreenGui; see
-- PanelWindow). Its footprint is the zone: stepping inside its circle opens the
-- panel, walking out closes it, no button press. The ring's look is authored too:
-- if it carries a SurfaceGui with "Idle" and "Inside" frames, Inside is shown
-- while the player stands in the ring and Idle the rest of the time. Optional attribute "Radius" overrides the
-- circle size (default: half the part's width).
--
-- So a new stall needs no code: copy a ring, move it, set its Station, and build
-- the panel it names. Everything here is client-side.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapLayout = require(Shared:WaitForChild("Config"):WaitForChild("MapLayout"))

local InteractionController = {}

-- Extra distance beyond the ring before the panel closes, so standing right on
-- the edge doesn't flicker it open and shut.
local EXIT_MARGIN = 2.5
-- Ignore players far above or below the ring (e.g. on another floor).
local VERTICAL_TOLERANCE = 10
-- Long enough that a slow-loading map is not mistaken for an unconfigured one.
local NO_ZONE_WARNING_DELAY = 20

local deps: any = nil
local PanelWindow: any = nil

local player = Players.LocalPlayer

type Zone = {
	ring: BasePart,
	panel: string,
	radius: number,
	-- True from stepping in until leaving. Latching on entry is what stops a panel
	-- the player closed by hand from snapping straight back open.
	occupied: boolean,
	idle: GuiObject?,
	active: GuiObject?,
}

local zones: { Zone } = {}
local adopted: { [Instance]: boolean } = {}
local warnedMissing: { [string]: boolean } = {}

function InteractionController.init(injected: any)
	deps = injected
	PanelWindow = deps.UI.PanelWindow
end

local function setActive(zone: Zone, active: boolean)
	if zone.idle then
		zone.idle.Visible = not active
	end
	if zone.active then
		zone.active.Visible = active
	end
end

local function open(zone: Zone)
	if PanelWindow.hasPanel(zone.panel) then
		PanelWindow.showPanel(zone.panel)
	elseif not warnedMissing[zone.panel] then
		warnedMissing[zone.panel] = true
		warn(("[InteractionController] %s opens panel %q, but no ScreenGui in StarterGui has Panel = %q"):format(
			zone.ring:GetFullName(),
			zone.panel,
			zone.panel
		))
	end
end

local function leave(zone: Zone)
	zone.occupied = false
	setActive(zone, false)
	if PanelWindow.isPanelOpen(zone.panel) then
		PanelWindow.hidePanel()
	end
end

-- Polled rather than Touched: touch events fire unreliably for a thin
-- non-colliding ring and would miss a player standing still inside it.
local function update()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end

	local position = root.Position
	for _, zone in zones do
		local center = zone.ring.Position
		local horizontal = Vector2.new(position.X - center.X, position.Z - center.Z).Magnitude
		local vertical = math.abs(position.Y - center.Y)
		if not zone.occupied then
			if horizontal <= zone.radius and vertical <= VERTICAL_TOLERANCE then
				zone.occupied = true
				setActive(zone, true)
				open(zone)
			end
		elseif horizontal > zone.radius + EXIT_MARGIN or vertical > VERTICAL_TOLERANCE + EXIT_MARGIN then
			leave(zone)
		end
	end
end

local function adopt(ring: Instance)
	if adopted[ring] or not ring:IsA("BasePart") then
		return
	end
	local station = ring:GetAttribute("Station")
	if type(station) ~= "string" or station == "" then
		warn(("[InteractionController] %s is tagged %s but has no Station attribute"):format(
			ring:GetFullName(),
			MapLayout.Tags.Interactable
		))
		return
	end
	adopted[ring] = true
	local radius = ring:GetAttribute("Radius")
	local surface = ring:FindFirstChildWhichIsA("SurfaceGui")
	local idle = surface and surface:FindFirstChild("Idle")
	local active = surface and surface:FindFirstChild("Inside")
	local zone: Zone = {
		ring = ring,
		panel = station,
		radius = if type(radius) == "number" and radius > 0 then radius else ring.Size.X / 2,
		occupied = false,
		idle = if idle and idle:IsA("GuiObject") then idle else nil,
		active = if active and active:IsA("GuiObject") then active else nil,
	}
	setActive(zone, false)
	table.insert(zones, zone)
end

function InteractionController.start()
	local tag = MapLayout.Tags.Interactable
	for _, ring in CollectionService:GetTagged(tag) do
		adopt(ring)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(adopt)
	RunService.Heartbeat:Connect(update)

	-- An untagged stall has no way in at all, and a missing tag is silent, so
	-- check once, late enough for the map to have arrived.
	task.delay(NO_ZONE_WARNING_DELAY, function()
		if #zones == 0 then
			warn(("[InteractionController] nothing in the map is tagged %s, so no panel can be opened"):format(tag))
		end
	end)
end

return InteractionController
