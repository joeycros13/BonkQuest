--!strict
-- WorldEnemyController: the client-side life of the enemies standing in the
-- world. It owns everything visual about them and none of their state:
--   * an idle wander that drifts each enemy around its spawn point, pausing and
--     turning on the spot so it reads as alive rather than as a moving prop,
--   * a health bar billboard above each one, driven by replicated attributes,
--   * hiding a defeated enemy until the server respawns it,
--   * weapon fights: while MeleeService has an enemy (AiState Chase / Return) it
--     stops wandering and glides after the server's FightPos / FightLook, and it
--     flinches and pops a damage number whenever its HP drops.
--     targets() hands WeaponController the enemies a swing could touch.
--
-- WorldEnemyService is the authority: it publishes EnemyId / Archetype / MaxHp /
-- Hp / Alive / WanderRadius as attributes and tags the body
-- WorldEnemy, and this controller only reads them. Discovery is by that tag, so
-- enemies are adopted wherever they are and whenever they appear -- including the
-- ones the server clones in after this controller has already started.
--
-- Movement runs as an Animation.Scheduler system (Render, priority 10), so it
-- always lands before the enemy animators place the limbs. A rigged body
-- (EnemyAnimator) is moved by its Root alone -- the animator carries the rest --
-- and anything else by PivotTo.
--
-- The wander is cosmetic and per-client -- two players see the same enemy at
-- slightly different spots, which is why MeleeService allows some slack on hits
-- against a wandering enemy (Balance.Melee.hitSlack).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Animation = require(Shared:WaitForChild("Animation"))
local Effects = Animation.Effects
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Enemies = require(Config:WaitForChild("Enemies"))
local MapLayout = require(Config:WaitForChild("MapLayout"))
local Format = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Format"))

local WorldEnemyController = {}

-- How long to wait for WorldEnemyService to publish an enemy's attributes.
local ATTRIBUTE_TIMEOUT = 30

-- Wander tuning. Presentation only, so it lives here rather than in Balance.
local SPEED_MIN, SPEED_MAX = 1.6, 3.2 -- studs/sec while drifting
local PAUSE_MIN, PAUSE_MAX = 1.5, 4.0 -- seconds spent standing still
local TURN_RATE = math.rad(220) -- how fast it swings to a new heading
local ARRIVE_EPSILON = 0.05
-- What an enemy does on reaching a drift target: stand still, turn on the spot,
-- or head straight off again. The remainder of 1 is the "keep moving" case.
local CHANCE_PAUSE = 0.75
local CHANCE_TURN = 0.15
-- Bosses are calmer still: they always stop between drifts, rest longer, and
-- step more slowly.
local BOSS_PAUSE_SCALE = 2.5
local BOSS_SPEED_SCALE = 0.6

-- How quickly a fighting enemy closes on the server's latest position (1/sec).
-- The server publishes ~20 times a second; this hides the steps between.
local FOLLOW_RATE = 12

local deps: any = nil
local BonkPop: any = nil
local barTemplate: BillboardGui? = nil
local bossBarTemplate: BillboardGui? = nil
local EnemyAnimator: any = nil

