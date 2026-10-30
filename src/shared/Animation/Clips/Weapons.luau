--!strict
-- Weapons: how every weapon in Config/Weapons is held and swung, as clips for
-- the R6 player rig.
--
--   WeaponClips.hold(def)       looping, priority Hold: how the weapon is carried
--                               (nil for unarmed weapons -- the arms stay free)
--   WeaponClips.swing(def)      the arms of one swing, priority Action, length 1
--                               (play at speed 1 / def.cooldown). Markers "Hit" at
--                               def.hitTime, "TrailOn" / "TrailOff" around it.
--   WeaponClips.swingBody(def)  the body of the same swing (twist, lean, lunge), an
--                               ADDITIVE clip -- play it alongside, at the same
--                               speed, so walking, bob and foot planting carry on.
--   WeaponClips.extra(def, name) another swing played with the def's hold and hands
--                               (the fishing rod's Reel): arms clip, body clip
--   WeaponClips.report(def)     how well the poses can actually be reached
--   WeaponClips.gripAt(def, u)  the weapon's CFrame in the root's space at swing time u
--                               (nil = the hold), for tests and the flail's chain
-- Clips are built once per weapon and cached.
--
-- ==================== authoring ====================
-- Poses say where the RIGHT HAND is and where the WEAPON POINTS; the R6 solver
-- below works out the arm and the weapon's turn in the hand. All in the torso's
-- frame, studs from the torso's centre: +X right, +Y up, -Z forward. For scale:
-- shoulders are at (+-1, 0.5, 0), a hanging hand at (1.5, -1, 0), and a straight
-- arm reaches about 1.6 from its shoulder (+0.4 / -0.3 by sliding the shoulder).
--
--   hand = { x, y, z }   right hand position
--   dir  = { x, y, z }   weapon direction (the model's -Z), need not be unit
--   roll = degrees       turn about that direction (which way edges / flats face):
--                        written for an edge on the model's -Y (HOLDS' `edge` turns a
--                        weapon whose edge is elsewhere onto it)
--   two  = 0..1          two-handed only: left hand on the shaft (1) or free (0)
--   off  = studs         where on the shaft the left hand goes, measured toward the
--                        tip (default: the model's OffGrip; slides along the shaft to
--                        stay reachable). Negative = behind the right hand, toward the butt.
--   left = { x, y, z }   where the free left hand goes when two = 0
--   wy wp ry rz          body: twist left, lean forward, whole-body turn (deg),
--                        step forward (studs)
--   hit = true           the strike: the swing is retimed so this key lands on the
--                        def's hitTime (so one swing serves weapons of any timing)
--   stop = true          the motion comes to rest here (a turning point); a reversal
--                        rests by itself, every other key is passed THROUGH
-- HOLDS[id] is one pose (plus `edge`: degrees that turn the model's edge onto -Y, and
-- `sym`: the edge is on both sides). SWINGS[name] is a list of keys { u = 0..1, ... };
-- fields a key leaves out come from the hold (hand, dir, roll, two, off, left) or are 0
-- (body). So the first and last keys are just { u = 0 } and { u = 1 }.
--
-- Motion (2026-10-29, the user: "no weird stopping parts and pauses"): the keys are joined
-- by one smooth spline (each key's speed carries through it; only the ends, `stop` keys
-- and turning points rest), the hands moving round their shoulders so a straight arm
-- stays straight. LEAD[name] = { from, to }: across that stretch of the swing the weapon
-- turns about its own length so its edge (or striking face) LEADS the way it is moving
-- (the user: the greatsword came down on its flat), measured from the swing itself.
-- Arms (the same day, "some of the weapons and tools twist the arm in weird ways"): an
-- arm turns about its own length so its front faces the way the weapon leaves the fist,
-- as a wrist would, instead of flipping as the hand passes over the head.
-- Every swing is right-handed: it starts on the right and travels to the left
-- (user, 2026-10-11).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animation = script.Parent.Parent
local Clip = require(Animation.Clip)

local Weapons = {}

type Key = { [string]: any }

-- ==================== holds ====================

-- the one-handed hold at the hip, and the two-handed carry across the body
local HIP = { hand = { 1.45, -0.8, -0.35 }, dir = { 0, 0.25, -1 }, roll = 0 }
local BLADE = { hand = { 1.5, -0.85, -0.25 }, dir = { 0, 0.55, -1 }, roll = 0 }
local CARRY_2H = { hand = { 1.1, -0.9, -0.75 }, dir = { -0.75, 0.65, -0.2 }, roll = 0, two = 1 }
local LEVEL_2H = { hand = { 1.1, -0.7, -0.8 }, dir = { 1, 0.12, 0.3 }, roll = 0, two = 1 }

local function with(base: Key, extra: Key): Key
	local out = table.clone(base)
	for k, v in extra do
		out[k] = v
	end
	return out
end

Weapons.HOLDS = {
	-- one-handed, low and ready at the hip
	Dagger = HIP,
	-- the Sickle's edge is on the inside of its curve (+Y)
	Sickle = { hand = { 1.5, -0.8, -0.3 }, dir = { 0, 0.45, -1 }, roll = 0, edge = 180 },
	Machete = BLADE,
	-- the Rusty Blade (Relic): the Machete's hold; double-edged
	RustyBlade = with(BLADE, { sym = true }),
	WorldheartBlade = with(BLADE, { sym = true }),
	WorldheartBlade2 = with(BLADE, { sym = true }),
	WorldheartBlade3 = with(BLADE, { sym = true }),
	WorldheartBlade4 = with(BLADE, { sym = true }),
	-- held by the shaft at the hip (the model's grip is on the shaft, the D-grip
	-- behind the hand), blade forward-up, flats up/down ready for the bonk
	Shovel = { hand = { 1.45, -0.8, -0.35 }, dir = { 0, 0.5, -1 }, roll = 90 },
	-- the giant Corn Cob (secret): held like the Dagger
	CornCob = HIP,
	-- the Pumpkin King's Mace (Legendary): the one-handed hold as well
	PumpkinMace = HIP,
	-- both hands, head up on the left
	Pitchfork = CARRY_2H,
	-- the Weathervane Spear (Legendary): the Pitchfork's two-handed hold
	WeathervaneSpear = CARRY_2H,
	-- both hands on the two pegs (right on the upper peg, left on the lower), the
	-- snath leaning up to the right, blade out to the right and curving down
	Scythe = { hand = { 0.9, 1.0, -1.25 }, dir = { 0.57, 0.82, -0.03 }, roll = 125, two = 1 },
	-- the Farrier's Hammer (Rare, 2026-10-26): its horseshoe face is the -Y side
	FarriersHammer = HIP,
	-- the Crowbane Hoe (Epic, 2026-10-26): the two-handed carry, its blade on -Y
	CrowbaneHoe = CARRY_2H,
	-- ==================== World 2 (2026-10-11) ====================
	Hatchet = HIP,
	Cleaver = HIP,
	Mace = with(HIP, { sym = true }),
	-- the Firefly Lantern: held out in front at waist height, handle tipped up, so the
	-- lantern hangs on its chain clear of the ground (from the hip it hung 0.9 into it)
	LanternFlail = { hand = { 1.35, 0.3, -1.35 }, dir = { 0, 0.5, -1 }, roll = 0 },
	MarshmallowStick = HIP,
	HoneycombHammer = with(HIP, { sym = true }),
	CopperDrill = HIP,
	WoodsmansAxe = with(CARRY_2H, { sym = true }),
	Greatclub = CARRY_2H,
	HeartwoodStaff = CARRY_2H,
	-- ==================== gathering tools (Config/Tools, 2026-10-18) ====================
	WoodenAxe = HIP,
	WoodenPickaxe = with(HIP, { sym = true }),
	-- the fishing rod: one hand at the hip, the rod pointing out ahead and up toward the
	-- water (user, 2026-10-18: one-handed normally, both hands only for the cast). The
	-- reel hangs under the rod (roll 0: the model's -Y is down).
	WoodenRod = { hand = { 1.45, -0.75, -0.45 }, dir = { 0, 0.45, -1 }, roll = 0, two = 0 },
	StoneAxe = HIP,
	StoneRod = { hand = { 1.45, -0.75, -0.45 }, dir = { 0, 0.45, -1 }, roll = 0, two = 0 },
	CrystalPickaxe = with(HIP, { sym = true }),
	CrystalRod = { hand = { 1.45, -0.75, -0.45 }, dir = { 0, 0.45, -1 }, roll = 0, two = 0 },
	SandstoneAxe = HIP,
	SandstoneShovel = with(HIP, { two = 0 }), -- rests in one hand; digs with both
	SandstoneRod = { hand = { 1.45, -0.75, -0.45 }, dir = { 0, 0.45, -1 }, roll = 0, two = 0 },
	-- the 10-stud Pinecone Staff (6.3 ahead of the hand, 3.8 behind): held level across
	-- the front, head out to the right and a touch back, the butt crossing in front of
	-- the body to the left hand (behind the grip, off = -1.6). The staff stays across the
	-- front so its long butt never passes through the body (user, 2026-10-11).
	Quarterstaff = with(LEVEL_2H, { off = -1.6 }),
	-- ==================== World 3 (2026-10-13) ====================
	BatwingBlade = BLADE,
	IronPickaxe = with(HIP, { sym = true }),
	PebbleMallet = with(HIP, { sym = true }),
	QueensFang = BLADE,
	DiamondPickaxe = with(HIP, { sym = true }),
	-- the Machete's hold and diagonal swing (user, 2026-10-13)
	RockCandyClub = BLADE,
	EmberCoalMaul = CARRY_2H,
	-- the glaive: the Pinecone Staff's level hold across the front; the right hand on the upper
	-- wrap, the left on the lower wrap 1.9 behind it (user 2026-10-13: hands on the handle)
	GeodeGlaive = with(LEVEL_2H, { off = -1.9 }),
	-- the Gold Gauntlets (worn): a fight-ready guard, both fists up in front of the face with
	-- the arms angled up (user, 2026-10-13). The gloves line up with the forearms (def.worn),
	-- so only the hands' positions matter.
	GoldGauntlets = { hand = { 1.0, 1.05, -1.15 }, dir = { 0, 1, -1 }, roll = 0, two = 0, left = { -1.0, 1.05, -1.15 } },
	-- ==================== World 4 (2026-10-29) ====================
	BoneClub = HIP,
	Khopesh = HIP,
	ScarabMace = with(HIP, { sym = true }),
	LinenSpear = CARRY_2H,
	DesertScimitar = HIP,
	-- the greatsword's blade is wide on the model's X (edges +-X, flats +-Y): `edge` 90 turns
	-- an edge onto -Y. A two-handed guard, the blade up and forward, both hands on the hilt
	-- (the left behind the right, toward the pommel).
	SarcophagusGreatsword = { hand = { 0.5, -0.1, -1.5 }, dir = { -0.1, 0.7, -1 }, roll = 90, two = 1, off = -0.55, edge = 90, sym = true },
	-- the ankh is flat on Y: it strikes edge-on
	CursedAnkh = with(CARRY_2H, { edge = 90 }),
	-- the crook: held level across the front like the Pinecone Staff, its hook (-Y) out to
	-- the right, the left hand behind the right toward the foot
	PharaohsCrook = with(LEVEL_2H, { off = -1.0 }),
	StaffOfRa = CARRY_2H,
	CactusClub = HIP,
} :: { [string]: Key }

-- ==================== swings ====================

-- the two-handed overhead lift (Splitter, Boulder Club): weapon straight up
local LIFT_HAND = { 0.8, 1.6, -0.95 }
local LIFT_DIR = { 0.05, 1, -0.1 }
local RECOVER_2H = { u = 0.88, hand = { 1.0, -0.4, -1.35 }, dir = { -0.45, 0.6, -0.65 }, two = 0, off = 1.9, left = { -1.1, -0.6, -0.6 } }
-- on the way up the left hand also lets go (it can't slide down past the right
-- hand) and takes the haft again below it at the top
local LIFT_FREE_2H = { u = 0.17, hand = { 1.05, 0.45, -1.15 }, dir = { -0.35, 0.85, -0.45 }, two = 0, off = 0.6, left = { -0.9, 0.0, -1.0 }, wy = -5, wp = -3 }

-- The fishing fight's base pose (Struggle, Heave, Lurch): the rod held up and back in both
-- hands, leaning back against the fish.
local STRUGGLE_POSE = { hand = { 0.3, 0.85, -1.05 }, dir = { 0, 1, -0.4 }, two = 1, off = -0.55, wp = -11, wy = -5 }
local function struggleAt(u: number): Key
	local key = table.clone(STRUGGLE_POSE) :: Key
	key.u = u
	return key
end
local STRUGGLE, STRUGGLE_MID, STRUGGLE_END = struggleAt(0), struggleAt(0.5), struggleAt(1)

Weapons.SWINGS = {
	-- Dagger (the Trowel): pull it back along the side, then lunge it straight forward.
	Jab = {
		{ u = 0 },
		{ u = 0.3, hand = { 1.45, -0.55, 0.75 }, dir = { 0, 0.1, -1 }, wy = -18, wp = -4, stop = true },
		{ u = 0.5, hand = { 0.85, 0.05, -1.4 }, dir = { -0.1, 0.02, -1 }, wy = 18, wp = 8, rz = 0.55, hit = true },
		{ u = 0.66, hand = { 0.95, -0.05, -1.3 }, dir = { -0.08, 0.04, -1 }, wy = 12, wp = 6, rz = 0.4 },
		{ u = 1 },
	},
	-- Copper Drill: the Dagger's lunge with the bit spinning, driven in and wound out.
	Drill = {
		{ u = 0 },
		{ u = 0.3, hand = { 1.45, -0.5, 0.7 }, dir = { 0, 0.1, -1 }, roll = 90, wy = -16, wp = -3, stop = true },
		{ u = 0.5, hand = { 0.85, 0.0, -1.42 }, dir = { -0.1, 0.0, -1 }, roll = 720, wy = 18, wp = 8, rz = 0.55, hit = true },
		{ u = 0.68, hand = { 0.9, -0.05, -1.35 }, dir = { -0.08, 0.02, -1 }, roll = 1080, wy = 14, wp = 7, rz = 0.45 },
		{ u = 1, roll = 1440 },
	},
	-- Marshmallow Stick: a toasting-fork poke straight out, flicked up at the end.
	Poke = {
		{ u = 0 },
		{ u = 0.28, hand = { 1.45, -0.5, 0.6 }, dir = { 0, 0.2, -1 }, wy = -15, wp = -3, stop = true },
		{ u = 0.5, hand = { 0.9, 0.15, -1.45 }, dir = { -0.08, 0.05, -1 }, wy = 16, wp = 7, rz = 0.5, hit = true },
		{ u = 0.68, hand = { 1.0, 0.55, -1.3 }, dir = { -0.05, 0.6, -1 }, wy = 10, wp = 3, rz = 0.3, stop = true },
		{ u = 1 },
	},
	-- Sickle, Khopesh, Batwing Blade: swing out to the right, then a flat reaping hook
	-- straight across the body, the edge leading (LEAD).
	Hook = {
		{ u = 0 },
		{ u = 0.3, hand = { 2.45, 0.25, 0.35 }, dir = { 0.7, 0, -0.7 }, roll = -90, wy = -30, stop = true },
		{ u = 0.55, hand = { 0.75, 0.15, -1.45 }, dir = { -0.2, 0, -1 }, roll = -90, wy = 8, wp = 6, rz = 0.2, hit = true },
		{ u = 0.72, hand = { -0.35, 0.05, -1.1 }, dir = { -1, 0, -0.35 }, roll = -90, wy = 35, wp = 6, stop = true },
		{ u = 1 },
	},
	-- Stone & Bone Cleaver: straight up over the head (the blade straight up), then one
	-- chop down in front, edge first (user, 2026-10-11), bouncing up off the blow.
	Cleave = {
		{ u = 0 },
		{ u = 0.36, hand = { 1.15, 2.0, -0.25 }, dir = { 0.02, 1, -0.05 }, wp = -6, stop = true },
		{ u = 0.56, hand = { 1.0, -0.1, -1.45 }, dir = { 0, -0.4, -1 }, wp = 10, rz = 0.3, hit = true },
		{ u = 0.7, hand = { 1.0, 0.12, -1.42 }, dir = { 0, -0.18, -1 }, wp = 8, rz = 0.25 },
		{ u = 1 },
	},
	-- Machete, Rusty Blade: raise it up to the right, then slash diagonally down across the
	-- body and all the way through, edge first.
	Diagonal = {
		{ u = 0 },
		{ u = 0.35, hand = { 1.95, 1.65, 0.2 }, dir = { 1, 0.95, 0.3 }, wy = -25, wp = -5, stop = true },
		{ u = 0.52, hand = { 0.7, 0.2, -1.4 }, dir = { -0.6, -0.3, -1 }, wy = 15, wp = 10, rz = 0.3, hit = true },
		-- (the long blade must stay above the ground on the follow-through)
		{ u = 0.72, hand = { 0.05, -0.85, -1.05 }, dir = { -1, -0.3, -0.5 }, wy = 30, wp = 10, stop = true },
		{ u = 1 },
	},
	-- Desert Scimitar: a flowing crescent at shoulder height, cocked back over the right
	-- shoulder and drawn round to the left.
	Crescent = {
		{ u = 0 },
		{ u = 0.32, hand = { 2.1, 1.3, 0.45 }, dir = { 0.75, 0.35, 0.6 }, wy = -32, wp = -3, stop = true },
		{ u = 0.5, hand = { 0.9, 0.75, -1.5 }, dir = { -0.45, 0.05, -1 }, wy = 10, wp = 5, rz = 0.3, hit = true },
		{ u = 0.7, hand = { -0.45, 0.35, -1.0 }, dir = { -1, -0.2, 0.15 }, wy = 38, wp = 5, stop = true },
		{ u = 1 },
	},
	-- Queen's Fang: raised high, then plunged down and forward point first, like a bite.
	FangStrike = {
		{ u = 0 },
		{ u = 0.36, hand = { 1.25, 1.95, -0.5 }, dir = { 0.05, 1, 0.1 }, wy = -10, wp = -8, stop = true },
		{ u = 0.52, hand = { 0.9, 0.05, -1.5 }, dir = { -0.05, -0.3, -1 }, wy = 8, wp = 8, rz = 0.45, hit = true },
		{ u = 0.66, hand = { 0.9, -0.05, -1.45 }, dir = { -0.05, -0.36, -1 }, wy = 6, wp = 7, rz = 0.35, stop = true },
		{ u = 1 },
	},
	-- Shovel: straight up off the shoulder, then straight down. Bonk (on the flat).
	Bonk = {
		{ u = 0 },
		{ u = 0.35, hand = { 1.15, 2.05, -0.15 }, dir = { 0, 1, 0.25 }, wp = -8, stop = true },
		{ u = 0.6, hand = { 1.0, -0.15, -1.45 }, dir = { 0, -0.45, -1 }, wp = 14, rz = 0.3, hit = true },
		{ u = 0.74, hand = { 1.0, 0.05, -1.42 }, dir = { 0, -0.25, -1 }, wp = 10, rz = 0.25 },
		{ u = 1 },
	},
	-- Corn Cob: a bigger bonk for an 8.7-stud cob. Raised high with the cob tipped
	-- back over the shoulder, slammed down in front (the tip just meets the
	-- ground), bouncing up off the slam.
	CornBonk = {
		{ u = 0 },
		{ u = 0.38, hand = { 1.05, 2.0, 0.05 }, dir = { 0.05, 0.75, 0.66 }, wp = -10, stop = true },
		{ u = 0.6, hand = { 0.95, -0.1, -1.45 }, dir = { 0, -0.14, -1 }, wp = 6, rz = 0.35, hit = true },
		{ u = 0.74, hand = { 0.95, 0.1, -1.42 }, dir = { 0, 0.02, -1 }, wp = 4, rz = 0.3 },
		{ u = 1 },
	},
	-- Farrier's Hammer, Honeycomb Hammer, Pebble Mallet: a smith's blow. Cocked back beside
	-- the head, the face struck straight down in front, and a little rebound.
	Hammer = {
		{ u = 0 },
		{ u = 0.38, hand = { 1.35, 1.75, 0.15 }, dir = { 0.15, 0.55, 0.85 }, wy = -12, wp = -8, stop = true },
		{ u = 0.6, hand = { 1.0, -0.05, -1.45 }, dir = { -0.02, -0.35, -1 }, wp = 12, rz = 0.35, hit = true },
		{ u = 0.72, hand = { 1.0, 0.2, -1.4 }, dir = { 0, -0.1, -1 }, wp = 9, rz = 0.3, stop = true },
		{ u = 1 },
	},
	-- Bone Club, Cactus Club: a big overhead smash, high over the right shoulder and down
	-- across to the left.
	ClubSmash = {
		{ u = 0 },
		{ u = 0.38, hand = { 1.75, 1.7, 0.3 }, dir = { 0.6, 1, 0.45 }, wy = -28, wp = -8, stop = true },
		{ u = 0.58, hand = { 0.55, -0.25, -1.35 }, dir = { -0.5, -0.15, -0.9 }, wy = 20, wp = 8, rz = 0.35, hit = true },
		{ u = 0.74, hand = { 0.3, -0.35, -1.25 }, dir = { -0.7, -0.15, -0.7 }, wy = 26, wp = 7, stop = true },
		{ u = 1 },
	},
	-- Mace, Scarab Mace: a round forehand bash at head height, wound back behind the right
	-- shoulder and swung round in front.
	Bash = {
		{ u = 0 },
		{ u = 0.36, hand = { 2.05, 1.0, 0.6 }, dir = { 0.55, 0.75, 0.7 }, wy = -35, wp = -4, stop = true },
		{ u = 0.56, hand = { 0.8, 0.35, -1.5 }, dir = { -0.4, -0.1, -1 }, wy = 12, wp = 7, rz = 0.35, hit = true },
		{ u = 0.74, hand = { -0.4, 0.0, -1.0 }, dir = { -1, -0.25, 0.05 }, wy = 36, wp = 6, stop = true },
		{ u = 1 },
	},
	-- Lantern Flail (the Firefly Lantern): a morning-star smash, never straight over the
	-- head (2026-10-29, the user: the overhead whirl put the arm straight up by the head).
	-- The handle is drawn back over the right shoulder like the Bash, then brought down in
	-- front and on across to the left; the lantern follows its own set path
	-- (FlailController PATHS.FlailWhirl): behind on the windup, up over the top, down in
	-- front on the hit.
	FlailWhirl = {
		{ u = 0 },
		{ u = 0.32, hand = { 1.9, 0.75, -0.85 }, dir = { 0.3, 0.8, 0.5 }, wy = -12, wp = -4, stop = true },
		{ u = 0.56, hand = { 0.95, 0.15, -1.5 }, dir = { 0.05, 0.1, -1 }, wy = 12, wp = 9, rz = 0.35, hit = true },
		{ u = 0.74, hand = { 0.3, -0.35, -1.2 }, dir = { -0.55, -0.35, -0.75 }, wy = 24, wp = 6, stop = true },
		{ u = 1 },
	},
	-- Pitchfork, Linen Spear: bring it over to the right side (body turned right, both
	-- hands), then drive it forward like the dagger -- the right hand thrusts, the left
	-- lets go and guards.
	Thrust = {
		{ u = 0 },
		{ u = 0.3, hand = { 1.5, -0.6, 0.5 }, dir = { -0.3, 0.15, -0.95 }, two = 1, wy = -24, wp = -3, stop = true },
		{ u = 0.5, hand = { 1.05, -0.25, -1.35 }, dir = { 0.05, 0, -1 }, two = 0, left = { -0.9, -0.7, -1.2 }, wy = 12, wp = 10, rz = 0.9, hit = true },
		{ u = 0.68, hand = { 1.1, -0.35, -1.2 }, dir = { 0.05, 0.02, -1 }, two = 0, left = { -0.9, -0.7, -1.2 }, wy = 8, wp = 6, rz = 0.5 },
		{ u = 1 },
	},
	-- Scythe: the snath swung level out to the right (hands on both pegs, blade at
	-- the right end pointing forward), then one sweep across to the left at a
	-- slight downward angle. The blade's inner edge faces back along the snath,
	-- so with the snath out to the right it LEADS the leftward sweep. A quick
	-- wind-up, then one sweep that builds up speed, is fastest at the hit (u ~0.46)
	-- and slows into the finish on the left (user, 2026-10-11).
	Sweep = {
		{ u = 0 },
		{ u = 0.2, hand = { 1.6, -0.5, -1.15 }, dir = { 1, 0.2, 0 }, roll = 5, ry = -75, wp = 2 },
		{ u = 0.72, hand = { 1.5, -0.6, -1.1 }, dir = { 1, -0.12, 0 }, roll = 5, ry = 70, wp = 6 },
		{ u = 1 },
	},
	-- Weathervane Spear "Gust" (user's pick, 2026-10-19): one wide level sweep. The right
	-- hand holds the spear straight out in front (the left lets go: R6 arms can't both
	-- reach a shaft pointing ahead) and the BODY turns, like the Scythe's: wound up turned
	-- right with the tip out on the right, then round to the left in one sweep that is
	-- fastest as the tip passes in front. A gust rolls out on the hit (impact = "Gust").
	Gust = {
		{ u = 0 },
		{ u = 0.24, hand = { 1.4, -0.7, -0.7 }, dir = { -0.05, 0.04, -1 }, two = 0, left = { -1.2, -0.6, -0.9 }, ry = -85, wp = 1 },
		{ u = 0.74, hand = { 1.2, -0.55, -1.0 }, dir = { -0.05, 0.02, -1 }, two = 0, left = { -1.25, -0.55, -0.7 }, ry = 70, wp = 6 },
		{ u = 1 },
	},
	-- Pumpkin King's Mace "Pumpkin smash" (user's pick, 2026-10-19): raised high over the
	-- right shoulder, then one heavy diagonal smash down and across to the left, the
	-- pumpkin's face first, the head just meeting the ground (impact = "Pumpkin").
	PumpkinSmash = {
		{ u = 0 },
		{ u = 0.38, hand = { 1.75, 1.7, 0.3 }, dir = { 0.6, 1, 0.45 }, wy = -28, wp = -8, stop = true },
		{ u = 0.58, hand = { 0.55, -0.25, -1.35 }, dir = { -0.5, -0.15, -0.9 }, wy = 20, wp = 8, rz = 0.35, hit = true },
		{ u = 0.74, hand = { 0.35, -0.15, -1.28 }, dir = { -0.65, -0.05, -0.75 }, wy = 24, wp = 6, rz = 0.3, stop = true },
		{ u = 1 },
	},
	-- Birch Hatchet: the Machete's diagonal chop, with a higher follow-through so
	-- the long bearded head stays above the ground.
	Chop1H = {
		{ u = 0 },
		{ u = 0.35, hand = { 1.95, 1.65, 0.2 }, dir = { 1, 0.95, 0.3 }, wy = -25, wp = -5, stop = true },
		{ u = 0.52, hand = { 0.7, 0.2, -1.4 }, dir = { -0.6, -0.2, -1 }, wy = 15, wp = 8, rz = 0.3, hit = true },
		{ u = 0.72, hand = { 0.1, -0.55, -0.95 }, dir = { -1, 0.05, -0.45 }, wy = 28, wp = 6, stop = true },
		{ u = 1 },
	},
	-- Gathering axes: a woodcutter's chop into the trunk, drawn back over the right
	-- shoulder and swung in at waist height, the bit first.
	Chop = {
		{ u = 0 },
		{ u = 0.34, hand = { 2.0, 1.05, 0.45 }, dir = { 0.6, 0.55, 0.75 }, wy = -35, wp = -3, stop = true },
		{ u = 0.52, hand = { 0.85, -0.2, -1.45 }, dir = { -0.35, -0.2, -1 }, wy = 12, wp = 8, rz = 0.35, hit = true },
		{ u = 0.66, hand = { 0.5, -0.2, -1.38 }, dir = { -0.6, -0.15, -0.8 }, wy = 18, wp = 7, stop = true },
		{ u = 1 },
	},
	-- Pinecone Staff: a right-handed sweep (user, 2026-10-11). Both hands keep the
	-- staff level across the front of the body, and the BODY turns: wound up to the
	-- right with the head out behind on the right, then one sweep round the front to the
	-- left. The staff never turns inside the body's frame, so its 3.8-stud butt stays
	-- in front of the body the whole way.
	StaffSweep = {
		{ u = 0 },
		{ u = 0.25, hand = { 1.2, -0.4, -0.9 }, dir = { 1, 0.15, 0.35 }, two = 1, off = -1.6, ry = -40, wp = -2 },
		{ u = 0.7, hand = { 1.0, -0.45, -1.35 }, dir = { 1, 0.06, -0.25 }, two = 1, off = -1.6, ry = 100, wp = 5 },
		{ u = 1 },
	},
	-- Geode Glaive: the Pinecone Staff's sweep with the left hand on the glaive's lower
	-- wrap, the blade's edge leading
	GlaiveSweep = {
		{ u = 0 },
		{ u = 0.25, hand = { 1.2, -0.4, -0.9 }, dir = { 1, 0.15, 0.35 }, two = 1, off = -1.9, ry = -40, wp = -2 },
		{ u = 0.7, hand = { 1.0, -0.45, -1.35 }, dir = { 1, 0.06, -0.25 }, two = 1, off = -1.9, ry = 100, wp = 5 },
		{ u = 1 },
	},
	-- Pharaoh's Crook: the same level sweep, the hook reaching out on the right and
	-- dragged round to the left, hook first
	CrookSweep = {
		{ u = 0 },
		{ u = 0.25, hand = { 1.2, -0.35, -0.9 }, dir = { 1, 0.2, 0.35 }, two = 1, off = -1.0, ry = -45, wp = -2 },
		{ u = 0.7, hand = { 1.0, -0.4, -1.35 }, dir = { 1, 0.08, -0.25 }, two = 1, off = -1.0, ry = 95, wp = 5 },
		{ u = 1 },
	},
	-- Lumberjack's Splitter, Crowbane Hoe (2H): both hands follow the haft overhead and
	-- down (the left just behind the right, off = -0.55); one chop that stops with the
	-- lower bit clear of the ground. The lift goes STRAIGHT UP, out in front-right of the
	-- face (user, 2026-10-11).
	Chop2H = {
		{ u = 0, off = 1.9 },
		LIFT_FREE_2H,
		{ u = 0.36, hand = LIFT_HAND, dir = LIFT_DIR, two = 1, off = -0.55, wy = -10, wp = -6, stop = true },
		{ u = 0.6, hand = { 0.55, 0.3, -1.45 }, dir = { -0.02, -0.1, -1 }, two = 1, off = -0.55, wp = 8, rz = 0.4, hit = true },
		{ u = 0.72, hand = { 0.55, 0.42, -1.42 }, dir = { -0.02, 0.0, -1 }, two = 1, off = -0.55, wp = 7, rz = 0.3 },
		-- back to the hold: the left hand lets go (it can't slide past the right one
		-- along the haft) while the head comes up in front, and re-grips at the hold
		RECOVER_2H,
		{ u = 1, off = 1.9 },
	},
	-- Sarcophagus Greatsword: a two-handed cleave, the blade raised back over the right
	-- shoulder and brought down diagonally across to the left, edge first.
	GreatCleave = {
		{ u = 0 },
		{ u = 0.36, hand = { 0.95, 1.55, -0.85 }, dir = { 0.45, 0.9, 0.1 }, two = 1, off = -0.55, wy = -24, wp = -6, stop = true },
		{ u = 0.6, hand = { 0.45, -0.05, -1.6 }, dir = { -0.5, -0.2, -1 }, two = 1, off = -0.55, wy = 16, wp = 9, rz = 0.45, hit = true },
		{ u = 0.76, hand = { 0.0, -0.45, -1.3 }, dir = { -0.85, -0.3, -0.45 }, two = 1, off = -0.55, wy = 26, wp = 8, stop = true },
		-- back up to the guard in front, the pommel kept off the belly
		{ u = 0.88, hand = { 0.65, -0.3, -1.55 }, dir = { -0.3, 0.35, -1 }, two = 1, off = -0.55, wy = 8, wp = 3 },
		{ u = 1 },
	},
	-- Heartwood Staff: a two-handed smite, lifted overhead and brought down across to the
	-- left on the living head.
	StaffSmite = {
		{ u = 0, off = 1.9 },
		LIFT_FREE_2H,
		{ u = 0.36, hand = { 0.9, 1.55, -0.9 }, dir = { 0.3, 1, 0.05 }, two = 1, off = -0.55, wy = -14, wp = -6, stop = true },
		{ u = 0.6, hand = { 0.4, 0.2, -1.45 }, dir = { -0.45, -0.12, -1 }, two = 1, off = -0.55, wy = 14, wp = 8, rz = 0.4, hit = true },
		{ u = 0.74, hand = { 0.1, 0.0, -1.35 }, dir = { -0.75, -0.12, -0.65 }, two = 1, off = -0.55, wy = 22, wp = 7, stop = true },
		RECOVER_2H,
		{ u = 1, off = 1.9 },
	},
	-- Staff of Ra: the sun disc raised to the sky, then thrust out to point at the foe like
	-- a spell cast, the left hand letting go and reaching after it.
	SunCall = {
		{ u = 0, off = 2.0 },
		LIFT_FREE_2H,
		{ u = 0.38, hand = LIFT_HAND, dir = LIFT_DIR, two = 1, off = -0.55, wy = -6, wp = -8, stop = true },
		{ u = 0.58, hand = { 1.15, 0.4, -1.45 }, dir = { -0.08, 0.15, -1 }, two = 0, off = -0.55, left = { -0.75, 0.6, -1.4 }, wy = 6, wp = 10, rz = 0.5, hit = true },
		{ u = 0.72, hand = { 1.15, 0.35, -1.42 }, dir = { -0.08, 0.08, -1 }, two = 0, off = -0.55, left = { -0.8, 0.5, -1.3 }, wy = 4, wp = 8, rz = 0.4 },
		with(RECOVER_2H, { off = 2.0 }),
		{ u = 1, off = 2.0 },
	},
	-- Gold Gauntlets: one punch a click, the fists taking turns (the def's `swings`; 2026-10-29,
	-- the user: the old one-two threw two punches for one hit). Each fist pulls back a touch and
	-- drives straight out from the guard, the body twisting into it, while the other fist stays
	-- up by the face.
	PunchRight = {
		{ u = 0 },
		{ u = 0.18, hand = { 1.35, 1.55, -0.75 }, left = { -1.0, 1.15, -1.05 }, wy = -12, stop = true },
		{ u = 0.4, hand = { 0.45, 0.75, -1.6 }, left = { -1.0, 1.2, -1.0 }, wy = 22, wp = 6, rz = 0.35, hit = true },
		{ u = 0.58, hand = { 0.65, 0.85, -1.45 }, left = { -1.0, 1.15, -1.05 }, wy = 14, wp = 4, rz = 0.25 },
		{ u = 1 },
	},
	PunchLeft = {
		{ u = 0 },
		{ u = 0.18, hand = { 1.0, 1.15, -1.05 }, left = { -1.35, 1.55, -0.75 }, wy = 12, stop = true },
		{ u = 0.4, hand = { 1.0, 1.2, -1.0 }, left = { -0.45, 0.75, -1.6 }, wy = -22, wp = 6, rz = 0.35, hit = true },
		{ u = 0.58, hand = { 1.0, 1.15, -1.05 }, left = { -0.65, 0.85, -1.45 }, wy = -14, wp = 4, rz = 0.25 },
		{ u = 1 },
	},
	-- Pickaxes: a mining swing (user, 2026-10-13). Raised high with the head tipped back
	-- over the shoulder, then driven straight down in front so the point bites into the
	-- rock, and pulled free.
	Mine = {
		{ u = 0 },
		{ u = 0.38, hand = { 1.1, 2.0, 0.05 }, dir = { 0.02, 0.85, 0.5 }, wp = -9, stop = true },
		{ u = 0.58, hand = { 0.95, -0.25, -1.45 }, dir = { 0, -0.45, -1 }, wp = 14, rz = 0.35, hit = true },
		{ u = 0.72, hand = { 0.95, -0.05, -1.42 }, dir = { 0, -0.28, -1 }, wp = 11, rz = 0.3 },
		{ u = 1 },
	},
	-- Diamond Pickaxe: the same mining swing, stopping a little higher and less steep for
	-- its 1.5x longer head
	MineLong = {
		{ u = 0 },
		{ u = 0.38, hand = { 1.1, 2.0, 0.05 }, dir = { 0.02, 0.85, 0.5 }, wp = -9, stop = true },
		{ u = 0.58, hand = { 0.95, 0.05, -1.45 }, dir = { 0, -0.36, -1 }, wp = 12, rz = 0.35, hit = true },
		{ u = 0.72, hand = { 0.95, 0.2, -1.42 }, dir = { 0, -0.2, -1 }, wp = 9, rz = 0.3 },
		{ u = 1 },
	},
	-- Shovels (2026-10-29): a two-handed dig. The right hand stays on the handle's end,
	-- the left comes onto the shaft below it; the spade is driven into the ground (the
	-- hit), levered up level with its load, then swung up and tipped out to the left.
	Dig = {
		{ u = 0 },
		{ u = 0.22, hand = { 0.35, 0.5, -0.8 }, dir = { -0.35, -0.6, -1 }, two = 1, off = 0.9, wy = -6, wp = -3, stop = true },
		{ u = 0.5, hand = { 0.2, 0.0, -1.0 }, dir = { -0.45, -1, -0.3 }, two = 1, off = 0.9, wy = 4, wp = 8, rz = 0.3, hit = true },
		{ u = 0.66, hand = { 0.1, -0.35, -0.8 }, dir = { -0.3, -0.25, -1 }, two = 1, off = 0.8, wy = 6, wp = 5, rz = 0.2 },
		{ u = 0.84, hand = { 0.0, 0.5, -1.1 }, dir = { -0.8, 0.4, -0.5 }, roll = -60, two = 1, off = 0.8, wy = 25, wp = -2, stop = true },
		{ u = 1, two = 0 },
	},
	-- Rock Candy Club: the Machete's diagonal with a higher follow-through for the long candy
	DiagonalLong = {
		{ u = 0 },
		{ u = 0.35, hand = { 1.95, 1.65, 0.2 }, dir = { 1, 0.95, 0.3 }, wy = -25, wp = -5, stop = true },
		{ u = 0.52, hand = { 0.7, 0.2, -1.4 }, dir = { -0.6, -0.2, -1 }, wy = 15, wp = 8, rz = 0.3, hit = true },
		{ u = 0.72, hand = { 0.05, -0.65, -0.85 }, dir = { -1, -0.1, -0.5 }, wy = 30, wp = 8, stop = true },
		{ u = 1 },
	},
	-- Worldheart Blade (9 studs): the Machete's diagonal, levelled out on the follow-through
	-- so the long blade sweeps across in front instead of into the ground
	DiagonalHuge = {
		{ u = 0 },
		{ u = 0.35, hand = { 1.95, 1.65, 0.2 }, dir = { 1, 0.95, 0.3 }, wy = -25, wp = -5, stop = true },
		{ u = 0.52, hand = { 0.7, 0.25, -1.4 }, dir = { -0.6, -0.1, -1 }, wy = 15, wp = 6, rz = 0.3, hit = true },
		{ u = 0.72, hand = { 0.1, -0.4, -0.95 }, dir = { -1, 0.1, -0.45 }, wy = 28, wp = 5, stop = true },
		{ u = 1 },
	},
	-- Boulder Club, Ember Coal Maul, Cursed Ankh (2H): the overhead lift, slammed down until
	-- the head just meets the ground (the def's impact = "Slam" throws the dust ring there).
	Slam2H = {
		{ u = 0, off = 1.9 },
		LIFT_FREE_2H,
		{ u = 0.36, hand = LIFT_HAND, dir = LIFT_DIR, two = 1, off = -0.55, wy = -10, wp = -6, stop = true },
		{ u = 0.6, hand = { 0.55, 0.0, -1.55 }, dir = { -0.02, -0.25, -1 }, two = 1, off = -0.55, wp = 8, rz = 0.4, hit = true },
		{ u = 0.72, hand = { 0.55, 0.15, -1.52 }, dir = { -0.02, -0.12, -1 }, two = 1, off = -0.55, wp = 7, rz = 0.3 },
		RECOVER_2H,
		{ u = 1, off = 1.9 },
	},
	-- ==================== fishing (Config/Fishing, 2026-10-18) ====================
	-- The cast: the left hand comes onto the cork behind the right (off -0.55, toward the
	-- butt), both hands take the rod back over the head with a lean back, then whip it
	-- forward; the line is let go at the "Hit" (the rod's hitTime), with the rod tip still
	-- high so the bobber flies out in an arc. The left hand lets go on the way back.
	Cast = {
		{ u = 0 },
		{ u = 0.14, hand = { 0.3, -0.2, -1.2 }, dir = { 0, 0.7, -1 }, two = 1, off = -0.55 },
		{ u = 0.4, hand = { 0.1, 1.8, -0.55 }, dir = { 0.05, 0.6, 0.8 }, two = 1, off = -0.55, wy = -8, wp = -7, stop = true },
		{ u = 0.56, hand = { 0.2, 1.0, -1.35 }, dir = { 0, 0.5, -1 }, two = 1, off = -0.55, wy = 4, wp = 8, hit = true },
		{ u = 0.72, hand = { 0.3, 0.35, -1.45 }, dir = { 0, 0.1, -1 }, two = 1, off = -0.55, wy = 3, wp = 6, rz = 0.3 },
		{ u = 0.88, hand = { 0.9, -0.4, -1.0 }, dir = { 0, 0.35, -1 }, two = 0, off = -0.55 },
		{ u = 1 },
	},
	-- Landing a fish (FishingController plays it through WeaponClips.extra): both hands,
	-- the rod yanked up and back so the line pulls the fish out of the water.
	Reel = {
		{ u = 0 },
		{ u = 0.22, hand = { 0.3, -0.25, -1.2 }, dir = { 0, 0.3, -1 }, two = 1, off = -0.55, wp = 4, stop = true },
		{ u = 0.5, hand = { 0.25, 1.25, -0.95 }, dir = { 0, 1, 0.2 }, two = 1, off = -0.55, wp = -9, wy = -4, hit = true },
		{ u = 0.74, hand = { 0.3, 1.0, -1.05 }, dir = { 0, 1, 0.1 }, two = 1, off = -0.55, wp = -5 },
		{ u = 1 },
	},
	-- Fighting a hooked fish (issue 26, 2026-10-25): both hands on the rod held up and back,
	-- leaning back, yanked right then left. Starts and ends on the same pose, so
	-- FishingController replays it as a loop.
	Struggle = {
		STRUGGLE,
		{ u = 0.25, hand = { 0.5, 0.75, -1.05 }, dir = { 0.3, 1, -0.45 }, two = 1, off = -0.55, wp = -13, wy = -12 },
		STRUGGLE_MID,
		{ u = 0.75, hand = { 0.1, 0.85, -1.05 }, dir = { -0.25, 1, -0.45 }, two = 1, off = -0.55, wp = -12, wy = 3 },
		STRUGGLE_END,
	},
	-- A check in the green: one big heave up and back, then back into the struggle.
	Heave = {
		STRUGGLE,
		{ u = 0.35, hand = { 0.3, 1.35, -0.75 }, dir = { 0, 1, 0.25 }, two = 1, off = -0.55, wp = -18, wy = -4, rz = -0.3 },
		STRUGGLE_END,
	},
	-- A miss: the fish pulls the player forward a step and the rod dips toward the water.
	Lurch = {
		STRUGGLE,
		{ u = 0.3, hand = { 0.3, 0.15, -1.4 }, dir = { 0, 0.25, -1 }, two = 1, off = -0.55, wp = 12, rz = 0.5 },
		STRUGGLE_END,
	},
} :: { [string]: { Key } }

-- Where in each swing (key time) the weapon turns to lead with its edge or face.
Weapons.LEAD = {
	Hook = { 0.3, 0.72 },
	Cleave = { 0.36, 0.7 },
	Diagonal = { 0.35, 0.72 },
	Crescent = { 0.32, 0.7 },
	Hammer = { 0.38, 0.72 },
	ClubSmash = { 0.38, 0.74 },
	Bash = { 0.36, 0.74 },
	Chop1H = { 0.35, 0.72 },
	Chop = { 0.34, 0.66 },
	GlaiveSweep = { 0.25, 0.7 },
	CrookSweep = { 0.25, 0.7 },
	Chop2H = { 0.36, 0.72 },
	GreatCleave = { 0.36, 0.76 },
	Mine = { 0.38, 0.72 },
	MineLong = { 0.38, 0.72 },
	DiagonalLong = { 0.35, 0.72 },
	DiagonalHuge = { 0.35, 0.72 },
} :: { [string]: { number } }

-- ==================== the R6 solver ====================

-- R6 shoulders (StarterPlayer/StarterCharacter), and the palm in arm space.
local RS_C0 = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
local RS_C1 = CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
local LS_C0 = CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)
local LS_C1 = CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)
local PALM = Vector3.new(0, -1, 0)
local SLIDE_MIN, SLIDE_MAX = -0.3, 0.4 -- how far a shoulder may move toward its target
local REST_RIGHT = (RS_C0 * RS_C1:Inverse()) * PALM
local REST_LEFT = (LS_C0 * LS_C1:Inverse()) * PALM
local FORWARD = Vector3.new(0, 0, -1) -- a weapon's length (the model's -Z), and an arm's front
local TWIST_MAX = math.rad(100) -- how far a forearm turns to follow the weapon in its fist
local TWIST_FADE = math.rad(100)

local rad = math.rad

local function fromTo(a: Vector3, b: Vector3): CFrame
	local d = math.clamp(a:Dot(b), -1, 1)
	local axis = a:Cross(b)
	if axis.Magnitude < 1e-6 then
		if d > 0 then
			return CFrame.identity
		end
		local perp = if math.abs(a.X) < 0.9 then Vector3.xAxis else Vector3.zAxis
		return CFrame.fromAxisAngle(a:Cross(perp).Unit, math.pi)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(d))
