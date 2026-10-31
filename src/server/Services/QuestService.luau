--!strict
-- QuestService: every questline in Config/Quests (Dale the Farmer's, Ranger
-- Rowan's...), each one step at a time and all side by side. Saved as the
-- "quest" section of PlayerDataService: { lines = { [lineId] = { step, state,
-- progress } } } (2026-10-11; the old single-line save { step, state, progress }
-- loads as Dale's line).
--
-- Each player's place in each line is published as attributes named by
-- Quests.attr(field, lineId), e.g. "QuestStep_DaleFarm", which the client's
-- dialogue, tracker and guide arrow read:
--   Step      1..#steps, or #steps + 1 once the line is finished
--   State     "Offer"  the giver has this step to give
--             "Active" accepted, not done yet
--             "Ready"  done; talk to the giver to hand it in
--             "Done"   every step handed in
--   Progress  kills / coins earned / level / coins held, toward the goal
--
-- The client asks through Remotes.QuestAction(action, lineId), action "accept" |
-- "turnIn", only honoured near that line's quest giver: a model tagged
-- QuestGiver whose "QuestLine" attribute names the line.
--
-- Progress: kills come from WorldEnemyService.onDefeated; "earn" counts rises of
-- the Coins attribute after accepting; "level" and "give" are re-read from Level
-- / Coins whenever those change, so spending coins can take a "give" step back
-- from Ready to Active. "gather" and "bring" re-read the materials held
-- (2026-10-19), falling back to Active like "give" if they are spent; a "gather"
-- step counts what was already held when it was accepted and takes nothing at
-- hand-in (issue 21, 2026-10-25, the user: logs already held count, so a player
-- who has them is rewarded straight away; it counted only rises after accepting). A "hunt"
-- step (2026-10-26) counts each of its kinds up to its own count; the kills are published
-- (before Progress) as "QuestKills_<line>" ("Chicken=5,Bull=2") and saved with the line.
-- Every line hears every kill and coin, so two lines can move at once.
--
-- Studio only: setting a player's "DevQuestStep_<lineId>" attribute (a step
-- number) from the Server datamodel jumps them to that step, on offer, for
-- testing ("DevQuestStep" alone means Dale's line).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local MapLayout = require(Config:WaitForChild("MapLayout"))
local Materials = require(Config:WaitForChild("Materials"))
local Quests = require(Config:WaitForChild("Quests"))

local QuestService = {}

-- How close (studs) a player must stand to the quest giver to accept or hand in.
local TALK_RANGE = 16
-- reward loot spills this far from the giver, toward the player
local REWARD_SPILL_AHEAD = 4
-- the line an old single-line save (and a bare "DevQuestStep") belongs to
local LEGACY_LINE = "DaleFarm"

local deps: any = nil

type State = {
	line: Quests.Line,
	step: number,
	state: string,
	progress: number,
	-- a hunt step's kills per enemy (Config/Worlds id -> count)
	kills: { [string]: number },
	-- the Coins value last seen, so "earn" counts only rises
	coinsSeen: number,
}

local states: { [Player]: { [string]: State } } = {}

local function coins(player: Player): number
	return deps.Services.CoinService.get(player)
end

local function level(player: Player): number
	local value = player:GetAttribute("Level")
	return if type(value) == "number" then value else 1
end

-- Progress and state go out before the step number: the client reacts to each
-- attribute as it arrives, and a new step paired with the previous step's
-- progress once made the tracker show a fresh step as already done.
local function encodeKills(kills: { [string]: number }): string
	local parts = {}
	for enemy, n in kills do
		table.insert(parts, enemy .. "=" .. n)
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

local function publish(player: Player, s: State)
	local id = s.line.id
	player:SetAttribute(Quests.attr("Kills", id), encodeKills(s.kills))
	player:SetAttribute(Quests.attr("Progress", id), s.progress)
	player:SetAttribute(Quests.attr("State", id), s.state)
	player:SetAttribute(Quests.attr("Step", id), s.step)
end

-- Re-read progress that follows a live value (level, coins held) and settle
-- whether the step is done.
local function refresh(player: Player, s: State)
	local step = s.line.steps[s.step]
	if not step or (s.state ~= "Active" and s.state ~= "Ready") then
		return
	end
	local goal = Quests.goal(step)
	if step.kind == "level" then
		s.progress = math.min(level(player), goal)
	elseif step.kind == "give" then
		s.progress = math.min(coins(player), goal)
	elseif step.kind == "gather" then
		s.progress = math.min(Materials.counts(player)[step.target or ""] or 0, goal)
	elseif step.kind == "bring" then
		-- each item counts up to what it needs, so extra logs never stand in for stone
		local held = Materials.counts(player)
		local total = 0
		for _, item in step.items or {} do
			total += math.min(held[item.id] or 0, item.count)
		end
		s.progress = total
	elseif step.kind == "hunt" then
		local total = 0
		for _, target in step.targets or {} do
			total += math.min(s.kills[target.id] or 0, target.count)
		end
		s.progress = total
	end
	if s.progress >= goal then
		s.state = "Ready"
	elseif step.kind == "give" or step.kind == "bring" or step.kind == "gather" then
		s.state = "Active"
	end
	publish(player, s)
end

local function addProgress(player: Player, s: State, amount: number)
	if s.state ~= "Active" then
		return
	end
	s.progress += amount
	refresh(player, s)
end

local function onKill(enemy: any, killer: Player?)
	local lines = killer and states[killer]
	if not lines then
		return
	end
	for _, s in lines do
		local step = s.line.steps[s.step]
		if step and step.kind == "kill" and enemy.archetype == step.target then
			addProgress(killer :: Player, s, 1)
		elseif step and step.kind == "hunt" and s.state == "Active" then
			for _, target in step.targets or {} do
				if target.id == enemy.archetype and (s.kills[target.id] or 0) < target.count then
					s.kills[target.id] = (s.kills[target.id] or 0) + 1
					refresh(killer :: Player, s)
				end
			end
		end
	end
end

-- The giver of `lineId` the player is talking to (within TALK_RANGE), if any.
local function giverNear(player: Player, lineId: string): Model?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	for _, giver in CollectionService:GetTagged(MapLayout.Tags.QuestGiver) do
		if giver:GetAttribute("QuestLine") == lineId and giver:IsA("Model") then
			if (giver:GetPivot().Position - root.Position).Magnitude <= TALK_RANGE then
				return giver
			end
		end
	end
	return nil
end

-- Where a reward spills: on the ground between the giver and the player, so the
-- coins don't land on the house behind the giver.
local function spillSpot(player: Player, giver: Model): Vector3
	local at = giver:GetPivot().Position
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local flat = Vector3.new(root.Position.X - at.X, 0, root.Position.Z - at.Z)
		if flat.Magnitude > 0.1 then
			return at + flat.Unit * math.min(REWARD_SPILL_AHEAD, flat.Magnitude)
		end
	end
	return at
end

-- Pay a step's reward (user, 2026-10-11): the coins and EXP spill out in front
-- of the giver once the conversation closes and fly into the HUD, like a kill's
-- loot; a weapon also shows the Index's NEW popup across the top of the screen
-- (IndexService.showWeapon). A quest item (crafting, 2026-10-12) goes to
-- MaterialService, which hands each one over only once ever.
local function grant(player: Player, reward: Quests.Reward, giver: Model?)
	local spot = if giver then spillSpot(player, giver) else nil
	if reward.coins and reward.coins > 0 then
		if spot then
			deps.Services.CoinService.spill(player, reward.coins, spot, true)
		else
			deps.Services.CoinService.add(player, reward.coins)
		end
	end
	if reward.exp and reward.exp > 0 then
		if spot then
			deps.Services.ExpService.spill(player, reward.exp, spot, true)
		else
			deps.Services.ExpService.add(player, reward.exp)
		end
	end
	if reward.weapon then
		deps.Services.MeleeService.grant(player, reward.weapon)
		deps.Services.IndexService.showWeapon(player, reward.weapon)
	end
	if reward.item then
		deps.Services.MaterialService.giveOnce(player, reward.item, spot)
	end
end

-- Quest items for steps already handed in: a save from before the items existed
-- (2026-10-12) gets the ones it earned. giveOnce skips any already received.
local function backfillItems(player: Player, s: State)
	for index = 1, math.min(s.step - 1, #s.line.steps) do
		local item = s.line.steps[index].reward.item
		if item then
			deps.Services.MaterialService.giveOnce(player, item)
		end
	end
end

local function accept(player: Player, s: State)
	if s.state ~= "Offer" then
		return
	end
	s.state = "Active"
	s.progress = 0
	s.kills = {}
	s.coinsSeen = coins(player)
	publish(player, s)
	-- a level, coin or material goal can already be met
	refresh(player, s)
end

local function turnIn(player: Player, s: State, giver: Model?)
	local step = s.line.steps[s.step]
	if s.state ~= "Ready" or not step then
		return
	end
	if step.kind == "give" then
		local amount = Quests.goal(step)
		if coins(player) < amount then
			refresh(player, s)
			return
		end
		deps.Services.CoinService.add(player, -amount)
	elseif step.kind == "bring" then
		if not deps.Services.MaterialService.take(player, step.items or {}) then
			refresh(player, s)
			return
		end
	end
	-- Move on before paying out, so reward coins never count toward the next step.
	s.step += 1
	s.state = if s.line.steps[s.step] then "Offer" else "Done"
	s.progress = 0
	s.kills = {}
	-- every line's coin baseline moves past the payout
	for _, other in states[player] or {} do
		other.coinsSeen = coins(player)
	end
	grant(player, step.reward, giver)
	for _, other in states[player] or {} do
		other.coinsSeen = coins(player)
	end
	publish(player, s)
end

local function onAction(player: Player, action: any, lineId: any)
	-- older clients sent no line: that was always Dale's
	local line = Quests.get(if lineId == nil then LEGACY_LINE else lineId)
	local s = line and states[player] and states[player][line.id]
	local giver = line and giverNear(player, line.id)
	if not s or not giver then
		return
	end
	if action == "accept" then
		accept(player, s)
	elseif action == "turnIn" then
		turnIn(player, s, giver)
	end
end

local function jumpTo(player: Player, s: State, step: any)
	if type(step) == "number" and s.line.steps[step] then
		s.step, s.state, s.progress, s.kills, s.coinsSeen = step, "Offer", 0, {}, coins(player)
		publish(player, s)
	end
end

-- The admin panel's Quests tab (2026-10-19): put a line on `step` (1..#steps; one past
-- the end finishes it), on offer. No step rewards are paid, but quest items from steps
-- before it are handed over (backfillItems), so the second armour set still works.
-- Returns the step it landed on and whether the line is done, or nil for an unknown line.
function QuestService.setStep(player: Player, lineId: any, step: any): (number?, boolean)
	local s = states[player] and states[player][lineId]
	if not s or type(step) ~= "number" then
		return nil, false
	end
	local n = #s.line.steps
	step = math.clamp(math.floor(step), 1, n + 1)
	s.step = step
	s.state = if step > n then "Done" else "Offer"
	s.progress, s.kills, s.coinsSeen = 0, {}, coins(player)
	publish(player, s)
	backfillItems(player, s)
	return step, step > n
end

-- The step a line is on (for the admin panel's Skip), or nil.
function QuestService.stepOf(player: Player, lineId: any): number?
	local s = states[player] and states[player][lineId]
	return s and s.step
end

local function onPlayer(player: Player)
	if states[player] then
		return
	end
	local lines: { [string]: State } = {}
	states[player] = lines
	for _, id in Quests.order do
		local line = Quests.get(id)
		if line then
			local s: State = { line = line, step = 1, state = "Offer", progress = 0, kills = {}, coinsSeen = coins(player) }
			lines[id] = s
			publish(player, s)
		end
	end
	player:GetAttributeChangedSignal("Coins"):Connect(function()
		local now = coins(player)
		for _, s in lines do
			local gained = now - s.coinsSeen
			s.coinsSeen = now
			local step = s.line.steps[s.step]
			if step and step.kind == "earn" and gained > 0 then
				addProgress(player, s, gained)
			else
				refresh(player, s)
			end
		end
	end)
	player:GetAttributeChangedSignal("Materials"):Connect(function()
		for _, s in lines do
			refresh(player, s)
		end
	end)
	player:GetAttributeChangedSignal("Level"):Connect(function()
		for _, s in lines do
			refresh(player, s)
		end
	end)
	if RunService:IsStudio() then
		for id, s in lines do
			local name = "DevQuestStep_" .. id
			player:GetAttributeChangedSignal(name):Connect(function()
				jumpTo(player, s, player:GetAttribute(name))
			end)
		end
		player:GetAttributeChangedSignal("DevQuestStep"):Connect(function()
			local s = lines[LEGACY_LINE]
			if s then
				jumpTo(player, s, player:GetAttribute("DevQuestStep"))
			end
		end)
	end
end

local function loadLine(player: Player, s: State, value: any)
	if type(value) ~= "table" or type(value.step) ~= "number" then
		return
	end
	local finished = value.step > #s.line.steps
	if not (s.line.steps[value.step] or finished) then
		return
	end
	s.step = if finished then #s.line.steps + 1 else value.step
	s.state = if finished then "Done" elseif value.state == "Active" or value.state == "Ready" then value.state else "Offer"
	s.progress = if type(value.progress) == "number" then value.progress else 0
	s.kills = {}
	if type(value.kills) == "string" then
		for enemy, n in value.kills:gmatch("(%w+)=(%d+)") do
			s.kills[enemy] = tonumber(n) or 0
		end
	end
	s.coinsSeen = coins(player)
	publish(player, s)
	refresh(player, s)
	backfillItems(player, s)
end

function QuestService.init(injected: any)
	deps = injected
	-- Registered after coins and EXP (SERVICE_ORDER), so the loaded balance and
	-- level are already in place and never count as progress.
	deps.Services.PlayerDataService.register("quest", {
		load = function(player: Player, value: any)
			if type(value) ~= "table" then
				return
			end
			onPlayer(player)
			local lines = states[player]
			if not lines then
				return
			end
			if type(value.lines) == "table" then
				for id, s in lines do
					loadLine(player, s, value.lines[id])
				end
			elseif type(value.step) == "number" and lines[LEGACY_LINE] then
				-- the single-line save from before 2026-10-11
				loadLine(player, lines[LEGACY_LINE], value)
			end
		end,
		save = function(player: Player): any
			local out = {}
			for _, id in Quests.order do
				local step = player:GetAttribute(Quests.attr("Step", id))
				if type(step) == "number" then
					out[id] = {
						step = step,
						state = player:GetAttribute(Quests.attr("State", id)),
						progress = player:GetAttribute(Quests.attr("Progress", id)),
						kills = player:GetAttribute(Quests.attr("Kills", id)),
					}
				end
			end
			return { lines = out }
		end,
	})
end

function QuestService.start()
	deps.Services.WorldEnemyService.onDefeated(onKill)
	deps.Remotes.getEvent("QuestAction").OnServerEvent:Connect(onAction)
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return QuestService
