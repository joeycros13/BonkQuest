-- obelisk_carving.luau (2026-10-29): carves the tomb's clue on World 4's Obelisk_3 (Edit mode, execute_luau): a sun,
-- the obelisk, its shadow running off to one side and a little figure sinking with its arms up where the shadow ends,
-- inside a carved border. Thin darker parts lying on the shaft's lower front face (the face toward the quicksand), in
-- the model `Carving` inside Obelisk_3. Re-running replaces it.
local ob = workspace.Worlds.W04_ScorchingSands.Decorations.Ruins.Obelisks.Obelisk_3
local old = ob:FindFirstChild("Carving")
if old then
	old:Destroy()
end
local carving = Instance.new("Model")
carving.Name = "Carving"
carving.Parent = ob

local INK = Color3.fromHex("a5824f")
local cf = ob:GetPivot()
local n = cf.LookVector -- the face toward the quicksand
local base = Vector3.new(cf.Position.X, 0, cf.Position.Z)
-- the shaft's face: 1.589 out at y 11, leaning in 0.028 a stud as it rises (measured with rays)
local function out(v: number): number
	return 1.589 - (v - 11) * 0.028
end
local right = (-n):Cross(Vector3.yAxis).Unit -- a viewer's right, facing the carving
local up = (Vector3.yAxis - n * 0.028).Unit -- along the face, leaning with it
local outward = up:Cross(right).Unit
if outward:Dot(n) < 0 then
	outward = -outward
end
local DEPTH, LIFT = 0.05, 0.02

local function at(u: number, v: number): Vector3
	return base + Vector3.new(0, v, 0) + n * (out(v) + LIFT + DEPTH / 2) + right * u
end

local function part(name: string, size: Vector3, frame: CFrame)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = frame
	p.Color = INK
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Parent = carving
	return p
end

local function line(u1: number, v1: number, u2: number, v2: number, w: number?)
	local a, b = at(u1, v1), at(u2, v2)
	local dir = (right * (u2 - u1) + up * (v2 - v1)).Unit
	local side = outward:Cross(dir).Unit
	local len = (b - a).Magnitude + (w or 0.08)
	part("Line", Vector3.new(len, w or 0.08, DEPTH), CFrame.fromMatrix((a + b) / 2, dir, side))
end

local function disc(u: number, v: number, r: number)
	local p = part("Disc", Vector3.new(DEPTH, r * 2, r * 2), CFrame.fromMatrix(at(u, v), outward, up))
	p.Shape = Enum.PartType.Cylinder
end

-- the border
line(-1.25, 11.25, 1.25, 11.25)
line(-1.25, 15.5, 1.25, 15.5)
line(-1.25, 11.25, -1.25, 15.5)
line(1.25, 11.25, 1.25, 15.5)
-- the sun and its rays
disc(0.6, 14.85, 0.26)
for k = 0, 5 do
	local a = math.rad(k * 60 + 30)
	line(0.6 + math.cos(a) * 0.36, 14.85 + math.sin(a) * 0.36, 0.6 + math.cos(a) * 0.5, 14.85 + math.sin(a) * 0.5, 0.06)
end
-- the obelisk
line(0.42, 12.2, 0.48, 13.9)
line(0.82, 12.2, 0.76, 13.9)
line(0.48, 13.9, 0.62, 14.22)
line(0.76, 13.9, 0.62, 14.22)
line(0.3, 12.15, 0.94, 12.15)
-- its shadow, off to the left
line(0.3, 12.15, -0.95, 12.15, 0.1)
-- the figure sinking at the shadow's end: a head above the ground line, arms up
disc(-0.95, 12.55, 0.13)
line(-1.04, 12.4, -1.17, 12.85, 0.06)
line(-0.86, 12.4, -0.73, 12.85, 0.06)
-- the sand swirling round it
line(-1.2, 11.95, -1.02, 11.9, 0.06)
line(-0.88, 11.9, -0.7, 11.95, 0.06)
line(-1.08, 11.7, -0.82, 11.7, 0.06)
return #carving:GetChildren() .. " pieces"
