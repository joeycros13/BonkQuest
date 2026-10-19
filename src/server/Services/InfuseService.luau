--!strict
-- InfuseService: setting the secret-weapon cores into the blade (Config/Infuse, 2026-10-12).
--
-- Remotes.InfuseCore(core) -> (ok, reason) from a player standing at that core's world's Infuser (a
-- model tagged "Infuser" with a "World" attribute). The first core must be the Farm Core: the Rusty
-- Blade and the core are used up and the Worldheart Blade granted. Each later core, at its own world's
-- Infuser, swaps the current tier for the next (WorldheartBlade -> WorldheartBlade2 ...; Infuse.bladeOf). reason is one of:
--   "unknown"  not a core        "done"   already infused       "core"   the player doesn't hold it
--   "range"    not at that world's Infuser                      "blade"  no Rusty Blade to awaken
--   "order"    a later core before the Farm Core has awakened the blade
-- On success Remotes.CoreInfused { core, awakened, infuser } plays the client's reveal; after
-- Infuse.REVEAL_SECONDS the Worldheart Blade goes into the hand and (when it awakened) the
-- AWAKENED! popup shows.
--
-- Gems: whenever a Worldheart Blade is put in a character's hand, a small copy of each infused core
-- (the Farm Core always: it is what awakened the blade) is welded into its socket, so everyone sees
-- the filled sockets. From the second core on, an energy blade (setEnergy) shows the longer reach.
-- Saved as the "infuse" section: { cores = { [id] = true } }.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Infuse = require(Config:WaitForChild("Infuse"))
local Materials = require(Config:WaitForChild("Materials"))
local Weapons = require(Config:WaitForChild("Weapons"))
local Weld = require(Shared:WaitForChild("Animation"):WaitForChild("Weld"))

local InfuseService = {}

local TAG = "Infuser"
local EQUIPPED_NAME = "EquippedWeapon"
local VERTICAL_TOLERANCE = 12

local deps: any = nil
local infused: RemoteEvent? = nil
local profiles: { [Player]: { [string]: boolean } } = {}

local function coresOf(player: Player): { [string]: boolean }
	local cores = profiles[player]
	if not cores then
		cores = {}
		profiles[player] = cores
	end
	return cores
end

local function publish(player: Player)
	local list = {}
	for id in coresOf(player) do
		table.insert(list, id)
	end
	table.sort(list, function(a, b)
		return (Infuse.socketOf(a) or 99) < (Infuse.socketOf(b) or 99)
	end)
	player:SetAttribute("InfusedCores", table.concat(list, ","))
end

-- The Infuser for `world` the player stands at, if any.
local function infuserNear(player: Player, world: number): Instance?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	for _, inst in CollectionService:GetTagged(TAG) do
		-- only the altars in the map: backup copies in ServerStorage keep the tag, and the client
		-- can't see them, so the reveal had no altar to play over (2026-10-19)
		if inst:GetAttribute("World") == world and inst:IsDescendantOf(workspace) then
			local at = if inst:IsA("Model") then inst:GetPivot().Position elseif inst:IsA("BasePart") then inst.Position else nil
			if at then
				local offset = root.Position - at
				if Vector2.new(offset.X, offset.Z).Magnitude <= Infuse.RANGE and math.abs(offset.Y) <= VERTICAL_TOLERANCE then
					return inst
				end
			end
		end
	end
	return nil
end

-- The longer reach of a blade with 2+ cores (Config/Infuse tiers): a glowing violet energy blade,
-- thinner than the steel (so it hides inside it) but wider and (1 + reachBonus) times as long from the
-- guard, so it shows only as a glowing rim along the edges and spikes and past the tip. The model never
-- grows. (A full-size see-through shell washed the whole blade pink and hid the sockets.)
local ENERGY_COLOR = Color3.fromHex("b98cff")
local ENERGY_TRANSPARENCY = 0.35
local ENERGY_THICKNESS = 0.6 -- of the steel's (stays inside it)
local ENERGY_WIDTH = 1.14 -- of the steel's (the rim that shows)
local function setEnergy(_player: Player, model: Model, tierNumber: number)
	local old = model:FindFirstChild("EnergyBlade")
	if old then
		old:Destroy()
	end
	local grip = model.PrimaryPart
	local edge = model:FindFirstChild("Edge")
	local tier = Infuse.tier(tierNumber)
	if not (grip and edge and edge:IsA("BasePart")) or tier.reachBonus <= 0 then
		return
	end
	local rel = grip.CFrame:ToObjectSpace(edge.CFrame)
	local length = edge.Size.Z
	local reach = length * (1 + tier.reachBonus)
	local guardEnd = rel.Position.Z + length / 2 -- the blade runs toward -Z from here
	local energy = edge:Clone()
	energy.Name = "EnergyBlade"
	for _, child in energy:GetChildren() do
		child:Destroy()
	end
	energy.Size = Vector3.new(edge.Size.X * ENERGY_THICKNESS, edge.Size.Y * ENERGY_WIDTH, reach)
	energy.CFrame = grip.CFrame * CFrame.new(rel.Position.X, rel.Position.Y, guardEnd - reach / 2)
	energy.Material = Enum.Material.Neon
	energy.Color = ENERGY_COLOR
	energy.Transparency = ENERGY_TRANSPARENCY
	energy.CastShadow = false
	energy.CanCollide = false
	energy.CanQuery = false
	energy.CanTouch = false
	energy.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = grip
	weld.Part1 = energy
	weld.Parent = energy
	energy.Anchored = false
	energy.Parent = model
