--!strict
-- Tools: the gathering tools -- axes, pickaxes, shovels and fishing rods (2026-10-18,
-- the user's design). Each kind has its own hotbar slot next to the weapon's
-- (WeaponHud/Hotbar, Slot2.. in Tools.Kinds order), and each world sells a better tier
-- of the kinds it uses (World 1 a Wooden Axe, World 2 a Stone Axe...). A gathering node
-- (Config/Gathering) names the kind it needs and the lowest tier that can break it, so
-- an activity that comes back in a later world needs that world's tool. A higher tier
-- also hits harder (`power`), so old nodes go faster.
--
-- A slot always holds the player's best tool of its kind (highest tier owned). Taking a
-- tool out puts the weapon away, and taking the weapon out puts the tool away: one
-- thing in hand. Tools never hurt enemies.
--
--   id        the key, saved in the player's "tools" section and the model's name in
--             ReplicatedStorage/Assets/Tools (a Grip PrimaryPart, like a weapon)
--   name      shown in the hotbar and the shop
--   kind      one of Tools.Kinds
--   tier      1 = World 1's tool, 2 = the next world's...
--   world     the world whose shop sells it
--   power     taken off a node's hp per hit
--   rarity    its tile skin (the hotbar slot, the Inventory)
--   price     coins at that world's shop (placeholder)
--   icon      its drawn picture (none yet: the hotbar falls back to the 3D view)
-- Swinging reuses the weapon animation system (Animation.Clips.Weapons keys holds by id
-- and swings by `swing`), so each tool has the same swing fields a weapon has:
--   handed, cooldown, hitTime, reach, arc, maxTargets, swing

local RunService = game:GetService("RunService")

local Tools = {}

export type ToolDef = {
	id: string,
	name: string,
	kind: string,
	tier: number,
	world: number,
	power: number,
	rarity: string,
	price: number?,
	icon: string?,
	handed: number,
	cooldown: number,
	hitTime: number,
	reach: number,
	arc: number,
	maxTargets: number,
	swing: string,
	knockback: number,
}

-- Hotbar order: Slot2 is the first kind, Slot3 the second, and so on (keys 2, 3...).
-- A slot shows only once the player owns a tool of its kind.
Tools.Kinds = { "Axe", "Pickaxe", "Shovel", "Rod" }

Tools.KindNames = {
	Axe = "Axe",
	Pickaxe = "Pickaxe",
	Shovel = "Shovel",
	Rod = "Fishing Rod",
}

Tools.Defs = {
	-- ==================== World 1 (The Sunny Meadows) ====================
	-- Placeholder numbers: an oak (Config/Gathering, 50 hp) falls in 5 chops, about 4 s.
	WoodenAxe = {
		id = "WoodenAxe",
		name = "Wooden Axe",
		kind = "Axe",
		tier = 1,
		world = 1,
		power = 10,
		rarity = "Common",
		price = 50,
		handed = 1,
		cooldown = 0.8,
		hitTime = 0.52,
		reach = 5,
		arc = 70,
		maxTargets = 1,
		knockback = 0,
		-- the Machete's diagonal: a chop down and across into the trunk
		swing = "Diagonal",
	},
	WoodenPickaxe = {
		id = "WoodenPickaxe",
		name = "Wooden Pickaxe",
		kind = "Pickaxe",
		tier = 1,
		world = 1,
		power = 10,
		rarity = "Common",
		price = 50,
		handed = 1,
		cooldown = 0.9,
		hitTime = 0.58,
		reach = 5,
		arc = 70,
		maxTargets = 1,
		knockback = 0,
		-- the World 3 pickaxes' swing: up over the shoulder, then down into the rock
		swing = "Mine",
	},
	-- Fishing (Config/Fishing): held in one hand, cast with both (handed 2 gives the cast
	-- its left hand; the hold leaves it free). Its swing is the cast, and the swing's "Hit"
	-- marker is the moment the line is let go. A rod never breaks nodes (power 0).
	WoodenRod = {
		id = "WoodenRod",
		name = "Wooden Rod",
		kind = "Rod",
		tier = 1,
		world = 1,
		power = 0,
		rarity = "Common",
		price = 75,
		handed = 2,
		cooldown = 1.0,
		hitTime = 0.56,
		reach = 0,
		arc = 0,
		maxTargets = 0,
		knockback = 0,
		swing = "Cast",
	},
} :: { [string]: ToolDef }

-- Studio only (testing, 2026-10-18): every player owns these from the start. Empty it
-- once tools can be bought.
Tools.testStartTools = if RunService:IsStudio() then { "WoodenAxe", "WoodenPickaxe", "WoodenRod" } else {}

function Tools.get(id: any): ToolDef?
	return if type(id) == "string" then Tools.Defs[id] else nil
end

-- The hotbar slot number for a kind (Slot2 for the first kind), or nil.
function Tools.slotOf(kind: string): number?
	for i, k in Tools.Kinds do
		if k == kind then
			return i + 1
		end
	end
	return nil
end

-- The player's owned tool ids, from their "OwnedTools" attribute (ToolService publishes
-- it). Works on both sides.
function Tools.owned(player: Player): { [string]: boolean }
	local out: { [string]: boolean } = {}
	local text = player:GetAttribute("OwnedTools")
	for id in (if type(text) == "string" then text else ""):gmatch("[^,]+") do
		if Tools.Defs[id] then
			out[id] = true
		end
	end
	return out
end

-- The best tool of a kind in an owned set: the highest tier.
function Tools.bestOf(owned: { [string]: boolean }, kind: string): ToolDef?
	local best: ToolDef? = nil
	for id in owned do
		local def = Tools.Defs[id]
		if def and def.kind == kind and (best == nil or def.tier > best.tier) then
			best = def
		end
	end
	return best
end

return Tools
