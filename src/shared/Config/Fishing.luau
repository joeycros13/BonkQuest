--!strict
-- Fishing: casting a rod into the water for fish (2026-10-18, the user's design). A
-- fishing rod is a gathering tool (Config/Tools, kind "Rod"); fish are materials
-- (Config/Materials, `fished`). FishingService runs it on the server, FishingController
-- and FishingBarUI on the client.
--
--   1. Cast: a click with the rod out swings it back over the head with both hands and
--      throws the bobber about 5 blocks ahead (`castDistance`). It has to land on water:
--      a part tagged "FishingWater" (Fishing.Tag) whose `Spot` attribute names one of the
--      Spots below. Anywhere along the water works: the pier or any bank.
--   2. Wait: after `biteDelay` seconds a fish's shadow swims in (`approachSeconds`), then
--      bites: the bobber sinks under for `biteSeconds`. Click while it is under to hook
--      the fish; miss it and the bobber comes back up and you wait for the next one.
--      Clicking while nothing bites reels the line in.
--   3. The reel bar (issue 26, 2026-10-25, the user's design; it replaced three closing
--      rings): a tall bar on the right of the screen with a green zone in its middle and a
--      marker that slides up and down it without ever stopping. Each click while the
--      marker is in the green adds a check; `checks` (3) lands the fish. The first miss is
--      forgiven (`slips`), the next lets the fish go. Rarer fish have a smaller zone and a
--      faster marker, and the rarest one jerks in bursts (Difficulty); the zone shrinks a
--      little with each check (`shrink`). The player leans back and fights the rod.
--   4. Landed: the line pulls back and the fish pops up out of the water; it goes into
--      the player's materials (MaterialService.drop, the side toast).
--
-- A spot needs a rod of its `tier` or better (the user, 2026-10-20: tools only work for their
-- own world; a World 1 rod in a World 2 pond doesn't, and "Needs a Stone Rod" pops up, like
-- a weak axe on a tree). FishingService refuses the cast; FishingController shows the popup.
--
-- Every fish is the same model in the water, a dark shadow (ReplicatedStorage/Assets/
-- Fishing/FishShadow); only the icons differ (user, 2026-10-18).
--
-- The marker's path is a formula of time (Fishing.sliderAt), so the client draws it and the
-- server checks a click against the same clock (workspace:GetServerTimeNow()): the client
-- sends the server time it clicked at, and the server judges that moment, taking clicks
-- only up to `clickLag` seconds old.

local Fishing = {}

-- speed: sweeps (top to bottom, or back) a second; zone: the green's share of the bar;
-- jerk: 0..0.9, how much the speed surges and slows (in bursts JERK_RATE a second)
export type Difficulty = { speed: number, zone: number, jerk: number }
export type FishEntry = { id: string, weight: number }
export type Spot = { id: string, name: string, world: number, tier: number, fish: { FishEntry } }

Fishing.Tag = "FishingWater"

-- The cast (client, checked loosely by the server)
Fishing.castDistance = 20 -- studs ahead of the player the bobber lands (about 5 blocks)
Fishing.castHeight = 7 -- how far the bobber's arc rises above the straight line
Fishing.flightSeconds = 0.8
Fishing.maxCastRange = 30 -- the server refuses a landing farther than this from the player
Fishing.lineBreak = 36 -- walking this far from the bobber reels the line in

-- The wait and the bite (server)
Fishing.biteDelay = { 3, 8 } -- seconds after landing (and after each missed bite)
Fishing.approachSeconds = 1.6 -- the shadow swims to the bobber before it bites
Fishing.biteSeconds = { 1, 2 } -- how long the bobber stays under (user: 1-2 s)
Fishing.nibbles = { 1, 3 } -- little tugs on the bobber before the real bite (look only)
Fishing.nibbleSeconds = 0.6 -- each nibble's time; the bite waits for them

-- The reel bar
Fishing.checks = 3 -- clicks in the green to land the fish
Fishing.slips = 1 -- misses forgiven; the one after lets the fish go (user, 2026-10-25)
Fishing.shrink = 0.12 -- the zone loses this share of itself with each check
Fishing.barLead = 0.4 -- seconds after the bar pops in before the marker starts
Fishing.fightSeconds = 30 -- a fight nobody finishes lets the fish go
Fishing.clickGap = 0.12 -- clicks closer together than this count once
Fishing.clickLag = 0.6 -- the oldest click time the server takes (network lag)
local JERK_RATE = 4 -- radians a second of the jerk's surge

-- Generous zones (user: "so the players dont mess up"), harder for harder fish.
Fishing.Difficulty = {
	Easy = { speed = 0.55, zone = 0.34, jerk = 0 },
	Medium = { speed = 0.8, zone = 0.26, jerk = 0 },
	Hard = { speed = 1.0, zone = 0.2, jerk = 0.6 },
} :: { [string]: Difficulty }

-- How big each difficulty's shadow is in the water (a rare fish is a bigger shadow).
Fishing.ShadowScale = { Easy = 0.85, Medium = 1.0, Hard = 1.25 } :: { [string]: number }

-- Which difficulty each fish (a Config/Materials id) fights with.
Fishing.Fish = {
	Minnow = "Easy",
	Sunfish = "Medium",
	GoldenCarp = "Hard",
	Trout = "Easy",
	Perch = "Medium",
	RainbowTrout = "Hard",
	Glowfish = "Easy",
	BlindCavefish = "Medium",
	CrystalEel = "Hard",
} :: { [string]: string }

Fishing.Spots = {
	-- World 1's pond, by Finn's fishing hut
	SunnyPond = {
		id = "SunnyPond",
		name = "The Pond",
		world = 1,
		tier = 1,
		fish = {
			{ id = "Minnow", weight = 60 },
			{ id = "Sunfish", weight = 30 },
			{ id = "GoldenCarp", weight = 10 },
		},
	},
	-- World 2's creek and pond: one water part (Ground/Creek/Water), so the whole creek fishes
	-- too. The approved table's fish (memory tools-per-world): Trout and the rare Rainbow Trout, plus
	-- the Perch (the user, 2026-10-20: three tiers like World 1's pond, at its weights).
	RedwoodPond = {
		id = "RedwoodPond",
		name = "The Creek",
		world = 2,
		tier = 2,
		fish = {
			{ id = "Trout", weight = 60 },
			{ id = "Perch", weight = 30 },
			{ id = "RainbowTrout", weight = 10 },
		},
	},
	-- World 3's glowing lake in the middle hall (Ground/Lake/Water, 2026-10-24): the user's fish
	-- (memory tools-per-world), a Crystal Rod or better.
	CrystalLake = {
		id = "CrystalLake",
		name = "The Glowing Lake",
		world = 3,
		tier = 3,
		fish = {
			{ id = "Glowfish", weight = 60 },
			{ id = "BlindCavefish", weight = 30 },
			{ id = "CrystalEel", weight = 10 },
		},
	},
} :: { [string]: Spot }

function Fishing.spot(id: any): Spot?
	return if type(id) == "string" then Fishing.Spots[id] else nil
end

-- The rod a spot needs: the name of the lowest-tier rod that can fish it ("Stone Rod").
function Fishing.rodFor(spot: Spot): string
	local Tools = require(script.Parent:WaitForChild("Tools"))
	local best: any = nil
	for _, def in Tools.Defs do
		if def.kind == "Rod" and def.tier >= spot.tier and (best == nil or def.tier < best.tier) then
			best = def
		end
	end
	return if best then best.name else "better rod"
end

function Fishing.difficultyOf(fishId: string): Difficulty
	return Fishing.Difficulty[Fishing.Fish[fishId] or "Easy"] or Fishing.Difficulty.Easy
end

-- Where the marker is `t` seconds after it starts: 0 at the top of the bar, 1 at the
-- bottom. It eases at each end and never stops; a jerk speeds it up and slows it down
-- (its speed stays above zero while jerk < 1).
function Fishing.sliderAt(difficulty: Difficulty, t: number): number
	if t <= 0 then
		return 0
	end
	local phase = difficulty.speed * (t + difficulty.jerk / JERK_RATE * math.sin(JERK_RATE * t))
	return (1 - math.cos(math.pi * phase)) / 2
end

-- The green's share of the bar after `checks` checks; it sits in the bar's middle.
function Fishing.zoneSize(difficulty: Difficulty, checks: number): number
	return difficulty.zone * (1 - Fishing.shrink * checks)
end

-- Whether a click `t` seconds into the fight, with `checks` checks so far, is in the green.
function Fishing.inZone(difficulty: Difficulty, checks: number, t: number): boolean
	return math.abs(Fishing.sliderAt(difficulty, t) - 0.5) <= Fishing.zoneSize(difficulty, checks) / 2
end

-- A fish's chance at a spot (0..1), for the Index's drop slip.
function Fishing.chanceAt(spot: Spot, fishId: string): number?
	local total, mine = 0, nil
	for _, entry in spot.fish do
		total += entry.weight
		if entry.id == fishId then
			mine = entry.weight
		end
	end
	return if mine and total > 0 then mine / total else nil
end

return Fishing
