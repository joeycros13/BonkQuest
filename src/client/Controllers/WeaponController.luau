--!strict
-- WeaponController: the player's side of real-time weapon combat.
--
--   * Input: a left click (or the HUD's Attack button on touch, or R2) swings the
--     equipped weapon. The swing plays locally at once; the server hears
--     WeaponSwing at the start and WeaponHit when the swing's "Hit" marker passes,
--     naming the enemies inside its reach and arc. MeleeService re-checks all of it.
--   * Aim: a swing first turns the character toward the nearest enemy in reach,
--     so fights do not need precise steering.
--   * Animation (Animation system): every character holding a weapon (its
--     "Weapon" attribute) plays that weapon's hold clip, and a swing clip when its
--     "SwingSeq" attribute ticks (other players) or when the local player swings.
--     Both play on the character's shared animator (Animation.Character), above
--     PlayerAnimator's locomotion, so nothing fights over a joint. The poses
--     themselves -- HOLDS and SWINGS -- live in Animation.Clips.Weapons.
--   * Feel: a slash trail along the weapon during the strike. A weapon with
--     impact = "Slam" (the Corn Cob) also hits the ground on its "Hit" marker:
--     a ring of dust, flying clods and a shock flash where its head lands.
--     The camera never shakes or kicks (the user's call, 2026-10-09).
--   * Hand: the player has one selected weapon (the hotbar's; the player's
--     "SelectedWeapon" attribute), either in hand or put away ("Holstered").
--     `current()` is the weapon in hand (nil while put away), `selected()` the
--     hotbar's; `equip` selects a weapon and takes it out, `toggleHolster` puts
--     the selected one away or takes it out. MeleeService owns all of it.
--   * Tools (2026-10-18): the hand can hold a gathering tool instead (Config/Tools; the
--     character's "Tool" attribute, the player's "HeldTool" kind). `holdTool(kind)` takes
--     the best one of a kind out (or puts it away), `tool()` is the one in hand. A tool
--     swings with the same clips, rate limit and SwingSeq as a weapon, but its "Hit"
--     moment only reaches onSwingLanded listeners (GatherController), never enemies.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weapons = require(Shared:WaitForChild("Config"):WaitForChild("Weapons"))
local Infuse = require(Shared:WaitForChild("Config"):WaitForChild("Infuse"))
-- the Attack Speed upgrade shortens the swing (Upgrades.adjust)
local Upgrades = require(Shared:WaitForChild("Config"):WaitForChild("Upgrades"))
local Tools = require(Shared:WaitForChild("Config"):WaitForChild("Tools"))
local Animation = require(Shared:WaitForChild("Animation"))
local Character = Animation.Character
local WeaponClips = Animation.Clips.Weapons
local Effects = Animation.Effects

local WeaponController = {}

local deps: any = nil
local WorldEnemyController: any = nil
local swingRemote: RemoteEvent? = nil
local hitRemote: RemoteEvent? = nil
local equipRemote: RemoteEvent? = nil
local holsterRemote: RemoteEvent? = nil
local holdToolRemote: RemoteEvent? = nil

local player = Players.LocalPlayer
local changedEvent = Instance.new("BindableEvent")
-- fires on every swing's "Hit" marker, whatever it touched (World 3's secret crystals listen)
local landedEvent = Instance.new("BindableEvent")

-- Enemies within reach plus this get the auto-turn.
local AIM_ASSIST_RANGE = 3
local MAX_HEIGHT_GAP = 8

-- The ground slam (impact = "Slam"): dust bursts around the spot.
local SLAM_DUST_DIRECTIONS = 10
-- The Gust (impact = "Gust", the Weathervane Spear, 2026-10-19): wind bursts fanned
-- across the front, right to left like the sweep, a beat apart.
local GUST_BURSTS = 6
local GUST_SPREAD = 60 -- degrees either side of straight ahead
local GUST_STEP = 0.03 -- seconds between bursts
-- A weapon with Mood parts (the Pumpkin King's Mace's faces, 2026-10-19) turns Angry from
-- the trail coming on until this long after it goes off, then Calm again.
local MOOD_HOLD = 0.25

local rad = math.rad

-- ==================== rigs ====================

type Rig = {
	model: Model,
	animator: any,
	hold: any?, -- the playing hold track
	swing: any?, -- the playing swing track (arms)
	swingBody: any?, -- its additive body layer (twist, lean, lunge)
	trail: any?, -- slash trail handle on the held weapon
	trailModel: Model?,
}

local rigs: { [Model]: Rig } = {}
-- the swing that last turned a character's weapon angry (setMood)
local moodTrack: { [Model]: any } = setmetatable({}, { __mode = "k" }) :: any

local function alive(model: Model): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Whatever the character holds: its weapon, or a gathering tool (both swing the same way).
local function heldDef(model: Model): any
	return Weapons.get(model:GetAttribute("Weapon")) or Tools.get(model:GetAttribute("Tool"))
end

-- The slash trail for whatever the character holds right now (made lazily).
local function trailOf(rig: Rig): any?
	local held = rig.model:FindFirstChild("EquippedWeapon")
	if not (held and held:IsA("Model")) then
		return nil
	end
	if rig.trailModel ~= held then
		if rig.trail then
			rig.trail:Destroy()
		end
		rig.trail = Effects.trail(held, "SlashTrail")
		rig.trailModel = held
	end
	return rig.trail
end

-- Play the hold clip for the current weapon (or none: no weapon, dead).
local function sync(rig: Rig)
	local def = heldDef(rig.model)
	local want = if def and alive(rig.model) then WeaponClips.hold(def) else nil
	if rig.hold and rig.hold.clip ~= want then
		rig.hold:Stop()
		rig.hold = nil
	end
	if want and not rig.hold then
		rig.hold = rig.animator:Play(want)
	end
end

-- Where a slamming weapon's head meets the ground (or whatever is under it): a
-- ray down from the head, which is three quarters of the way to the far end.
local function slamSpot(rig: Rig): Vector3?
	local held = rig.model:FindFirstChild("EquippedWeapon")
	local grip = held and held:IsA("Model") and held.PrimaryPart
	if not grip then
		return nil
	end
	local look = grip.CFrame.LookVector
	local far = 0
	for _, part in held:GetDescendants() do
		if part:IsA("BasePart") then
			far = math.max(far, (part.Position - grip.Position):Dot(look) + part.Size.Magnitude / 2)
		end
	end
	local head = grip.Position + look * far * 0.75
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { workspace.CurrentCamera :: Instance }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	local runtime = workspace:FindFirstChild("Runtime")
	if runtime then
		table.insert(ignore, runtime)
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(head + Vector3.new(0, 4, 0), Vector3.new(0, -14, 0), params)
	return if hit then hit.Position else nil
end

-- Wind across the front of a sweep: bursts fanned from the right to the left, each aimed
-- outward, with a puff of dust on the ground under each.
local function gust(rig: Rig)
	local root = rig.model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.01 then
		return
	end
	look = look.Unit
	for i = 0, GUST_BURSTS - 1 do
		task.delay(i * GUST_STEP, function()
			local angle = -GUST_SPREAD + 2 * GUST_SPREAD * i / (GUST_BURSTS - 1)
			local dir = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(look)
			local from = root.Position + dir * 3 + Vector3.new(0, 0.4, 0)
			Effects.burst(CFrame.lookAt(from, from + dir), "GustWind")
			local low = root.Position + dir * 4 - Vector3.new(0, 2.6, 0)
			Effects.burst(CFrame.lookAt(low, low + dir + Vector3.new(0, 0.1, 0)), "GustDust")
		end)
	end
end

-- The mace's head lands: orange sparks with a glow, and seeds that jump and fall back.
local function pumpkin(rig: Rig)
	local spot = slamSpot(rig)
	if not spot then
		return
	end
	Effects.burst(spot + Vector3.new(0, 0.6, 0), "PumpkinSparks")
	Effects.burst(spot + Vector3.new(0, 0.4, 0), "PumpkinSeeds")
end

-- Show the parts of `held` whose Mood attribute is `mood` and hide the other moods'.
local function setMood(held: Instance, mood: string)
	for _, part in held:GetDescendants() do
		if part:IsA("BasePart") then
			local m = part:GetAttribute("Mood")
			if type(m) == "string" then
				part.Transparency = if m == mood then 0 else 1
			end
		end
	end
end

local function hasMood(held: Instance): boolean
	for _, part in held:GetDescendants() do
		if part:IsA("BasePart") and type(part:GetAttribute("Mood")) == "string" then
			return true
		end
	end
	return false
end

local function slam(rig: Rig)
	local spot = slamSpot(rig)
	if not spot then
		return
	end
	local low = spot + Vector3.new(0, 0.4, 0)
	for i = 1, SLAM_DUST_DIRECTIONS do
		local angle = (i + math.random() * 0.6) / SLAM_DUST_DIRECTIONS * 2 * math.pi
		local outward = Vector3.new(math.cos(angle), 0.12, math.sin(angle))
		Effects.burst(CFrame.lookAt(low, low + outward), "SlamDust")
	end
	Effects.burst(low, "SlamDebris")
	Effects.shockwave(spot + Vector3.new(0, 0.08, 0), "SlamRing")
end

local function startSwing(rig: Rig, def: Weapons.WeaponDef): any
	if rig.swing then
		rig.swing:Stop(0.05)
	end
	if rig.swingBody then
		rig.swingBody:Stop(0.05)
	end
	local speed = 1 / def.cooldown
	local track = rig.animator:Play(WeaponClips.swing(def), { speed = speed })
	-- The body moves additively on top of walking, so the legs and foot planting
	-- carry on through the attack.
	rig.swingBody = rig.animator:Play(WeaponClips.swingBody(def), { speed = speed })
	rig.swing = track
	local impact = if def.impact == "Slam" then slam elseif def.impact == "Gust" then gust elseif def.impact == "Pumpkin" then pumpkin else nil
	if impact then
		track:GetMarkerReachedSignal("Hit"):Once(function()
			if rig.swing == track then
				impact(rig)
			end
		end)
	end
	-- the mace's face: angry through the strike, calm again after
	local held = rig.model:FindFirstChild("EquippedWeapon")
	if held and held:IsA("Model") and hasMood(held) then
		local function calm()
			task.delay(MOOD_HOLD, function()
				-- unless a newer swing has turned it angry again
				if moodTrack[rig.model] == track then
					setMood(held, "Calm")
				end
			end)
		end
		track:GetMarkerReachedSignal("TrailOn"):Connect(function()
			moodTrack[rig.model] = track
			setMood(held, "Angry")
		end)
		track:GetMarkerReachedSignal("TrailOff"):Connect(calm)
		track.Stopped:Connect(calm)
	end
	local trail = trailOf(rig)
	if trail then
		track:GetMarkerReachedSignal("TrailOn"):Connect(function()
			trail:Enable(true)
		end)
		track:GetMarkerReachedSignal("TrailOff"):Connect(function()
			trail:Enable(false)
		end)
		track.Stopped:Connect(function()
			trail:Enable(false)
		end)
	end
	return track
end

local function adopt(model: Model, cull: boolean): Rig
	local existing = rigs[model]
	if existing then
		return existing
	end
	local rig: Rig = {
		model = model,
		animator = Character.get(model, { cull = cull }).animator,
		hold = nil,
		swing = nil,
		swingBody = nil,
		trail = nil,
		trailModel = nil,
	}
	rigs[model] = rig
	sync(rig)
	model:GetAttributeChangedSignal("Weapon"):Connect(function()
		sync(rig)
	end)
	model:GetAttributeChangedSignal("Tool"):Connect(function()
		sync(rig)
	end)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			if rig.swing then
				rig.swing:Stop(0)
			end
			if rig.swingBody then
				rig.swingBody:Stop(0)
			end
			sync(rig)
		end)
	end
	model.AncestryChanged:Connect(function(_, parent)
		if parent == nil and rigs[model] == rig then
			rigs[model] = nil
		end
	end)
	return rig
