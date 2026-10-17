--!strict
-- PlayerAnimator: idle, walk and sprint for every player character, on the
-- Animation system.
--
-- Each character gets one shared rig + animator (Animation.Character), and this
-- plays the Locomotion clip on it at priority Movement. The clip itself -- the
-- breathing idle, the bouncy walk, the sprint and all their tuning -- lives in
-- ReplicatedStorage.Shared.Animation.Clips.Locomotion. Weapons (WeaponController)
-- play their hold and swings on the SAME animator at higher priorities, so the
-- two never fight over a joint.
--
-- Other players' characters are level-of-detail culled (far ones update less
-- often); the local player's always run at full rate.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animation = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Animation"))
local Character = Animation.Character
local Locomotion = Animation.Clips.Locomotion

local PlayerAnimator = {}

local player = Players.LocalPlayer

local function animate(model: Model, cull: boolean, forceGround: boolean)
	local entry = Character.get(model, { cull = cull })
	entry.animator:Stop(Locomotion.clip, 0)
	entry.animator:Play(Locomotion.clip, { params = { model = model, forceGround = forceGround } })
end

local function watchCharacter(owner: Player, character: Model)
	if not Character.ready(character, 10) or not character.Parent then
		return
	end
	animate(character, owner ~= player, false)
	-- The avatar is rebuilt once its outfit lands; find the new joints.
	character:GetAttributeChangedSignal("AvatarReady"):Connect(function()
		local entry = Character.peek(character)
		if entry then
			entry.rig:Refresh()
		end
	end)
end

local function watchPlayer(owner: Player)
	owner.CharacterAdded:Connect(function(character)
		watchCharacter(owner, character)
	end)
	if owner.Character then
		task.spawn(watchCharacter, owner, owner.Character)
	end
end

-- Animate a character copy that isn't a player's (the Inventory preview, inside
-- a ViewportFrame's WorldModel). It always counts as standing, so it idles.
function PlayerAnimator.track(model: Model)
	animate(model, false, true)
end

function PlayerAnimator.untrack(model: Model)
	Character.release(model)
end

function PlayerAnimator.init(_injected: any) end

function PlayerAnimator.start()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, owner in Players:GetPlayers() do
		watchPlayer(owner)
	end
end

return PlayerAnimator
