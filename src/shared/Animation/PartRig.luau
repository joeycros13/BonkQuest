--!strict
-- PartRig: animates a model built from anchored parts (the enemies) by moving
-- the parts themselves -- no joints needed.
--
-- Rig contract (unchanged from the old EnemyAnimator):
--   * Root: the PrimaryPart, invisible; its bottom face is the feet line.
--   * Limb parts Torso, Head, LeftArm, RightArm, LeftLeg, RightLeg (optional
--     LeftBackLeg / RightBackLeg), each with an Attachment named "Joint" at the
--     point it rotates about.
--   * Optional lower limbs LeftLowerLeg / RightLowerLeg (knee Joint) and
--     LeftLowerArm / RightLowerArm (elbow Joint) are chained under their upper
--     limb: they follow it, then bend about their own joint (the Elder Treant's
--     knees and elbows). Rigs without them behave exactly as before.
--   * Optional LeftWing / RightWing (Joint at the wing root on the back): their
--     own channels, fluttered by the walk clip (the Fairy). Model attribute
--     WingStyle = "Flap" beats them up and down instead (the Cave Bat).
--   * Every other part has a string attribute "Follows" naming its limb. A part
--     with neither stays rigid to Root (moves with the model, never animates).
--   * Model attribute ArmStyle = "Hanging" marks avatar-style arms (rig.meta).
-- Channels: each limb name, plus "Body" -- the whole body around the feet line
-- (lift, lean, lunge, sway). A limb pose may include a translation (a jab).
--
-- Only the Root is moved by whoever walks the model; every other part is placed
-- relative to it here, all in one batched move per frame (PartBatch). Off-screen
-- rigs skip the move entirely.

local Animation = script.Parent
local PartBatch = require(Animation.PartBatch)

local PartRig = {}
PartRig.__index = PartRig

local LIMBS = { "Torso", "Head", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }
local OPTIONAL_LIMBS = { "LeftBackLeg", "RightBackLeg", "LeftLowerLeg", "RightLowerLeg", "LeftLowerArm", "RightLowerArm", "LeftWing", "RightWing" }
-- Lower limb -> the limb it hangs from.
local CHAIN = { LeftLowerLeg = "LeftLeg", RightLowerLeg = "RightLeg", LeftLowerArm = "LeftArm", RightLowerArm = "RightArm" }

type Bone = { part: BasePart, bone: string, rest: CFrame, joint: Vector3, static: boolean }

-- Build from a model in its rest pose, or nil if it isn't limbed.
function PartRig.new(model: Model)
	local root = model:FindFirstChild("Root")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	local joints: { [string]: Vector3 } = {}
	local function joint(name: string): boolean
		local part = model:FindFirstChild(name)
		local attachment = part and part:FindFirstChild("Joint")
		if part and part:IsA("BasePart") and attachment and attachment:IsA("Attachment") then
			joints[name] = root.CFrame:PointToObjectSpace(attachment.WorldPosition)
			return true
		end
		return false
	end
	for _, name in LIMBS do
		if not joint(name) then
			return nil
		end
	end
	for _, name in OPTIONAL_LIMBS do
		joint(name)
	end
	local bones: { Bone } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child ~= root then
			local follows = child:GetAttribute("Follows")
			local boneName = if type(follows) == "string" then follows else child.Name
			local pivot = joints[boneName]
			table.insert(bones, {
				part = child,
				bone = boneName,
				rest = root.CFrame:ToObjectSpace(child.CFrame),
				joint = pivot or Vector3.zero,
				static = pivot == nil,
			})
		end
	end
	local locals: { CFrame } = {}
	for i, b in bones do
		locals[i] = b.rest
	end
	return setmetatable({
		model = model,
		kind = "part",
		phase = "Render",
		root = root,
		bones = bones,
		channels = joints,
		feetY = -root.Size.Y / 2,
		meta = {
			hangingArms = model:GetAttribute("ArmStyle") == "Hanging",
			backLegs = joints.LeftBackLeg ~= nil,
			-- floating bodies (the Corn Wraith): model attribute Hover = bob height in studs
			hover = (function() local h = model:GetAttribute("Hover") return if type(h) == "number" and h > 0 then h else nil end)(),
			wingFlap = model:GetAttribute("WingStyle") == "Flap",
		},
		visible = true,
		_locals = locals, -- each bone's last pose relative to Root
		_xf = {} :: { [string]: CFrame }, -- each channel's transform about its joint, chains applied
	}, PartRig)
end

function PartRig:Has(name: string): boolean
	return name == "Body" or self.channels[name] ~= nil
end

function PartRig:GetPosition(): Vector3?
	return if self.root.Parent then self.root.Position else nil
end

function PartRig:IsAlive(): boolean
	return self.model.Parent ~= nil
end

function PartRig:FromJointSpace(_name: string, cframe: CFrame): CFrame
	return cframe
end

local identity = CFrame.identity

local function resolve(pose: { [string]: CFrame }, cover: { [string]: number }, add: { [string]: CFrame }, name: string): CFrame
	local p = pose[name]
	local result = if p then identity:Lerp(p, cover[name] or 1) else identity
	local a = add[name]
	if a then
		result *= a
	end
	return result
end

function PartRig:Apply(pose: { [string]: CFrame }, cover: { [string]: number }, add: { [string]: CFrame })
	local feet = self.feetY
	local body = CFrame.new(0, feet, 0) * resolve(pose, cover, add, "Body") * CFrame.new(0, -feet, 0)
	local xf = self._xf
	for name, j in self.channels do
		xf[name] = CFrame.new(j) * resolve(pose, cover, add, name) * CFrame.new(-j)
	end
	-- a lower limb rides on its upper limb, then bends about its own joint
	for lower, upper in CHAIN do
		local own, parent = xf[lower], xf[upper]
		if own and parent then
			xf[lower] = parent * own
		end
	end
	local locals = self._locals
	for i, b in self.bones do
		if not b.static then
			locals[i] = body * xf[b.bone] * b.rest
		end
	end
	self:Follow()
end

-- Place every part from the cached pose (also used on frames that skip evaluation).
function PartRig:Follow()
	if not self.visible then
		return
	end
	local rootCF = self.root.CFrame
	local locals = self._locals
	for i, b in self.bones do
		PartBatch.push(b.part, rootCF * locals[i])
	end
end

-- The rest pose relative to Root, for each bone part.
function PartRig:RestPose(): { [BasePart]: CFrame }
	local rest = {}
	for _, b in self.bones do
		rest[b.part] = b.rest
	end
	return rest
end

function PartRig:Release() end

return PartRig