type Enemy = {
	id: string,
	instance: Instance,
	anchor: BasePart, -- part the bar hangs off
	parts: { BasePart },
	collide: { [BasePart]: boolean }, -- original CanCollide, restored on respawn
	origin: CFrame,
	set: (CFrame) -> (),
	-- Wander state.
	position: Vector3,
	target: Vector3,
	yaw: number,
	targetYaw: number,
	pauseUntil: number,
	speed: number,
	wanderRadius: number,
	isBoss: boolean,
	-- Mirrored attributes.
	alive: boolean,
	ready: boolean, -- false until its first refresh (a body already dead on join doesn't pop)
	aiState: string,
	fightPos: Vector3?,
	fightLook: Vector3?,
	lastHp: number,
	radius: number, -- half the widest footprint; weapon reach is measured to the edge
	height: number,
	billboard: BillboardGui,
	hpFill: GuiObject?,
	hpLabel: TextLabel?,
	hpTrail: GuiObject?, -- the pale strip that lingers where the HP was, then slides down
	hpRatio: number,
	trailTween: Tween?,
	trailToken: number,
	-- whether the camera can see the body or its bar (checkSight), and the misses in a row
	seen: boolean,
	misses: number,
}

local enemies: { [string]: Enemy } = {}
-- Bodies already adopted, so a re-fired tag signal cannot register one twice.
local adopted: { [Instance]: string } = {}
local loop: any = nil
local warnedUnanchored = false

-- ==================== small helpers ====================

local function randomRange(min: number, max: number): number
	return min + math.random() * (max - min)
end

-- A uniformly distributed point in the wander disc around `origin`. The sqrt
-- keeps picks even across the disc instead of clustering them at the centre.
local function randomPointNear(origin: Vector3, radius: number): Vector3
	local angle = math.random() * math.pi * 2
	local distance = radius * math.sqrt(math.random())
	return origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

-- Signed shortest angle from `from` to `to`, in (-pi, pi].
local function angleDelta(from: number, to: number): number
	return ((to - from + math.pi) % (math.pi * 2)) - math.pi
end

local function partsOf(inst: Instance): { BasePart }
	local parts: { BasePart } = {}
	if inst:IsA("BasePart") then
		table.insert(parts, inst)
	end
	for _, descendant in inst:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

-- Height of the whole enemy, used to float the bar clear of its top face.
local function heightOf(inst: Instance): number
	if inst:IsA("Model") then
		return inst:GetExtentsSize().Y
	elseif inst:IsA("BasePart") then
		return inst.Size.Y
	end
	return 4
end

-- ==================== build ====================

local function numberAttr(inst: Instance, name: string, default: number): number
	local value = inst:GetAttribute(name)
	return if type(value) == "number" then value else default
end

-- Boss bars put a crown just left of the name, and the pair is centred as one
-- group. The name is TextScaled, so the group width is read off TextBounds as a
-- fraction of the row -- a ratio that stays put as the billboard grows and
-- shrinks with distance.
local function fitCrown(row: GuiObject, label: TextLabel, crown: GuiObject)
	local function place()
		local width = row.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local crownW = crown.AbsoluteSize.X / width
		local gap = crownW * numberAttr(crown, "Gap", 0.15)
		local textW = label.TextBounds.X / width
		local left = 0.5 - (crownW + gap + textW) / 2
		crown.Position = UDim2.fromScale(left, crown.Position.Y.Scale)
		label.Position = UDim2.fromScale(0.5 + (crownW + gap) / 2, label.Position.Y.Scale)
	end
	label:GetPropertyChangedSignal("TextBounds"):Connect(place)
	row:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	place()
end

-- The bar is hand-built: ReplicatedStorage/Assets/UI/EnemyHealthBar (bosses:
-- EnemyHealthBarBoss), a BillboardGui sized in studs. Found by name inside it:
-- EnemyName, Bar (the track, sized here), Fill, Trail, Amount and, on the boss
-- bar, Crown. Attributes: Clearance (studs above the body), WidthScale /
-- MinWidth / MaxWidth (bar width from the body's height) or BarWidth (bosses).
local function buildBar(anchor: BasePart, height: number, isBoss: boolean, displayName: string)
	local template = if isBoss and bossBarTemplate then bossBarTemplate else barTemplate
	local billboard = (template :: BillboardGui):Clone()
	billboard.StudsOffsetWorldSpace = Vector3.new(0, height / 2 + numberAttr(billboard, "Clearance", 1), 0)

	-- The billboard keeps its authored width as room for the name; only the
	-- bar's share of it changes per enemy.
	local room = billboard.Size.X.Scale
	local barWidth = numberAttr(billboard, "BarWidth", 0)
	if barWidth <= 0 then
		barWidth = math.clamp(
			height * numberAttr(billboard, "WidthScale", 0.8),
			numberAttr(billboard, "MinWidth", 3.6),
			numberAttr(billboard, "MaxWidth", 5.6)
		)
	end
	local bar = billboard:FindFirstChild("Bar", true)
	if bar and bar:IsA("GuiObject") then
		bar.Size = UDim2.fromScale(barWidth / room, bar.Size.Y.Scale)
	end

	local nameLabel = billboard:FindFirstChild("EnemyName", true)
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = displayName
		local crown = billboard:FindFirstChild("Crown", true)
		local row = nameLabel.Parent
		if crown and crown:IsA("GuiObject") and row and row:IsA("GuiObject") then
			fitCrown(row, nameLabel, crown)
		end
	end

	local fill = billboard:FindFirstChild("Fill", true)
	local trail = billboard:FindFirstChild("Trail", true)
	local label = billboard:FindFirstChild("Amount", true)
	billboard.Parent = anchor
	return billboard,
		if fill and fill:IsA("GuiObject") then fill else nil,
		if label and label:IsA("TextLabel") then label else nil,
		if trail and trail:IsA("GuiObject") then trail else nil
end

-- Show a new HP fraction. A drop leaves the pale Trail where the HP was for a
-- moment, then slides it down to the fill so the size of the hit reads; a rise
-- (respawn) snaps both.
local function setRatio(enemy: Enemy, ratio: number)
	local fill, trail = enemy.hpFill, enemy.hpTrail
	if fill then
		fill.Size = UDim2.fromScale(ratio, 1)
	end
	if trail then
		if ratio < enemy.hpRatio and enemy.alive then
			enemy.trailToken += 1
			local token = enemy.trailToken
			local delay = numberAttr(enemy.billboard, "TrailDelay", 0.35)
			local seconds = numberAttr(enemy.billboard, "TrailSeconds", 0.4)
			if enemy.trailTween then
				enemy.trailTween:Pause()
			end
			task.delay(delay, function()
				if enemy.trailToken ~= token then
					return -- another hit landed; that one restarts the slide
				end
				local tween = TweenService:Create(trail, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = UDim2.fromScale(enemy.hpRatio, 1),
				})
				enemy.trailTween = tween
				tween:Play()
			end)
		elseif ratio > enemy.hpRatio or not enemy.alive then
			-- (an unchanged ratio is just another attribute refreshing; leave a running slide be)
			enemy.trailToken += 1
			if enemy.trailTween then
				enemy.trailTween:Cancel()
				enemy.trailTween = nil
			end
			trail.Size = UDim2.fromScale(ratio, 1)
		end
	end
	enemy.hpRatio = ratio
end

-- ==================== visuals ====================

-- Death and respawn are local-only: the server merely flips the Alive attribute.
-- LocalTransparencyModifier is used instead of Transparency so the replicated
-- property is never touched, and collision is restored from the snapshot taken at
-- registration.
local function applyVisible(enemy: Enemy, visible: boolean)
	if not visible then
		Effects.burst(enemy.anchor.Position, "Poof")
	end
	for _, part in enemy.parts do
		part.LocalTransparencyModifier = if visible then 0 else 1
		part.CanCollide = if visible then enemy.collide[part] == true else false
	end
	enemy.billboard.Enabled = visible
	if visible then
		-- Respawn back at the spawn point, then drift out from there again.
		enemy.position = enemy.origin.Position
		enemy.target = enemy.origin.Position
		enemy.yaw = 0
		enemy.targetYaw = 0
		enemy.pauseUntil = 0
		enemy.set(enemy.origin)
	end
end

-- Where the local player's weapon struck the enemy: on the side of its body facing them, at
-- about their chest height, kept within the body's lower 20%..85% (the user, 2026-10-25:
-- pops go where the sword hits, so a big boss's BONK isn't off the top of the screen).
local function hitPoint(enemy: Enemy): Vector3
	local anchor = enemy.anchor
	local centre = anchor.Position
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local bottom = centre.Y - enemy.height / 2
	if not (root and root:IsA("BasePart")) then
		return centre + Vector3.new(0, enemy.height * 0.25, 0)
	end
	local toward = Vector3.new(root.Position.X - centre.X, 0, root.Position.Z - centre.Z)
	toward = if toward.Magnitude > 1e-3 then toward.Unit else anchor.CFrame.LookVector
	-- how far the body reaches toward the player: its root box seen along that direction
	local localDir = anchor.CFrame:VectorToObjectSpace(toward)
	local reach = math.abs(localDir.X) * anchor.Size.X / 2 + math.abs(localDir.Z) * anchor.Size.Z / 2
	local height = math.clamp(root.Position.Y + 0.6, bottom + enemy.height * 0.2, bottom + enemy.height * 0.85)
	local point = centre + toward * reach
	return Vector3.new(point.X, height, point.Z)
