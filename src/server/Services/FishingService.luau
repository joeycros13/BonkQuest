--!strict
-- FishingService: the server's side of fishing (2026-10-18, the user's design; the rules
-- and numbers are in Config/Fishing).
--
-- The client casts (Remotes.FishAction { action = "cast", at }), naming where its bobber
-- landed. This service checks a rod the player owns is in hand, the spot is in range and
-- on water (a part tagged Fishing.Tag), then runs the wait: after a random delay a fish
-- swims in ("Approach") and bites ("Bite"); a "hook" while it is under starts the rings.
-- Missing the bite only brings the bobber back up ("Surface") and the wait starts again.
--
-- The rings: the fish is picked by weight from the spot's table and fights with its
-- Difficulty. For each ring the server tells the client when it starts ("Ring" { n,
-- delay, closeSeconds, zone }); the client judges the click and answers { action =
-- "ring", n, ok }. The server re-checks the timing against its own clock (with
-- Fishing.ringSlack for lag both ways) and gives up on a ring nobody answered. All three
-- in time: the fish goes into the player's materials (MaterialService.drop) and the
-- client hears "Caught" { fish }. A miss: "Escaped".
--
-- The line comes in ("Reeled") when the player asks ("reel"), puts the rod away, dies,
-- leaves, or walks more than Fishing.lineBreak from the bobber. Nothing is saved but the
-- fish.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Fishing = require(Config:WaitForChild("Fishing"))
local Tools = require(Config:WaitForChild("Tools"))

local FishingService = {}

-- How long the client gets after a bite ends for a hook to still count (lag).
local HOOK_SLACK = 0.3
-- Seconds a ring may go unanswered past its close before the fish gets away.
local RING_TIMEOUT = 0.8
local CAST_COOLDOWN_TOLERANCE = 0.85

type Session = {
	token: number, -- bumped on every change; delayed steps check it is still theirs
	phase: string, -- "Waiting" | "Approach" | "Bite" | "Ring"
	spot: Fishing.Spot,
	at: Vector3,
	biteUntil: number,
	fish: string?,
	ring: number,
	ringAt: number,
}

local deps: any = nil
local stateRemote: RemoteEvent? = nil
local random = Random.new()
local sessions: { [Player]: Session } = {}
local lastCast: { [Player]: number } = {}

local function send(player: Player, message: { [string]: any })
	if stateRemote then
		stateRemote:FireClient(player, message)
	end
end

local function rodInHand(player: Player): Tools.ToolDef?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and humanoid and humanoid.Health > 0) then
		return nil
	end
	local tool = Tools.get(character:GetAttribute("Tool"))
	if tool and tool.kind == "Rod" and deps.Services.ToolService.owns(player, tool.id) then
		return tool
	end
	return nil
end

-- The water spot under a point, or nil if it is not over fishing water.
local function waterAt(at: Vector3): Fishing.Spot?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = CollectionService:GetTagged(Fishing.Tag)
	local hit = workspace:Raycast(at + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), params)
	return if hit then Fishing.spot(hit.Instance:GetAttribute("Spot")) else nil
end

local function finish(player: Player, state: string, extra: { [string]: any }?)
	sessions[player] = nil
	local message = extra or {}
	message.state = state
	send(player, message)
end

local scheduleBite: (player: Player, session: Session, first: boolean) -> ()

-- One step later, if the session hasn't moved on in the meantime.
local function later(player: Player, session: Session, seconds: number, step: () -> ())
	local token = session.token
	task.delay(seconds, function()
		if sessions[player] == session and session.token == token then
			step()
		end
	end)
end

local function moveTo(session: Session, phase: string)
	session.phase = phase
	session.token += 1
end

scheduleBite = function(player: Player, session: Session, first: boolean)
	moveTo(session, "Waiting")
	local wait = random:NextNumber(Fishing.biteDelay[1], Fishing.biteDelay[2])
	if first then
		wait += Fishing.flightSeconds
	end
	later(player, session, wait, function()
		moveTo(session, "Approach")
		send(player, { state = "Approach", seconds = Fishing.approachSeconds })
		later(player, session, Fishing.approachSeconds, function()
			moveTo(session, "Bite")
			local seconds = random:NextNumber(Fishing.biteSeconds[1], Fishing.biteSeconds[2])
			session.biteUntil = os.clock() + seconds
			send(player, { state = "Bite", seconds = seconds })
			later(player, session, seconds + HOOK_SLACK, function()
				-- not hooked: the bobber comes back up, and the next fish takes its time
				send(player, { state = "Surface" })
				scheduleBite(player, session, false)
			end)
		end)
	end)
end

