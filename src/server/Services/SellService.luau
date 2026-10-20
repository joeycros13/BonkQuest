--!strict
-- SellService: selling items from the Inventory's Sell Mode for coins (2026-10-20, the
-- user: every weapon, tool, armour set, potion and material sells, quest items aside).
--
-- Remotes.SellItems (a RemoteFunction) takes a list of { kind, id, count? } and returns
-- (ok, coins): `coins` is what was paid. Each line is checked on its own against
-- Config/Sell (what can be sold and its price) and what the player really holds; a line
-- that fails is skipped and the rest still sell. Stacks (potions, materials) sell
-- `count` of them, capped at what is held; weapons, tools and armour sell one.
--
-- Taking the item away goes through its own service, so the usual follow-ups happen:
-- selling the selected weapon selects the starter (MeleeService.removeWeapons), selling
-- the worn set takes it off and drops its bonus HP (ArmorService.revoke), selling the
-- tool in hand puts the next best of its kind out or none (ToolService.revoke).
-- Coins go in through CoinService.add with source "sell", so the leaderboards don't
-- count them as earned (like shop and reward coins).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sell = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Sell"))

local SellService = {}

local deps: any = nil

local MAX_LINES = 200 -- more than anyone owns; caps a junk request

-- Take one line's items away. Returns how many went (0 = not theirs, nothing taken).
local function take(player: Player, kind: string, id: string, count: number): number
	local services = deps.Services
	if kind == "weapon" then
		return if services.MeleeService.removeWeapons(player, { id }) > 0 then 1 else 0
	elseif kind == "tool" then
		return if services.ToolService.revoke(player, id) then 1 else 0
	elseif kind == "armor" then
		return if services.ArmorService.revoke(player, id) then 1 else 0
	end
	local service = if kind == "potion" then services.PotionService else services.MaterialService
	local n = math.min(count, service.get(player, id))
	if n > 0 then
		service.add(player, id, -n)
	end
	return n
end

-- Sell what `lines` names. Returns (ok, coins paid).
function SellService.sell(player: Player, lines: any): (boolean, number)
	if type(lines) ~= "table" then
		return false, 0
	end
	local total = 0
	local seen: { [string]: boolean } = {}
	for i, line in lines do
		if type(i) ~= "number" or i > MAX_LINES then
			break
		end
		if type(line) ~= "table" or type(line.kind) ~= "string" or type(line.id) ~= "string" then
			continue
		end
		local kind, id = line.kind, line.id
		local key = kind .. ":" .. id
		local price = Sell.price(kind, id)
		if not price or seen[key] then
			continue -- can't be sold, or already sold in this request
		end
		seen[key] = true
		local count = 1
		if Sell.Stacks[kind] then
			count = if type(line.count) == "number" and line.count == line.count then math.floor(line.count) else 0
			if count < 1 then
				continue
			end
		end
		total += take(player, kind, id, count) * price
	end
	if total <= 0 then
		return false, 0
	end
	deps.Services.CoinService.add(player, total, "sell")
	return true, total
end

function SellService.init(injected: any)
	deps = injected
end

function SellService.start()
	deps.Remotes.getFunction("SellItems").OnServerInvoke = function(player: Player, lines: any)
		return SellService.sell(player, lines)
	end
end

return SellService
