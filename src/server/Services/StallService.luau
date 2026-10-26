--!strict
-- StallService: what the market stalls sell (2026-10-12).
--
--   * Crafting stall: Remotes.CraftArmor(id) crafts an armour set (Config/Armor).
--     It needs the set's level, its coins and every material in its recipe
--     (MaterialService); all are spent, the set is granted (ArmorService) and
--     worn straight away.
--   * Weapons stall: Remotes.BuyWeapon(id) buys a weapon that has a `price` in
--     Config/Weapons (Common..Epic only); the coins are spent and the weapon is
--     granted (MeleeService) with the Index's pop-up (IndexService.showWeapon).
--     Its Tools tab (2026-10-19): Remotes.BuyTool(id) buys a gathering tool with a
--     `price` in Config/Tools, sold at its own world's stall; the coins are spent and
--     the tool is granted (ToolService), which shows its hotbar slot. A tool with a
--     `recipe` (2026-10-20, the Stone Axe) is an upgrade: it also takes the previous
--     tier of the same tool and the recipe's materials.
--
-- All are RemoteFunctions returning (ok, reason). reason is one of:
--   "unknown"    no such item, or it isn't for sale
--   "owned"      the player has it already
--   "level"      their level is too low
--   "coins"      not enough coins
--   "materials"  a recipe material is short
--   "tool"       an upgrade's previous tool isn't owned
--   "range"      they aren't standing at a stall of that kind
-- A stall is a ring tagged Interactable whose "Station" attribute is "Crafting"
-- or "Weapons" (InteractionController opens its panel on the client); a
-- request only counts from inside one, with a little slack. Each world has its
-- own pair (2026-10-12) and a ring's "World" attribute says whose items it
-- sells: a weapon or armour set is only sold at a stall of its own `world`.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Armor = require(Config:WaitForChild("Armor"))
local MapLayout = require(Config:WaitForChild("MapLayout"))
local Tools = require(Config:WaitForChild("Tools"))
local Weapons = require(Config:WaitForChild("Weapons"))

local StallService = {}

-- studs past a ring's edge a request still counts (the panel closes 2.5 out)
local RANGE_SLACK = 6
local VERTICAL_TOLERANCE = 12

local deps: any = nil

local function level(player: Player): number
	local value = player:GetAttribute("Level")
	return if type(value) == "number" then value else 1
end

-- Whether the player stands at a stall whose Station is `station` (and, when
-- `world` is given, whose World attribute matches it; a ring without one counts
-- as World 1).
function StallService.atStall(player: Player, station: string, world: number?): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	for _, ring in CollectionService:GetTagged(MapLayout.Tags.Interactable) do
		local ringWorld = ring:GetAttribute("World")
		ringWorld = if type(ringWorld) == "number" then ringWorld else 1
		if ring:IsA("BasePart") and ring:GetAttribute("Station") == station and (world == nil or world == ringWorld) then
			local radius = ring:GetAttribute("Radius")
			radius = if type(radius) == "number" and radius > 0 then radius else ring.Size.X / 2
			local offset = root.Position - ring.Position
			if Vector2.new(offset.X, offset.Z).Magnitude <= radius + RANGE_SLACK and math.abs(offset.Y) <= VERTICAL_TOLERANCE then
				return true
			end
		end
	end
	return false
end

-- Why the player can't craft `def` right now, or nil when they can.
function StallService.craftBlocker(player: Player, def: Armor.ArmorDef): string?
	if deps.Services.ArmorService.owns(player, def.id) then
		return "owned"
	elseif level(player) < def.level then
		return "level"
	elseif deps.Services.CoinService.get(player) < def.coins then
		return "coins"
	elseif not deps.Services.MaterialService.has(player, def.recipe) then
		return "materials"
	elseif not StallService.atStall(player, "Crafting", (def :: any).world or 1) then
		return "range"
	end
	return nil
end

