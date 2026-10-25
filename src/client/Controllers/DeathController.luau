--!strict
-- DeathController: a player's death, seen on every client (2026-10-25, the user's pick
-- "disintegrate" on https://claude.ai/artifact/MX1sY6kYn9VhiDJ4d7DDM1; the starfish flop is
-- kept for later).
--
-- The body no longer falls apart (DeathService keeps its joints and holds it where it
-- stood). When any character dies: it glows white (a Highlight fading in over GLOW_SECONDS),
-- then it's hidden on this client (LocalTransparencyModifier, its name tag and medal off)
-- and breaks into little white and gold blocks (BLOCK_COLORS), laid on each limb on a
-- PIECE-stud grid, that fly up and out, tumble, shrink and fade (top first), with the enemies' Poof and
-- DeathPop stars and a low EnemyPop. For the local player it also starts the BONKED! screen
-- (DeathScreenUI), which fades back in on the next body.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Animation = require(Shared:WaitForChild("Animation"))
local Effects = Animation.Effects

local DeathController = {}

local GLOW_SECONDS = 0.45 -- the white glow before the body breaks up
local PIECE = 0.5 -- a block's size, and the grid the limbs are sampled on
local FLY_SECONDS = 1.2 -- how long a block flies and fades
local STAGGER = 0.3 -- top blocks leave first, the feet this much later
local RISE = { 4, 9 } -- studs a block rises (random between)
local SPREAD = 2.5 -- studs a block drifts out from the body's middle
local LIMBS = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
-- the blocks are the white glow the body turned into, not its colours: an avatar's
-- outfit is clothing pictures over its body colours, which can't be sampled, so
-- body-coloured blocks came out skin-yellow for a player dressed in black
local BLOCK_COLORS = { Color3.new(1, 1, 1), Color3.fromHex("fff4c2"), Color3.fromHex("ffe680"), Color3.fromHex("ffd23f") }

local deps: any = nil
local player = Players.LocalPlayer
local dying: { [Model]: boolean } = {}

local function piecesFolder(): Instance
	local runtime = workspace:FindFirstChild("Runtime")
	if not runtime then
		runtime = Instance.new("Folder")
		runtime.Name = "Runtime"
		runtime.Parent = workspace
	end
	return runtime
end

-- Hide the body on this client: every part, decal and billboard (name tag, medal).
local function hide(character: Model)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = 1
		elseif d:IsA("BillboardGui") then
			d.Enabled = false
		end
	end
end

-- The blocks: each visible limb sampled on a PIECE grid across its front, flying away.
local function breakUp(character: Model)
	local torso = character:FindFirstChild("Torso")
	local centre = if torso and torso:IsA("BasePart") then torso.Position else character:GetPivot().Position
	local top, bottom = -math.huge, math.huge
	local cells = {}
	for _, name in LIMBS do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") and part.Transparency < 1 then
			local size = part.Size
			local nx = math.max(1, math.floor(size.X / PIECE + 0.5))
			local ny = math.max(1, math.floor(size.Y / PIECE + 0.5))
			for ix = 1, nx do
				for iy = 1, ny do
					local offset = Vector3.new(
						(ix - 0.5) / nx * size.X - size.X / 2,
						(iy - 0.5) / ny * size.Y - size.Y / 2,
						(math.random() - 0.5) * math.max(size.Z - PIECE, 0)
					)
					local cf = part.CFrame * CFrame.new(offset)
					top = math.max(top, cf.Position.Y)
					bottom = math.min(bottom, cf.Position.Y)
					table.insert(cells, { cf = cf, color = BLOCK_COLORS[math.random(#BLOCK_COLORS)] })
				end
			end
		end
	end
	local folder = piecesFolder()
	local height = math.max(top - bottom, 1)
	for _, cell in cells do
		local block = Instance.new("Part")
		block.Name = "DeathBlock"
		block.Anchored = true
		block.CanCollide = false
		block.CanQuery = false
		block.CanTouch = false
		block.CastShadow = false
		-- the white ones glow (Neon, under the Bloom), the gold ones don't
		block.Material = if cell.color == BLOCK_COLORS[1] then Enum.Material.Neon else Enum.Material.SmoothPlastic
		block.Color = cell.color
		block.Size = Vector3.one * PIECE
		block.CFrame = cell.cf
		block.Parent = folder
		local from = cell.cf.Position
		local out = Vector3.new(from.X - centre.X, 0, from.Z - centre.Z)
		out = if out.Magnitude > 1e-3 then out.Unit else Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
		local goal = from + out * (math.random() * SPREAD) + Vector3.new(0, RISE[1] + math.random() * (RISE[2] - RISE[1]), 0)
		local spin = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		local delay = (top - from.Y) / height * STAGGER
		TweenService:Create(block, TweenInfo.new(FLY_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay), {
			CFrame = CFrame.new(goal) * spin,
			Size = Vector3.one * PIECE * 0.25,
			Transparency = 1,
		}):Play()
		task.delay(FLY_SECONDS + delay + 0.1, function()
			block:Destroy()
		end)
	end
	Effects.burst(centre, "Poof", { count = 20 })
	Effects.burst(centre, "DeathPop", { count = 18 })
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local sounds = assets and assets:FindFirstChild("Sounds")
	local pop = sounds and sounds:FindFirstChild("EnemyPop")
	if pop and pop:IsA("Sound") then
		Effects.sound(pop, centre, { pitch = 0.8, volume = pop.Volume * 1.2 })
	end
end

local function onDied(character: Model)
	if dying[character] then
		return
	end
	dying[character] = true
	if character == player.Character then
		deps.UI.DeathScreenUI.died()
	end
	local glow = Instance.new("Highlight")
	glow.Name = "DeathGlow"
	glow.FillColor = Color3.new(1, 1, 1)
	glow.OutlineColor = Color3.new(1, 1, 1)
	glow.FillTransparency = 1
	glow.OutlineTransparency = 1
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Parent = character
	TweenService:Create(glow, TweenInfo.new(GLOW_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		FillTransparency = 0.05,
		OutlineTransparency = 0.3,
	}):Play()
	task.delay(GLOW_SECONDS, function()
		glow:Destroy()
		if character.Parent then
			breakUp(character)
			hide(character)
		end
	end)
end

local function watch(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	humanoid.Died:Connect(function()
		onDied(character)
	end)
	-- another player's Died can arrive late; their health reaching 0 is enough
	humanoid.HealthChanged:Connect(function(health)
		if health <= 0 then
			onDied(character)
		end
	end)
	character.AncestryChanged:Connect(function()
		if not character.Parent then
			dying[character] = nil
		end
	end)
end

local function onPlayer(other: Player)
	other.CharacterAdded:Connect(function(character)
		watch(character)
		if other == player then
			deps.UI.DeathScreenUI.respawned()
		end
	end)
	if other.Character then
		task.spawn(watch, other.Character)
	end
end

function DeathController.init(injected: any)
	deps = injected
end

function DeathController.start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, other in Players:GetPlayers() do
		onPlayer(other)
	end
end

return DeathController
