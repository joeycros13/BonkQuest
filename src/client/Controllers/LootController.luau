--!strict
-- LootController: what spills out of an enemy the local player defeats.
--
-- Each kind of loot (KINDS) has a server remote, a 3D model in
-- ReplicatedStorage/Assets/Effects and a HUD "sink" it flies to:
--   Coins  CoinService  -> CoinsDropped -> Coin    -> CoinsUI (coin counter)
--   Exp    ExpService   -> ExpDropped   -> ExpStar -> PlayerCardUI.Exp (EXP bar)
-- Each remote sends { body, position, amount, pieces }. `pieces` copies (local
-- only) jump out of the enemy on arcs, land around it with a little hop, spin
-- on the spot for SIT_SECONDS, then each turns into a 2D icon that flies to
-- its sink (sink.collect). The sink counts up when the first one lands. The
-- pieces are only the look; the amount is already added on the server.
--
-- Quest rewards use the same remotes with no body, a `position` in front of
-- the giver and `afterTalk = true`: the sink is told at once (so its counter
-- holds), but the pieces only fly out once the local player's conversation has
-- closed (InputLocked clears), so they land in view instead of behind the card.
--
-- A sink provides beginSpill(), endSpill(), collect(from, landed) and
-- flyStagger(). All movement goes through Animation.Motion / Animation.Tween
-- (Scheduler systems), never a RunService handler of its own.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Animation = require(Shared:WaitForChild("Animation"))
local Motion = Animation.Motion
local Tween = Animation.Tween

local LootController = {}

local FLING_TIME = 0.5 -- seconds in the air
local SIT_SECONDS = 1 -- how long they sit spinning on the ground
local SPIN_SPEED = 300 -- degrees per second while sitting
local LAND_RADIUS = { 2.2, 4.2 } -- studs from the enemy
local APEX = { 3, 5 } -- studs above the start

type Kind = { remote: string, model: string, restHeight: number, sink: () -> any }

local deps: any = nil
local KINDS: { Kind } = {}
local random = Random.new()
local folder: Folder? = nil

local function container(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "LootFX"
	f.Parent = Workspace
	folder = f
	return f
end

local function template(name: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local effects = assets and assets:FindFirstChild("Effects")
	local model = effects and effects:FindFirstChild(name)
	return if model and model:IsA("Model") then model else nil
end

-- Where a piece thrown toward `point` comes to rest: on whatever solid thing
-- is below it, ignoring characters, enemies and other loot.
local function groundAt(point: Vector3, fallbackY: number, restHeight: number): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local ignore: { Instance } = { container() }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	local worlds = Workspace:FindFirstChild("Worlds")
	if worlds then
		for _, world in worlds:GetChildren() do
			for _, name in { "Enemies", "Bosses" } do
				local f = world:FindFirstChild(name)
				if f then
					table.insert(ignore, f)
				end
			end
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(point + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), params)
	local y = if hit then hit.Position.Y else fallbackY
	return Vector3.new(point.X, y + restHeight, point.Z)
end

local function spill(kind: Kind, info: any, begun: boolean?)
	local sink = kind.sink()
	local pieceTemplate = template(kind.model)
	local pieces = math.max(1, math.floor(tonumber(info.pieces) or 3))
	local start: Vector3 = info.position
	local body = info.body
	-- the body as this client drew it (the wander is client-side)
	if typeof(body) == "Instance" and body.Parent then
		if body:IsA("Model") then
			start = body:GetBoundingBox().Position
		elseif body:IsA("BasePart") then
			start = body.Position
		end
	end
	if not begun then
		sink.beginSpill()
	end
	if not pieceTemplate or typeof(start) ~= "Vector3" then
		sink.endSpill()
		return
	end

	local counted = false
	local function landedOnHud()
		if not counted then
			counted = true
			sink.endSpill()
		end
	end
	local floorY = start.Y - 2
	local turn = random:NextNumber(0, math.pi * 2)
	for i = 1, pieces do
		-- spread them round the enemy, a little uneven
		local angle = turn + (i - 1) / pieces * math.pi * 2 + random:NextNumber(-0.4, 0.4)
		local reach = random:NextNumber(LAND_RADIUS[1], LAND_RADIUS[2])
		local land = groundAt(start + Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach), floorY, kind.restHeight)
		local from = start + Vector3.new(0, 1, 0)
		local apex = (from + land) / 2 + Vector3.new(0, random:NextNumber(APEX[1], APEX[2]), 0)
		local piece = pieceTemplate:Clone()
		piece:PivotTo(CFrame.new(from) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0))
		piece.Parent = container()

		local fling = Motion.path(piece, { apex, land }, FLING_TIME * random:NextNumber(0.9, 1.1), "Linear", { face = false })
		fling.Completed:Connect(function()
			-- a small hop where it lands, then spin on the spot
			local rest = piece:GetPivot()
			local hop = Tween.chain({
				Tween.new(piece, { Pivot = rest + Vector3.new(0, 0.45, 0) }, { time = 0.1, ease = "QuadOut" }),
				Tween.new(piece, { Pivot = rest }, { time = 0.1, ease = "QuadIn" }),
			})
			hop.Completed:Connect(function()
				local spin = Motion.spin(piece, Vector3.yAxis, SPIN_SPEED)
				task.delay(SIT_SECONDS + (i - 1) * sink.flyStagger(), function()
					spin:Stop()
					local camera = Workspace.CurrentCamera
					local screen = camera:WorldToViewportPoint(piece:GetPivot().Position)
					piece:Destroy()
					sink.collect(Vector2.new(screen.X, screen.Y), landedOnHud)
				end)
			end)
		end)
	end
	-- never leave the HUD waiting if something above goes wrong
	task.delay(FLING_TIME + SIT_SECONDS + 3, landedOnHud)
end

function LootController.init(injected: any)
	deps = injected
	KINDS = {
		-- a coin stands on its edge (radius 0.85)
		{ remote = "CoinsDropped", model = "Coin", restHeight = 0.85, sink = function()
			return deps.UI.CoinsUI
		end },
		-- a star stands on its lower points (outer radius 0.95)
		{ remote = "ExpDropped", model = "ExpStar", restHeight = 0.8, sink = function()
			return deps.UI.PlayerCardUI.Exp
		end },
	}
end

function LootController.start()
	for _, kind in KINDS do
		deps.Remotes.getEvent(kind.remote).OnClientEvent:Connect(function(info: any)
			if type(info) ~= "table" then
				return
			end
			local player = Players.LocalPlayer
			if info.afterTalk and player:GetAttribute("InputLocked") == true then
				kind.sink().beginSpill()
				task.spawn(function()
					while player:GetAttribute("InputLocked") == true do
						player:GetAttributeChangedSignal("InputLocked"):Wait()
					end
					-- let the camera settle back behind the player first
					task.wait(0.35)
					spill(kind, info, true)
				end)
			else
				spill(kind, info)
			end
		end)
	end
end

return LootController