end

-- A weapon hit: recoil, the EnemyHit sound, and the damage in a comic burst
-- bubble that pops like the defeat's BONK (2026-10-21, the user's request). A
-- critical hit gets the gold bubble and a lower, louder hit (the sound's
-- CritPitch / CritVolume attributes). The killing blow gets neither the sound
-- nor the bubble: a death shows only the defeat's BONK and pop (the user).
-- The bubble is only for the player who landed the hit (`mine`, from the enemy's
-- HitBy attribute; 2026-10-23, the user): everyone else still sees the spark,
-- flash and recoil and hears the hit.
local function showHit(enemy: Enemy, amount: number, crit: boolean, killing: boolean, mine: boolean)
	if EnemyAnimator then
		EnemyAnimator.flinch(enemy.instance)
	end
	local at = enemy.anchor.Position + Vector3.new(0, enemy.height * 0.15, 0)
	Effects.burst(at, "HitSpark")
	Effects.flash(enemy.instance, "HurtFlash")
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local sounds = assets and assets:FindFirstChild("Sounds")
	local hit = sounds and sounds:FindFirstChild("EnemyHit")
	if hit and hit:IsA("Sound") and not killing then
		local pitch = if crit then numberAttr(hit, "CritPitch", 0.85) else 1
		local volume = if crit then numberAttr(hit, "CritVolume", 1.4) else 1
		Effects.sound(hit, at, { pitch = hit.PlaybackSpeed * pitch * math.random(92, 110) / 100, volume = hit.Volume * volume })
	end
	if not killing and mine then
		BonkPop.hit(hitPoint(enemy), enemy.height / 4, amount, enemy.isBoss, crit, true)
	end
