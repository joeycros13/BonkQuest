--!strict
-- MapLayout: the contract between the map authored in Studio and the code that
-- reads it. Folder names, tag names, and attribute names live here so a rename
-- is one edit instead of a hunt through every controller.
--
-- The shape of the map is fixed and identical for every world:
--
--   Workspace
--   |-- Worlds
--   |   |-- W01_SunnyMeadows        tag WorldRoot, attrs WorldId/DisplayName/Order
--   |   |   |-- Ground              baseplate / terrain
--   |   |   |-- Structures          buildings, and anything the player walks up to
--   |   |   |-- Decorations         purely visual; code never touches these
--   |   |   |-- Spawns              PlayerSpawn + EnemySpawns/ + BossSpawns/
--   |   |   |-- Enemies             filled at runtime by WorldEnemyService
--   |   |   |-- Bosses              filled at runtime by WorldEnemyService
--   |   |   |-- Gathering           trees and rocks to break for materials (tag GatherNode)
--   |   |   `-- Ambience            lights, particles, sound emitters
--   |   `-- W02_...                 the same folders
--   |-- Shared                      Gates/, owned by no single world
--   `-- Runtime                     script-created only; never authored in Studio
--
-- Discovery is by TAG, not by path: code asks CollectionService for every
-- Interactable rather than walking a folder chain, so moving or
-- renaming geometry in Studio cannot silently switch a feature off. The folders
-- above are for humans.
--
-- Model templates live in ServerStorage/Assets/Enemies and /Bosses; the server
-- clones them onto the spawn markers, so clients never see the templates.
--
-- Attributes, by the tag that implies them (authored in Studio unless runtime):
--   WorldRoot     WorldId, DisplayName, Order
--   Interactable  Station, Radius
--   GatherNode    Node (a Config/Gathering id); NodeId is set at runtime by GatherService
--   QuestGiver    QuestLine
--   EnemySpawn    Archetype, RespawnSeconds, WanderRadius
--   BossSpawn     BossId, RespawnSeconds, WanderRadius
--   WorldEnemy    (runtime, published by WorldEnemyService; the only replication
--                 channel world enemies have) EnemyId, Archetype, IsBoss, MaxHp,
--                 Hp, Alive, WorldId, WanderRadius, and for weapon fights
--                 (MeleeService) AiState Idle/Chase/Return, FightPos, FightLook,
--                 AttackSeq (ticks each time an attack starts), AttackMove

local Workspace = game:GetService("Workspace")

local MapLayout = {}

-- === Workspace top level ===
MapLayout.WorldsFolder = "Worlds"
MapLayout.RuntimeFolder = "Runtime"

-- === Tags: how code finds things ===
MapLayout.Tags = {
	WorldRoot = "WorldRoot", -- a world's top folder
	Interactable = "Interactable", -- hand-built walk-in ring (a part) that opens a panel
	EnemySpawn = "EnemySpawn", -- marker a world enemy spawns at
	BossSpawn = "BossSpawn", -- marker a world boss spawns at
	WorldEnemy = "WorldEnemy", -- applied at RUNTIME to a live enemy or boss body
	AmbientIdle = "AmbientIdle", -- shopkeeper that idles (breathes, looks around, waves)
	Critter = "Critter", -- ambient animal (deer, squirrel, owl); CritterController animates it by its Kind attribute
	QuestGiver = "QuestGiver", -- NPC model you talk to for a questline (Config/Quests)
	TeleportZone = "TeleportZone", -- invisible box; standing in it sends you to its ObjectValue "Target" part (PortalService)
	GatherNode = "GatherNode", -- a tree / rock you break for materials; its Node attribute names a Config/Gathering def (GatherService)
}

-- === Asset libraries ===
-- ServerStorage/Assets holds the enemy and boss templates cloned onto spawn
-- markers; ReplicatedStorage/Assets the models clients need too (Weapons...).
MapLayout.AssetsFolder = "Assets"

-- === Lookups ===

function MapLayout.worldsFolder(): Instance?
	return Workspace:FindFirstChild(MapLayout.WorldsFolder)
end

-- Every world's top folder, in Explorer order (which the W## prefix makes play order).
function MapLayout.worldRoots(): { Instance }
	local roots: { Instance } = {}
	local folder = MapLayout.worldsFolder()
	if not folder then
		return roots
	end
	for _, child in folder:GetChildren() do
		if child:IsA("Folder") then
			table.insert(roots, child)
		end
	end
	table.sort(roots, function(a, b)
		return a.Name < b.Name
	end)
	return roots
end

-- The world folder an instance sits inside, found by walking up to a child of
-- Workspace.Worlds. Returns nil for anything outside a world (Shared, Runtime).
function MapLayout.worldRootOf(inst: Instance): Instance?
	local worlds = MapLayout.worldsFolder()
	if not worlds then
		return nil
	end
	local node: Instance? = inst
	while node do
		if node.Parent == worlds then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- WorldId of whatever world an instance belongs to (nil when the world folder
-- has no WorldId attribute; the caller falls back to Worlds.byFolder).
function MapLayout.worldIdOf(inst: Instance): number?
	local root = MapLayout.worldRootOf(inst)
	if not root then
		return nil
	end
	local id = root:GetAttribute("WorldId")
	return if type(id) == "number" then id else nil
end

-- A named folder inside a world, e.g. worldFolder(root, "Enemies").
function MapLayout.worldFolder(root: Instance, name: string): Instance?
	return root:FindFirstChild(name)
end

-- Container for script-created instances, created on first use, so they stay
-- out of the authored world folders.
function MapLayout.runtimeFolder(): Instance
	local existing = Workspace:FindFirstChild(MapLayout.RuntimeFolder)
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = MapLayout.RuntimeFolder
	folder.Parent = Workspace
	return folder
end

return MapLayout
