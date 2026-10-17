--!strict
-- Character: one JointRig + Animator per character model, shared by every
-- script that animates it (movement, weapons, emotes...). Because they all play
-- tracks on the SAME Animator, priorities decide who wins -- no script ever
-- fights another over a joint.
--
--   local entry = Character.get(model)            -- { model, rig, animator }
--   entry.animator:Play(clip)
--   Character.get(copy, { cull = false })           -- e.g. a UI preview copy
--   Character.release(model)                        -- stop and free (automatic when it's removed)
--   Character.ready(model, 5)                       -- wait for its limbs (true / false)

local Animation = script.Parent
local JointRig = require(Animation.JointRig)
local Animator = require(Animation.Animator)

local Character = {}

export type Entry = { model: Model, rig: any, animator: any }

local entries: { [Model]: Entry } = {}

-- Wait until the model has a root part and a torso (R6 or R15).
function Character.ready(model: Model, timeout: number?): boolean
	local deadline = os.clock() + (timeout or 5)
	while os.clock() < deadline do
		if model:FindFirstChild("HumanoidRootPart") and (model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")) then
			return true
		end
		if not model.Parent then
			return false
		end
		task.wait(0.05)
	end
	return false
end

function Character.get(model: Model, opts: any?): Entry
	local existing = entries[model]
	if existing and existing.animator.alive then
		return existing
	end
	local rig = JointRig.new(model)
	local animator = Animator.new(rig, opts)
	local entry: Entry = { model = model, rig = rig, animator = animator }
	entries[model] = entry
	model.AncestryChanged:Connect(function(_, parent)
		if parent == nil and entries[model] == entry then
			Character.release(model)
		end
	end)
	return entry
end

function Character.peek(model: Model): Entry?
	return entries[model]
end

function Character.release(model: Model)
	local entry = entries[model]
	if entry then
		entries[model] = nil
		entry.animator:Destroy()
	end
end

return Character
