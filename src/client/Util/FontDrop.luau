--!strict
-- FontDrop: puts a display font's letters in the middle of their label.
--
-- Roblox centres a font's line box, not its letters. Luckiest Guy draws its
-- capitals about 0.14 x the text size ABOVE the middle of the box (0.12-0.16
-- measured in Studio across sizes and strings, 2026-10-10; 0.14 left every
-- shop card label within about 1 px; Fredoka is centred), so every "centred"
-- Luckiest Guy label looked high. See the roblox-ui-text-centering skill.
--
-- FontDrop.watch(root) looks after every label under `root` (now and later)
-- in a font from DROPS that has a hand-placed UIPadding child: it sets the
-- padding to +d on top and -d below, so the letters move down by d without
-- the box (and so a TextScaled size) changing. d is DROPS[font] x the label's
-- real text size (TextBounds.Y, single-line text), written as a fraction of
-- the label's height, so UIScales (the panel pop, card hover) don't upset it.
-- Labels without a UIPadding are left alone; hand-placed labels should sit
-- centred in their box with no nudge of their own.
--
-- Text caps became paddings on 2026-10-11 (so the editor matches play): a
-- padding may carry InsetTop / InsetBottom attributes, the scale that shrinks
-- the text area to the old cap. The drop is added on top of them. A padding
-- with NoDrop = true is only an inset and gets no drop.

local FontDrop = {}

-- font family -> how far its letters sit above the middle, x text size
local DROPS: { [string]: number } = {
	["rbxasset://fonts/families/LuckiestGuy.json"] = 0.14,
}

local watched: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function fit(label: TextLabel | TextButton, pad: UIPadding, drop: number)
	local height = label.AbsoluteSize.Y
	if height <= 0 then
		return
	end
	local d = drop * label.TextBounds.Y / height
	local top = (tonumber(pad:GetAttribute("InsetTop")) or 0) + d
	local bottom = (tonumber(pad:GetAttribute("InsetBottom")) or 0) - d
	if
		math.abs(pad.PaddingTop.Scale - top) > 0.001
		or math.abs(pad.PaddingBottom.Scale - bottom) > 0.001
		or pad.PaddingTop.Offset ~= 0
		or pad.PaddingBottom.Offset ~= 0
	then
		pad.PaddingTop = UDim.new(top, 0)
		pad.PaddingBottom = UDim.new(bottom, 0)
	end
end

function FontDrop.track(label: Instance)
	if watched[label] or not (label:IsA("TextLabel") or label:IsA("TextButton")) then
		return
	end
	local drop = DROPS[label.FontFace.Family]
	local pad = label:FindFirstChildOfClass("UIPadding")
	if not (drop and pad) or pad:GetAttribute("NoDrop") then
		return
	end
	watched[label] = true
	local function refit()
		fit(label, pad, drop)
	end
	label:GetPropertyChangedSignal("TextBounds"):Connect(refit)
	label:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	refit()
end

function FontDrop.watch(root: Instance)
	for _, d in root:GetDescendants() do
		FontDrop.track(d)
	end
	root.DescendantAdded:Connect(function(d)
		-- a clone's UIPadding may arrive after the label itself
		task.defer(FontDrop.track, if d:IsA("UIPadding") and d.Parent then d.Parent else d)
	end)
end

return FontDrop
