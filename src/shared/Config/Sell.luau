--!strict
-- Sell: what can be sold from the Inventory's Sell Mode and for how much (2026-10-20,
-- the user: "all weapons, tools, armors, potions and materials (besides the quest
-- materials) should be sellable", priced per item, not per rarity).
--
-- Each item's price is the `sell` field on its own def (Config/Weapons, Tools, Armor,
-- Potions, Materials); the numbers are placeholders to tune. An item with no `sell`
-- can't be sold, and these never can, whatever their def says:
--   * the starter weapon (always owned) and key items (`keep`: the Rusty Blade and the
--     Worldheart Blades, the secret-weapon chain)
--   * quest items (`quest`) and secret-weapon cores (`core`): one per player, ever
--
-- Kinds: "weapon", "tool" and "armor" are owned once (count 1); "potion" and "material"
-- stack, and a sale names how many. SellService (server) re-checks everything here;
-- the Inventory reads it to show prices and to know which tiles can be picked.

local Config = script.Parent
local Armor = require(Config:WaitForChild("Armor"))
local Materials = require(Config:WaitForChild("Materials"))
local Potions = require(Config:WaitForChild("Potions"))
local Tools = require(Config:WaitForChild("Tools"))
local Weapons = require(Config:WaitForChild("Weapons"))

local Sell = {}

export type Kind = "weapon" | "tool" | "armor" | "potion" | "material"

-- The kinds that stack (a sale names a count).
Sell.Stacks = { potion = true, material = true } :: { [string]: boolean }

-- Coins one of this item sells for, or nil if it can't be sold.
function Sell.price(kind: string, id: any): number?
	local def: any = nil
	if kind == "weapon" then
		def = Weapons.get(id)
		if def and (def.starter or def.keep or def.unarmed) then
			return nil
		end
	elseif kind == "tool" then
		def = Tools.get(id)
	elseif kind == "armor" then
		def = Armor.get(id)
	elseif kind == "potion" then
		def = Potions.get(id)
	elseif kind == "material" then
		def = Materials.get(id)
		if def and (def.quest or def.core) then
			return nil
		end
	end
	local price = def and def.sell
	return if type(price) == "number" and price > 0 then price else nil
end

return Sell
