--!strict
-- GateService: buying a world gate (Shared.Config.Gates).
--
-- Remotes.GateBuy { id } from a player standing within Gates.BUY_RANGE of the
-- gate's SignBoard: if they haven't unlocked that world yet, their Level is at
-- least the gate's `level` and their Coins at least its `coins`, the coins are
-- spent (CoinService) and the world unlocked (PlayerDataService.unlockWorld,
-- published as HighestWorld and saved straight away). GateUI on the client
-- hides the gate's curtain for a player whose HighestWorld reaches the world.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Gates = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Gates"))

local GateService = {}

local deps: any = nil

local function signOf(gate: Gates.Gate): BasePart?
	local folder = workspace:FindFirstChild("Shared")
	local gates = folder and folder:FindFirstChild("Gates")
	local model = gates and gates:FindFirstChild(gate.model)
	local board = model and model:FindFirstChild("SignBoard", true)
	return if board and board:IsA("BasePart") then board else nil
end

local function number(player: Player, name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

-- Why a player can't buy a gate right now, or nil when they can.
function GateService.blocker(player: Player, gate: Gates.Gate): string?
	local PlayerDataService = deps.Services.PlayerDataService
	if PlayerDataService.highestWorld(player) >= gate.world then
		return "owned"
	elseif number(player, "Level") < gate.level then
		return "level"
	elseif deps.Services.CoinService.get(player) < gate.coins then
		return "coins"
	end
	local board = signOf(gate)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (board and root and root:IsA("BasePart")) or (root.Position - board.Position).Magnitude > Gates.BUY_RANGE then
		return "range"
	end
	return nil
end

local function buy(player: Player, payload: any)
	local id = type(payload) == "table" and payload.id
	local gate = type(id) == "string" and Gates.byId(id) or nil
	if not gate or GateService.blocker(player, gate) then
		return
	end
	deps.Services.CoinService.add(player, -gate.coins)
	deps.Services.PlayerDataService.unlockWorld(player, gate.world)
	task.spawn(deps.Services.PlayerDataService.saveNow, player)
end

function GateService.init(injected: any)
	deps = injected
end

function GateService.start()
	deps.Remotes.getEvent("GateBuy").OnServerEvent:Connect(buy)
end

return GateService
