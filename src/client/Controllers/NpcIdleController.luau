--!strict
-- NpcIdleController: gentle idle animation for decorative NPCs built from parts
-- (the market shopkeepers). Anything tagged AmbientIdle comes alive:
--
--   * breathing: the upper body rises and falls slightly,
--   * looking around: the head turns toward a new direction every few seconds,
--   * relaxed arms: a slow, small sway,
--   * now and then a little action: a friendly wave, or wiping the counter.
--
-- Each part says which body part it moves with through a "Bone" attribute:
--   Torso, Head, LeftArm, RightArm. Parts without one (legs, shoes) stay still.
-- The body is assumed to use classic blocky proportions: a 2x2x1 torso with the
-- neck at its top and the shoulders at its upper corners.
--
-- Optional model attributes:
--   IdleStyle    "Farmer" gives the quest farmer his own idle: a slow weight shift
--                from foot to foot, and the actions hatTip (hand to the brim and a
--                nod), brow (wipes his forehead) and stamp (lifts the pitchfork and
--                thumps it down). "Ranger" (Ranger Rowan, 2026-10-11): the same
--                weight shift with the lantern arm steady, and the actions scan
--                (a hand shading the eyes while the head sweeps the treeline),
--                raise (lifts the lantern to peer) and hatTip.
--                The stall keepers (2026-10-13, one each):
--                  "Farrier"    (W1 Weaponsmith) weight shift; hammer (taps an
--                               invisible shoe on the anvil), inspect (holds a
--                               shoe up to the eye), dust (brushes the apron).
--                  "Tailor"     (W1 Crafter) the raised needle arm stays steady;
--                               stitch (pulls the thread through), measure
--                               (arms out wide, eyeing each hand), thread
--                               (needle up to the eye, the other hand meets it).
--                  "Lumberjack" (W2 Weaponsmith) a heavier weight shift; stretch
--                               (both arms overhead, head back), beard (strokes
--                               his beard), flex (arms out, pumping).
--                  "Trapper"    (W2 Crafter) quick, wide glances; sniff (nose up,
--                               testing the air), crouch (stoops to read tracks),
--                               rummage (digs in a belt pouch).
--                  "Miner"      (W3 Weaponsmith) lampTap (taps the headlamp on his
--                               hard hat), shoulder (reaches back to settle the
--                               pickaxe), dust (brushes off the overalls).
--                  "Gemcutter"  (W3 Crafter) a calm, small shift; loupe (fingers
--                               the loupe and peers), polish (holds a gem up and
--                               rubs it), pouch (picks through the hip pouch).
--                  "Explorer"   (Explorer Pip, the W3 quest giver, 2026-10-17) the
--                               map arm stays steady; compass (holds the compass
--                               up and reads it, turning to get a bearing),
--                               glasses (pushes the round glasses up his nose),
--                               study (peers down at the map in his right hand,
--                               tracing the route).
--                  "Sensei"     (the Upgrades stand keeper, 2026-10-19) a calm, small
--                               shift with the staff arm steady and slow glances;
--                               stroke (the free hand strokes the long beard down),
--                               bow (a slow, respectful bow from the hips) and stamp
--                               (lifts the staff and thumps it down).
--                  "Wrapper"    (the Daily Rewards gift wrapper, 2026-10-20) a light shift
--                               with the spool arm steady; unspool (the free hand draws
--                               ribbon out from the spool, twice, eyes on it), beret
--                               (straightens the beret with a little wiggle) and pat (two
--                               pats on the apron pocket).
--                  "Archaeologist" (Professor Dusty, the W4 quest giver, 2026-10-29) the
--                               left arm rests raised with the magnifying glass, the
--                               brush in the right fist; peer (the glass up to the eye,
--                               leaning in and looking along something), brush (dusts
--                               a find in front of him, eyes down) and ponder (taps
--                               the brush handle on his chin, head tilted).
--                Default style: the shopkeepers' wave / wipe.
--   IdleActions  a comma list restricting the actions; "" means none.
--   HandPoint    Vector3, the torso-local fist of the right hand. Parts with
--                Bone = "Tool" (a held pitchfork) follow that point but keep
--                their own orientation, so a planted tool stays upright.
--
-- Purely decorative, so it runs on each player's client: nothing is replicated.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapLayout = require(Shared:WaitForChild("Config"):WaitForChild("MapLayout"))

