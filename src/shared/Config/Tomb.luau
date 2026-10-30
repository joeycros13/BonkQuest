--!strict
-- Tomb: World 4's secret tomb (2026-10-29, the user's design on
-- https://claude.ai/artifact/29us8FDHD1zBP9Nw9WRBnE). The quicksand at Obelisk_3's shadow tip (a
-- PortalService charge zone) drops you into a 17 x 17 maze full of traps (built by art/tools/w4/build_tomb.py
-- and build_tomb_studio.luau). Its goal, the sanctum in the middle, stands on its own island of walls, so
-- following one wall never finds it; stairs there lead down to the boulder tunnel and the Phantom Pharaoh's
-- burial chamber, and once you've reached the chamber a tablet at the landing offers the shortcut.
--
-- Every trap's timing is a formula of the server clock (workspace:GetServerTimeNow()), so the server
-- (TombService: hits, checkpoints, the shortcut) and every client (TombController: the animation) agree
-- without sending anything. A trap is a Model tagged TombTrap; its Kind attribute says which, the rest
-- of its attributes tune it:
--   Spikes    Period, Offset, OnFrom / OnTo (the share of the period they're up), Warn (when they rattle),
--             Damage; Zone (the cell), the Spikes model (the spike meshes, moved down into the floor)
--   Fire      the same timing, Side (+1 / -1: the wall the jackal head is on), Damage; Zone (the jet's
--             band), the Jackal model (its Eyes glow before it breathes), Flame, FlameCore
--   Blade     Period, Offset, Amplitude (degrees), Length (pivot to blade), Radius, Damage; Pivot (the
--             swing's centre: it swings about its Z axis, across the corridor), the Axe model
--   Saw       Period, Offset, Range (studs either side of the middle), Radius, Damage; Pivot (the slot's
--             middle on the floor, its X across the corridor), the Saw model (spun and slid along X)
--   Darts     Delay (plate or beat to volley), Rearm, Side, Damage, and either Plate parts (stepped on) or a
--             Period (fires on the beat); Zone, Hole parts. The server sets the model's FiredAt attribute
--             (the volley's server time)
--   Lava      Damage; Zone (the pit, up to just under a walker's middle). Falling in hurts and sends you
--             back to your checkpoint; the Beam across it is safe
--   Collapse  Hold (seconds standing on a cracked tile before it gives); Cracked tiles. Sends you back
--             to your checkpoint, no damage
--   Boulder   Period, Roll (seconds it rolls), Radius, Damage, ResetTo (the checkpoint a hit sends you
--             back to); Zone (the tunnel's lane: the alcoves are outside it), Start, End, Ball
-- Damage is a share of max health.

local Tomb = {}

Tomb.TRAP_TAG = "TombTrap"
Tomb.CHECKPOINT_TAG = "TombCheckpoint"
-- a player's last checkpoint (1 = the landing), set while they're in the tomb
Tomb.CHECKPOINT_ATTR = "TombCheckpoint"
-- saved: they have reached the burial chamber, so the shortcut tablet is theirs
Tomb.FOUND_ATTR = "TombFound"
-- the same trap can't hurt the same player again sooner than this
Tomb.HIT_COOLDOWN = 1

local function num(model: Instance, name: string, fallback: number): number
	local v = model:GetAttribute(name)
	return if type(v) == "number" then v else fallback
end
Tomb.num = num

-- How far through its cycle a timed trap is at server time t (0..1).
function Tomb.phase(model: Instance, t: number): number
	local period = num(model, "Period", 3)
	return ((t + num(model, "Offset", 0)) % period) / period
end

-- Spikes up / fire on.
function Tomb.active(model: Instance, t: number): boolean
	local p = Tomb.phase(model, t)
	return p >= num(model, "OnFrom", 0.6) and p < num(model, "OnTo", 0.9)
end

-- The warning just before: spikes rattle, the jackal's eyes glow.
function Tomb.warning(model: Instance, t: number): boolean
	local p = Tomb.phase(model, t)
	return p >= num(model, "Warn", 0.45) and p < num(model, "OnFrom", 0.6)
end

-- A blade's swing angle (radians) at t.
function Tomb.bladeAngle(model: Instance, t: number): number
	local period = num(model, "Period", 2.4)
	return math.rad(num(model, "Amplitude", 19)) * math.sin(2 * math.pi * (t + num(model, "Offset", 0)) / period)
end

-- A blade's pivot turned to its angle at t (the arm and blade hang below it).
function Tomb.bladePivot(model: Instance, t: number): CFrame?
	local pivot = model:FindFirstChild("Pivot")
	if not (pivot and pivot:IsA("BasePart")) then
		return nil
	end
	return pivot.CFrame * CFrame.Angles(0, 0, Tomb.bladeAngle(model, t))
end

-- A buzzsaw's offset along its slot (studs across the corridor) and its spin angle at t.
function Tomb.saw(model: Instance, t: number): (number, number)
	local period = num(model, "Period", 2.6)
	local x = num(model, "Range", 2.4) * math.sin(2 * math.pi * (t + num(model, "Offset", 0)) / period)
	return x, (t * num(model, "Spin", 14)) % (2 * math.pi)
end

-- Where the boulder is at t: rolling?, its centre, how far along (0..1) and how far it has rolled (studs).
function Tomb.boulder(model: Instance, t: number): (boolean, Vector3, number, number)
	local start = model:FindFirstChild("Start") :: BasePart?
	local finish = model:FindFirstChild("End") :: BasePart?
	if not (start and finish) then
		return false, Vector3.zero, 0, 0
	end
	local period = num(model, "Period", 6.5)
	local roll = num(model, "Roll", 3.6)
	local into = (t + num(model, "Offset", 0)) % period
	local u = math.clamp(into / roll, 0, 1)
	local a, b = start.Position, finish.Position
	return into < roll, a:Lerp(b, u), u, (b - a).Magnitude * u
end

-- Inside a part's box (a zone, a plate, a tile), with `pad` studs to spare round its sides.
function Tomb.inside(part: BasePart, point: Vector3, pad: number?): boolean
	local p = part.CFrame:PointToObjectSpace(point)
	local h = part.Size / 2
	local e = pad or 0
	return math.abs(p.X) <= h.X + e and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z + e
end

-- Over a flat part (a plate or a tile): within its footprint and no higher than `above` over it.
function Tomb.over(part: BasePart, point: Vector3, above: number, pad: number?): boolean
	local p = part.CFrame:PointToObjectSpace(point)
	local h = part.Size / 2
	local e = pad or 0
	return math.abs(p.X) <= h.X + e and math.abs(p.Z) <= h.Z + e and p.Y >= -1 and p.Y <= above
end

return Tomb