end

local function orth(v: Vector3, axis: Vector3): Vector3
	return v - axis * axis:Dot(v)
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- An armed arm's turn about the shoulder: its length along `a` (from the joint toward the
-- hand), its front (the arm's local -Z) facing the way the weapon leaves the fist, as a
-- wrist turns. `long` is the arm's own joint-to-palm direction. Where the weapon runs along
-- the arm (a thrust) the front falls back to the arm swung there from straight ahead with
-- its front up, which only turns over for an arm reaching straight back -- the old
-- shortest turn from hanging turned over for a hand above the head, so every overhead
-- swing spun the arm about itself.
local function armFrame(long: Vector3, a: Vector3, aim: Vector3): CFrame
	local ahead = Vector3.new(long.X, 0, long.Y) -- the hanging arm pitched forward
	local ref = orth(fromTo(ahead, a) * Vector3.yAxis, a)
	if ref.Magnitude < 1e-3 then
		ref = orth(FORWARD, a)
	end
	ref = ref.Unit
	local front = ref
	local want = orth(aim, a)
	local share = want.Magnitude
	local k = smooth((share - 0.1) / 0.6)
	if k > 0 then
		want /= share
		local angle = math.atan2(a:Dot(ref:Cross(want)), ref:Dot(want))
		-- a weapon leaving the fist BEHIND the arm's front: past TWIST_FADE the turn fades
		-- back to none at straight behind, where its side would flip
		local keep = smooth((math.pi - math.abs(angle)) / (math.pi - TWIST_FADE))
		front = CFrame.fromAxisAngle(a, math.clamp(angle, -TWIST_MAX, TWIST_MAX) * k * keep) * ref
	end
	-- the rotation taking (long, front, side) onto (a, front, a x front)
	local side = a:Cross(front)
	local sideLocal = long:Cross(FORWARD)
	local function column(e: Vector3): Vector3
		return a * long:Dot(e) + front * FORWARD:Dot(e) + side * sideLocal:Dot(e)
	end
	return CFrame.fromMatrix(Vector3.zero, column(Vector3.xAxis), column(Vector3.yAxis), column(Vector3.zAxis))
end

-- Point a straight arm at `target`. Returns the joint pose (torso frame, about
-- the shoulder), the arm part's CFrame in torso space, and how far off it lands.
-- `aim` is the held weapon's direction (nil: a free or gloved hand).
local function reach(c0: CFrame, c1: CFrame, target: Vector3, aim: Vector3?): (CFrame, CFrame, number)
	local joint = c0.Position
	local rest = (c0 * c1:Inverse()) * PALM - joint
	local length = rest.Magnitude
	local toTarget = target - joint
	local dist = toTarget.Magnitude
	local dir = if dist > 1e-4 then toTarget / dist else rest.Unit
	local slide = math.clamp(dist - length, SLIDE_MIN, SLIDE_MAX)
	local turn = if aim then armFrame(rest.Unit, dir, aim) else fromTo(rest.Unit, dir)
	local pose = CFrame.new(dir * slide) * turn
	local arm = CFrame.new(joint) * pose * c0.Rotation * c1:Inverse()
	return pose, arm, math.abs(dist - length - slide)
end

local function vec(t: { number }?, fallback: Vector3): Vector3
	return if t then Vector3.new(t[1], t[2], t[3]) else fallback
end

-- Where the left hand sits on the weapon (in the Grip's space), and how far ahead of the
-- grip the head is, from the model.
local offGripCache: { [string]: Vector3 } = {}
local headCache: { [string]: number } = {}
local function modelOf(def: any): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Weapons")
	-- gathering tools (Config/Tools) keep their models in Assets/Tools
	local tools = assets and assets:FindFirstChild("Tools")
	local model = (folder and folder:FindFirstChild(def.id)) or (tools and tools:FindFirstChild(def.id))
	return if model and model:IsA("Model") then model else nil
end
local function offGripOf(def: any): Vector3
	local cached = offGripCache[def.id]
	if cached then
		return cached
	end
	local point = Vector3.new(0, 0, -1.9)
	local model = modelOf(def)
	local grip = model and model.PrimaryPart
	local attachment = grip and grip:FindFirstChild("OffGrip")
	if attachment and attachment:IsA("Attachment") then
		point = attachment.Position
	end
	offGripCache[def.id] = point
	return point
end
local function headOf(def: any): number
	local cached = headCache[def.id]
	if cached then
		return cached
	end
	local far = 3
	local model = modelOf(def)
	local grip = model and model.PrimaryPart
	if model and grip then
		far = 0
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part ~= grip then
				local z = grip.CFrame:PointToObjectSpace(part.Position).Z
				far = math.max(far, -z + part.Size.Magnitude / 2)
			end
		end
		far = math.max(far, 1)
	end
	headCache[def.id] = far * 0.75
	return headCache[def.id]
end

type Solved = { channels: { [string]: CFrame }, body: CFrame, grip: CFrame, rightErr: number, leftErr: number }

-- One flat pose -> joint channels.
local function solve(p: any, def: any): Solved
	local out: { [string]: CFrame } = {}
	-- a worn weapon (gauntlets) stays lined up with the forearm: no turn in the hand
	local armed = not def.unarmed and not def.worn
	local aimDir = p.dir.Unit
	local rightPose, arm, rightErr = reach(RS_C0, RS_C1, p.hand, if armed then aimDir else nil)
	out.RightShoulder = rightPose
	local grip = arm * CFrame.new(PALM)
	if armed then
		local aim = fromTo(FORWARD, aimDir) * CFrame.Angles(0, 0, rad(p.roll + p.edge))
		local turn = grip.Rotation:Inverse() * aim
		out.Grip = turn
		grip = grip * turn
	end
	local leftErr = 0
	if (def.handed or 1) >= 2 then
		-- Left hand on the shaft, sliding along it to the most reachable point.
		local off = offGripOf(def)
		local along = if p.off then p.off else -off.Z
		local function at(distance: number): Vector3
			return grip * Vector3.new(off.X, off.Y, -distance)
		end
		local shaftAim = if armed then aimDir else nil
		local shaftPose, _, err = reach(LS_C0, LS_C1, at(along), shaftAim)
		if not p.off and err > 0.1 then
			-- Slide either way along the shaft (on the scythe the left hand sits
			-- behind the right one, toward the butt).
			for d = along - 1.2, along + 1.2, 0.1 do
				local candidate, _, e = reach(LS_C0, LS_C1, at(d), shaftAim)
				if e < err - 0.02 then
					shaftPose, err = candidate, e
				end
			end
		end
		local freePose, _, freeErr = reach(LS_C0, LS_C1, p.left)
		out.LeftShoulder = freePose:Lerp(shaftPose, math.clamp(p.two, 0, 1))
		leftErr = if p.two > 0.5 then err else freeErr
	end
	local body = CFrame.new(0, 0, -p.rz) * CFrame.Angles(0, rad(p.ry + p.wy), 0) * CFrame.Angles(rad(-p.wp), 0, 0)
	return { channels = out, body = body, grip = grip, rightErr = rightErr, leftErr = leftErr }
end

-- ==================== sampling ====================

-- A key (with hold fallbacks) -> a flat pose table.
local function flat(key: Key, hold: Key, def: any): any
	local function pick(name: string)
		local value = key[name]
		if value == nil then
			value = hold[name]
		end
		return value
	end
	local off = pick("off")
	return {
		hand = vec(pick("hand"), REST_RIGHT),
		dir = vec(pick("dir"), Vector3.new(0, 0.3, -1)),
		roll = pick("roll") or 0,
		two = pick("two") or 0,
		off = off,
		-- the shaft spot to blend from when only one side of a stretch names it
		offValue = off or -offGripOf(def).Z,
		left = vec(pick("left"), REST_LEFT),
		wy = key.wy or 0,
		wp = key.wp or 0,
		ry = key.ry or 0,
		rz = key.rz or 0,
		edge = 0, -- (a swing's spline turns the hold's `edge` in)
	}
end

-- A pose as numbers to spline: the hands as a direction from their shoulder and a
-- distance (so a straight arm stays straight between keys instead of cutting in toward
-- the shoulder, which a rigid R6 arm can't follow), then the weapon and the body.
local RJ, LJ = RS_C0.Position, LS_C0.Position
local function packPose(f: any): { number }
	local h, l, d = f.hand - RJ, f.left - LJ, f.dir.Unit
	local hu, lu = h.Unit, l.Unit
	return { hu.X, hu.Y, hu.Z, h.Magnitude, lu.X, lu.Y, lu.Z, l.Magnitude, d.X, d.Y, d.Z, f.roll, f.two, f.offValue, f.wy, f.wp, f.ry, f.rz }
end
local function unpackPose(v: { number }, useOff: boolean, edge: number): any
	local function unit(x: number, y: number, z: number, fallback: Vector3): Vector3
		local w = Vector3.new(x, y, z)
		return if w.Magnitude > 1e-4 then w.Unit else fallback
	end
	return {
		hand = RJ + unit(v[1], v[2], v[3], Vector3.new(0, -1, 0)) * v[4],
		left = LJ + unit(v[5], v[6], v[7], Vector3.new(0, -1, 0)) * v[8],
		dir = unit(v[9], v[10], v[11], FORWARD),
		roll = v[12],
		two = v[13],
		off = if useOff then v[14] else nil,
		wy = v[15],
		wp = v[16],
		ry = v[17],
		rz = v[18],
		edge = edge,
	}
end

local function hermite(p0: number, p1: number, m0: number, m1: number, x: number): number
	local x2, x3 = x * x, x * x * x
	return (2 * x3 - 3 * x2 + 1) * p0 + (x3 - 2 * x2 + x) * m0 + (-2 * x3 + 3 * x2) * p1 + (x3 - x2) * m1
end

-- The spline through a swing's keys: each value's speed through a key is the average of
-- its speeds either side (so the motion carries through it), zero at the ends, at `stop`
-- keys and wherever that value turns back (so it never overshoots a key). A `hit` key that
-- the weapon bounces back from is an impact: the stroke arrives at full speed (twice its
-- average) and the rebound leaves at half its own, so the blow lands hard instead of easing
-- to a stop on the target.
local IMPACT_IN, IMPACT_OUT = 2, 0.5
-- (the left hand's grip and its spot on the shaft change as they please, not with the blow)
local GRIP_CHANNELS = { [13] = true, [14] = true }
-- where each direction starts in a packed pose (the right hand, the left hand, the weapon)
local VECTOR_CHANNELS = { 1, 5, 9 }
local function spline(keys: { Key }, hold: Key, def: any): (number) -> any
	local ts, vs, stops, hits, named = {}, {}, {}, {}, {}
	local edge = hold.edge or 0
	for i, key in keys do
		local f = flat(key, hold, def)
		ts[i], vs[i], stops[i], hits[i], named[i] = key.u, packPose(f), key.stop == true, key.hit == true, f.off ~= nil
	end
	local n = #ts
	local into, outof = {}, {}
	for i = 1, n do
		local mIn, mOut = table.create(#vs[i], 0), table.create(#vs[i], 0)
		if i > 1 and i < n and not stops[i] then
			local dtA, dtB = math.max(ts[i] - ts[i - 1], 1e-4), math.max(ts[i + 1] - ts[i], 1e-4)
			for c = 1, #vs[i] do
				local d0 = (vs[i][c] - vs[i - 1][c]) / dtA
				local d1 = (vs[i + 1][c] - vs[i][c]) / dtB
				if hits[i] and not GRIP_CHANNELS[c] then
					-- the blow: in at full speed; out carrying through (no faster than the
					-- follow-through can take without overshooting it) or bouncing back
					mIn[c] = d0 * IMPACT_IN
					if d0 * d1 > 0 then
						mOut[c] = math.sign(d1) * math.min(math.abs(mIn[c]), 3 * math.abs(d1))
					else
						mOut[c] = d1 * IMPACT_OUT
					end
				elseif d0 * d1 > 0 then
					local limit = 3 * math.min(math.abs(d0), math.abs(d1))
					local m = math.clamp((d0 + d1) / 2, -limit, limit)
					mIn[c], mOut[c] = m, m
				end
			end
		end
		into[i], outof[i] = mIn, mOut
	end
	-- the edge offset turns in over the wind-up and back out on the way to the hold, so the
	-- hold itself looks as it always did
	local firstStop, lastStop = 0.3, 0.75
	for i = 2, n - 1 do
		if stops[i] or hits[i] then
			firstStop = ts[i]
			break
		end
	end
	for i = n - 1, 2, -1 do
		if stops[i] or hits[i] then
			lastStop = ts[i]
			break
		end
	end
	local function edgeAt(u: number): number
		if edge == 0 then
			return 0
		end
		return edge * smooth(u / math.max(firstStop, 1e-3)) * smooth((1 - u) / math.max(1 - lastStop, 1e-3))
	end
	-- The directions (each hand from its shoulder, the weapon) travel along the arc between
	-- keys. Splined as three numbers they cut across the middle of a big turn, so the turn
	-- bunched up halfway and slowed into the blow. Each stretch's turn is timed by the turning
	-- speeds at its two keys, with the same rules as the numbers: carried through a key the
	-- motion passes through, zero at a stop or a turn back, and at a hit full speed in (twice
	-- the stretch's own) and carried through or bounced back out.
	local function dirOf(i: number, c: number): Vector3
		return Vector3.new(vs[i][c], vs[i][c + 1], vs[i][c + 2])
	end
	local function angleBetween(a: Vector3, b: Vector3): number
		return math.acos(math.clamp(a:Dot(b), -1, 1))
	end
	-- the way the arc from a to b leaves a, and arrives at b
	local function leaving(a: Vector3, b: Vector3): Vector3
		local t = b - a * a:Dot(b)
		return if t.Magnitude > 1e-5 then t.Unit else Vector3.zero
	end
	local arcSpeed: { [number]: { [number]: { number } } } = {} -- [key][channel] = { in, out } (radians a key-time unit)
	for i = 1, n do
		arcSpeed[i] = {}
		for _, c in VECTOR_CHANNELS do
			local speeds = { 0, 0 }
			if i > 1 and i < n and not stops[i] then
				local here = dirOf(i, c)
				local before, after = dirOf(i - 1, c), dirOf(i + 1, c)
				local w0 = angleBetween(before, here) / math.max(ts[i] - ts[i - 1], 1e-4)
				local w1 = angleBetween(here, after) / math.max(ts[i + 1] - ts[i], 1e-4)
				-- carried on, or turned back?
				local arriving = -leaving(here, before)
				local onward = arriving:Dot(leaving(here, after)) > -0.2 and w0 > 1e-3 and w1 > 1e-3
				if hits[i] then
					speeds[1] = w0 * IMPACT_IN
					speeds[2] = if onward then math.min(speeds[1], 3 * w1) else w1 * IMPACT_OUT
				elseif onward then
					local m = math.min((w0 + w1) / 2, 3 * math.min(w0, w1))
					speeds[1], speeds[2] = m, m
				end
			end
			arcSpeed[i][c] = speeds
		end
	end
	local function slerp(a: Vector3, b: Vector3, t: number): Vector3
		local angle = angleBetween(a, b)
		if angle < 1e-4 then
			return a
		end
		local sinA = math.sin(angle)
		if sinA < 1e-3 then
			local m = a:Lerp(b, t)
			return if m.Magnitude > 1e-4 then m.Unit else a
		end
		return (a * math.sin((1 - t) * angle) + b * math.sin(t * angle)) / sinA
	end
	return function(u: number): any
		if n == 1 then
			return unpackPose(vs[1], named[1], 0)
		end
		local i = 1
		while i < n - 1 and u > ts[i + 1] do
			i += 1
		end
		local span = ts[i + 1] - ts[i]
		local x = if span > 0 then math.clamp((u - ts[i]) / span, 0, 1) else 1
		local a, b, ma, mb = vs[i], vs[i + 1], outof[i], into[i + 1]
		local v = table.create(#a, 0)
		for c = 1, #a do
			v[c] = hermite(a[c], b[c], ma[c] * span, mb[c] * span, x)
		end
		for _, c in VECTOR_CHANNELS do
			local from, to = dirOf(i, c), dirOf(i + 1, c)
			local angle = angleBetween(from, to)
			local progress = x
			if angle > 1e-4 and span > 0 then
				local m0 = math.min(arcSpeed[i][c][2] * span / angle, 3)
				local m1 = math.min(arcSpeed[i + 1][c][1] * span / angle, 3)
				progress = hermite(0, 1, m0, m1, x)
			end
			local d = slerp(from, to, progress)
			v[c], v[c + 1], v[c + 2] = d.X, d.Y, d.Z
		end
		return unpackPose(v, named[i] or named[i + 1], edgeAt(u))
	end
end

-- Retime a swing so its `hit` key (at key time k) lands at clip time h: a smooth,
-- always-forward curve through (0, 0), (h, k), (1, 1).
local function warp(h: number?, k: number?): (number) -> number
	if not h or not k or h <= 0 or h >= 1 or k <= 0 or k >= 1 or math.abs(h - k) < 1e-3 then
		return function(u: number): number
			return u
		end
	end
	local s0, s1 = k / h, (1 - k) / (1 - h)
	local mid = 2 * s0 * s1 / (s0 + s1)
	return function(u: number): number
		if u <= h then
			return hermite(0, k, s0 * h, mid * h, u / h)
		end
		return hermite(k, 1, mid * (1 - h), s1 * (1 - h), (u - h) / (1 - h))
	end
end

local function holdOf(def: any): Key
	if def.unarmed then
		return {}
	end
	return Weapons.HOLDS[def.id] or { hand = { 1.5, -0.85, -0.3 }, dir = { 0, 0.3, -1 } }
end

-- The edge leading: across the LEAD stretch, the roll that turns the edge (the -Y side,
-- after the hold's `edge`) toward the way the weapon's head is moving, measured from the
-- swing itself (the body's turn included), blended in where the head moves fast and
-- across its length (a thrust keeps its roll). `sym`: either side of the edge will do.
local LEAD_SAMPLES = 96
local function leadRolls(def: any, sample: (number) -> any, window: { number }, sym: boolean): (number) -> number
	local head = headOf(def)
	local tips, frames, rolls = {}, {}, {}
	for j = 0, LEAD_SAMPLES do
		local p = sample(j / LEAD_SAMPLES)
		local s = solve(p, def)
		tips[j] = s.body * (s.grip * Vector3.new(0, 0, -head))
		frames[j] = s.body.Rotation * fromTo(FORWARD, p.dir.Unit)
		rolls[j] = p.roll
	end
	local moves, fastest = {}, 0
	for j = 0, LEAD_SAMPLES do
		local a, b = math.max(j - 1, 0), math.min(j + 1, LEAD_SAMPLES)
		local v = frames[j]:VectorToObjectSpace(tips[b] - tips[a])
		moves[j] = v
		local u = j / LEAD_SAMPLES
		if u >= window[1] and u <= window[2] then
			fastest = math.max(fastest, v.Magnitude)
		end
	end
	local period = if sym then 180 else 360
	local out = {}
	local last: number? = nil
	for j = 0, LEAD_SAMPLES do
		local u = j / LEAD_SAMPLES
		local v = moves[j]
		local roll = rolls[j]
		local across = math.sqrt(v.X * v.X + v.Y * v.Y)
		local weight = 0
		if fastest > 0 and across > 1e-6 then
			local inside = smooth((u - window[1]) / 0.06) * smooth((window[2] - u) / 0.06)
			weight = inside * smooth((across / v.Magnitude - 0.3) / 0.3) * smooth(v.Magnitude / (0.35 * fastest))
		end
		if weight > 0 then
			local target = math.deg(math.atan2(v.X, -v.Y))
			local near = last or roll
			target += math.round((near - target) / period) * period
			last = target
			roll += (target - roll) * weight
		end
		out[j] = roll
	end
	local soft = {}
	for j = 0, LEAD_SAMPLES do
		local sum, count = 0, 0
		for d = -2, 2 do
			local i = j + d
			if i >= 0 and i <= LEAD_SAMPLES then
				sum += out[i]
				count += 1
			end
		end
		soft[j] = sum / count
	end
	return function(u: number): number
		local x = math.clamp(u, 0, 1) * LEAD_SAMPLES
		local j = math.min(math.floor(x), LEAD_SAMPLES - 1)
		return soft[j] + (soft[j + 1] - soft[j]) * (x - j)
	end
end

-- The pose at clip time u of one swing as the def plays it (retimed, edge leading).
type Sampler = (number) -> any
local samplerCache: { [string]: Sampler } = {}
local function samplerOf(def: any, swingName: string?, hitAt: number?): Sampler
	local name = swingName or def.swing
	local cacheKey = def.id .. "/" .. tostring(name) .. "/" .. tostring(hitAt)
	local cached = samplerCache[cacheKey]
	if cached then
		return cached
	end
	local keys = Weapons.SWINGS[name] or { { u = 0 }, { u = 1 } }
	local hold = holdOf(def)
	local sample = spline(keys, hold, def)
	local hitKey: number? = nil
	for _, key in keys do
		if key.hit then
			hitKey = key.u
			break
		end
	end
	local retime = warp(if swingName then hitAt else (hitAt or def.hitTime), hitKey)
	local window = Weapons.LEAD[name]
	local roll = if window and not def.worn and not def.unarmed then leadRolls(def, sample, window, hold.sym == true) else nil
	local function at(u: number): any
		local k = retime(u)
		local p = sample(k)
		if roll then
			p.roll = roll(k)
		end
		return p
	end
	samplerCache[cacheKey] = at
	return at
end

-- ==================== clips ====================

local SAMPLES = 40
local TRAIL_BEFORE, TRAIL_AFTER = 0.2, 0.18

local holdCache: { [string]: any } = {}
local swingCache: { [string]: any } = {}
local bodyCache: { [string]: any } = {}

function Weapons.hold(def: any): any
	if def.unarmed then
		return nil
	end
	local cached = holdCache[def.id]
	if cached then
		return cached
	end
	local hold = holdOf(def)
	local solved = solve(flat({}, hold, def), def)
	local joints = {}
	for joint, cf in solved.channels do
		-- A two-handed weapon carried in one hand leaves the left arm free (unless the
		-- hold places the left hand, like the gauntlets' guard).
		if joint == "LeftShoulder" and (hold.two or 0) <= 0 and not hold.left then
			continue
		end
		joints[joint] = { { t = 0, cf = cf } }
	end
	local clip = Clip.new({
		name = "Hold_" .. def.id,
		priority = "Hold",
		looped = true,
		length = 1,
		fadeIn = 0.15,
		fadeOut = 0.15,
		joints = joints,
	})
	holdCache[def.id] = clip
	return clip
end

-- Builds the arms and body clips of one swing: the def's own (`swing`), or another named
-- swing held the same way (`extra`, cached under "<id>/<swing>").
local function build(def: any, swingName: string?, hitAt: number?)
	local cacheKey = if swingName then def.id .. "/" .. swingName else def.id
	local sample = samplerOf(def, swingName, hitAt)
	local arms: { [string]: { any } } = {}
	local body: { any } = {}
	for i = 0, SAMPLES do
		local u = i / SAMPLES
		local solved = solve(sample(u), def)
		for joint, cf in solved.channels do
			arms[joint] = arms[joint] or {}
			table.insert(arms[joint], { t = u, cf = cf, ease = "Linear" })
		end
		table.insert(body, { t = u, cf = solved.body, ease = "Linear" })
	end
	local hit = hitAt or def.hitTime or 0.5
	swingCache[cacheKey] = Clip.new({
		name = "Swing_" .. cacheKey,
		priority = "Action",
		length = 1,
		fadeIn = 0.04,
		fadeOut = 0.1,
		joints = arms,
		markers = {
			{ t = math.max(0, hit - TRAIL_BEFORE), name = "TrailOn" },
			{ t = hit, name = "Hit" },
			{ t = math.min(1, hit + TRAIL_AFTER), name = "TrailOff" },
		},
	})
	bodyCache[cacheKey] = Clip.new({
		name = "SwingBody_" .. cacheKey,
		priority = "Action",
		additive = true,
		length = 1,
		fadeIn = 0.04,
		fadeOut = 0.1,
		joints = { Root = body },
	})
end

function Weapons.swing(def: any): any
	if not swingCache[def.id] then
		build(def)
	end
	return swingCache[def.id]
end

function Weapons.swingBody(def: any): any
	if not bodyCache[def.id] then
		build(def)
	end
	return bodyCache[def.id]
end

-- Another swing in SWINGS played with this def's hold and hands (the rod's Reel): the arms
-- clip and its additive body clip, a "Hit" marker at `hitAt` (default 0.5).
function Weapons.extra(def: any, swingName: string, hitAt: number?): (any, any)
	local key = def.id .. "/" .. swingName
	if not swingCache[key] then
		build(def, swingName, hitAt)
	end
	return swingCache[key], bodyCache[key]
end

-- The pose at one point of a swing (u) or the hold (u = nil), solved: channel
-- CFrames plus the body pose -- for previews and tests.
function Weapons.pose(def: any, u: number?): Solved
	if u == nil then
		return solve(flat({}, holdOf(def), def), def)
	end
	return solve(samplerOf(def)(u), def)
end

-- The weapon's CFrame in the root's space (the body's turn included) at swing time u, or
-- in the hold (u = nil).
function Weapons.gripAt(def: any, u: number?): CFrame
	local solved = Weapons.pose(def, u)
	return solved.body * solved.grip
end

-- Worst reach error (studs) for each hand across the hold and the swing, and
-- the swing fraction where each happens (-1 = the hold).
function Weapons.report(def: any): (number, number, number, number)
	local right, left, rightAt, leftAt = 0, 0, 0, 0
	for i = -1, SAMPLES do
		local u = if i < 0 then nil else i / SAMPLES
		local solved = Weapons.pose(def, u)
		if solved.rightErr > right then
			right, rightAt = solved.rightErr, u or -1
		end
		if solved.leftErr > left then
			left, leftAt = solved.leftErr, u or -1
		end
	end
	return right, left, rightAt, leftAt
end

-- (tests: the spline and the hold of a def)
Weapons._spline = function(def: any, name: string): (number) -> any
	return spline(Weapons.SWINGS[name], holdOf(def), def)
end

return Weapons