local NpcIdleController = {}

local deps: any = nil

-- ==================== tuning ====================

local BREATH_RATE = 1.7
local BREATH_LIFT = 0.03
local WEIGHT_SHIFT = 0.025 -- radians the farmer / ranger rock from foot to foot
local LOOK_MIN, LOOK_MAX = 2, 5 -- seconds between glances
local LOOK_ANGLES = { -0.5, -0.25, 0, 0, 0.3, 0.45 } -- radians of head turn
local ACTION_MIN, ACTION_MAX = 6, 12 -- seconds between little actions
local CULL_DISTANCE = 180

-- ==================== state ====================

type PartInfo = { part: BasePart, rest: CFrame, bone: string? }

type Npc = {
	model: Model,
	parts: { PartInfo },
	frame: CFrame, -- torso centre at rest
	phase: number,
	-- head look
	headYaw: number,
	headTarget: number,
	nextLook: number,
	-- actions
	action: string?,
	actionStart: number,
	nextAction: number,
	actions: { string },
	style: string?,
	hand: Vector3?,
}

local npcs: { [Model]: Npc } = {}
local rng = Random.new()

local NECK = Vector3.new(0, 1, 0)
local SHOULDER_L = Vector3.new(-1.5, 0.75, 0)
local SHOULDER_R = Vector3.new(1.5, 0.75, 0)

local function adopt(inst: Instance)
	if not inst:IsA("Model") or npcs[inst] then
		return
	end
	local torso = inst:FindFirstChild("Torso")
	if not (torso and torso:IsA("BasePart")) then
		return
	end
	local frame = torso.CFrame
	local parts: { PartInfo } = {}
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			local bone = d:GetAttribute("Bone")
			table.insert(parts, {
				part = d,
				rest = frame:ToObjectSpace(d.CFrame),
				bone = if type(bone) == "string" then bone else nil,
			})
		end
	end
	local now = os.clock()
	local styleAttr = inst:GetAttribute("IdleStyle")
	local style = if type(styleAttr) == "string" then styleAttr else nil
	local actions = if style == "Farmer" then { "hatTip", "brow", "stamp" }
		elseif style == "Ranger" then { "scan", "raise", "hatTip" }
		elseif style == "Farrier" then { "hammer", "inspect", "dust" }
		elseif style == "Tailor" then { "stitch", "measure", "thread" }
		elseif style == "Lumberjack" then { "stretch", "beard", "flex" }
		elseif style == "Trapper" then { "sniff", "crouch", "rummage" }
		elseif style == "Miner" then { "lampTap", "shoulder", "dust" }
		elseif style == "Gemcutter" then { "loupe", "polish", "pouch" }
		elseif style == "Explorer" then { "compass", "glasses", "study" }
		elseif style == "Sensei" then { "stroke", "bow", "stamp" }
		elseif style == "Wrapper" then { "unspool", "beret", "pat" }
		elseif style == "Archaeologist" then { "peer", "brush", "ponder" }
		else { "wave", "wipe" }
	local handAttr = inst:GetAttribute("HandPoint")
	local listed = inst:GetAttribute("IdleActions")
	if type(listed) == "string" then
		actions = {}
		for name in string.gmatch(listed, "[^,%s]+") do
			table.insert(actions, name)
		end
	end
	npcs[inst] = {
		model = inst,
		parts = parts,
		frame = frame,
		phase = rng:NextNumber(0, math.pi * 2),
		headYaw = 0,
		headTarget = 0,
		nextLook = now + rng:NextNumber(LOOK_MIN, LOOK_MAX),
		action = nil,
		actionStart = 0,
		nextAction = now + rng:NextNumber(ACTION_MIN, ACTION_MAX),
		actions = actions,
		style = style,
		hand = if typeof(handAttr) == "Vector3" then handAttr else nil,
	}
