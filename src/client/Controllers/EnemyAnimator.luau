--!strict
-- EnemyAnimator: animation for world enemy bodies that have limbs, on the
-- Animation system.
--
-- Each limbed body gets a PartRig (the rig contract -- Root, limbs with "Joint"
-- attachments, "Follows" on extras, ArmStyle -- is documented there) and an
-- Animator. The clips live in ReplicatedStorage.Shared.Animation.Clips.Enemies:
--   * Walk: always playing; fades in from how fast Root actually moves.
--   * Moves: additive attack clips layered on the walk (peck / gore / stab /
--     pounce / charge / slam / stomp / smash / swoop / punch / legstab /
--     rearslam). An enemy with several moves
--     (melee.moves) gets a fresh AttackMove from the server before each tick.
--     Each time MeleeService starts an attack it bumps the body's AttackSeq
--     attribute, and the body's own AttackMove plays. At the move's "Strike"
--     marker the blow's effect plays (the bull's charge kicks up dust).
--   * Flinch: a short additive recoil at Override priority, so a hit never
--     cancels an attack in progress.
--
-- Mood: parts with a Mood attribute ("Calm" / "Angry") are shown only in that
-- mood -- the chicken's two pairs of brows. A body is Angry while it chases a
-- player (AiState "Chase") and Calm otherwise.
--
-- WorldEnemyController moves only each rigged body's Root; the animator places
-- every other part relative to it in one batched move per frame, and skips
-- bodies that are off-screen or far away (Animation.Animator.LOD).
--
-- Presentation only: nothing here is replicated or authoritative.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapLayout = require(Shared:WaitForChild("Config"):WaitForChild("MapLayout"))
local Enemies = require(Shared:WaitForChild("Config"):WaitForChild("Enemies"))
local Animation = require(Shared:WaitForChild("Animation"))
local PartRig = Animation.PartRig
local Animator = Animation.Animator
local Effects = Animation.Effects
local EnemyClips = Animation.Clips.Enemies

local EnemyAnimator = {}