local function pickFish(spot: Fishing.Spot): string
	local total = 0
	for _, entry in spot.fish do
		total += entry.weight
	end
	local roll = random:NextNumber() * total
	for _, entry in spot.fish do
		roll -= entry.weight
		if roll <= 0 then
			return entry.id
		end
	end
	return spot.fish[#spot.fish].id
end

local function startRing(player: Player, session: Session, n: number)
	local difficulty = Fishing.difficultyOf(session.fish :: string)
	moveTo(session, "Ring")
	session.ring = n
	session.ringAt = os.clock() + Fishing.ringGap
	send(player, {
		state = "Ring",
		n = n,
		of = Fishing.rings,
		delay = Fishing.ringGap,
		closeSeconds = difficulty.closeSeconds,
		zone = difficulty.zone,
	})
	later(player, session, Fishing.ringGap + difficulty.closeSeconds + RING_TIMEOUT, function()
		finish(player, "Escaped")
	end)
end

local function onCast(player: Player, at: any)
	if typeof(at) ~= "Vector3" then
		return
	end
	local rod = rodInHand(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (rod and root and root:IsA("BasePart")) then
		return
	end
	local now = os.clock()
	if now - (lastCast[player] or 0) < rod.cooldown * CAST_COOLDOWN_TOLERANCE then
		return
	end
	lastCast[player] = now
	local offset = at - root.Position
	local spot = waterAt(at)
	if Vector3.new(offset.X, 0, offset.Z).Magnitude > Fishing.maxCastRange or math.abs(offset.Y) > 20 or not spot then
		finish(player, "Reeled")
		return
	end
	-- a rod only fishes its own world's water or older (FishingController shows "Needs a Stone Rod")
	if rod.tier < (spot.tier or 1) then
		finish(player, "Reeled")
		return
	end
	local session: Session = {
		token = 0,
		phase = "Waiting",
		spot = spot,
		at = at,
		biteUntil = 0,
		fish = nil,
		ring = 0,
		ringAt = 0,
	}
	sessions[player] = session
	send(player, { state = "Cast", spot = spot.id })
	scheduleBite(player, session, true)
end

local function onHook(player: Player)
	local session = sessions[player]
	if not (session and rodInHand(player)) then
		return
	end
	if session.phase ~= "Bite" or os.clock() > session.biteUntil + HOOK_SLACK then
		return
	end
	session.fish = pickFish(session.spot)
	startRing(player, session, 1)
end

local function onRing(player: Player, n: any, ok: any)
	local session = sessions[player]
	if not (session and session.phase == "Ring" and n == session.ring) then
		return
	end
	if ok ~= true or not rodInHand(player) then
		finish(player, "Escaped")
		return
	end
	local difficulty = Fishing.difficultyOf(session.fish :: string)
	local enter, leave = Fishing.zoneTimes(difficulty)
	local elapsed = os.clock() - session.ringAt
	if elapsed < enter - Fishing.ringSlack or elapsed > leave + Fishing.ringSlack * 2 then
		finish(player, "Escaped")
		return
	end
	if n < Fishing.rings then
		startRing(player, session, n + 1)
		return
	end
	local fish = session.fish :: string
	finish(player, "Caught", { fish = fish })
	deps.Services.MaterialService.drop(player, { { id = fish, amount = 1 } }, session.at + Vector3.new(0, 2, 0))
end

local function onAction(player: Player, payload: any)
	if type(payload) ~= "table" then
		return
	end
	local action = payload.action
	if action == "cast" then
		onCast(player, payload.at)
	elseif action == "hook" then
		onHook(player)
	elseif action == "ring" then
		onRing(player, payload.n, payload.ok)
	elseif action == "reel" then
		if sessions[player] then
			finish(player, "Reeled")
		end
	end
end

function FishingService.init(injected: any)
	deps = injected
	stateRemote = deps.Remotes.getEvent("FishState")
end

function FishingService.start()
	deps.Remotes.getEvent("FishAction").OnServerEvent:Connect(onAction)
	Players.PlayerRemoving:Connect(function(player: Player)
		sessions[player] = nil
		lastCast[player] = nil
	end)
	-- The line comes in when the rod is put away, the player dies, or walks too far off.
	task.spawn(function()
		while true do
			task.wait(0.5)
			for player, session in sessions do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local far = root
					and root:IsA("BasePart")
					and Vector3.new(root.Position.X - session.at.X, 0, root.Position.Z - session.at.Z).Magnitude
						> Fishing.lineBreak
				if not rodInHand(player) or not root or far then
					finish(player, "Reeled")
				end
			end
		end
	end)
end

return FishingService
