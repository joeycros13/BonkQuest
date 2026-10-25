--!strict
-- GatherController: the player's side of gathering -- trees and rocks broken for
-- materials with a tool (2026-10-18; GatherService, Config/Gathering, Config/Tools).
--
--   * Striking: every tool swing's "Hit" moment (WeaponController.onSwingLanded) checks
--     the nodes (models tagged "GatherNode") inside the tool's reach and arc, the same
--     test enemies get, nearest first, up to the tool's maxTargets. A node the tool can
--     break (its kind, at least its tier) wobbles away from the player with a puff of
--     dust and a thud straight away, and the server hears Remotes.GatherHit; the server
--     decides the damage. One it can't, and a weapon swing that reaches a node without
--     striking an enemy, gets the wrong-tool hint and a dull clunk (issue 23, 2026-10-25):
--     a BONK-style pop where it was struck naming the tool and what to do, with the hotbar
--     slot shaking (Util.ToolHint, shared with fishing).
--   * Health bar: a clone of the enemies' hand-built ReplicatedStorage/Assets/UI/
--     EnemyHealthBar over the node (its EnemyName shows the node's name), filled from
--     Remotes.GatherState. It shows while the node is damaged and hides once nobody has
--     hit it for the template's NodeBarSeconds (default 4).
--   * Breaking: a broken node vanishes for this player only (LocalTransparencyModifier,
--     and it stops colliding locally) with the defeat Poof and the EnemyPop sound; the
--     materials come as the usual side toast. Its `Remains` child (a stump, rubble), if
--     it has one, shows while it is broken. When the server says it is back, it fades in.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Gathering = require(Shared:WaitForChild("Config"):WaitForChild("Gathering"))
local Tools = require(Shared:WaitForChild("Config"):WaitForChild("Tools"))
local Animation = require(Shared:WaitForChild("Animation"))
local Effects = Animation.Effects
local Tween = Animation.Tween

local Util = script.Parent.Parent:WaitForChild("Util")
local Format = require(Util:WaitForChild("Format"))
local ToolHint = require(Util:WaitForChild("ToolHint"))

local GatherController = {}

local MAX_HEIGHT_GAP = 10
-- How far a struck node leans away from the player, in degrees (trees lean from their
-- foot, so a tall one sways more at the top).
local WOBBLE_DEGREES = 3.5
local WOBBLE_OUT = 0.05
local WOBBLE_BACK = 0.3
local FADE_IN = 0.45
-- the "Needs a ..." popup: no more than one per node this often
local NEEDS_EVERY = 1.5

local player = Players.LocalPlayer
local assets = ReplicatedStorage:WaitForChild("Assets")

type Node = {
	model: Model,
	def: Gathering.NodeDef,
	base: CFrame, -- the authored pivot the wobble returns to
	parts: { BasePart }, -- the standing node's parts
	remains: { BasePart }, -- shown only while broken
	collide: { [BasePart]: boolean },
	broken: boolean,
	wobble: any?,
	billboard: BillboardGui?,
	fill: GuiObject?,
	trail: GuiObject?,
	amount: TextLabel?,
	ratio: number,
	hideToken: number,
	needsAt: number,
}

local hitRemote: RemoteEvent? = nil
local WeaponController: any = nil
local barTemplate: BillboardGui? = nil
-- NodeId -> node
local nodes: { [string]: Node } = {}

local function numberAttr(inst: Instance, name: string, fallback: number): number
	local value = inst:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function playSound(name: string, at: Instance, pitch: number?)
	local template = assets:FindFirstChild("Sounds") and assets.Sounds:FindFirstChild(name)
	if template and template:IsA("Sound") then
		Effects.sound(template, at, { pitch = pitch })
	end
end

-- ==================== nodes ====================

local function anchorOf(node: Node): BasePart?
	local biggest: BasePart? = nil
	local volume = -1
	for _, part in node.parts do
		local v = part.Size.X * part.Size.Y * part.Size.Z
		if v > volume then
			biggest, volume = part, v
		end
	end
	return biggest
end

local function setShown(parts: { BasePart }, collide: { [BasePart]: boolean }, shown: boolean)
	for _, part in parts do
		part.LocalTransparencyModifier = if shown then 0 else 1
		part.CanCollide = shown and collide[part] == true
		part.CanQuery = shown
	end
end

local function add(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local id = model:GetAttribute("NodeId")
	local def = Gathering.get(model:GetAttribute("Node"))
	if type(id) ~= "string" then
		-- the server names it on start; wait for that
		model:GetAttributeChangedSignal("NodeId"):Once(function()
			add(model)
		end)
		return
	end
	if not def or nodes[id] then
		return
	end
	local remainsRoot = model:FindFirstChild("Remains")
	local node: Node = {
		model = model,
		def = def,
		base = model:GetPivot(),
		parts = {},
		remains = {},
		collide = {},
		broken = false,
		wobble = nil,
		billboard = nil,
		fill = nil,
		trail = nil,
		amount = nil,
		ratio = 1,
		hideToken = 0,
		needsAt = -math.huge,
	}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			node.collide[part] = part.CanCollide
			if remainsRoot and part:IsDescendantOf(remainsRoot) then
				table.insert(node.remains, part)
			else
				table.insert(node.parts, part)
			end
		end
	end
	setShown(node.remains, node.collide, false)
	nodes[id] = node
end

local function remove(model: Instance)
	local id = model:GetAttribute("NodeId")
	if type(id) == "string" and nodes[id] and nodes[id].model == model then
		local node = nodes[id]
		if node.billboard then
			node.billboard:Destroy()
		end
		nodes[id] = nil
	end
end

-- ==================== health bar ====================

local function barOf(node: Node): BillboardGui?
	if node.billboard then
		return node.billboard
	end
	local anchor = anchorOf(node)
	if not (barTemplate and anchor) then
		return nil
	end
	local billboard = barTemplate:Clone()
	local cf, size = node.model:GetBoundingBox()
	local top = cf.Position + Vector3.new(0, size.Y / 2 + numberAttr(billboard, "Clearance", 1), 0)
	billboard.Adornee = anchor
	billboard.StudsOffsetWorldSpace = top - anchor.Position
	-- the bar's share of the billboard's width, from the node's height like an enemy's
	local room = billboard.Size.X.Scale
	local width = math.clamp(
		size.Y * numberAttr(billboard, "WidthScale", 0.8),
		numberAttr(billboard, "MinWidth", 3.6),
		numberAttr(billboard, "MaxWidth", 5.6)
	)
	local bar = billboard:FindFirstChild("Bar", true)
	if bar and bar:IsA("GuiObject") then
		bar.Size = UDim2.fromScale(width / room, bar.Size.Y.Scale)
	end
	local name = billboard:FindFirstChild("EnemyName", true)
	if name and name:IsA("TextLabel") then
		name.Text = node.def.name
	end
	local fill = billboard:FindFirstChild("Fill", true)
	local trail = billboard:FindFirstChild("Trail", true)
	local amount = billboard:FindFirstChild("Amount", true)
	node.fill = if fill and fill:IsA("GuiObject") then fill else nil
	node.trail = if trail and trail:IsA("GuiObject") then trail else nil
	node.amount = if amount and amount:IsA("TextLabel") then amount else nil
	billboard.Enabled = false
	billboard.Parent = anchor
	node.billboard = billboard
	return billboard
end

local function showBar(node: Node, hp: number, max: number)
	local billboard = barOf(node)
	if not billboard then
		return
	end
	local ratio = math.clamp(hp / math.max(max, 1), 0, 1)
	if node.fill then
		node.fill.Size = UDim2.fromScale(ratio, 1)
	end
	if node.trail then
		if ratio < node.ratio then
			-- the pale trail stays where the hp was a moment, then slides down
			local trail = node.trail
			task.delay(numberAttr(billboard, "TrailDelay", 0.35), function()
				TweenService:Create(trail, TweenInfo.new(numberAttr(billboard, "TrailSeconds", 0.4), Enum.EasingStyle.Quad), {
					Size = UDim2.fromScale(node.ratio, 1),
				}):Play()
			end)
		else
			node.trail.Size = UDim2.fromScale(ratio, 1)
		end
	end
	node.ratio = ratio
	if node.amount then
		node.amount.Text = Format.ratio(math.ceil(hp), max)
	end
	billboard.Enabled = ratio < 1 and not node.broken

	node.hideToken += 1
	local token = node.hideToken
	task.delay(numberAttr(billboard, "NodeBarSeconds", 4), function()
		if node.hideToken == token and node.billboard then
			node.billboard.Enabled = false
		end
	end)
end

-- ==================== striking ====================

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

type Struck = { id: string, node: Node, distance: number }

-- The standing nodes this swing reached, nearest first: reach to the node's edge and
-- the arc widened by its size, like WeaponController's enemy test.
local function struck(root: BasePart, def: any): { Struck }
	local look = flat(root.CFrame.LookVector)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local arc = def.arc or 90
	local halfArc = math.rad(arc / 2)
	local out: { Struck } = {}
	for id, node in nodes do
		if node.broken or not node.model.Parent then
			continue
		end
		local cf, size = node.model:GetBoundingBox()
		local offset = cf.Position - root.Position
		if math.abs(offset.Y) > MAX_HEIGHT_GAP + size.Y / 2 then
			continue
		end
		local radius = math.max(size.X, size.Z) / 2
		local toward = flat(offset)
		local distance = toward.Magnitude
		if distance - radius > (def.reach or 0) then
			continue
		end
		if arc < 360 and distance > radius then
			local angle = math.acos(math.clamp(toward.Unit:Dot(look), -1, 1))
			if angle > halfArc + math.atan2(radius, distance) then
				continue
			end
		end
		table.insert(out, { id = id, node = node, distance = distance })
	end
	table.sort(out, function(a, b)
		return a.distance < b.distance
	end)
	return out
end

-- Lean the node away from the player and spring it back.
local function wobble(node: Node, from: Vector3)
	local away = flat(node.base.Position - from)
	if away.Magnitude < 1e-3 then
		return
	end
	if node.wobble then
		node.wobble:Cancel()
	end
	local axis = Vector3.yAxis:Cross(away.Unit)
	local lean = CFrame.new(node.base.Position)
		* CFrame.fromAxisAngle(axis, math.rad(WOBBLE_DEGREES))
		* (node.base - node.base.Position)
	node.wobble = Tween.chain({
		Tween.new(node.model, { Pivot = lean }, { time = WOBBLE_OUT, ease = "QuadOut" }),
		Tween.new(node.model, { Pivot = node.base }, { time = WOBBLE_BACK, ease = "BackOut" }),
	})
end

-- Where a swing meets the node: the side facing the player, at chest height.
local function strikePoint(node: Node, from: Vector3): Vector3
	local cf, size = node.model:GetBoundingBox()
	local toward = flat(from - cf.Position)
	local side = if toward.Magnitude > 1e-3 then toward.Unit else Vector3.zero
	local radius = math.max(size.X, size.Z) / 2
	return Vector3.new(cf.X, math.min(from.Y, cf.Y + size.Y / 2), cf.Z) + side * radius * 0.8
end

-- The wrong-tool hint (a node the thing in hand can't break), where it was struck (Util.ToolHint).
local function showNeeds(node: Node, from: Vector3)
	local now = os.clock()
	if now - node.needsAt < NEEDS_EVERY then
		return
	end
	node.needsAt = now
	ToolHint.show(strikePoint(node, from), node.def.tool, node.def.tier)
	playSound("SecretThud", node.model, 0.6)
end

local function onSwingLanded(root: BasePart, def: any, struckEnemy: boolean?)
	if player:GetAttribute("InputLocked") then
		return
	end
	-- a weapon never breaks a node, but one it reaches (with no enemy struck) gets the hint
	if not def.kind then
		if not struckEnemy then
			local reached = struck(root, def)
			if reached[1] then
				showNeeds(reached[1].node, root.Position)
			end
		end
		return
	end
	local tool = def :: Tools.ToolDef
	local all = struck(root, tool)
	local hits = {}
	for _, hit in all do
		if hit.node.def.tool == tool.kind and tool.tier >= hit.node.def.tier then
			table.insert(hits, hit)
		end
	end
	if #hits == 0 then
		if all[1] then
			showNeeds(all[1].node, root.Position)
		end
		return
	end
	local ids = {}
	for i = 1, math.min(#hits, tool.maxTargets) do
		local hit = hits[i]
		table.insert(ids, hit.id)
		wobble(hit.node, root.Position)
		-- the dust comes off the side facing the player, at chest height
		Effects.burst(strikePoint(hit.node, root.Position), "Dust", { count = 6 })
		playSound("SecretThud", hit.node.model, 0.9 + math.random() * 0.2)
	end
	if hitRemote then
		hitRemote:FireServer(ids)
	end
end

-- ==================== server state ====================

local function breakNode(node: Node)
	node.broken = true
	if node.wobble then
		node.wobble:Cancel()
		node.wobble = nil
	end
	node.model:PivotTo(node.base)
	if node.billboard then
		node.billboard.Enabled = false
	end
	Effects.burst(node.model:GetBoundingBox().Position, "Poof", { count = 18 })
	playSound("EnemyPop", node.model)
	setShown(node.parts, node.collide, false)
	setShown(node.remains, node.collide, true)
	node.ratio = 1
end

local function restore(node: Node)
	node.broken = false
	setShown(node.remains, node.collide, false)
	setShown(node.parts, node.collide, true)
	-- fade back in from nothing
	for _, part in node.parts do
		part.LocalTransparencyModifier = 1
		Tween.to(part, { LocalTransparencyModifier = 0 }, FADE_IN, "QuadOut")
	end
	Effects.burst(node.model:GetBoundingBox().Position, "Dust", { count = 8 })
	if node.fill then
		node.fill.Size = UDim2.fromScale(1, 1)
	end
	if node.trail then
		node.trail.Size = UDim2.fromScale(1, 1)
	end
end

local function onState(info: any)
	if type(info) ~= "table" or type(info.id) ~= "string" then
		return
	end
	local node = nodes[info.id]
	if not node then
		return
	end
	if info.broken then
		if not node.broken then
			breakNode(node)
		end
	elseif node.broken then
		restore(node)
	elseif type(info.hp) == "number" and type(info.max) == "number" then
		showBar(node, info.hp, info.max)
	end
end

-- ==================== lifecycle ====================

-- The nearest node standing for this player that drops `material` (the guide arrow on a
-- "gather" or "bring" quest step, 2026-10-19), or nil.
function GatherController.nearest(material: string, from: Vector3): Vector3?
	local best: Vector3? = nil
	local bestDistance = math.huge
	for _, node in nodes do
		if node.broken or not node.model.Parent then
			continue
		end
		local drops = false
		for _, drop in node.def.drops do
			if drop.id == material then
				drops = true
				break
			end
		end
		if drops then
			local position = node.model:GetPivot().Position
			local distance = ((position - from) * Vector3.new(1, 0, 1)).Magnitude
			if distance < bestDistance then
				best, bestDistance = position, distance
			end
		end
	end
	return best
end

function GatherController.init(injected: any)
	hitRemote = injected.Remotes.getEvent("GatherHit")
	WeaponController = injected.Controllers.WeaponController
	injected.Remotes.getEvent("GatherState").OnClientEvent:Connect(onState)
end

function GatherController.start()
	task.spawn(function()
		local ui = assets:WaitForChild("UI", 10)
		local template = ui and ui:WaitForChild("EnemyHealthBar", 10)
		if template and template:IsA("BillboardGui") then
			barTemplate = template
		else
			warn("[GatherController] missing ReplicatedStorage/Assets/UI/EnemyHealthBar; gathering nodes get no health bar")
		end
	end)
	for _, model in CollectionService:GetTagged(Gathering.Tag) do
		add(model)
	end
	CollectionService:GetInstanceAddedSignal(Gathering.Tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(Gathering.Tag):Connect(remove)
	if WeaponController then
		WeaponController.onSwingLanded(onSwingLanded)
	end
end

return GatherController
