--!strict
-- Gates: the world gates and every word their signs show (the user's rule,
-- 2026-10-10: UI text lives in code, the sign itself is hand-built in Studio).
--
-- Each gate is a model in Workspace.Shared.Gates named `model`, holding a
-- `Barrier` (the vine curtain) and a `SignBoard`; its sign is the SurfaceGui in
-- StarterGui whose `GateId` attribute is the gate's id. Buying it (GateService)
-- needs the player's Level >= `level`, Coins >= `coins` and every `materials`
-- entry (gathered materials, 2026-10-19, user: the gate ties into gathering),
-- spends the coins and materials and unlocks `world` (PlayerDataService.unlockWorld, saved). A player whose
-- HighestWorld >= `world` sees the gate open: no curtain, the sign says so.
-- A gate also needs the world before it unlocked (2026-10-24, the user: with the branching world map,
-- World 4's gate stands in World 2, so a World 2 player could otherwise skip World 3): `requires`
-- (default `world` - 1; Gates.requires) must be <= the player's HighestWorld.
-- Costs are placeholders until the user sets them.

export type Gate = {
	id: string,
	world: number, -- the world it opens (Config/Worlds id; its `name` is the sign's title)
	model: string, -- Workspace.Shared.Gates.<model>
	level: number,
	coins: number,
	materials: { { id: string, count: number } }?, -- shown on the sign's MaterialRow1, 2...
	requires: number?, -- the world that must be unlocked first (default world - 1)
}

local Gates = {}

Gates.list = {
	{
		id = "World2",
		world = 2,
		model = "World2Gate",
		level = 25, -- the user's pick (2026-10-19); 10 on the old curve, then 18
		coins = 2500, -- the 30-minute World 1 (2026-10-19)
		materials = { { id = "OakLog", count = 20 }, { id = "Stone", count = 20 } },
	},
	-- behind World 2's boss ruins, centred on them: the crystal wall in the cave mouth (2026-10-13)
	{
		id = "World3",
		world = 3,
		model = "World3Gate",
		-- 2026-10-21 (the user asked about 50-75 / 25-50k): a typical player has 25,000
		-- coins at about level 50, so this keeps World 2 near its 45 minutes (47.9 with
		-- world_sim.py); 75 / 50,000 would make it 103. Was 36 (20 before 2026-10-19).
		level = 50,
		coins = 25000,
		materials = { { id = "RedwoodLog", count = 25 }, { id = "AmberSap", count = 3 } }, -- 3 sap: the user, 2026-10-21
	},
	-- World 4's gate is a mock until World 4 exists (2026-10-24, the user: continue the gates' pattern and tune
	-- World 3 to it): level 75 (a gate every 25 levels), 225,000 coins, 20 Crystal Shards and 3 Raw Gems (World 3's
	-- mined materials; 2026-10-24, the user's pick of the simulated options: 30 + 5 and 250,000 made World 3 58.7 min,
	-- this 52.9, the middle of its 45-60). World 3's run (world_sim.py, world3.json's gate) aims at it. It stands in World 2 and needs
	-- World 3 (memory world-map-branches).
	-- The Caravan Gate (2026-10-25, the user's pick B): in the corridor out of World 2's south-west corner,
	-- its two lattice doors swing open (GateUI, SwingAngle).
	{
		id = "World4",
		world = 4,
		model = "World4Gate",
		level = 75,
		coins = 225000,
		materials = { { id = "CrystalShard", count = 20 }, { id = "RawGem", count = 3 } },
		requires = 3,
	},
} :: { Gate }

-- The world a player must have unlocked before this gate can be bought.
function Gates.requires(gate: Gate): number
	return gate.requires or gate.world - 1
end

-- How close (studs from the sign board) a player must stand to buy.
Gates.BUY_RANGE = 40

-- Everything the sign says. %d / %s are filled by GateUI.
Gates.Text = {
	banner = "World %d", -- the world number
	level = "Level %d", -- the level needed
	coins = "%s Coins", -- the price, with commas
	youLevel = "You: %d", -- shown beside an unmet level
	youCoins = "You: %s", -- shown beside unmet coins
	material = "%s %s", -- a material's count (with commas) and name
	youMaterial = "You: %s", -- shown beside an unmet material
	buy = "Buy",
	locked = "Locked",
	needsWorld = "World %d first", -- the Buy button while the world before isn't unlocked
	unlocked = "Unlocked!",
}

function Gates.byId(id: string): Gate?
	for _, gate in Gates.list do
		if gate.id == id then
			return gate
		end
	end
	return nil
end

return Gates
