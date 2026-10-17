--!strict
-- SecretService: World 3's secret crystal code (2026-10-13).
--
-- Three floor crystals are tagged "SecretCrystal" with SecretOrder 1..3 (Cyan, Pink,
-- Lavender: Blue, Pink, Purple, the order the hint crystals on the entry tunnel's left
-- wall show). A player who strikes them in that order opens the front mineshaft
-- (W03 Structures/Mineshafts/EntryMineshaft) for themselves: this sets their
-- SecretOpen_W3 attribute for the session and their client opens the way in.
--
-- The client says which crystal a swing reached (Remotes.SecretCrystalHit); the server
-- re-checks that the player is standing by it with a weapon out, then steps the code:
-- the next crystal in order moves it on, any other resets it (the first crystal
-- starts it again).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local SecretService = {}

local TAG = "SecretCrystal"
local ATTRIBUTE = "SecretOpen_W3"
local STEPS = 3
local MAX_DISTANCE = 16 -- studs from the crystal (the longest reach plus the cluster's size)
local MIN_GAP = 0.15 -- seconds between counted hits

local progress: { [Player]: number } = {}
local lastHit: { [Player]: number } = {}

local function crystal(order: number): Model?
	for _, m in CollectionService:GetTagged(TAG) do
		if m:IsA("Model") and m:GetAttribute("SecretOrder") == order and m:IsDescendantOf(workspace) then
			return m
		end
	end
	return nil
end

local function onHit(player: Player, order: any)
	if type(order) ~= "number" or order ~= math.floor(order) or order < 1 or order > STEPS then
		return
	end
	if player:GetAttribute(ATTRIBUTE) then
		return
	end
	local now = os.clock()
	if now - (lastHit[player] or 0) < MIN_GAP then
		return
	end
	lastHit[player] = now
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local target = crystal(order)
	if not (character and root and root:IsA("BasePart") and target and character:GetAttribute("Weapon")) then
		return
	end
	if (target:GetPivot().Position - root.Position).Magnitude > MAX_DISTANCE then
		return
	end
	local step = progress[player] or 0
	if order == step + 1 then
		step = order
	else
		step = if order == 1 then 1 else 0
	end
	progress[player] = step
	if step >= STEPS then
		progress[player] = nil
		player:SetAttribute(ATTRIBUTE, true)
	end
end

function SecretService.init(deps: any)
	deps.Remotes.getEvent("SecretCrystalHit").OnServerEvent:Connect(onHit)
end

function SecretService.start()
	Players.PlayerRemoving:Connect(function(player: Player)
		progress[player] = nil
		lastHit[player] = nil
	end)
end

return SecretService