-- What plays at a move's "Strike" marker, per move. (entry, frontOfFeet: CFrame)
local STRIKE_EFFECTS: { [string]: (any, CFrame) -> () } = {
	gore = function(_entry, front)
		Effects.burst(front, "Dust", { count = 18 })
		Effects.shockwave(front, "Shockwave", { endSize = 9, color = Color3.fromRGB(214, 196, 160) })
	end,
	peck = function(_entry, front)
		Effects.burst(front, "Dust", { count = 6 })
	end,
	-- the Fairy's wand zap pops fairy dust in front of her, where the player stands
	zap = function(_entry, front)
		Effects.burst(front * CFrame.new(0, 2.2, -1.2), "FairyZap")
	end,
	pounce = function(_entry, front)
		Effects.burst(front, "Dust", { count = 8 })
	end,
	charge = function(_entry, front)
		Effects.burst(front, "Dust", { count = 16 })
		Effects.shockwave(front, "Shockwave", { endSize = 8, color = Color3.fromRGB(176, 150, 112) })
	end,
	slam = function(_entry, front)
		Effects.burst(front, "Dust", { count = 26 })
		Effects.shockwave(front, "Shockwave", { endSize = 14, color = Color3.fromRGB(176, 150, 112) })
	end,
	-- The treant's stomp lands under its left foot, not at its front.
	stomp = function(entry, _front)
		local root = entry.rig.root
		local at = root.CFrame * CFrame.new(0, entry.rig.feetY + 0.2, 0)
		local shin = entry.model:FindFirstChild("LeftLowerLeg")
		if shin and shin:IsA("BasePart") then
			local p = root.CFrame:PointToObjectSpace(shin.Position)
			at = root.CFrame * CFrame.new(p.X, entry.rig.feetY + 0.2, p.Z)
		end
		Effects.burst(at, "Dust", { count = 34 })
		Effects.shockwave(at, "Shockwave", { endSize = 22, color = Color3.fromRGB(150, 122, 84) })
	end,
	-- The overhead smash lands where the two fists come down, in front (the treant's
	-- HandL / HandR, the Crystal Golem's LeftFist / RightFist).
	smash = function(entry, front)
		local root = entry.rig.root
		local at = front
		local l = entry.model:FindFirstChild("HandL") or entry.model:FindFirstChild("LeftFist")
		local r = entry.model:FindFirstChild("HandR") or entry.model:FindFirstChild("RightFist")
		if l and r and l:IsA("BasePart") and r:IsA("BasePart") then
			local p = root.CFrame:PointToObjectSpace((l.Position + r.Position) / 2)
			at = root.CFrame * CFrame.new(p.X, entry.rig.feetY + 0.2, p.Z)
		end
		Effects.burst(at, "Dust", { count = 30 })
		Effects.shockwave(at, "Shockwave", { endSize = 20, color = Color3.fromRGB(150, 122, 84) })
	end,
	-- Pebble Golem: a puff of grit where the punch lands.
	punch = function(_entry, front)
		Effects.burst(front * CFrame.new(0, 2.5, 0), "Dust", { count = 6 })
	end,
	-- Spider Queen: her front legs spike the ground in front of her.
	legstab = function(_entry, front)
		Effects.burst(front, "Dust", { count = 18 })
		Effects.shockwave(front, "Shockwave", { endSize = 12, color = Color3.fromRGB(120, 110, 150) })
	end,
	-- Spider Queen: she slams down from rearing up and crystal shards burst out.
	rearslam = function(_entry, front)
		Effects.burst(front, "Dust", { count = 30 })
		Effects.burst(front, "CrystalBurst")
		Effects.shockwave(front, "Shockwave", { endSize = 24, color = Color3.fromRGB(143, 228, 247) })
	end,
}

type Entry = {
	model: Model,
	rig: any,
	animator: any,
	move: any?, -- the playing move track
	halfLength: number, -- half the body's front-to-back size
	attackConn: RBXScriptConnection?,
	moodConns: { RBXScriptConnection },
}

local entries: { [Model]: Entry } = {}

local function build(model: Model, cull: boolean): Entry?
	local rig = PartRig.new(model)
	if not rig then
		return nil
	end
	local animator = Animator.new(rig, { cull = cull })
	animator:Play(EnemyClips.walk, { params = { rig = rig } })
	local entry: Entry = {
		model = model,
		rig = rig,
		animator = animator,
		move = nil,
		halfLength = model:GetExtentsSize().Z / 2,
		attackConn = nil,
		moodConns = {},
	}
	entries[model] = entry
	return entry
end

local function destroy(model: Model)
	local entry = entries[model]
	if entry then
		entries[model] = nil
		if entry.attackConn then
			entry.attackConn:Disconnect()
		end
		for _, conn in entry.moodConns do
			conn:Disconnect()
		end
		entry.animator:Destroy()
	end
end

local function play(entry: Entry?, move: string)
	if not entry then
		return
	end
	local clip = EnemyClips.move(move, entry.rig.meta.hangingArms)
	if not clip then
		return
	end
	if entry.move then
		entry.move:Stop(0.08)
	end
	local track = entry.animator:Play(clip)
	entry.move = track
	local effect = STRIKE_EFFECTS[move]
	if effect then
		track:GetMarkerReachedSignal("Strike"):Once(function()
			local root = entry.rig.root
			effect(entry, root.CFrame * CFrame.new(0, entry.rig.feetY + 0.2, -entry.halfLength))
		end)
	end
end

-- ==================== mood ====================

local function setMood(model: Model, angry: boolean)
	local want = if angry then "Angry" else "Calm"
	for _, part in model:GetDescendants() do
		local mood = part:GetAttribute("Mood")
		if mood ~= nil and part:IsA("BasePart") then
			part.Transparency = if mood == want then 0 else 1
		end
	end
end

local function isAngry(model: Model): boolean
	return model:GetAttribute("AiState") == "Chase"
end

local function hasMood(model: Model): boolean
	for _, part in model:GetDescendants() do
		if part:GetAttribute("Mood") ~= nil then
			return true
		end
	end
	return false
end

-- ==================== world bodies ====================

local function adopt(inst: Instance)
	if not inst:IsA("Model") or entries[inst] then
		return
	end
	local entry = build(inst, true)
	if entry then
		-- MeleeService bumps AttackSeq each time this enemy starts an attack.
		entry.attackConn = inst:GetAttributeChangedSignal("AttackSeq"):Connect(function()
			local move = inst:GetAttribute("AttackMove")
			if type(move) == "string" then
				play(entry, move)
			end
		end)
		if hasMood(inst) then
			local function refresh()
				setMood(inst, isAngry(inst))
			end
			table.insert(entry.moodConns, inst:GetAttributeChangedSignal("AiState"):Connect(refresh))
			refresh()
		end
	end
end

-- ==================== queries ====================

-- Is this body animated here? (Then only its Root needs moving.)
function EnemyAnimator.isRigged(model: Instance): boolean
	return entries[model :: any] ~= nil
end

-- Recoil from a weapon hit, on top of whatever the body is doing.
function EnemyAnimator.flinch(model: Instance)
	local entry = entries[model :: any]
	if entry then
		entry.animator:Stop("Enemy_flinch", 0)
		entry.animator:Play(EnemyClips.flinch(entry.rig.meta.hangingArms))
	end
end

-- Show the body off (the world unlock cinematic's boss shot, issue 28): its attack move and
-- its angry face for a moment, here only.
function EnemyAnimator.showOff(model: Instance)
	local entry = entries[model :: any]
	if not entry then
		return
	end
	local def = Enemies.get(model:GetAttribute("Archetype") :: any)
	local melee = def and (def :: any).melee
	local move = melee and (melee.move or (melee.moves and melee.moves[1]))
	if type(move) == "string" then
		play(entry, move)
	end
	if model:IsA("Model") and hasMood(model) then
		setMood(model, true)
		task.delay(1.6, function()
			if model.Parent then
				setMood(model, isAngry(model))
			end
		end)
	end
end

-- ==================== lifecycle ====================

function EnemyAnimator.init(_injected: any) end

function EnemyAnimator.start()
	local tag = MapLayout.Tags.WorldEnemy
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
		task.defer(adopt, inst)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
		if inst:IsA("Model") then
			destroy(inst)
		end
	end)
	for _, inst in CollectionService:GetTagged(tag) do
		adopt(inst)
	end
end

return EnemyAnimator
