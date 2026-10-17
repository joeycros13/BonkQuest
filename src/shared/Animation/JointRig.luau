--!strict
-- JointRig: drives a character's joints (Motor6D or AnimationConstraint, R6 or
-- R15) from named poses.
--
-- Channels (pose names):
--   Root Waist Neck
--   LeftShoulder LeftElbow LeftWrist RightShoulder RightElbow RightWrist
--   LeftHip LeftKnee LeftAnkle RightHip RightKnee RightAnkle
--   Grip   the held weapon's HandWeld (rotates the weapon in the hand)
-- Poses are in the PARENT part's frame (see Pose for the axes) whatever the
-- joint's own orientation; the rig converts with Transform = q^-1 * pose * q.
--
-- Missing joints fold into a neighbour so one clip fits both rigs: on R6, Waist
-- folds into Root, and Right/LeftElbow and Wrist fold into Grip.
--
-- Blending with Roblox's own Animator: a joint this rig is not posing is left
-- alone (so jump / fall / climb from the default Animate script still show);
-- a partly weighted pose blends from whatever that Animator wrote this frame.
-- When a pose stops, the joint is released back once -- unless something else
-- (Roblox's Animator) has already written it this frame, so there is no snap.

local JointRig = {}
JointRig.__index = JointRig

-- canonical name -> { { part, joint }, ... } tried in order (R6 first, then R15)
local ALIASES: { [string]: { { string } } } = {
	Root = { { "HumanoidRootPart", "RootJoint" }, { "LowerTorso", "Root" } },
	Waist = { { "UpperTorso", "Waist" } },
	Neck = { { "Torso", "Neck" }, { "Head", "Neck" } },
	RightShoulder = { { "Torso", "Right Shoulder" }, { "RightUpperArm", "RightShoulder" } },
	LeftShoulder = { { "Torso", "Left Shoulder" }, { "LeftUpperArm", "LeftShoulder" } },
	RightElbow = { { "RightLowerArm", "RightElbow" } },
	LeftElbow = { { "LeftLowerArm", "LeftElbow" } },
	RightWrist = { { "RightHand", "RightWrist" } },
	LeftWrist = { { "LeftHand", "LeftWrist" } },
	RightHip = { { "Torso", "Right Hip" }, { "RightUpperLeg", "RightHip" } },
	LeftHip = { { "Torso", "Left Hip" }, { "LeftUpperLeg", "LeftHip" } },
	RightKnee = { { "RightLowerLeg", "RightKnee" } },
	LeftKnee = { { "LeftLowerLeg", "LeftKnee" } },
	RightAnkle = { { "RightFoot", "RightAnkle" } },
	LeftAnkle = { { "LeftFoot", "LeftAnkle" } },
}

-- Applied in this order: a missing `from` joint's pose is composed onto `into`.
local FOLDS: { { string } } = {
	{ "Waist", "Root" },
	{ "RightElbow", "Grip" },
	{ "RightWrist", "Grip" },
}

type Joint = { inst: any, q: CFrame, qi: CFrame, kind: string, rest: CFrame, last: CFrame? }

local function bind(model: Model, partName: string, jointName: string): Joint?
	local part = model:FindFirstChild(partName)
	local inst = part and part:FindFirstChild(jointName)
	if not inst then
		return nil
	end
	local q: CFrame
	if inst:IsA("Motor6D") then
		q = inst.C0.Rotation
	elseif inst:IsA("AnimationConstraint") then
		local a0 = inst.Attachment0
		q = if a0 then a0.CFrame.Rotation else CFrame.identity
	else
		return nil
	end
	return { inst = inst, q = q, qi = q:Inverse(), kind = "motor", rest = CFrame.identity }
end

function JointRig.new(model: Model)
	local self = setmetatable({
		model = model,
		kind = "joint",
		phase = "Joints",
		root = model:FindFirstChild("HumanoidRootPart") :: BasePart?,
		joints = {} :: { [string]: Joint },
		written = {} :: { [string]: boolean },
		visible = true,
		_gripWeld = nil :: Weld?,
	}, JointRig)
	self:Refresh()
	return self
end

-- Re-find the joints (after the avatar is rebuilt).
function JointRig:Refresh()
	table.clear(self.joints)
	for name, options in ALIASES do
		for _, option in options do
			local joint = bind(self.model, option[1], option[2])
			if joint then
				self.joints[name] = joint
				break
			end
		end
	end
	self.root = self.model:FindFirstChild("HumanoidRootPart") :: BasePart?
	self._gripWeld = nil
end

function JointRig:Has(name: string): boolean
	return self.joints[name] ~= nil
end

function JointRig:GetPosition(): Vector3?
	local root = self.root
	return if root and root.Parent then root.Position else nil
end

function JointRig:IsAlive(): boolean
	return self.model.Parent ~= nil
end

-- Joints replaced under us (an avatar rebuild) are found again on the next Apply.
local function stale(self: any): boolean
	for _, joint in self.joints do
		if joint.kind ~= "weld" and joint.inst.Parent == nil then
			return true
		end
	end
	return false
end

-- The held weapon's weld acts as the "Grip" joint. Looked up lazily, because
-- weapons come and go.
function JointRig:_grip(): Joint?
	local weapon = self.model:FindFirstChild("EquippedWeapon")
	local primary = weapon and (weapon :: Model).PrimaryPart
	local weld = primary and primary:FindFirstChild("HandWeld")
	if not (weld and weld:IsA("Weld")) then
		self.joints.Grip = nil
		self._gripWeld = nil
		self.written.Grip = nil -- the weld went with the weapon; nothing to release
		return nil
	end
	if weld ~= self._gripWeld then
		-- The rest C0 is kept on the weld itself (Weld.toSocket sets it), so a copy
		-- cloned mid-pose (the Inventory preview) still knows its true rest. A weld
		-- without one has not been posed yet, so its C0 is the rest.
		local rest = weld:GetAttribute("RestC0")
		if typeof(rest) ~= "CFrame" then
			rest = weld.C0
			weld:SetAttribute("RestC0", rest)
		end
		self._gripWeld = weld
		self.joints.Grip = { inst = weld, q = CFrame.identity, qi = CFrame.identity, kind = "weld", rest = rest :: CFrame }
	end
	return self.joints.Grip
end

-- An Animation Editor pose (raw joint Transform) in the parent frame.
function JointRig:FromJointSpace(name: string, cframe: CFrame): CFrame
	local joint = self.joints[name]
	return if joint then joint.q * cframe * joint.qi else cframe
end

local identity = CFrame.identity

function JointRig:Apply(pose: { [string]: CFrame }, cover: { [string]: number }, add: { [string]: CFrame })
	self._checks = (self._checks or 0) + 1
	if self._checks % 30 == 0 and stale(self) then
		self:Refresh()
	end
	if pose.Grip or add.Grip or pose.RightElbow or pose.RightWrist or self.written.Grip then
		self:_grip()
	end
	local joints = self.joints
	for _, fold in FOLDS do
		local from, into = fold[1], fold[2]
		if not joints[from] and joints[into] then
			local p = pose[from]
			if p then
				pose[into] = (pose[into] or identity) * p
				cover[into] = math.max(cover[into] or 0, cover[from] or 0)
				pose[from] = nil
			end
			local a = add[from]
			if a then
				add[into] = (add[into] or identity) * a
				add[from] = nil
			end
		end
	end

	local written = self.written
	for name, joint in joints do
		local p, a = pose[name], add[name]
		if p or a then
			local c = cover[name] or 0
			if joint.kind == "weld" then
				local local_ = if p then identity:Lerp(p, c) else identity
				if a then
					local_ *= a
				end
				joint.inst.C0 = joint.rest * local_
			else
				local result = joint.inst.Transform
				if p then
					local target = joint.qi * p * joint.q
					result = if c >= 0.999 then target else result:Lerp(target, c)
				end
				if a then
					result *= joint.qi * a * joint.q
				end
				joint.inst.Transform = result
				joint.last = result
			end
			written[name] = true
		elseif written[name] then
			-- Released: hand the joint back once.
			if joint.kind == "weld" then
				joint.inst.C0 = joint.rest
			elseif joint.inst.Transform == joint.last then
				joint.inst.Transform = identity
			end
			joint.last = nil
			written[name] = nil
		end
	end
	self._last = pose
	self._lastCover = cover
	self._lastAdd = add
end

-- Re-apply the last pose (frames where the Animator skipped evaluation): Roblox's
-- Animator rewrites joints every frame, so skipping would flicker.
function JointRig:Follow()
	if self._last then
		self:Apply(self._last, self._lastCover, self._lastAdd)
	end
end

function JointRig:Release()
	for name, joint in self.joints do
		if self.written[name] and joint.inst.Parent then
			if joint.kind == "weld" then
				joint.inst.C0 = joint.rest
			elseif joint.inst.Transform == joint.last then
				joint.inst.Transform = identity
			end
		end
		joint.last = nil
	end
	table.clear(self.written)
	self._last = nil
end

return JointRig
