--!strict
-- AvatarService: every player is an R6 avatar wearing their own outfit.
--
-- The rig comes from StarterPlayer/StarterCharacter, an R6 model, which is what
-- locks the rig type (the Game Settings avatar option needs a published place).
-- A StarterCharacter stops Roblox loading the player's appearance, so this puts
-- it back: each new character gets the player's HumanoidDescription -- clothes,
-- accessories, face and colours. Body-part and package ids are cleared first so
-- everyone keeps the classic blocky R6 shape that matches the map.
--
-- When dressing is done the character's "AvatarReady" attribute is set;
-- MeleeService waits for it before welding a weapon, since dressing replaces
-- parts of the character.

local Players = game:GetService("Players")

local AvatarService = {}

-- Package / body-part fields of a HumanoidDescription. R6 has no use for them.
local BODY_PARTS = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }

local descriptions: { [number]: HumanoidDescription } = {}

local function descriptionFor(player: Player): HumanoidDescription?
	local cached = descriptions[player.UserId]
	if cached then
		return cached
	end
	-- Local Studio test players have no real account to read from.
	if player.UserId <= 0 then
		return nil
	end
	local ok, result = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)
	if not ok or not result then
		warn(("[AvatarService] could not read %s's avatar: %s"):format(player.Name, tostring(result)))
		return nil
	end
	for _, field in BODY_PARTS do
		(result :: any)[field] = 0
	end
	descriptions[player.UserId] = result
	return result
end

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		warn("[AvatarService] character is not R6; is StarterPlayer/StarterCharacter missing?")
	end
	-- ApplyDescription needs the character in the world.
	while not character:IsDescendantOf(workspace) and player.Character == character do
		task.wait()
	end
	local description = descriptionFor(player)
	if description and player.Character == character then
		local ok, err = pcall(function()
			humanoid:ApplyDescription(description:Clone())
		end)
		if not ok then
			warn(("[AvatarService] could not dress %s: %s"):format(player.Name, tostring(err)))
		end
	end
	character:SetAttribute("AvatarReady", true)
end

function AvatarService.init(_injected: any) end

function AvatarService.start()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		descriptions[player.UserId] = nil
	end)
end

return AvatarService
