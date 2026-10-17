--!strict
-- Weld: attach things to things.
--
--   Weld.attach(part0, part1, c0?, c1?)      -- rigid Weld; keeps the current offset if c0 is nil
--   Weld.rigidify(model)                       -- WeldConstraint every part to the PrimaryPart
--   Weld.prepare(model, { massless, collide, query, touch, anchored })
--   Weld.socket(character, "RightHand")        -- part + offset of a carry point
--   Weld.toSocket(model, character, "RightHand", offset?, name?) -- carry a model
--   Weld.detach(weldOrModel)                   -- remove welds made here
--   Weld.temporary(part0, part1, seconds, c0?, c1?)
--
-- Sockets give a POSITION on the body; the carried model takes the body part's
-- orientation, so a weapon built along -Z points where the fist points.
--   RightHand LeftHand   palms (R15 grip attachments; R6 arm bottoms)
--   Back                 between the shoulder blades
--   Hip                  right hip, for a sheathed weapon
--   Head                 top of the head

local Weld = {}

local TAG = "AnimationWeld"

function Weld.attach(part0: BasePart, part1: BasePart, c0: CFrame?, c1: CFrame?, name: string?): Weld
	local weld = Instance.new("Weld")
	weld.Name = name or "AnimationWeld"
	weld.Part0 = part0
	weld.Part1 = part1
	weld.C0 = c0 or part0.CFrame:ToObjectSpace(part1.CFrame)
	weld.C1 = c1 or CFrame.identity
	weld:SetAttribute(TAG, true)
	-- Animators pose a weld by rewriting C0; this is where it returns to.
	weld:SetAttribute("RestC0", weld.C0)
	weld.Parent = part1
	return weld
end

-- Hold every part of a model rigidly to its PrimaryPart (keeps current offsets).
function Weld.rigidify(model: Model, root: BasePart?): number
	local anchor = root or model.PrimaryPart
	assert(anchor, "Weld.rigidify needs a PrimaryPart or a root")
	local n = 0
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= anchor then
			local constraint = Instance.new("WeldConstraint")
			constraint.Part0 = anchor
			constraint.Part1 = part
			constraint:SetAttribute(TAG, true)
			constraint.Parent = part
			n += 1
		end
	end
	return n
end

-- Physical settings for something carried by a character.
function Weld.prepare(model: Instance, opts: any?)
	local options = opts or {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = options.anchored == true
			part.Massless = options.massless ~= false
			part.CanCollide = options.collide == true
			part.CanQuery = options.query == true
			part.CanTouch = options.touch == true
		end
	end
end

-- socket name -> { { part, attachment?, fallback offset }, ... } tried in order
local SOCKETS: { [string]: { any } } = {
	RightHand = { { "RightHand", "RightGripAttachment" }, { "Right Arm", "RightGripAttachment", CFrame.new(0, -1, 0) } },
	LeftHand = { { "LeftHand", "LeftGripAttachment" }, { "Left Arm", "LeftGripAttachment", CFrame.new(0, -1, 0) } },
	Back = { { "UpperTorso", "BodyBackAttachment" }, { "Torso", "BodyBackAttachment", CFrame.new(0, 0, 0.5) } },
	Hip = { { "LowerTorso", "RightHipRigAttachment" }, { "Torso", "RightHipAttachment", CFrame.new(0.8, -0.8, 0) } },
	Head = { { "Head", "HatAttachment", CFrame.new(0, 0.6, 0) } },
}

function Weld.socket(character: Model, name: string): (BasePart?, CFrame)
	for _, option in SOCKETS[name] or {} do
		local part = character:FindFirstChild(option[1])
		if part and part:IsA("BasePart") then
			local attachment = option[2] and part:FindFirstChild(option[2])
			if attachment and attachment:IsA("Attachment") then
				return part, CFrame.new(attachment.Position)
			end
			return part, option[3] or CFrame.identity
		end
	end
	return nil, CFrame.identity
end

-- Weld a model's PrimaryPart to a character socket. The model is made
-- massless and non-colliding first. Returns the Weld (nil if no socket).
function Weld.toSocket(model: Model, character: Model, socket: string, offset: CFrame?, name: string?): Weld?
	local part, at = Weld.socket(character, socket)
	local primary = model.PrimaryPart
	if not (part and primary) then
		return nil
	end
	Weld.prepare(model)
	local c0 = at * (offset or CFrame.identity)
	model:PivotTo(part.CFrame * c0)
	return Weld.attach(part, primary, c0, CFrame.identity, name)
end

-- Remove a weld, or every weld this module made inside a model.
function Weld.detach(target: Instance)
	if target:IsA("JointInstance") or target:IsA("WeldConstraint") then
		target:Destroy()
		return
	end
	for _, d in target:GetDescendants() do
		if (d:IsA("JointInstance") or d:IsA("WeldConstraint")) and d:GetAttribute(TAG) then
			d:Destroy()
		end
	end
end

function Weld.temporary(part0: BasePart, part1: BasePart, seconds: number, c0: CFrame?, c1: CFrame?): Weld
	local weld = Weld.attach(part0, part1, c0, c1)
	task.delay(seconds, function()
		if weld.Parent then
			weld:Destroy()
		end
	end)
	return weld
end

return Weld
