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
-- Costs are placeholders until the user sets them.

export type Gate = {
	id: string,
	world: number, -- the world it opens (Config/Worlds id; its `name` is the sign's title)
	model: string, -- Workspace.Shared.Gates.<model>
	level: number,
	coins: number,
	materials: { { id: string, count: number } }?, -- shown on the sign's MaterialRow1, 2...
}

local Gates = {}

Gates.list = {
	{
		id = "World2",
		world = 2,
		model = "World2Gate",
		level = 10,
		coins = 5000,
		materials = { { id = "OakLog", count = 20 }, { id = "Stone", count = 20 } },
	},
	-- behind World 2's boss ruins, centred on them; a copy of the forest gate for now
	{ id = "World3", world = 3, model = "World3Gate", level = 20, coins = 25000 },
} :: { Gate }

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
