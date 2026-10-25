--!strict
-- FishingService: the server's side of fishing (2026-10-18, the user's design; the rules
-- and numbers are in Config/Fishing).
--
-- The client casts (Remotes.FishAction { action = "cast", at }), naming where its bobber
-- landed. This service checks a rod the player owns is in hand, the spot is in range and
-- on water (a part tagged Fishing.Tag), then runs the wait: after a random delay a fish
-- is picked by weight from the spot's table and swims in ("Approach" { seconds, size,
-- nibbles }: the client sizes its shadow by the fish's difficulty and plays the nibbles),
-- then bites ("Bite"); a "hook" while it is under starts the fight. Missing the bite only
-- brings the bobber back up ("Surface") and the wait starts again with a new fish.
--
-- The fight (the reel bar, issue 26, 2026-10-25): "Fight" { startAt, speed, zone, jerk,
-- checks, slips } starts the marker at server time `startAt` (workspace:GetServerTimeNow).
-- Each click arrives as { action = "click", at } (the server time the player clicked at;
-- taken if it is at most Fishing.clickLag old, else now), and is judged with
-- Fishing.inZone, the same formula the client draws. In the green: a check; out: a miss.
-- The answer is "Tally" { checks, misses, ok }. Fishing.checks checks: the fish goes into
-- the player's materials (MaterialService.drop) and the client hears "Caught" { fish }.
-- More misses than Fishing.slips, or Fishing.fightSeconds without a finish: "Escaped".
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
local Materials = require(Config:WaitForChild("Materials"))
local Potions = require(Config:WaitForChild("Potions"))

local FishingService = {}

-- How long the client gets after a bite ends for a hook to still count (lag).
local HOOK_SLACK = 0.3
local CAST_COOLDOWN_TOLERANCE = 0.85

type Session = {
	token: number, -- bumped on every change; delayed steps check it is still theirs
	phase: string, -- "Waiting" | "Approach" | "Bite" | "Fight"
	spot: Fishing.Spot,
	at: Vector3,
	biteUntil: number,
	fish: string?,
	startAt: number, -- server time the fight's marker starts
	checks: number,
	misses: number,
	lastClick: number,
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

-- A running Angler's potion (Config/Potions) multiplies the weight of every fish rarer than
-- Common, so the uncommon and rare ones bite more often.
local function pickFish(spot: Fishing.Spot, player: Player): string
	local angler = Potions.multiplier(player, "Angler")
	local weights = {}
	local total = 0
	for index, entry in spot.fish do
		local def = Materials.get(entry.id)
		local weight = if def and def.rarity ~= "Common" then entry.weight * angler else entry.weight
		weights[index] = weight
		total += weight
	end
	local roll = random:NextNumber() * total
	for index, entry in spot.fish do
		roll -= weights[index]
		if roll <= 0 then
			return entry.id
		end
	end
	return spot.fish[#spot.fish].id
end

scheduleBite = function(player: Player, session: Session, first: boolean)
	moveTo(session, "Waiting")
	local wait = random:NextNumber(Fishing.biteDelay[1], Fishing.biteDelay[2])
	if first then
		wait += Fishing.flightSeconds
	end
	later(player, session, wait, function()
		moveTo(session, "Approach")
		local fish = pickFish(session.spot, player)
		session.fish = fish
		local nibbles = random:NextInteger(Fishing.nibbles[1], Fishing.nibbles[2])
		send(player, {
			state = "Approach",
			seconds = Fishing.approachSeconds,
			size = Fishing.ShadowScale[Fishing.Fish[fish] or "Easy"] or 1,
			nibbles = nibbles,
			nibbleSeconds = Fishing.nibbleSeconds,
		})
		later(player, session, Fishing.approachSeconds + nibbles * Fishing.nibbleSeconds, function()
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

local function startFight(player: Player, session: Session)
	local difficulty = Fishing.difficultyOf(session.fish :: string)
	moveTo(session, "Fight")
	session.startAt = workspace:GetServerTimeNow() + Fishing.barLead
	session.checks = 0
	session.misses = 0
	send(player, {
		state = "Fight",
		startAt = session.startAt,
		speed = difficulty.speed,
		zone = difficulty.zone,
		jerk = difficulty.jerk,
		checks = Fishing.checks,
		slips = Fishing.slips,
	})
	later(player, session, Fishing.barLead + Fishing.fightSeconds, function()
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
		startAt = 0,
		checks = 0,
		misses = 0,
		lastClick = 0,
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
	startFight(player, session)
end

local function onClick(player: Player, at: any)
	local session = sessions[player]
	if not (session and session.phase == "Fight" and rodInHand(player)) then
		return
	end
	local clock = os.clock()
	if clock - session.lastClick < Fishing.clickGap then
		return
	end
	session.lastClick = clock
	-- the moment the player clicked, by the server's clock: theirs if it is believable
	local now = workspace:GetServerTimeNow()
	local when = if type(at) == "number" and at <= now + 0.05 and at >= now - Fishing.clickLag then at else now
	local t = when - session.startAt
	if t < 0 then
		return
	end
	local difficulty = Fishing.difficultyOf(session.fish :: string)
	local ok = Fishing.inZone(difficulty, session.checks, t)
	if ok then
		session.checks += 1
	else
		session.misses += 1
	end
	if session.misses > Fishing.slips then
		finish(player, "Escaped", { checks = session.checks, misses = session.misses })
		return
	end
	if session.checks < Fishing.checks then
		send(player, { state = "Tally", checks = session.checks, misses = session.misses, ok = ok })
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
	elseif action == "click" then
		onClick(player, payload.at)
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
