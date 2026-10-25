--!strict
-- DeathService: a player's body on dying (2026-10-25, the user: the body shouldn't fall
-- apart; it disintegrates instead).
--
-- Every character keeps its joints when it dies (Humanoid.BreakJointsOnDeath off) and its
-- root is anchored the moment it dies, so the body stays standing where it was while every
-- client plays the disintegration (Client.Controllers.DeathController) and the dying player
-- gets the BONKED! screen (Client.UI.DeathScreenUI). The respawn waits Players.RespawnTime
-- (4 s, set in Studio).

local Players = game:GetService("Players")

local DeathService = {}

local function watch(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	humanoid.BreakJointsOnDeath = false
	humanoid.Died:Connect(function()
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.Anchored = true
			-- upright, facing the way it did (the clients lift it from here)
			local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
			if look.Magnitude > 1e-3 then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + look.Unit)
			end
		end
	end)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(watch)
	if player.Character then
		task.spawn(watch, player.Character)
	end
end

function DeathService.init(_injected: any) end

function DeathService.start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return DeathService
