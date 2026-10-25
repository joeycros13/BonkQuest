--!strict
-- SpillService: coins and EXP count only once they reach the HUD (2026-10-25, the user, issue 24:
-- "Coins and exp should only be actually counted once they hit the bars").
--
-- A kill or a quest reward spills coins / EXP stars that fly to the HUD (LootController). The
-- amount waits here, held, until the player's client says the spill's first piece reached its
-- bar (Remotes.LootLanded(id)); only then does CoinService / ExpService add it, so the counter,
-- the level and the level-up heal all happen when the player sees the loot arrive.
--
-- The amount is decided here on the server; the client only says when. A client that never
-- answers still gets it after the hold's timeout, and leaving pays out everything held. While
-- held, an amount isn't spendable, but it is saved: CoinService / ExpService add `held()` to
-- what they save, so a save mid-flight loses nothing.
--
--   SpillService.hold(player, kind, amount, timeout, pay) -> id   pay() runs once, on landing or timeout
--   SpillService.held(player, kind) -> number   the total held for a kind ("Coins" / "Exp")
--
-- Timeouts (SpillService.KILL_SECONDS / TALK_SECONDS): a kill's pieces land in about 2.5 s; a
-- quest reward's wait for the conversation to close first.

local SpillService = {}

SpillService.KILL_SECONDS = 6
SpillService.TALK_SECONDS = 120

local Players = game:GetService("Players")

type Hold = { kind: string, amount: number, pay: () -> () }

local deps: any = nil
local holds: { [Player]: { [number]: Hold } } = {}
local nextId = 0

local function release(player: Player, id: number)
	local mine = holds[player]
	local hold = mine and mine[id]
	if not hold then
		return
	end
	mine[id] = nil
	hold.pay()
end

-- Hold `amount` of `kind` for `player` until their spill lands (or `timeout` seconds pass);
-- `pay` adds it. Returns the id the client sends back.
function SpillService.hold(player: Player, kind: string, amount: number, timeout: number, pay: () -> ()): number
	nextId += 1
	local id = nextId
	local mine = holds[player]
	if not mine then
		mine = {}
		holds[player] = mine
	end
	mine[id] = { kind = kind, amount = amount, pay = pay }
	task.delay(timeout, release, player, id)
	return id
end

function SpillService.held(player: Player, kind: string): number
	local total = 0
	for _, hold in holds[player] or {} do
		if hold.kind == kind then
			total += hold.amount
		end
	end
	return total
end

function SpillService.init(injected: any)
	deps = injected
end

function SpillService.start()
	deps.Remotes.getEvent("LootLanded").OnServerEvent:Connect(function(player: Player, id: any)
		if type(id) == "number" then
			release(player, id)
		end
	end)
	-- leaving pays out whatever is still in the air (the savers count held amounts too, so
	-- either order with PlayerDataService's save on leave keeps them)
	Players.PlayerRemoving:Connect(function(player: Player)
		local mine = holds[player]
		if mine then
			for id in mine do
				release(player, id)
			end
			holds[player] = nil
		end
	end)
end

return SpillService
