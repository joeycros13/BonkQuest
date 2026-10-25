--!strict
-- WorldGuardService: keeps players out of worlds they haven't unlocked (2026-10-24, the user:
-- players could parkour onto the rim and walk from World 1 into World 2 without buying the gate).
--
-- Each world's invisible `Borders` walls (hand-placed in Studio, over the rim and above each gate)
-- stop the climb; this is the net behind them. Every CHECK_SECONDS it casts a ray down from each
-- player's root into every world's Ground folder: the world of the ground under their feet is the
-- world they are in. Standing on ground of a world above their HighestWorld sends them back
-- (PortalService.sendTo, behind the black fade) to the last spot where they stood on ground they
-- have unlocked, or to their highest world's Spawns/PlayerSpawn if there is none yet. Enemies are
-- shared by every player on the server, so they can't be hidden from one player; sending the
-- player back is the only fix that also stops gathering and fishing there.
--
-- Not before the player's data has loaded (HighestWorld is 1 until then), and not while a
-- teleport is under way.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Worlds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Worlds"))

local WorldGuardService = {}

local CHECK_SECONDS = 0.25
local RAY_DOWN = 80 -- studs below the root the ground is looked for (hedge tops count as ground)

local deps: any = nil
local lastSafe: { [Player]: CFrame } = {}
local grounds: { { folder: Instance, world: number } } = {}
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include

-- Every world's Ground folder, with its world id.
local function collectGrounds()
	table.clear(grounds)
	local list = {}
	local root = workspace:FindFirstChild("Worlds")
	for _, folder in if root then root:GetChildren() else {} do
		local def = Worlds.byFolder(folder.Name)
		local ground = folder:FindFirstChild("Ground")
		if def and ground then
			table.insert(grounds, { folder = ground, world = def.id })
			table.insert(list, ground)
		end
	end
	params.FilterDescendantsInstances = list
end

-- The world of the ground under a position, or nil (over nothing, or mid-air far above it).
local function worldUnder(position: Vector3): number?
	local hit = workspace:Raycast(position, Vector3.new(0, -RAY_DOWN, 0), params)
	if not hit then
		return nil
	end
	for _, g in grounds do
		if hit.Instance:IsDescendantOf(g.folder) then
			return g.world
		end
	end
	return nil
end

local function spawnOf(world: number): BasePart?
	local def = Worlds.get(world)
	local folder = def and workspace:FindFirstChild("Worlds") and workspace.Worlds:FindFirstChild(def.folder)
	local spawns = folder and folder:FindFirstChild("Spawns")
	local spawn = spawns and spawns:FindFirstChild("PlayerSpawn")
	return if spawn and spawn:IsA("BasePart") then spawn else nil
end

local function check(player: Player)
	if not player:GetAttribute("DataLoaded") or deps.Services.PortalService.isBusy(player) then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) then
		return
	end
	local world = worldUnder(root.Position)
	if not world then
		return
	end
	local highest = deps.Services.PlayerDataService.highestWorld(player)
	if world <= highest then
		-- remember only spots they actually stood on, not a jump's arc
		if humanoid.FloorMaterial ~= Enum.Material.Air then
			lastSafe[player] = root.CFrame
		end
		return
	end
	local back = lastSafe[player]
	if back then
		task.spawn(deps.Services.PortalService.sendTo, player, back)
	else
		local spawn = spawnOf(highest)
		if spawn then
			task.spawn(deps.Services.PortalService.send, player, spawn)
		end
	end
end

function WorldGuardService.init(injected: any)
	deps = injected
end

function WorldGuardService.start()
	collectGrounds()
	Players.PlayerRemoving:Connect(function(player)
		lastSafe[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			for _, player in Players:GetPlayers() do
				check(player)
			end
		end
	end)
end

return WorldGuardService
