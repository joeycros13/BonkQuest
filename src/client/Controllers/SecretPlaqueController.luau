--!strict
-- SecretPlaqueController: the plaque in each secret room (2026-10-29, the user's pick: style A
-- "Treasure plaque" on https://claude.ai/artifact/T214LqBq6uhjktkzPRPpfP). It tells players there is
-- something to find without giving the drop rate: the room's core as a black shadow in a glowing
-- niche, "Something precious rests here…", a line naming the room's keeper and a "Very rare" chip.
-- For a player who holds the core or has infused it into the Worldheart Blade it turns to the core in
-- full colour with its name and "Found!". Each player sees their own state; nothing is replicated.
--
-- Each plaque is a hand-built part tagged SecretPlaque holding a SurfaceGui named Plaque:
--   Plate/Panel/Niche (Frame, a circle) with Core (ImageLabel: the core's icon, set by this code),
--   Plate/Panel/Title, Line (TextLabels), Plate/Panel/Chip (Frame) with Label.
-- The gui's attributes say what it shows (every word and colour is there, none in code):
--   CoreId                         the Config/Materials core in the room
--   LockedTitle / LockedLine       the words before it's found
--   FoundLine                      the line once it's found (the title becomes the core's name)
--   LockedChip / FoundChip         the chip's word
--   ChipLocked / ChipFound         the chip's colour
--   NicheLocked / NicheFound       the niche's colour
--   CoreLocked / CoreFound         the core icon's tint (black for the shadow, white for its colours)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Materials = require(Config:WaitForChild("Materials"))
local Infuse = require(Config:WaitForChild("Infuse"))

local SecretPlaqueController = {}

local TAG = "SecretPlaque"

local FontDrop: any = nil
local plaques: { [Instance]: SurfaceGui } = {}

local function found(coreId: string): boolean
	local player = Players.LocalPlayer
	return (Materials.counts(player)[coreId] or 0) > 0 or Infuse.infused(player)[coreId] == true
end

local function attr(gui: Instance, name: string, fallback: any): any
	local v = gui:GetAttribute(name)
	return if v ~= nil then v else fallback
end

local function fill(gui: SurfaceGui)
	local coreId = gui:GetAttribute("CoreId")
	local def = if type(coreId) == "string" then Materials.get(coreId) else nil
	if not def then
		return
	end
	local have = found(coreId :: string)
	local panel = gui:FindFirstChild("Panel", true)
	if not panel then
		return
	end
	local niche = panel:FindFirstChild("Niche") :: Frame?
	local core = niche and niche:FindFirstChild("Core") :: ImageLabel?
	local title = panel:FindFirstChild("Title") :: TextLabel?
	local line = panel:FindFirstChild("Line") :: TextLabel?
	local chip = panel:FindFirstChild("Chip") :: Frame?
	local chipLabel = chip and chip:FindFirstChild("Label") :: TextLabel?
	if niche then
		niche.BackgroundColor3 = attr(gui, if have then "NicheFound" else "NicheLocked", niche.BackgroundColor3)
	end
	if core then
		core.Image = def.icon or ""
		core.ImageColor3 = attr(gui, if have then "CoreFound" else "CoreLocked", core.ImageColor3)
	end
	if title then
		title.Text = if have then def.name else attr(gui, "LockedTitle", title.Text)
	end
	if line then
		line.Text = attr(gui, if have then "FoundLine" else "LockedLine", line.Text)
	end
	if chip then
		chip.BackgroundColor3 = attr(gui, if have then "ChipFound" else "ChipLocked", chip.BackgroundColor3)
	end
	if chipLabel then
		chipLabel.Text = attr(gui, if have then "FoundChip" else "LockedChip", chipLabel.Text)
	end
end

local function refreshAll()
	for _, gui in plaques do
		fill(gui)
	end
end

local function adopt(part: Instance)
	if plaques[part] then
		return
	end
	local gui = part:FindFirstChild("Plaque")
	if not (gui and gui:IsA("SurfaceGui")) then
		return
	end
	plaques[part] = gui
	if FontDrop then
		FontDrop.watch(gui)
	end
	fill(gui)
end

function SecretPlaqueController.init(deps: any)
	FontDrop = deps.Util and deps.Util.FontDrop
end

function SecretPlaqueController.start()
	for _, part in CollectionService:GetTagged(TAG) do
		adopt(part)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(adopt)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(part)
		plaques[part] = nil
	end)
	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal("Materials"):Connect(refreshAll)
	player:GetAttributeChangedSignal("InfusedCores"):Connect(refreshAll)
end

return SecretPlaqueController