end

local function release(inst: Instance)
	local npc = npcs[inst :: Model]
	if npc then
		for _, p in npc.parts do
			p.part.CFrame = npc.frame * p.rest
		end
		npcs[inst :: Model] = nil
	end
end

-- 0 -> 1 -> 0 across u in [0, 1].
local function bump(u: number): number
	return math.sin(math.clamp(u, 0, 1) * math.pi)
end

local function about(pivot: Vector3, rot: CFrame): CFrame
	return CFrame.new(pivot) * rot * CFrame.new(-pivot)
end

-- Rises to 1, holds, falls back: a gesture that stays at its peak for a while.
local function plateau(u: number): number
	return math.min(1, bump(u) * 1.6)
end

-- How long each action lasts, in seconds.
local ACTION_SECONDS: { [string]: number } = {
	wave = 1.8, wipe = 2.4, hatTip = 2.2, brow = 2.6, stamp = 1.3, scan = 3.4, raise = 1.8,
	hammer = 2.4, inspect = 2.6, dust = 1.6, -- Farrier
	stitch = 2.8, measure = 2.4, thread = 2.6, -- Tailor
	stretch = 2.6, beard = 2.4, flex = 2.0, -- Lumberjack
	sniff = 2.4, crouch = 2.2, rummage = 2.4, -- Trapper
	lampTap = 2.2, shoulder = 2.4, -- Miner (+ dust)
	loupe = 2.8, polish = 2.6, pouch = 2.4, -- Gemcutter
	compass = 3.0, glasses = 1.8, study = 3.2, -- Explorer
	stroke = 2.8, bow = 2.6, -- Sensei (+ stamp)
	unspool = 2.8, beret = 2.2, pat = 1.8, -- Wrapper
	peer = 3.0, brush = 2.6, ponder = 2.4, -- Archaeologist
}

-- Per-style base motion: a weight shift (radians), whether the right arm holds still (a held
-- tool), and how often / how far the head glances around.
local STYLE_BASE: { [string]: { shift: number, steadyRight: boolean, lookRate: number, lookScale: number } } = {
	Farmer = { shift = WEIGHT_SHIFT, steadyRight = true, lookRate = 1, lookScale = 1 },
	Ranger = { shift = WEIGHT_SHIFT, steadyRight = true, lookRate = 1, lookScale = 1 },
	Farrier = { shift = WEIGHT_SHIFT, steadyRight = false, lookRate = 1, lookScale = 0.8 },
	Tailor = { shift = 0.012, steadyRight = true, lookRate = 1.2, lookScale = 0.7 },
	Lumberjack = { shift = 0.035, steadyRight = false, lookRate = 0.8, lookScale = 1 },
	Trapper = { shift = 0, steadyRight = false, lookRate = 2, lookScale = 1.4 },
	Miner = { shift = 0.03, steadyRight = false, lookRate = 1, lookScale = 1 },
	Gemcutter = { shift = 0.012, steadyRight = false, lookRate = 0.8, lookScale = 0.7 },
	Explorer = { shift = WEIGHT_SHIFT, steadyRight = true, lookRate = 1.3, lookScale = 1.1 },
	Sensei = { shift = 0.012, steadyRight = true, lookRate = 0.7, lookScale = 0.8 },
	Wrapper = { shift = 0.02, steadyRight = true, lookRate = 1.1, lookScale = 0.9 },
	Archaeologist = { shift = WEIGHT_SHIFT, steadyRight = false, lookRate = 1.1, lookScale = 1 },
}

