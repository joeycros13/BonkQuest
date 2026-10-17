--!strict
-- PartBatch: collects anchored-part moves for the frame and applies them all in
-- one workspace:BulkMoveTo call -- far cheaper than setting CFrame part by part.
--
-- PartRig, Tween and Motion push into it during the Render phase; the flush
-- runs last in that phase (priority 100). Anything can push:
--   PartBatch.push(part, cframe)

local Workspace = game:GetService("Workspace")

local Scheduler = require(script.Parent.Scheduler)

local PartBatch = {}

local parts: { BasePart } = {}
local cframes: { CFrame } = {}
local count = 0

function PartBatch.push(part: BasePart, cframe: CFrame)
	count += 1
	parts[count] = part
	cframes[count] = cframe
end

function PartBatch.flush()
	if count == 0 then
		return
	end
	-- The arrays are reused between frames; drop last frame's leftovers.
	for i = #parts, count + 1, -1 do
		parts[i] = nil
		cframes[i] = nil
	end
	local ok = pcall(Workspace.BulkMoveTo, Workspace, parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	if not ok then
		-- A part was destroyed mid-frame; fall back to moving the rest one by one.
		for i = 1, count do
			local part = parts[i]
			if part.Parent then
				part.CFrame = cframes[i]
			end
		end
	end
	count = 0
end

Scheduler.bind("Render", "PartBatch.flush", 100, PartBatch.flush)

return PartBatch