end

-- ==================== characters ====================

local function watchCharacter(owner: Player, character: Model)
	if not Character.ready(character, 10) or not character.Parent then
		return
	end
	local rig = adopt(character, owner ~= player)
	if owner == player then
		changedEvent:Fire()
		character:GetAttributeChangedSignal("Weapon"):Connect(function()
			changedEvent:Fire()
		end)
		character:GetAttributeChangedSignal("Tool"):Connect(function()
			changedEvent:Fire()
		end)
	else
		-- Other players' swings arrive as a counter bump from the server.
		character:GetAttributeChangedSignal("SwingSeq"):Connect(function()
			local def = heldDef(character)
			if def and alive(character) then
				startSwing(rig, def)
			end
		end)
	end
end

local function watchPlayer(owner: Player)
	owner.CharacterAdded:Connect(function(character)
		watchCharacter(owner, character)
	end)
	if owner.Character then
		task.spawn(watchCharacter, owner, owner.Character)
	end
end

-- ==================== hitting ====================

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

type Hit = { id: string, pos: Vector3, distance: number }

-- Enemies inside the weapon's reach and arc, nearest first. Reach is measured to
-- the enemy's edge, and the arc is widened by the enemy's own width, so a long
-- body can be hit on its nose.
local function findHits(root: BasePart, def: Weapons.WeaponDef): { Hit }
	local look = flat(root.CFrame.LookVector)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local halfArc = rad(def.arc / 2)
	local hits: { Hit } = {}
	for _, target in WorldEnemyController.targets() do
		local offset = target.position - root.Position
		if math.abs(offset.Y) > MAX_HEIGHT_GAP then
			continue
		end
		local toward = flat(offset)
		local distance = toward.Magnitude
		if distance - target.radius > def.reach then
			continue
		end
		if def.arc < 360 and distance > target.radius then
			local angle = math.acos(math.clamp(toward.Unit:Dot(look), -1, 1))
			if angle > halfArc + math.atan2(target.radius, distance) then
				continue
			end
		end
		table.insert(hits, { id = target.id, pos = target.position, distance = distance })
	end
	table.sort(hits, function(a, b)
		return a.distance < b.distance
	end)
	return hits