end

-- ---------- gems in the blade's sockets ----------
local function setGems(player: Player, model: Model)
	local tierNumber = Infuse.tierOf(Weapons.get(model:GetAttribute("WeaponId")))
	if not tierNumber then
		return
	end
	local grip = model.PrimaryPart
	local cores = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Cores")
	if not (grip and cores) then
		return
	end
	for _, child in model:GetChildren() do
		if child:GetAttribute("SocketGem") then
			child:Destroy()
		end
	end
	for _, id in Infuse.gemsFor(player, tierNumber) do
		local n = Infuse.socketOf(id)
		local socket = n and grip:FindFirstChild("Socket" .. n)
		local template = cores:FindFirstChild(id)
		if socket and socket:IsA("Attachment") and template and template:IsA("Model") then
			local gem = template:Clone()
			local cf, scale = Infuse.gemCFrame(socket)
			gem:ScaleTo(scale)
			gem:PivotTo(cf)
			gem:SetAttribute("SocketGem", id)
			for _, part in gem:GetDescendants() do
				if part:IsA("BasePart") then
					part.CanCollide = false
					part.CanQuery = false
					part.CanTouch = false
					part.Massless = true
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = grip
					weld.Part1 = part
					weld.Parent = part
					part.Anchored = false
				end
			end
			gem.Parent = model
		end
	end
	setEnergy(player, model, tierNumber)
end

local function refreshHeld(player: Player)
	local character = player.Character
	local held = character and character:FindFirstChild(EQUIPPED_NAME)
	if held and held:IsA("Model") then
		setGems(player, held)
	end
end

-- ---------- infusing ----------
function InfuseService.infuse(player: Player, core: any): (boolean, string?)
	local def = Materials.get(core)
	if not (def and def.core) then
		return false, "unknown"
	end
	local id: string = def.id
	local cores = coresOf(player)
	if cores[id] then
		return false, "done"
	end
	local MaterialService = deps.Services.MaterialService
	local MeleeService = deps.Services.MeleeService
	if MaterialService.get(player, id) < 1 then
		return false, "core"
	end
	local infuser = infuserNear(player, def.world)
	if not infuser then
		return false, "range"
	end
	local awakens = id == Infuse.FIRST
	-- the blade that goes in and the one that comes out
	local current = Infuse.bladeOf(Infuse.count(player))
	local nextBlade = if awakens then Infuse.AWAKENED else Infuse.bladeOf(Infuse.count(player) + 1)
	if awakens then
		if not MeleeService.owns(player, Infuse.BLADE) then
			return false, "blade"
		end
	elseif not (cores[Infuse.FIRST] and MeleeService.owns(player, current)) then
		return false, "order"
	end
	-- world order: world N's core only after worlds 1..N-1 (the Farm Core is socket 1)
	if not Infuse.isNext(player, id) then
		return false, "order"
	end
	if not Weapons.get(nextBlade) then
		return false, "unknown" -- that tier isn't made yet
	end

	MaterialService.add(player, id, -1)
	cores[id] = true
	publish(player)
	-- hands empty while the reveal plays at the altar
	MeleeService.setHolstered(player, true)
	MeleeService.revoke(player, if awakens then Infuse.BLADE else current)
	MeleeService.grant(player, nextBlade)
	if infused then
		infused:FireClient(player, { core = id, awakened = awakens, infuser = infuser })
	end
	task.delay(Infuse.REVEAL_SECONDS, function()
		if player.Parent then
			MeleeService.equip(player, nextBlade)
			deps.Services.IndexService.showWeapon(player, nextBlade)
		end
	end)
	return true, nil
end

function InfuseService.init(injected: any)
	deps = injected
	infused = deps.Remotes.getEvent("CoreInfused")
	deps.Services.PlayerDataService.register("infuse", {
		load = function(player: Player, value: any)
			if type(value) ~= "table" or type(value.cores) ~= "table" then
				return
			end
			local cores = coresOf(player)
			for id, v in value.cores do
				local def = Materials.get(id)
				if v == true and def and def.core then
					cores[id] = true
				end
			end
			publish(player)
		end,
		save = function(player: Player): any
			local cores = profiles[player]
			return if cores then { cores = table.clone(cores) } else nil
		end,
	})
end

function InfuseService.start()
	deps.Remotes.getFunction("InfuseCore").OnServerInvoke = function(player: Player, core: any)
		return InfuseService.infuse(player, core)
	end
	local function onCharacter(player: Player, character: Model)
		character.ChildAdded:Connect(function(child)
			if child.Name == EQUIPPED_NAME and child:IsA("Model") then
				setGems(player, child)
			end
		end)
	end
	local function onPlayer(player: Player)
		publish(player)
		player:GetAttributeChangedSignal("InfusedCores"):Connect(function()
			refreshHeld(player)
		end)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			onCharacter(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	-- PlayerDataService saves on leave first (it connected earlier), then this clears
	Players.PlayerRemoving:Connect(function(player: Player)
		task.defer(function()
			profiles[player] = nil
		end)
	end)
end

return InfuseService
