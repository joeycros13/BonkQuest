--!strict
-- SpawnService: where a player appears (issue 25, 2026-10-25, the user: spawn in the
-- newest world unlocked, picked in Settings; a death respawns you in the world you died in).
--
-- Every world has a SpawnLocation named Spawns/PlayerSpawn (Worlds 2 and 3's were plain
-- parts until 2026-10-25), all enabled and neutral, so Roblox would pick one at random for
-- a player with no RespawnLocation: every player gets one the moment they join (World 1's).
--   * Join: once the save has loaded (DataLoaded), the player goes to the world their
--     "Spawn in" setting names (Config/Settings SpawnWorld: 0 = the newest world unlocked,
--     else that world, never past HighestWorld), behind the join cover, and that world's
--     spawn becomes their RespawnLocation.
--   * Death: the RespawnLocation becomes the spawn of the unlocked world they last stood in
--     (WorldGuardService.worldOf), so dying in World 2 brings them back to World 2.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Settings"))

local SpawnService = {}

local deps: any = nil

local function spawnOf(world: number): SpawnLocation?
	local spawn = deps.Services.WorldGuardService.spawnOf(world)
	return if spawn and spawn:IsA("SpawnLocation") then spawn else nil
end

local function respawnIn(player: Player, world: number)
	local spawn = spawnOf(world) or spawnOf(1)
	if spawn then
		player.RespawnLocation = spawn
	end
end

-- Send the player to the world their setting picks, and respawn them there.
local function placeOnJoin(player: Player)
	local highest = deps.Services.PlayerDataService.highestWorld(player)
	local world = Settings.spawnWorld(player, highest)
	respawnIn(player, world)
	local spawn = spawnOf(world)
	local character = player.Character
	if spawn and character and character:FindFirstChild("HumanoidRootPart") then
		-- behind the join cover, so no fade
		deps.Services.PortalService.send(player, spawn, { fade = false })
	end
end

local function watchDeaths(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	humanoid.Died:Connect(function()
		local highest = deps.Services.PlayerDataService.highestWorld(player)
		local world = deps.Services.WorldGuardService.worldOf(player) or 1
		respawnIn(player, math.clamp(world, 1, highest))
	end)
end

local function onPlayer(player: Player)
	respawnIn(player, 1)
	player.CharacterAdded:Connect(function(character)
		watchDeaths(player, character)
	end)
	if player.Character then
		task.spawn(watchDeaths, player, player.Character)
	end
	task.spawn(function()
		if player:GetAttribute("DataLoaded") ~= true then
			player:GetAttributeChangedSignal("DataLoaded"):Wait()
		end
		if player.Parent and not player.Character then
			player.CharacterAdded:Wait()
		end
		if player.Parent then
			placeOnJoin(player)
		end
	end)
end

function SpawnService.init(injected: any)
	deps = injected
end

function SpawnService.start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return SpawnService