function StallService.craft(player: Player, id: any): (boolean, string?)
	local def = Armor.get(id)
	if not def then
		return false, "unknown"
	end
	local blocker = StallService.craftBlocker(player, def)
	if blocker then
		return false, blocker
	end
	if not deps.Services.MaterialService.take(player, def.recipe) then
		return false, "materials"
	end
	deps.Services.CoinService.add(player, -def.coins)
	deps.Services.ArmorService.grant(player, def.id)
	-- put it on, unless the set worn is better (a coin set bought after a crafted one, 2026-10-26)
	local worn = Armor.get(player:GetAttribute("EquippedArmor") or "")
	if not worn or worn.health < def.health then
		deps.Services.ArmorService.equip(player, def.id)
	end
	task.spawn(deps.Services.PlayerDataService.saveNow, player)
	return true, nil
end

-- Why the player can't buy weapon `def` right now, or nil when they can.
function StallService.buyBlocker(player: Player, def: Weapons.WeaponDef): string?
	if not def.price or def.starter or def.unarmed then
		return "unknown"
	elseif deps.Services.MeleeService.owns(player, def.id) then
		return "owned"
	elseif deps.Services.CoinService.get(player) < def.price then
		return "coins"
	elseif not StallService.atStall(player, "Weapons", def.world or 1) then
		return "range"
	end
	return nil
end

function StallService.buy(player: Player, id: any): (boolean, string?)
	local def = Weapons.get(id)
	if not def then
		return false, "unknown"
	end
	local blocker = StallService.buyBlocker(player, def)
	if blocker then
		return false, blocker
	end
	deps.Services.CoinService.add(player, -(def.price :: number))
	deps.Services.MeleeService.grant(player, def.id)
	deps.Services.IndexService.showWeapon(player, def.id)
	task.spawn(deps.Services.PlayerDataService.saveNow, player)
	return true, nil
end

-- Why the player can't buy tool `def` right now, or nil when they can.
function StallService.buyToolBlocker(player: Player, def: Tools.ToolDef): string?
	if not def.price then
		return "unknown"
	elseif deps.Services.ToolService.owns(player, def.id) then
		return "owned"
	end
	local recipe = def.recipe
	if recipe then
		if recipe.tool and not deps.Services.ToolService.owns(player, recipe.tool) then
			return "tool"
		end
		for _, item in recipe.materials do
			if deps.Services.MaterialService.get(player, item.id) < item.count then
				return "materials"
			end
		end
	end
	if deps.Services.CoinService.get(player) < def.price then
		return "coins"
	elseif not StallService.atStall(player, "Weapons", def.world) then
		return "range"
	end
	return nil
end

function StallService.buyTool(player: Player, id: any): (boolean, string?)
	local def = Tools.get(id)
	if not def then
		return false, "unknown"
	end
	local blocker = StallService.buyToolBlocker(player, def)
	if blocker then
		return false, blocker
	end
	deps.Services.CoinService.add(player, -(def.price :: number))
	local recipe = def.recipe
	if recipe then
		for _, item in recipe.materials do
			deps.Services.MaterialService.add(player, item.id, -item.count)
		end
		if recipe.tool then
			deps.Services.ToolService.revoke(player, recipe.tool)
		end
	end
	deps.Services.ToolService.grant(player, def.id)
	task.spawn(deps.Services.PlayerDataService.saveNow, player)
	return true, nil
end

function StallService.init(injected: any)
	deps = injected
end

function StallService.start()
	deps.Remotes.getFunction("CraftArmor").OnServerInvoke = function(player: Player, id: any)
		return StallService.craft(player, id)
	end
	deps.Remotes.getFunction("BuyWeapon").OnServerInvoke = function(player: Player, id: any)
		return StallService.buy(player, id)
	end
	deps.Remotes.getFunction("BuyTool").OnServerInvoke = function(player: Player, id: any)
		return StallService.buyTool(player, id)
	end
end

return StallService