local function pose(npc: Npc, now: number, dt: number)
	-- choose where to look next
	local base = npc.style and STYLE_BASE[npc.style]
	if now >= npc.nextLook then
		npc.headTarget = LOOK_ANGLES[rng:NextInteger(1, #LOOK_ANGLES)] * (if base then base.lookScale else 1)
		npc.nextLook = now + rng:NextNumber(LOOK_MIN, LOOK_MAX) / (if base then base.lookRate else 1)
	end
	npc.headYaw += (npc.headTarget - npc.headYaw) * math.min(1, dt * 3)

	-- start / finish little actions
	if not npc.action and now >= npc.nextAction and #npc.actions > 0 then
		npc.action = npc.actions[rng:NextInteger(1, #npc.actions)]
		npc.actionStart = now
	end
	local armL, armR, lean = 0, 0, 0 -- arm raise (out to the side) in radians
	local fwdL, fwdR = 0, 0 -- arm swing toward the front
	local nod = 0 -- head tips forward
	local yawExtra = 0 -- extra head turn on top of the glances
	local action = npc.action
	local u = if action then (now - npc.actionStart) / (ACTION_SECONDS[action] or 2) else 0
	if action and u >= 1 then
		npc.action = nil
		npc.nextAction = now + rng:NextNumber(ACTION_MIN, ACTION_MAX)
		action = nil
	end
	if action == "wave" then
		local up = bump(u)
		armR = 2.5 * math.min(1, up * 1.6) + 0.25 * math.sin(now * 14) * up
	elseif action == "wipe" then
		local k = bump(u)
		fwdL, fwdR = 1.2 * k, 1.2 * k
		lean = 0.12 * k
		armL = 0.35 * math.sin(now * 6) * k
		armR = -0.35 * math.sin(now * 6) * k
	elseif action == "hatTip" then
		-- free hand up to the front of the brim, inward, with a small nod mid-way
		local k = plateau(u)
		fwdL = 2.55 * k
		armL = -0.5 * k
		nod = 0.1 * k + 0.14 * bump((u - 0.35) / 0.3)
	elseif action == "brow" then
		-- forearm across the forehead, swiping side to side
		local k = plateau(u)
		fwdL = 2.25 * k
		armL = (-0.2 - 0.4 * (0.5 + 0.5 * math.sin(now * 5))) * k
		nod = 0.15 * k
	elseif action == "stamp" then
		-- lift the pitchfork, then thump it down (the Tool follows the fist)
		local lift = if u < 0.45 then math.sin(u / 0.45 * math.pi / 2) else math.max(0, 1 - (u - 0.45) / 0.1)
		local thump = if u >= 0.55 then bump((u - 0.55) / 0.45) else 0
		fwdR = 0.3 * lift - 0.04 * thump
		lean = 0.05 * lift
	elseif action == "scan" then
		-- free hand flat over the brow, the head sweeping left and right under it
		local k = plateau(u)
		fwdL = 2.35 * k
		armL = -0.35 * k
		nod = 0.05 * k
		yawExtra = 0.55 * math.sin(u * math.pi * 2) * k
	elseif action == "raise" then
		-- lift the lantern a little higher to peer into the dark (the Tool follows the fist)
		local k = bump(u)
		fwdR = 0.35 * k
		lean = -0.03 * k
	-- ---------- Farrier ----------
	elseif action == "hammer" then
		-- raise the hammer hand and tap an (invisible) shoe on the anvil three times, eyes on the work
		local k = plateau(u)
		local tap = (1 - math.cos(u * math.pi * 6)) / 2
		fwdR = (1.0 + 0.8 * tap) * k
		nod = 0.18 * k
		lean = 0.05 * k
	elseif action == "inspect" then
		-- hold a shoe up in front of the eye and turn it over
		local k = plateau(u)
		fwdL = 2.25 * k
		armL = -0.45 * k
		nod = -0.04 * k
		yawExtra = 0.22 * math.sin(u * math.pi * 2) * k
	elseif action == "dust" then
		-- brush both hands down the front of the apron
		local k = bump(u)
		fwdL = (0.4 + 0.25 * math.sin(now * 11)) * k
		fwdR = (0.4 + 0.25 * math.sin(now * 11 + math.pi)) * k
		armL, armR = -0.18 * k, -0.18 * k
		nod = 0.2 * k
	-- ---------- Tailor (the right arm rests raised, holding the needle) ----------
	elseif action == "stitch" then
		-- the left hand holds the cloth out while the needle hand pulls the thread through, three times
		local k = plateau(u)
		local pull = math.max(0, math.sin(u * math.pi * 6))
		fwdL = 0.9 * k
		fwdR = 0.45 * pull * k
		armR = 0.35 * pull * k
		nod = 0.15 * k
	elseif action == "measure" then
		-- arms out wide as if sizing a length of hide, glancing from one hand to the other
		local k = plateau(u)
		armL = 1.25 * k
		armR = 0.9 * k
		fwdL = 0.25 * k
		yawExtra = 0.5 * math.sin(u * math.pi * 2) * k
	elseif action == "thread" then
		-- needle up to the eye, the other hand comes up to meet it, a little fiddle
		local k = plateau(u)
		fwdR = 0.7 * k
		armR = -0.25 * k
		fwdL = (2.0 + 0.05 * math.sin(now * 12)) * k
		armL = -0.3 * k
		nod = -0.08 * k
	-- ---------- Lumberjack ----------
	elseif action == "stretch" then
		-- both arms overhead, leaning back with the head tipped up (a big yawn)
		local k = plateau(u)
		armL, armR = 2.7 * k, 2.7 * k
		lean = -0.08 * k
		nod = -0.2 * k
	elseif action == "beard" then
		-- hand to the chin, stroking the beard down
		local k = plateau(u)
		fwdR = (1.85 + 0.15 * math.sin(now * 7)) * k
		armR = -0.45 * k
		nod = -0.06 * k
		yawExtra = 0.12 * k
	elseif action == "flex" then
		-- arms out to the sides, pumping, chest out
		local k = plateau(u)
		local pump = 0.15 * math.sin(now * 9)
		armL, armR = (1.45 + pump) * k, (1.45 + pump) * k
		fwdL, fwdR = 0.25 * k, 0.25 * k
		lean = -0.05 * k
	-- ---------- Trapper ----------
	elseif action == "sniff" then
		-- nose up, testing the air left and right in quick little turns
		local k = plateau(u)
		nod = -0.22 * k
		yawExtra = 0.35 * math.sin(u * math.pi * 4) * k
	elseif action == "crouch" then
		-- stoop forward to read tracks on the ground, hands on the knees
		local k = plateau(u)
		lean = 0.18 * k
		nod = 0.28 * k
		fwdL, fwdR = 0.3 * k, 0.3 * k
	elseif action == "rummage" then
		-- a hand into the belt pouch, digging about, eyes down
		local k = plateau(u)
		fwdR = (0.35 + 0.08 * math.sin(now * 15)) * k
		armR = -0.25 * k
		nod = 0.3 * k
	-- ---------- Miner ----------
	elseif action == "lampTap" then
		-- hand up to the headlamp on the front of the hard hat, tapping it twice
		local k = plateau(u)
		local tap = math.max(0, math.sin(u * math.pi * 4))
		fwdR = (2.6 + 0.12 * tap) * k
		armR = -0.45 * k
		nod = (0.06 + 0.05 * tap) * k
	elseif action == "shoulder" then
		-- reach back over the right shoulder to settle the pickaxe, a little shrug
		local k = plateau(u)
		armR = 2.9 * k
		fwdR = -0.25 * k
		lean = 0.04 * k
		yawExtra = 0.25 * k
	-- ---------- Gemcutter ----------
	elseif action == "loupe" then
		-- fingers to the loupe on the forehead, then peering ahead at something small
		local k = plateau(u)
		fwdR = 2.65 * k
		armR = -0.3 * k
		nod = (-0.05 + 0.1 * bump((u - 0.3) / 0.5)) * k
	elseif action == "polish" then
		-- holds a gem up in front, the other hand rubbing it in little circles
		local k = plateau(u)
		fwdL = 1.55 * k
		armL = -0.3 * k
		fwdR = (1.45 + 0.12 * math.sin(now * 10)) * k
		armR = (-0.35 + 0.1 * math.cos(now * 10)) * k
		nod = 0.14 * k
	elseif action == "pouch" then
		-- a hand into the pouch on the left hip, picking through the crystals, eyes down
		local k = plateau(u)
		fwdL = (0.32 + 0.07 * math.sin(now * 14)) * k
		armL = -0.2 * k
		nod = 0.28 * k
		yawExtra = -0.2 * k
	-- ---------- Explorer (the right arm rests raised, holding the map) ----------
	elseif action == "compass" then
		-- the compass hand comes up in front of the chest, eyes down on it, turning a little to get a bearing
		local k = plateau(u)
		fwdL = 1.5 * k
		armL = -0.3 * k
		nod = 0.22 * k
		yawExtra = (0.12 + 0.15 * math.sin(u * math.pi * 2)) * k
	elseif action == "glasses" then
		-- a finger up to the bridge of the round glasses, pushing them back up, a small nod
		local k = plateau(u)
		fwdL = 2.45 * k
		armL = -0.55 * k
		nod = (0.04 + 0.06 * bump((u - 0.4) / 0.3)) * k
	elseif action == "study" then
		-- lifts the map a touch and peers down at it, the head tracing the route across
		local k = plateau(u)
		fwdR = 0.12 * k
		nod = 0.2 * k
		yawExtra = (-0.38 + 0.1 * math.sin(u * math.pi * 3)) * k
	-- ---------- Sensei (the right arm rests raised, holding the staff) ----------
	elseif action == "stroke" then
		-- the free hand up to the chin, drawing down the long beard twice, a thoughtful tilt
		local k = plateau(u)
		fwdL = (1.75 - 0.25 * math.max(0, math.sin(u * math.pi * 4))) * k
		armL = -0.45 * k
		nod = -0.05 * k
		yawExtra = -0.1 * k
	elseif action == "bow" then
		-- a slow bow from the hips, the head following it down
		local k = plateau(u)
		lean = 0.22 * k
		nod = 0.2 * k
		fwdL = 0.15 * k
	-- ---------- Wrapper (the right arm rests raised, holding the ribbon spool) ----------
	elseif action == "unspool" then
		-- the free hand reaches across to the spool and draws the ribbon out to the side, twice
		local k = plateau(u)
		local pull = (1 - math.cos(u * math.pi * 4)) / 2
		fwdL = (1.0 - 0.25 * pull) * k
		armL = (-0.45 + 1.0 * pull) * k
		nod = 0.16 * k
		yawExtra = (0.25 - 0.45 * pull) * k
	elseif action == "beret" then
		-- the hand up to the beret's side, straightening it with a little wiggle
		local k = plateau(u)
		fwdL = 2.75 * k
		armL = (-0.4 + 0.06 * math.sin(now * 13)) * k
		nod = -0.04 * k
		yawExtra = -0.08 * k
	elseif action == "pat" then
		-- two pats on the apron pocket, eyes down to it
		local k = plateau(u)
		local tap = math.max(0, math.sin(u * math.pi * 4))
		fwdL = (0.5 + 0.12 * tap) * k
		armL = -0.32 * k
		nod = 0.22 * k
	-- ---------- Archaeologist (the left arm rests raised with the magnifier, the brush in the right fist) ----------
	elseif action == "peer" then
		-- the glass comes up in front of the eye, he leans in and looks slowly along something
		local k = plateau(u)
		fwdL = 0.35 * k
		armL = -0.25 * k
		lean = 0.07 * k
		nod = 0.06 * k
		yawExtra = 0.18 * math.sin(u * math.pi * 2) * k
	elseif action == "brush" then
		-- dusting a find in front of him: the brush hand flicks side to side, eyes down
		local k = plateau(u)
		local flick = math.sin(now * 11)
		fwdR = (0.75 + 0.1 * flick) * k
		armR = (-0.2 + 0.16 * flick) * k
		lean = 0.08 * k
		nod = 0.26 * k
	elseif action == "ponder" then
		-- the brush handle tapped against the chin, head tilted, thinking it over
		local k = plateau(u)
		local tap = math.max(0, math.sin(u * math.pi * 6))
		fwdR = (1.8 + 0.08 * tap) * k
		armR = -0.45 * k
		nod = -0.06 * k
		yawExtra = -0.15 * k
	end

	local t = now + npc.phase
	-- breathing only ever settles the body down onto the legs (0 .. -lift), never up off them
	local breath = BREATH_LIFT * (math.sin(t * BREATH_RATE) - 1) * 0.5
	local sway = 0.04 * math.sin(t * 0.9)
	-- styled NPCs shift their weight slowly from foot to foot, and an arm holding a
	-- tool (pitchfork, lantern, needle) stays steady
	local roll = if base then base.shift * math.sin(t * 0.45) else 0
	local swayR = if base and base.steadyRight then 0 else sway

	-- upper body: breathe, lean and shift weight (pivot at the hips)
	local hips = Vector3.new(0, -1, 0)
	-- Tilting about the hips' centre lifts one bottom corner of the torso (half-width 1, half-depth 0.5);
	-- the body drops by exactly that much, so the torso never comes apart from the legs (user, 2026-10-11:
	-- "their bodies detach from their legs").
	local settle = math.abs(math.sin(roll)) * 1 + math.abs(math.sin(lean)) * 0.5
	local body = CFrame.new(0, breath - settle, 0) * about(hips, CFrame.Angles(-lean, 0, roll))
	local head = body * about(NECK, CFrame.Angles(0.05 * math.sin(t * 0.7) - nod, npc.headYaw + yawExtra, 0))
	-- arms: positive raise lifts the arm out to the side; forward swings it to the front
	local left = body * about(SHOULDER_L, CFrame.Angles(fwdL, 0, 0) * CFrame.Angles(0, 0, -(armL + sway)))
	local right = body * about(SHOULDER_R, CFrame.Angles(fwdR, 0, 0) * CFrame.Angles(0, 0, armR + swayR))
	-- a held tool follows the fist but keeps its own (upright) orientation
	local hand = npc.hand
	local tool = if hand then CFrame.new(right * hand - hand) else nil

	for _, p in npc.parts do
		local bone = p.bone
		local offset = if bone == "Torso" then body
			elseif bone == "Head" then head
			elseif bone == "LeftArm" then left
			elseif bone == "RightArm" then right
			elseif bone == "Tool" then tool
			else nil
		if offset then
			p.part.CFrame = npc.frame * offset * p.rest
		end
	end
end

local function step(dt: number)
	local now = os.clock()
	local camera = Workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position
	for model, npc in npcs do
		if not model.Parent then
			npcs[model] = nil
			continue
		end
		if not camPos or (npc.frame.Position - camPos).Magnitude <= CULL_DISTANCE then
			pose(npc, now, dt)
		end
	end
end

function NpcIdleController.init(injected: any)
	deps = injected
end

function NpcIdleController.start()
	local tag = MapLayout.Tags.AmbientIdle
	for _, inst in CollectionService:GetTagged(tag) do
		adopt(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(adopt)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(release)
	RunService.PreRender:Connect(step)
end

return NpcIdleController
