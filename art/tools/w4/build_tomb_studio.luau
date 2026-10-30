-- build_tomb_studio.luau (2026-10-29): builds World 4's secret tomb v2 in Studio (Edit mode, execute_luau) from
-- src/shared/DevData/W4Tomb.luau, which art/tools/w4/build_tomb.py writes. It clears the old shell
-- (Ground/SecretTomb) and the old traps, checkpoints, torches, clutter and Eyes, lays the new walls, floors, stairs,
-- tunnel and chamber, places every trap from the ServerStorage/Assets/TombTraps templates (Blender meshes) with
-- the attributes Config/Tomb reads, and moves the landing, the chamber's contents, the zones and the Phantom
-- Pharaoh's marker into the new layout (once: the tomb folder's LayoutV2 attribute).
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local CS = game:GetService("CollectionService")

local D = require(RS.Shared.DevData.W4Tomb:Clone())
local O = Vector3.new(D.origin[1], D.origin[2], D.origin[3])
local function L(v): Vector3
	return O + Vector3.new(v[1], v[2], v[3])
end

local w4 = workspace.Worlds.W04_ScorchingSands
local ground = w4.Ground.SecretTomb
local tomb = w4.Structures.SecretTomb
local TT = SS.Assets.TombTraps

-- templates kept from v1: a torch facing +Z and a checkpoint plate
if not TT:FindFirstChild("Torch") then
	for _, t in tomb.Torches:GetChildren() do
		local p = t:GetPivot().Position - O
		if math.abs(p.Z - 1.4) < 0.05 then
			local c = t:Clone()
			c.Parent = TT
			break
		end
	end
end
if not TT:FindFirstChild("Checkpoint") then
	local c = tomb.Checkpoints:FindFirstChild("Checkpoint1"):Clone()
	c.Name = "Checkpoint"
	c.Parent = TT
end
local effects = RS.Assets.Effects
if not effects:FindFirstChild("TombDart") then
	local dart = TT.Dart:Clone()
	dart.Name = "TombDart"
	dart.Parent = effects
end

-- clear the old layout
for _, c in ground:GetChildren() do
	c:Destroy()
end
for _, name in { "Traps", "Checkpoints", "Torches", "Eyes", "Clutter" } do
	local f = tomb:FindFirstChild(name)
	if f then
		f:Destroy()
	end
end
local function folder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f :: Folder
end

