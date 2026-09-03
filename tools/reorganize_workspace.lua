--!nocheck
-- One-off Workspace reorganization. Paste into the Roblox Studio Command Bar.
-- Studio owns world geometry, so this must run in Studio (not synced via Rojo).
-- Safe to re-run: every step checks for the already-reorganized state first.

local Workspace = game:GetService("Workspace")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local log = {}
local function note(fmt, ...)
	table.insert(log, string.format(fmt, ...))
end
local function missing(what)
	table.insert(log, "SKIPPED (not found): " .. what)
end

local function pad(i)
	return string.format("%02d", i)
end

local function posOf(inst)
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		local ok, cf = pcall(function()
			return inst:GetPivot()
		end)
		if ok then
			return cf.Position
		end
	end
	return Vector3.zero
end

-- Deterministic ordering so numbering is stable across runs.
local function sorted(container)
	local kids = container:GetChildren()
	table.sort(kids, function(a, b)
		local pa, pb = posOf(a), posOf(b)
		if math.abs(pa.X - pb.X) > 0.01 then
			return pa.X < pb.X
		end
		if math.abs(pa.Z - pb.Z) > 0.01 then
			return pa.Z < pb.Z
		end
		return a.Name < b.Name
	end)
	return kids
end

local function ensureFolder(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	note("created Folder %s", f:GetFullName())
	return f
end

-- ClassName is immutable, so converting Model<->Folder means rebuilding the node.
local function convert(inst, className, newName)
	if not inst then
		return nil
	end
	newName = newName or inst.Name
	if inst.ClassName == className then
		inst.Name = newName
		return inst
	end
	local new = Instance.new(className)
	new.Name = newName
	for _, child in ipairs(inst:GetChildren()) do
		child.Parent = new
	end
	new.Parent = inst.Parent
	note("converted %s [%s] -> %s [%s]", inst.Name, inst.ClassName, newName, className)
	inst:Destroy()
	return new
end

local function renameAll(container, prefix)
	if not container then
		return
	end
	local i = 0
	for _, child in ipairs(sorted(container)) do
		i += 1
		child.Name = prefix .. "_" .. pad(i)
	end
	note("renamed %d children of %s to %s_NN", i, container.Name, prefix)
end

-- Numbers within each distinct existing name, e.g. Tree1A -> Tree1A_01..13
local function renameGrouped(container)
	if not container then
		return
	end
	local counters = {}
	for _, child in ipairs(sorted(container)) do
		local base = child.Name
		counters[base] = (counters[base] or 0) + 1
		child.Name = base .. "_" .. pad(counters[base])
	end
	note("grouped-renamed %d children of %s", #container:GetChildren(), container.Name)
end

-- Final sweep: any remaining duplicate sibling names get _NN suffixes.
local function dedupe(root)
	local fixed = 0
	local function walk(node)
		local byName = {}
		for _, child in ipairs(sorted(node)) do
			byName[child.Name] = byName[child.Name] or {}
			table.insert(byName[child.Name], child)
		end
		for name, group in pairs(byName) do
			if #group > 1 then
				for i, child in ipairs(group) do
					child.Name = name .. "_" .. pad(i)
					fixed += 1
				end
			end
		end
		for _, child in ipairs(node:GetChildren()) do
			if #child:GetChildren() > 0 then
				walk(child)
			end
		end
	end
	walk(root)
	note("deduped %d objects with duplicate sibling names", fixed)
end

local function reorganize()
	local map = ensureFolder(Workspace, "Map")
	local structures = ensureFolder(map, "Structures")
	local scenery = ensureFolder(map, "Scenery")
	local lighting = ensureFolder(map, "Lighting")

	-- Structures: EquipmentHut (west) and the spawn gazebo (east).
	local hut = Workspace:FindFirstChild("EquipmentHut") or structures:FindFirstChild("EquipmentHut")
	if hut then
		hut.Parent = structures
		convert(hut:FindFirstChild("WoodWallOutline"), "Folder", "WallFrame")
		local wallFrame = hut:FindFirstChild("WallFrame")
		if wallFrame then
			renameAll(wallFrame, "Beam")
		end
		local wood = hut:FindFirstChild("Wood")
		if wood then
			wood.Name = "WoodPile"
			renameAll(wood, "Log")
		end
		convert(hut:FindFirstChild("Spears"), "Folder", "Spears")
		local spears = hut:FindFirstChild("Spears")
		if spears then
			renameAll(spears, "Spear")
		end
		local windows = hut:FindFirstChild("Windows")
		if windows then
			renameAll(windows, "Window")
		end
	else
		missing("Workspace.EquipmentHut")
	end

	local gazebo = Workspace:FindFirstChild("Spawn") or structures:FindFirstChild("SpawnGazebo")
	if gazebo then
		gazebo.Name = "SpawnGazebo"
		gazebo.Parent = structures
		convert(gazebo:FindFirstChild("SpawnPillars"), "Folder", "Pillars")
		local pillars = gazebo:FindFirstChild("Pillars")
		if pillars then
			renameAll(pillars, "Pillar")
		end
		convert(gazebo:FindFirstChild("SpawnBenches"), "Folder", "Benches")
		local benches = gazebo:FindFirstChild("Benches")
		if benches then
			renameAll(benches, "Bench")
		end
		local frame = gazebo:FindFirstChild("Structure")
		if frame then
			frame.Name = "Frame"
		end
	else
		missing("Workspace.Spawn")
	end

	-- Pond: rename the inner basin first so the parent can take the name "Pond".
	local pond = Workspace:FindFirstChild("PondDecoration") or map:FindFirstChild("Pond")
	if pond then
		local basin = pond:FindFirstChild("Pond")
		if basin then
			basin.Name = "Basin"
		end
		pond.Name = "Pond"
		pond.Parent = map

		convert(pond:FindFirstChild("PondRocks"), "Folder", "Rocks")
		local rocks = pond:FindFirstChild("Rocks")
		if rocks then
			-- Each rock was a Model wrapping exactly one MeshPart; unwrap them.
			local i = 0
			for _, wrapper in ipairs(sorted(rocks)) do
				if wrapper:IsA("Model") and #wrapper:GetChildren() == 1 then
					local inner = wrapper:FindFirstChildWhichIsA("BasePart")
					if inner then
						i += 1
						inner.Name = "PondRock_" .. pad(i)
						inner.Parent = rocks
						wrapper:Destroy()
					end
				end
			end
			note("unwrapped %d single-part rock models", i)
			if i == 0 then
				renameAll(rocks, "PondRock")
			end
		end

		convert(pond:FindFirstChild("PondGrass"), "Folder", "Reeds")
		local reeds = pond:FindFirstChild("Reeds")
		if reeds then
			renameAll(reeds, "Reed")
		end

		convert(pond:FindFirstChild("PondBenches"), "Folder", "Benches")
		local pondBenches = pond:FindFirstChild("Benches")
		if pondBenches then
			renameAll(pondBenches, "Bench")
		end
	else
		missing("Workspace.PondDecoration")
	end

	-- Scenery: trees, perimeter hedges, pond path.
	local trees = Workspace:FindFirstChild("Trees") or scenery:FindFirstChild("Trees")
	if trees then
		trees.Parent = scenery
		renameGrouped(trees)
	else
		missing("Workspace.Trees")
	end

	local hedges = Workspace:FindFirstChild("Hedges")
	if hedges then
		hedges = convert(hedges, "Folder", "PerimeterHedges")
		hedges.Parent = scenery
		renameAll(hedges, "Hedge")
	elseif not scenery:FindFirstChild("PerimeterHedges") then
		missing("Workspace.Hedges")
	end

	local path = Workspace:FindFirstChild("PondPath") or scenery:FindFirstChild("PondPath")
	if path then
		path.Parent = scenery
		renameAll(path, "PathStone")
	else
		missing("Workspace.PondPath")
	end

	-- Lighting.
	local posts = Workspace:FindFirstChild("LightPosts") or lighting:FindFirstChild("LampPosts")
	if posts then
		posts.Name = "LampPosts"
		posts.Parent = lighting
		renameAll(posts, "LampPost")
	else
		missing("Workspace.LightPosts")
	end

	dedupe(map)
end

local recording
local ok = pcall(function()
	recording = ChangeHistoryService:TryBeginRecording("Reorganize Workspace")
end)

local success, err = pcall(reorganize)

if ok and recording then
	pcall(function()
		ChangeHistoryService:FinishRecording(
			recording,
			success and Enum.FinishRecordingOperation.Commit or Enum.FinishRecordingOperation.Cancel
		)
	end)
end

for _, line in ipairs(log) do
	print("[reorg] " .. line)
end

if success then
	print(string.format("[reorg] DONE. Workspace now has %d top-level children.", #Workspace:GetChildren()))
else
	warn("[reorg] FAILED: " .. tostring(err))
end