end

-- Turn to face the nearest enemy close enough to be worth swinging at.
local function aimAssist(root: BasePart, def: Weapons.WeaponDef)
	local best: Vector3? = nil
	local bestDistance = math.huge
	for _, target in WorldEnemyController.targets() do
		local toward = flat(target.position - root.Position)
		local distance = toward.Magnitude - target.radius
		if distance <= def.reach + AIM_ASSIST_RANGE and distance < bestDistance and toward.Magnitude > 0.5 then
			best, bestDistance = target.position, distance
		end
	end
	if best then
		local at = root.Position
		root.CFrame = CFrame.lookAt(at, Vector3.new(best.X, at.Y, best.Z))
	end
end

-- The swing's "Hit" marker: check what it touched and tell the server.
local function landSwing(character: Model, root: BasePart, def: any)
	local held = heldDef(character)
	if player.Character ~= character or not held or held.id ~= def.id or not alive(character) then
		return
	end
	-- a tool's swing is for the trees and rocks (GatherController), never enemies
	if def.kind then
		landedEvent:Fire(root, def, false)
		return
	end
	local hits = findHits(root, def)
	-- listeners hear whether an enemy was struck (a weapon swing at a tree next to an
	-- enemy shouldn't show the wrong-tool hint)
	landedEvent:Fire(root, def, #hits > 0)
	if #hits == 0 or not hitRemote then
		return
	end
	local payload = {}
	for i = 1, math.min(#hits, def.maxTargets) do
		table.insert(payload, { id = hits[i].id, pos = hits[i].pos })
	end
	hitRemote:FireServer(payload)
end

-- ==================== public ====================

local lastSwing = 0
local clickFilter: ((any) -> boolean)? = nil

-- The weapon in hand (nil while it is put away).
function WeaponController.current(): Weapons.WeaponDef?
	local character = player.Character
	return if character then Upgrades.adjust(player, Infuse.adjust(player, Weapons.get(character:GetAttribute("Weapon")))) else nil
end

-- The selected weapon, the one in the hotbar, in hand or not.
function WeaponController.selected(): Weapons.WeaponDef?
	return Upgrades.adjust(player, Infuse.adjust(player, Weapons.get(player:GetAttribute("SelectedWeapon")) or Weapons.get(Weapons.default)))
end

-- The gathering tool in hand (nil while none is out).
function WeaponController.tool(): Tools.ToolDef?
	local character = player.Character
	return if character then Tools.get(character:GetAttribute("Tool")) else nil
end

-- Take out the best tool of a kind (a hotbar tool slot), or put it away if it is out.
function WeaponController.holdTool(kind: string)
	if holdToolRemote then
		holdToolRemote:FireServer(kind)
	end
end

function WeaponController.isHolstered(): boolean
	return player:GetAttribute("Holstered") == true
end

-- Put the selected weapon away, or take it out.
function WeaponController.toggleHolster()
	if holsterRemote then
		holsterRemote:FireServer(not WeaponController.isHolstered())
	end
end

-- Pose a character copy that isn't a player's (the Inventory preview): it holds
-- whatever its "Weapon" attribute names, like a real character.
function WeaponController.track(model: Model)
	adopt(model, false)
end

function WeaponController.untrack(model: Model)
	local rig = rigs[model]
	if rig then
		rigs[model] = nil
		if rig.hold then
			rig.hold:Stop(0)
		end
		if rig.trail then
			rig.trail:Destroy()
		end
	end
end

-- Fires when the local player's weapon changes, is put away or taken out (or
-- they respawn).
function WeaponController.onChanged(callback: () -> ()): RBXScriptConnection
	return changedEvent.Event:Connect(callback)
end

-- Fires on each of the local player's swings at its "Hit" moment, with (root, def,
-- struckEnemy), whether or not an enemy was in reach (for things that react to being struck).
function WeaponController.onSwingLanded(callback: (BasePart, Weapons.WeaponDef, boolean) -> ()): RBXScriptConnection
	return landedEvent.Event:Connect(callback)
end

function WeaponController.equip(id: string)
	if equipRemote and Weapons.get(id) then
		equipRemote:FireServer(id)
	end
end

-- Let something take the local player's clicks before they become swings: `filter(def)`
-- returns true to swallow the click (FishingController while a line is out).
function WeaponController.setClickFilter(filter: ((any) -> boolean)?)
	clickFilter = filter
end

-- Play another swing (Animation.Clips.Weapons SWINGS[name]) with what is in hand, on the
-- local player only (the rod's Reel). Returns the arms track, or nil.
function WeaponController.playExtra(name: string, seconds: number, hitAt: number?): any?
	local character = player.Character
	local def = character and heldDef(character)
	local rig = character and rigs[character]
	if not (def and rig and alive(character :: Model)) then
		return nil
	end
	if rig.swing then
		rig.swing:Stop(0.05)
	end
	if rig.swingBody then
		rig.swingBody:Stop(0.05)
	end
	local arms, body = WeaponClips.extra(def, name, hitAt)
	rig.swing = rig.animator:Play(arms, { speed = 1 / seconds })
	rig.swingBody = rig.animator:Play(body, { speed = 1 / seconds })
	return rig.swing
end

-- The model in the local player's hand (a weapon or tool), or nil.
function WeaponController.heldModel(): Model?
	local character = player.Character
	local held = character and character:FindFirstChild("EquippedWeapon")
	return if held and held:IsA("Model") then held else nil
end

function WeaponController.swing()
	local character = player.Character
	local def: any = WeaponController.current() or WeaponController.tool()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and def and alive(character) and root and root:IsA("BasePart")) then
		return
	end
	-- no swinging while talking to an NPC (QuestController sets this)
	if player:GetAttribute("InputLocked") then
		return
	end
	-- a click something else takes instead of a swing (FishingController: hooking a
	-- fish, the rings, reeling in)
	if clickFilter and clickFilter(def) then
		return
	end
	local now = os.clock()
	if now - lastSwing < def.cooldown then
		return
	end
	lastSwing = now

	-- the turn toward the nearest enemy is for weapons only
	if not def.kind then
		aimAssist(root, def)
	end
	if swingRemote then
		swingRemote:FireServer(def.id)
	end
	local rig = rigs[character]
	if rig then
		startSwing(rig, def):GetMarkerReachedSignal("Hit"):Once(function()
			landSwing(character, root, def)
		end)
	else
		-- No rig yet (the first frames after spawning): hit on time anyway.
		task.delay(def.cooldown * def.hitTime, landSwing, character, root, def)
	end
end

-- ==================== lifecycle ====================

function WeaponController.init(injected: any)
	deps = injected
	WorldEnemyController = deps.Controllers.WorldEnemyController
	swingRemote = deps.Remotes.getEvent("WeaponSwing")
	hitRemote = deps.Remotes.getEvent("WeaponHit")
	equipRemote = deps.Remotes.getEvent("EquipWeapon")
	holsterRemote = deps.Remotes.getEvent("HolsterWeapon")
	holdToolRemote = deps.Remotes.getEvent("HoldTool")
end

function WeaponController.start()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
	for _, name in { "SelectedWeapon", "Holstered", "HeldTool", "OwnedTools" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			changedEvent:Fire()
		end)
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			WeaponController.swing()
		end
	end)
end

return WeaponController