local function part(name: string, size: Vector3, cf: CFrame, color: string?, parent: Instance, solid: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	if color then
		p.Color = Color3.fromHex(color)
	else
		p.Transparency = 1
		p.CastShadow = false
	end
	p.CanCollide = solid == true
	p.CanQuery = solid == true
	p.CanTouch = false
	p.Parent = parent
	return p
end

-- the shell
for _, b in D.boxes do
	local solid = b.f ~= "Bands" and b.n ~= "Rim"
	part(b.n, Vector3.new(b.s[1], b.s[2], b.s[3]), CFrame.new(L(b.c)), b.col, folder(ground, b.f), solid)
end

-- the traps
local traps = folder(tomb, "Traps")
local function trapModel(item): (Model, CFrame)
	local m = Instance.new("Model")
	m.Name = item.kind .. "_" .. item.n
	m:SetAttribute("Kind", item.kind)
	m:SetAttribute("Cell", item.r .. "," .. item.c)
	m.Parent = traps
	return m, CFrame.new(L(item.pos)) * CFrame.Angles(0, math.rad(item.yaw), 0)
end
local function clone(name: string, cf: CFrame, parent: Instance, as: string?): Model
	local c = TT[name]:Clone()
	c.Name = as or name
	c:PivotTo(cf)
	c.Parent = parent
	return c
end
local WALL_H = D.wallH

for _, item in D.traps do
	local m, cf = trapModel(item)
	local kind = item.kind
	if kind == "Saw" then
		m:SetAttribute("Period", item.period)
		m:SetAttribute("Offset", item.offset)
		m:SetAttribute("Range", 2.4)
		m:SetAttribute("Radius", 2.2)
		m:SetAttribute("Spin", 14)
		m:SetAttribute("Damage", 0.2)
		part("Pivot", Vector3.new(1, 0.2, 1), cf, nil, m)
		clone("BuzzsawTrack", cf, m, "Track")
		clone("Buzzsaw", cf, m, "Saw")
		part("Zone", Vector3.new(8, 6, 3), cf * CFrame.new(0, 3, 0), nil, m)
	elseif kind == "Blade" then
		m:SetAttribute("Period", item.period)
		m:SetAttribute("Offset", item.offset)
		m:SetAttribute("Amplitude", 16)
		m:SetAttribute("Length", 7.35)
		m:SetAttribute("Radius", 2.2)
		m:SetAttribute("Damage", 0.2)
		local pivot = cf * CFrame.new(0, WALL_H, 0)
		part("Pivot", Vector3.new(0.5, 0.5, 0.5), pivot, nil, m)
		clone("SwingAxe", pivot, m, "Axe")
		part("Zone", Vector3.new(8, 7, 3), cf * CFrame.new(0, 3.5, 0), nil, m)
	elseif kind == "Fire" then
		m:SetAttribute("Period", item.period)
		m:SetAttribute("Offset", item.offset)
		m:SetAttribute("OnFrom", 0.55)
		m:SetAttribute("OnTo", 0.85)
		m:SetAttribute("Warn", 0.4)
		m:SetAttribute("Side", item.side)
		m:SetAttribute("Damage", 0.2)
		local head = CFrame.new(L(item.wall) + Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, math.rad(item.face), 0)
		clone("JackalHead", head, m, "Jackal")
		local mouth = (head * CFrame.new(0, 1.22, -2.61)).Position
		local fwd = head.LookVector
		local flame = part("Flame", Vector3.new(1.5, 1.5, 5.2), CFrame.lookAt(mouth + fwd * 2.65, mouth + fwd * 4), "ff7a1a", m)
		flame.Material = Enum.Material.Neon
		flame.Transparency = 1
		flame.CastShadow = false
		local core = part("FlameCore", Vector3.new(0.7, 0.7, 5), CFrame.lookAt(mouth + fwd * 2.55, mouth + fwd * 4), "ffd34d", m)
		core.Material = Enum.Material.Neon
		core.Transparency = 1
		core.CastShadow = false
		part("Zone", Vector3.new(8, 4.5, 2.6), cf * CFrame.new(0, 3.75, 0), nil, m)
	elseif kind == "Darts" then
		m:SetAttribute("Side", item.side)
		m:SetAttribute("Damage", 0.15)
		if item.beat then
			m:SetAttribute("Period", item.period)
			m:SetAttribute("Offset", item.offset)
			m:SetAttribute("Delay", 0.35)
		else
			m:SetAttribute("Delay", 0.15)
			m:SetAttribute("Rearm", 2)
			for _, z in { -3.8, 3.8 } do
				part("Plate", Vector3.new(7.8, 0.1, 2), cf * CFrame.new(0, 0.05, z), "b8925a", m)
			end
		end
		local panel = CFrame.new(L(item.wall) + Vector3.new(0, 0.66, 0)) * CFrame.Angles(0, math.rad(item.face), 0)
		clone("DartPanel", panel, m, "Panel")
		for _, h in { 0.83, 1.58, 2.33 } do
			part("Hole", Vector3.new(0.1, 0.1, 0.1), panel * CFrame.new(0, h, -0.66), nil, m)
		end
		part("Zone", Vector3.new(8, 4, 3), cf * CFrame.new(0, 2, 0), nil, m)
	elseif kind == "Spikes" then
		m:SetAttribute("Period", item.period)
		m:SetAttribute("Offset", item.offset)
		m:SetAttribute("OnFrom", 0.62)
		m:SetAttribute("OnTo", 0.9)
		m:SetAttribute("Warn", 0.45)
		m:SetAttribute("Damage", 0.15)
		local spikes = Instance.new("Model")
		spikes.Name = "Spikes"
		spikes.Parent = m
		for _, dx in { -2, 2 } do
			for _, dz in { -2, 2 } do
				local tile = clone("SpikeTile", cf * CFrame.new(dx, 0, dz), m, "Tile")
				tile.Spikes.Parent = spikes
			end
		end
		part("Zone", Vector3.new(8, 5, 8), cf * CFrame.new(0, 2.5, 0), nil, m)
	elseif kind == "Collapse" then
		m:SetAttribute("Hold", 0.3)
		for row = 0, 3 do
			for col = 0, 3 do
				local safe = item.safe[row + 1] == col
				local at = cf * CFrame.new(-3 + col * 2, 0.05, -3.75 + row * 2.5)
				-- a cracked tile is only a shade darker with one thin crack: look before you step
				local tile = part(if safe then "Tile" else "Cracked", Vector3.new(1.96, 0.1, 2.46), at, if safe then "c4a378" else "b8955f", m)
				if not safe then
					local crack = part("Crack", Vector3.new(0.06, 0.02, 2.1), at * CFrame.new(0, 0.06, 0) * CFrame.Angles(0, math.rad(if (row + col) % 2 == 0 then 32 else -38), 0), "7a5a36", tile)
					crack.CastShadow = false
				end
			end
		end
	elseif kind == "Lava" then
		m:SetAttribute("Damage", 0.2)
		local h = item.hole
		local x0, x1, z0, z1 = h[1], h[2], h[3], h[4]
		local lava = part("Lava", Vector3.new(x1 - x0, 2.4, z1 - z0), CFrame.new(L({ (x0 + x1) / 2, -2.8, (z0 + z1) / 2 })), "ff4d1a", m, true)
		lava.Material = Enum.Material.Neon
		local light = Instance.new("PointLight")
		light.Color = Color3.fromHex("ff7a2a")
		light.Range = 16
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = lava
		local bx, bz = (x0 + x1) / 2, (z0 + z1) / 2
		local size
		if item.axis == "z" then
			bx += item.beam
			size = Vector3.new(1.4, 4, z1 - z0)
		else
			bz += item.beam
			size = Vector3.new(x1 - x0, 4, 1.4)
		end
		part("Beam", size, CFrame.new(L({ bx, -2, bz })), "8f7656", m, true)
		part("Zone", Vector3.new(x1 - x0, 5.8, z1 - z0), CFrame.new(L({ (x0 + x1) / 2, -1.1, (z0 + z1) / 2 })), nil, m)
	end
	CS:AddTag(m, "TombTrap")
end

-- the boulder in the tunnel
do
	local b = D.boulder
	local m = Instance.new("Model")
	m.Name = "Boulder"
	m:SetAttribute("Kind", "Boulder")
	m:SetAttribute("Period", 6.5)
	m:SetAttribute("Roll", 3.6)
	m:SetAttribute("Radius", 3.3)
	m:SetAttribute("Damage", 0.2)
	m:SetAttribute("ResetTo", 7)
	m.Parent = traps
	part("Start", Vector3.new(1, 1, 1), CFrame.new(L(b.start)), nil, m)
	part("End", Vector3.new(1, 1, 1), CFrame.new(L(b.finish)), nil, m)
	local ball = TT.TombBoulder.Rock:Clone()
	ball.Name = "Ball"
	ball.CFrame = CFrame.new(L(b.start))
	ball.Transparency = 1
	ball.Parent = m
	local z = b.zone
	part("Zone", Vector3.new(z[2] - z[1], 10, z[4] - z[3]), CFrame.new(L({ (z[1] + z[2]) / 2, D.low + 5, (z[3] + z[4]) / 2 })), nil, m)
	CS:AddTag(m, "TombTrap")
end

-- checkpoints, torches, clutter
local cps = folder(tomb, "Checkpoints")
local cpRot = TT.Checkpoint:GetPivot().Rotation
for _, c in D.checkpoints do
	local cp = TT.Checkpoint:Clone()
	cp.Name = "Checkpoint" .. c.index
	cp:SetAttribute("Index", c.index)
	cp:PivotTo(CFrame.new(L(c.pos) + Vector3.new(0, 0.1, 0)) * cpRot)
	cp.Parent = cps
	CS:AddTag(cp, "TombCheckpoint")
end
-- torchlight, not daylight: dim, short lights and an ambience zone with the outdoor haze off
local torchLight = TT.Torch:FindFirstChild("PointLight", true)
if torchLight then
	torchLight.Brightness = 0.6
	torchLight.Range = 16
end
for _, z in { tomb.Zones.MazeAmbience, tomb.Zones.ChamberAmbience } do
	z:SetAttribute("ExposureCompensation", -0.2)
	z:SetAttribute("AtmosphereDensity", 0)
	z:SetAttribute("AtmosphereHaze", 0)
	z:SetAttribute("AtmosphereGlare", 0)
end
tomb.Zones.MazeAmbience:SetAttribute("Ambient", Color3.fromHex("3a3542"))
tomb.Zones.MazeAmbience:SetAttribute("OutdoorAmbient", Color3.fromHex("3a3542"))
tomb.Zones.MazeAmbience:SetAttribute("Brightness", 0)
local torches = folder(tomb, "Torches")
local torchRot = TT.Torch:GetPivot().Rotation
for _, t in D.torches do
	local tc = TT.Torch:Clone()
	tc:PivotTo(CFrame.new(L(t.pos)) * CFrame.Angles(0, math.atan2(t.face[1], t.face[2]), 0) * torchRot)
	tc.Parent = torches
end
local clutter = folder(tomb, "Clutter")
for _, c in D.clutter do
	clone(c.name, CFrame.new(L(c.pos)) * CFrame.Angles(0, math.rad(c.yaw), 0), clutter)
end

-- move the landing, the chamber's contents, the zones and the Phantom Pharaoh (once)
if not tomb:GetAttribute("LayoutV2") then
	local delta = Vector3.new(D.chamberDelta[1], D.chamberDelta[2], D.chamberDelta[3])
	local function shift(inst: Instance)
		if inst:IsA("Model") then
			inst:PivotTo(inst:GetPivot() + delta)
		elseif inst:IsA("BasePart") then
			inst.CFrame = inst.CFrame + delta
		elseif inst:IsA("Folder") then
			for _, c in inst:GetChildren() do
				shift(c)
			end
		end
	end
	shift(tomb.Chamber)
	shift(tomb.Zones.ChamberAmbience)
	shift(tomb.Zones.ChamberZone)
	shift(w4.Spawns.EnemySpawns.PhantomPharaoh_01)
	local land = tomb.Landing
	local lc = L(D.landing)
	land.Landing.CFrame = CFrame.new(lc + Vector3.new(-2, 0.1, 0))
	land.Sandfall.CFrame = CFrame.new(lc + Vector3.new(-2.5, D.wallH - 0.3, -2))
	land.SandPile.CFrame = CFrame.new(lc + Vector3.new(-2.5, 0.2, -2)) * land.SandPile.CFrame.Rotation
	land.SandPileTop.CFrame = CFrame.new(lc + Vector3.new(-2.5, 0.9, -2)) * land.SandPileTop.CFrame.Rotation
	local tab = land.ShortcutTablet
	local was = tab:GetPivot()
	tab:PivotTo(CFrame.new(O + Vector3.new(D.tablet[1], was.Position.Y - O.Y, D.tablet[2])) * CFrame.Angles(0, math.pi, 0) * was.Rotation)
	tomb:SetAttribute("LayoutV2", true)
end
local mz = D.mazeZone
local amb = tomb.Zones.MazeAmbience
amb.Size = Vector3.new(mz[2] - mz[1], mz[4] - mz[3], mz[6] - mz[5])
amb.CFrame = CFrame.new(L({ (mz[1] + mz[2]) / 2, (mz[3] + mz[4]) / 2, (mz[5] + mz[6]) / 2 }))

local n = 0
for _, d in ground:GetDescendants() do
	if d:IsA("BasePart") then
		n += 1
	end
end
local t = 0
for _, d in tomb:GetDescendants() do
	if d:IsA("BasePart") then
		t += 1
	end
end
return ("shell %d parts, structures %d parts, traps %d"):format(n, t, #traps:GetChildren())