end

-- A defeat (user, 2026-10-11: kills were too quiet): a white Poof cloud, gold
-- DeathPop stars with a flash, a ground ring, and the EnemyPop sound
-- (ReplicatedStorage/Assets/Sounds), all sized up for bigger bodies (bosses).
-- No camera shake. The BONK is only for the player whose hit finished it (`mine`);
-- everyone sees the cloud and hears the pop. A killing blow that was a critical hit
-- (`crit`: the enemy's CritHp was 0) pops the CRITICAL BONK and a lower, louder pop
-- (EnemyPop's CritPitch / CritVolume, like EnemyHit's; 2026-10-24, the user).
local function showDefeat(enemy: Enemy, mine: boolean, crit: boolean)
	local scale = math.clamp(enemy.height / 4, 0.8, 2.5)
	local at = enemy.anchor.Position + Vector3.new(0, enemy.height * 0.1, 0)
	Effects.burst(at, "Poof", { count = math.floor(22 * scale) })
	Effects.burst(at, "DeathPop", { count = math.floor(20 * scale) })
	Effects.shockwave(enemy.anchor.Position - Vector3.new(0, enemy.height / 2 - 0.2, 0), "Shockwave", { endSize = 9 * scale })
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local sounds = assets and assets:FindFirstChild("Sounds")
	local pop = sounds and sounds:FindFirstChild("EnemyPop")
	if pop and pop:IsA("Sound") then
		-- bigger bodies pop a little lower
		local pitch = if crit then numberAttr(pop, "CritPitch", 0.85) else 1
		local volume = if crit then numberAttr(pop, "CritVolume", 1.4) else 1
		Effects.sound(pop, at, { pitch = math.random(95, 108) / 100 / math.sqrt(scale) * pitch, volume = pop.Volume * volume })
	end
	-- and the comic "BONK!" where the killing blow landed (2026-10-17, Bonk Quest); a boss's
	-- is the BOSS BONK (issue 27, 2026-10-25)
	if not mine then
		return
	end
	BonkPop.show(hitPoint(enemy), enemy.height / 4, enemy.isBoss, crit, true)
end

-- Mirror the authoritative attributes onto the bar and alive state.
local function refreshFromAttributes(enemy: Enemy)
	local inst = enemy.instance
	local maxHp = tonumber(inst:GetAttribute("MaxHp")) or 1
	local hp = tonumber(inst:GetAttribute("Hp")) or maxHp
	local alive = inst:GetAttribute("Alive") ~= false
	local aiState = inst:GetAttribute("AiState")
	local nextState = if type(aiState) == "string" then aiState else "Idle"
	if nextState == "Idle" and enemy.aiState ~= "Idle" then
		-- Back from a fight: rest a moment where it stands, then wander from there.
		enemy.target = enemy.position
		enemy.pauseUntil = os.clock() + randomRange(PAUSE_MIN, PAUSE_MAX)
	end
	enemy.aiState = nextState

	-- enemy.alive is the state BEFORE this update, so the killing blow shows too.
	-- HitBy names the player whose hit this was (set with Hp by WorldEnemyService).
	local mine = inst:GetAttribute("HitBy") == Players.LocalPlayer.UserId
	if hp < enemy.lastHp and enemy.alive then
		showHit(enemy, math.floor(enemy.lastHp - hp + 0.5), inst:GetAttribute("CritHp") == hp, hp <= 0 or not alive, mine)
	end
	enemy.lastHp = hp

	if alive ~= enemy.alive then
		if not alive and enemy.ready then
			showDefeat(enemy, mine, inst:GetAttribute("CritHp") == 0)
		end
		enemy.alive = alive
		applyVisible(enemy, alive)
	end

	setRatio(enemy, if maxHp > 0 then math.clamp(hp / maxHp, 0, 1) else 0)
	if enemy.hpLabel then
		enemy.hpLabel.Text = Format.ratio(math.max(0, hp), maxHp)
	end
end

-- ==================== wander ====================

-- Decide what happens after reaching a drift target.
local function chooseNext(enemy: Enemy, now: number)
	local calm = if enemy.isBoss then BOSS_PAUSE_SCALE else 1
	local roll = math.random()
	if roll < CHANCE_PAUSE or enemy.isBoss then
		enemy.pauseUntil = now + randomRange(PAUSE_MIN, PAUSE_MAX) * calm
	elseif roll < CHANCE_PAUSE + CHANCE_TURN then
		-- Turn on the spot: the heading changes while it stands still.
		enemy.pauseUntil = now + randomRange(PAUSE_MIN, PAUSE_MAX) * calm
		enemy.targetYaw = math.random() * math.pi * 2
	end
	enemy.target = randomPointNear(enemy.origin.Position, enemy.wanderRadius)
	enemy.speed = randomRange(SPEED_MIN, SPEED_MAX) * (if enemy.isBoss then BOSS_SPEED_SCALE else 1)
end

local function step(enemy: Enemy, dt: number, now: number)
	-- A dead enemy is hidden.
	if not enemy.alive then
		return
	end

	local fightPos = enemy.fightPos
	if enemy.aiState ~= "Idle" and fightPos then
		-- In a weapon fight the server decides where it is; glide after it.
		enemy.position = enemy.position:Lerp(fightPos, 1 - math.exp(-FOLLOW_RATE * dt))
		local look = enemy.fightLook
		if look and look.Magnitude > 1e-3 then
			local localLook = enemy.origin.Rotation:VectorToObjectSpace(look)
			enemy.targetYaw = math.atan2(-localLook.X, -localLook.Z)
		end
	elseif now >= enemy.pauseUntil then
		local delta = enemy.target - enemy.position
		local distance = delta.Magnitude
		if distance <= ARRIVE_EPSILON then
			chooseNext(enemy, now)
		else
			local direction = delta / distance
			enemy.position += direction * math.min(enemy.speed * dt, distance)
			-- Face the way it is walking. A model's forward is its pivot's -Z, and the
			-- yaw below is applied on top of the marker's authored rotation, so the
			-- heading has to be measured in the marker's own frame -- otherwise a
			-- marker turned to face the hub walks its enemy backwards.
			local localDir = enemy.origin.Rotation:VectorToObjectSpace(direction)
			enemy.targetYaw = math.atan2(-localDir.X, -localDir.Z)
		end
	end

	-- Ease toward the desired heading; this is what makes the turns readable.
	local maxTurn = TURN_RATE * dt
	enemy.yaw += math.clamp(angleDelta(enemy.yaw, enemy.targetYaw), -maxTurn, maxTurn)

	-- Keep the enemy's authored tilt, then add the wander yaw on top.
	enemy.set(CFrame.new(enemy.position) * enemy.origin.Rotation * CFrame.Angles(0, enemy.yaw, 0))
end

-- A living enemy's bar only shows while the player's character is within the
-- bar's "ShowDistance" attribute (user, 2026-10-12: 32 studs). Measured from the
-- character, not the camera, so zooming out doesn't hide a bar you're next to.
-- And only while the camera can see the enemy (2026-10-26, the user: like the quest
-- markers, no bars through walls, hills or trees): checkSight casts from the camera to
-- the body's middle and its head every SightSeconds (on the bar template, 0.2);
-- one that reaches means seen, and SightMisses (2) misses in a row hide the bar again, so
-- the edge of cover doesn't flicker. Other enemies and the player's own body never block
-- the line, and nearly see-through parts are looked through.
local function inRange(enemy: Enemy, from: Vector3?): boolean
	if not from then
		return true
	end
	local range = numberAttr(enemy.billboard, "ShowDistance", 32)
	return (enemy.anchor.Position - from).Magnitude <= range
end

local SEE_THROUGH = 0.9
local MAX_SEE_THROUGH = 4

local function reaches(from: Vector3, to: Vector3, skip: { Instance }): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = table.clone(skip)
	params.FilterDescendantsInstances = list
	for _ = 1, MAX_SEE_THROUGH do
		local hit = workspace:Raycast(from, to - from, params)
		if not hit then
			return true
		end
		local blocker = hit.Instance
		if not (blocker:IsA("BasePart") and blocker.Transparency + blocker.LocalTransparencyModifier >= SEE_THROUGH) then
			return false
		end
		table.insert(list, blocker)
		params.FilterDescendantsInstances = list
	end
	return false
end

local function checkSight()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local from = if root and root:IsA("BasePart") then root.Position else nil
	local eye = camera.CFrame.Position
	local skip: { Instance } = {}
	if character then
		table.insert(skip, character)
	end
	for _, enemy in enemies do
		table.insert(skip, enemy.instance)
	end
	for _, enemy in enemies do
		if enemy.alive and inRange(enemy, from) then
			local centre = enemy.anchor.Position
			local head = enemy.instance:FindFirstChild("Head", true)
			local points = { centre }
			if head and head:IsA("BasePart") then
				table.insert(points, head.Position)
			end
			local seen = false
			for _, point in points do
				if reaches(eye, point, skip) then
					seen = true
					break
				end
			end
			if seen then
				enemy.misses = 0
				enemy.seen = true
			else
				enemy.misses += 1
				if enemy.misses >= numberAttr(enemy.billboard, "SightMisses", 2) then
					enemy.seen = false
				end
			end
		else
			enemy.misses = 0
			enemy.seen = false
		end
	end
end

local function showBar(enemy: Enemy, from: Vector3?)
	local show = enemy.alive and enemy.seen and inRange(enemy, from)
	if enemy.billboard.Enabled ~= show then
		enemy.billboard.Enabled = show
	end
end

local function startLoop()
	if loop then
		return
	end
	loop = Animation.Scheduler.bind("Render", "WorldEnemyController", 10, function(dt: number, now: number)
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local from = if root and root:IsA("BasePart") then root.Position else nil
		for _, enemy in enemies do
			step(enemy, dt, now)
			showBar(enemy, from)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(if barTemplate then numberAttr(barTemplate, "SightSeconds", 0.2) else 0.2)
			checkSight()
		end
	end)
end

-- ==================== registration ====================

-- Wait for the server to publish this instance's id before adopting it.
local function waitForId(inst: Instance): string?
	local deadline = os.clock() + ATTRIBUTE_TIMEOUT
	while os.clock() < deadline do
		local id = inst:GetAttribute("EnemyId")
		if type(id) == "string" then
			return id
		end
		task.wait(0.25)
	end
	return nil
end

local function register(inst: Instance)
	if not (inst:IsA("BasePart") or inst:IsA("Model")) or adopted[inst] then
		return
	end
	-- Claimed before the wait below, not after: the startup sweep and the tag's
	-- added signal can otherwise both pick up the same body and build it twice.
	adopted[inst] = ""

	local id = waitForId(inst)
	if not id then
		adopted[inst] = nil
		warn(("[WorldEnemyController] %s never received an EnemyId; skipping"):format(inst:GetFullName()))
		return
	end

	local parts = partsOf(inst)

	-- Resolve how this enemy is posed and where its bar hangs off: a Model
	-- moves by pivot so its whole body follows, a lone part by CFrame.
	local origin: CFrame
	local set: (CFrame) -> ()
	local anchor: BasePart?
	if inst:IsA("Model") then
		local model = inst :: Model
		origin = model:GetPivot()
		anchor = model.PrimaryPart or parts[1]
		local primary = model.PrimaryPart
		set = function(cf: CFrame)
			if primary and primary.Name == "Root" and EnemyAnimator and EnemyAnimator.isRigged(model) then
				-- The animator places every other part from Root this frame.
				primary.CFrame = cf * primary.PivotOffset:Inverse()
			else
				model:PivotTo(cf)
			end
		end
	else
		local part = inst :: BasePart
		origin = part.CFrame
		anchor = part
		set = function(cf: CFrame)
			part.CFrame = cf
		end
	end
	if not anchor then
		warn(("[WorldEnemyController] %s has no BasePart; skipping"):format(inst:GetFullName()))
		return
	end

	local collide: { [BasePart]: boolean } = {}
	for _, part in parts do
		collide[part] = part.CanCollide
		-- The wander writes CFrames every frame, so physics must not also be
		-- moving the part. Anchoring locally is enough while the server-side part
		-- sits still, but an unanchored part will still be corrected by
		-- replication, so say so once rather than fighting it silently.
		if not part.Anchored then
			part.Anchored = true
			if not warnedUnanchored then
				warnedUnanchored = true
				warn(
					("[WorldEnemyController] %s is not Anchored; anchor the enemies in Studio or their wander will stutter"):format(
						part:GetFullName()
					)
				)
			end
		end
	end

	local height = heightOf(inst)
	local isBoss = inst:GetAttribute("IsBoss") == true
	local archetype = inst:GetAttribute("Archetype")
	local def = if type(archetype) == "string" then Enemies.get(archetype) else nil
	local displayName = if def and def.name then def.name else (if type(archetype) == "string" then archetype else inst.Name)
	local billboard, fill, label, trail = buildBar(anchor, height, isBoss, displayName)
	local footprint = if inst:IsA("Model") then inst:GetExtentsSize() else (inst :: BasePart).Size
	local maxHpAttribute = tonumber(inst:GetAttribute("MaxHp")) or 1

	-- Published per enemy by the service, so a spawn marker can widen or tighten
	-- one enemy's drift without touching Balance.
	local radiusAttribute = inst:GetAttribute("WanderRadius")
	local wanderRadius = if type(radiusAttribute) == "number"
		then radiusAttribute
		else Balance.WorldEnemy.wanderRadius

	local enemy: Enemy = {
		id = id,
		instance = inst,
		anchor = anchor,
		parts = parts,
		collide = collide,
		origin = origin,
		set = set,
		position = origin.Position,
		target = randomPointNear(origin.Position, wanderRadius),
		yaw = 0,
		targetYaw = 0,
		pauseUntil = 0,
		speed = randomRange(SPEED_MIN, SPEED_MAX) * (if inst:GetAttribute("IsBoss") then BOSS_SPEED_SCALE else 1),
		wanderRadius = wanderRadius,
		isBoss = isBoss,
		alive = true,
		ready = false,
		aiState = "Idle",
		fightPos = nil,
		fightLook = nil,
		lastHp = tonumber(inst:GetAttribute("Hp")) or maxHpAttribute,
		radius = math.max(footprint.X, footprint.Z) / 2,
		height = height,
		billboard = billboard,
		hpFill = fill,
		hpLabel = label,
		hpTrail = trail,
		hpRatio = 1,
		trailTween = nil,
		trailToken = 0,
		seen = false,
		misses = 0,
	}

	enemies[id] = enemy
	adopted[inst] = id
	refreshFromAttributes(enemy)
	enemy.ready = true
	inst.AttributeChanged:Connect(function(name: string)
		-- The fight pose changes many times a second and only feeds the glide.
		if name == "FightPos" then
			local value = inst:GetAttribute("FightPos")
			enemy.fightPos = if typeof(value) == "Vector3" then value else nil
		elseif name == "FightLook" then
			local value = inst:GetAttribute("FightLook")
			enemy.fightLook = if typeof(value) == "Vector3" then value else nil
		elseif name ~= "AttackSeq" then
			refreshFromAttributes(enemy)
		end
	end)
end

-- Drop an enemy whose body was destroyed or untagged, so its billboard and its
-- slot in the wander loop go with it.
local function unregister(inst: Instance)
	local id = adopted[inst]
	if not id then
		return
	end
	local enemy = enemies[id]
	if enemy then
		enemy.billboard:Destroy()
	end
	enemies[id] = nil
	adopted[inst] = nil
end

-- ==================== weapon targets ====================

export type Target = {
	id: string,
	position: Vector3, -- where this client is drawing it
	radius: number,
}

-- Every enemy a weapon could hit right now: alive, visible and not walking home.
function WorldEnemyController.targets(): { Target }
	local list: { Target } = {}
	for id, enemy in enemies do
		if enemy.alive and enemy.aiState ~= "Return" then
			table.insert(list, { id = id, position = enemy.position, radius = enemy.radius })
		end
	end
	return list
end

-- ==================== lifecycle ====================

-- Have a body stop wandering and turn to face `point` for `seconds`, here only (the world
-- unlock cinematic turns the boss to its camera, issue 28). A fight still wins.
-- Puts a wandering enemy back on its spawn point (the middle of its wander circle),
-- holds it there for `seconds` turned toward `point`, and returns that spot. The
-- unlock cinematic uses it so its boss shot is framed on the spawn point, not wherever
-- the boss had roamed to.
function WorldEnemyController.face(model: Instance, point: Vector3, seconds: number): Vector3?
	for _, enemy in enemies do
		if enemy.instance == model then
			if not (enemy.aiState ~= "Idle" and enemy.fightPos) then
				enemy.position = enemy.origin.Position
			end
			enemy.target = enemy.position
			enemy.pauseUntil = os.clock() + seconds
			local look = Vector3.new(point.X - enemy.position.X, 0, point.Z - enemy.position.Z)
			if look.Magnitude > 1e-3 then
				local localLook = enemy.origin.Rotation:VectorToObjectSpace(look.Unit)
				enemy.targetYaw = math.atan2(-localLook.X, -localLook.Z)
			end
			return enemy.position
		end
	end
	return nil
end

function WorldEnemyController.init(injected: any)
	deps = injected
	BonkPop = deps.Util.BonkPop
	EnemyAnimator = deps.Controllers.EnemyAnimator
end

function WorldEnemyController.start()
	local tag = MapLayout.Tags.WorldEnemy

	local assets = ReplicatedStorage:WaitForChild("Assets", 10)
	local ui = assets and assets:WaitForChild("UI", 10)
	local template = ui and ui:WaitForChild("EnemyHealthBar", 10)
	if not (template and template:IsA("BillboardGui")) then
		warn("[WorldEnemyController] missing ReplicatedStorage/Assets/UI/EnemyHealthBar; enemies get no health bar")
		return
	end
	barTemplate = template
	local bossTemplate = ui:WaitForChild("EnemyHealthBarBoss", 10)
	bossBarTemplate = if bossTemplate and bossTemplate:IsA("BillboardGui") then bossTemplate else nil

	-- One thread each: a straggler waiting on its attributes must not hold up the
	-- rest. The added signal covers both the bodies already present and every one
	-- the server clones in later, so no folder is ever enumerated.
	for _, inst in CollectionService:GetTagged(tag) do
		task.spawn(register, inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst: Instance)
		task.spawn(register, inst)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(unregister)

	startLoop()
end

return WorldEnemyController
