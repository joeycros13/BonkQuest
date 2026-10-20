--!strict
-- Responsive: keeps every pixel-only UI value in step with the screen, so the
-- game looks the same on a phone as on a monitor (user's rule, 2026-10-11:
-- nothing in the UI may be fixed in pixels -- no sizes, fonts or placements).
--
-- Sizes and positions are authored in scale, so they already follow the
-- screen. Since 2026-10-11 the rest is authored natively in scale as well, so
-- the Studio editor shows the UI exactly as a playtest does (the user's ask):
--   outlines   UIStroke.StrokeSizingMode = ScaledSize: Thickness is a fraction
--              of the parent's shorter side, or of the font size on text
--   corners, paddings, list/grid gaps   Scale, not Offset
--   text caps  a single-line label's cap became a UIPadding inset (InsetTop /
--              InsetBottom attributes) so TextScaled draws at the old cap size
-- This module covers what still only exists in pixels, multiplying each by
-- factor() = screen height / REFERENCE_HEIGHT (the 1080-high screen the UI was
-- designed at):
--   UIStroke.Thickness                  only FixedSize outlines (never under 1)
--   UITextSizeConstraint Max/MinTextSize caps kept on wrapping, multi-line text
--   ScrollingFrame.ScrollBarThickness
--   Image SliceScale (ScaleType Slice)   9-slice borders are drawn in pixels (a pill
--                                        button skin, PillSlice attribute, follows its own height)
--   the Offset part of UICorner.CornerRadius, UIPadding, UIListLayout.Padding
--     and UIGridLayout.CellPadding
--   BillboardGui.Size offsets           in-world bars and prompts drawn in pixels
-- The authored value is kept in a "Base<Property>" attribute the first time it
-- is seen, so it is never scaled twice (clones of a template carry the
-- attribute with them). Everything is re-applied when the screen changes size
-- (rotation, resizing the window).
--
-- Covers every ScreenGui and BillboardGui under PlayerGui and any BillboardGui
-- that appears in Workspace. SurfaceGuis live in the world (their pixels are
-- per stud) and are left alone.
--
-- Code that sets one of these properties itself goes through px() /
-- setStroke(), so its value is scaled the same way.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Responsive = {}

local REFERENCE_HEIGHT = 1080
local MIN_FACTOR, MAX_FACTOR = 0.25, 4

-- No list of scaled objects is kept: a weak table loses Instances while they
-- still exist (their Lua handles get collected), so a resize rescans instead.
-- Resizes are rare, and the rescan only touches PlayerGui and billboards.
local changed = Instance.new("BindableEvent")
local current = 1
local pillWatched: { [Instance]: boolean } = {}

function Responsive.factor(): number
	return current
end

local function measure(): number
	local camera = Workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else REFERENCE_HEIGHT
	if height < 2 then
		height = REFERENCE_HEIGHT
	end
	return math.clamp(height / REFERENCE_HEIGHT, MIN_FACTOR, MAX_FACTOR)
end

-- A pixel value authored for the reference screen, sized for this one.
function Responsive.px(value: number): number
	return value * current
end

-- Fires (factor) whenever the screen's scale changes.
function Responsive.onChanged(callback: (number) -> ()): RBXScriptConnection
	return changed.Event:Connect(callback)
end

-- The authored value of `prop`, recorded on first sight.
local function base(inst: Instance, prop: string, value: any): any
	local key = "Base" .. prop
	local stored = inst:GetAttribute(key)
	if stored == nil then
		inst:SetAttribute(key, value)
		return value
	end
	return stored
end

local function udim(u: UDim, offset: number): UDim
	return UDim.new(u.Scale, offset * current)
end

-- Apply to one instance; returns true when it holds something to scale.
local function apply(inst: Instance): boolean
	if inst:IsA("UIStroke") then
		if inst.StrokeSizingMode == Enum.StrokeSizingMode.ScaledSize then
			return false -- already relative to its parent / font size
		end
		local b = base(inst, "Thickness", inst.Thickness)
		inst.Thickness = if b > 0 then math.max(1, b * current) else 0
		return true
	elseif inst:IsA("UITextSizeConstraint") then
		local maxBase = base(inst, "MaxTextSize", inst.MaxTextSize)
		local minBase = base(inst, "MinTextSize", inst.MinTextSize)
		local minSize = math.max(1, math.floor(minBase * current + 0.5))
		inst.MinTextSize = minSize
		inst.MaxTextSize = math.max(minSize, math.floor(maxBase * current + 0.5))
		return true
	elseif inst:IsA("ScrollingFrame") then
		local b = base(inst, "ScrollBarThickness", inst.ScrollBarThickness)
		inst.ScrollBarThickness = math.max(if b > 0 then 2 else 0, math.floor(b * current + 0.5))
		return true
	elseif (inst:IsA("ImageLabel") or inst:IsA("ImageButton")) and inst.ScaleType == Enum.ScaleType.Slice then
		local pill = inst:GetAttribute("PillSlice")
		if type(pill) == "number" and pill > 0 then
			-- a pill button skin (2026-10-20): its corners are the image's whole height, so the
			-- slice scale follows the image's own height and both ends stay perfect semicircles
			-- (PillSlice = the source rows the two corners cover)
			local img = inst :: ImageLabel
			if not pillWatched[img] then
				-- (a table, not an attribute: a template's clone would carry the attribute but not the connection)
				pillWatched[img] = true
				img.Destroying:Connect(function()
					pillWatched[img] = nil
				end)
				img:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
					if img.AbsoluteSize.Y > 0 then
						img.SliceScale = img.AbsoluteSize.Y / pill
					end
				end)
			end
			if img.AbsoluteSize.Y > 0 then
				img.SliceScale = img.AbsoluteSize.Y / pill
			end
			return true
		end
		local b = base(inst, "SliceScale", inst.SliceScale)
		inst.SliceScale = b * current
		return true
	elseif inst:IsA("UICorner") then
		local b: UDim = base(inst, "CornerRadius", inst.CornerRadius)
		if b.Offset == 0 then
			return false
		end
		inst.CornerRadius = UDim.new(b.Scale, b.Offset * current)
		return true
	elseif inst:IsA("UIPadding") then
		local any = false
		for _, prop in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
			local value: UDim = (inst :: any)[prop]
			local b: UDim = base(inst, prop, value)
			if b.Offset ~= 0 then
				any = true
				-- keep whatever scale is set now (Util.FontDrop writes the scale part)
				;(inst :: any)[prop] = udim(value, b.Offset)
			end
		end
		return any
	elseif inst:IsA("UIListLayout") then
		local b: UDim = base(inst, "Padding", inst.Padding)
		if b.Offset == 0 then
			return false
		end
		inst.Padding = UDim.new(b.Scale, b.Offset * current)
		return true
	elseif inst:IsA("UIGridLayout") then
		local b: UDim2 = base(inst, "CellPadding", inst.CellPadding)
		if b.X.Offset == 0 and b.Y.Offset == 0 then
			return false
		end
		inst.CellPadding = UDim2.new(b.X.Scale, b.X.Offset * current, b.Y.Scale, b.Y.Offset * current)
		return true
	elseif inst:IsA("BillboardGui") then
		local b: UDim2 = base(inst, "Size", inst.Size)
		inst.Size = UDim2.new(b.X.Scale, b.X.Offset * current, b.Y.Scale, b.Y.Offset * current)
		return true
	end
	return false
end

local function inWorld(inst: Instance): boolean
	return inst:FindFirstAncestorWhichIsA("SurfaceGui") ~= nil or inst:IsA("SurfaceGui")
end

local function adopt(inst: Instance)
	if not inWorld(inst) then
		apply(inst)
	end
end

local function adoptTree(root: Instance)
	adopt(root)
	for _, d in root:GetDescendants() do
		adopt(d)
	end
end

-- Set an outline from code (state colours, selected rims). For a ScaledSize
-- stroke `px` is its fraction (of the parent's shorter side, or the font size)
-- and is set as is; for a FixedSize one it is the value for the reference screen.
function Responsive.setStroke(stroke: UIStroke, px: number)
	if stroke.StrokeSizingMode == Enum.StrokeSizingMode.ScaledSize then
		stroke.Thickness = math.max(0, px)
		return
	end
	stroke:SetAttribute("BaseThickness", px)
	stroke.Thickness = if px > 0 then math.max(1, px * current) else 0
end

local function refresh()
	local factor = measure()
	if math.abs(factor - current) < 1e-3 then
		return
	end
	current = factor
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		adoptTree(playerGui)
	end
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BillboardGui") then
			adoptTree(d)
		end
	end
	changed:Fire(current)
end

function Responsive.init(_injected: any)
	current = measure()
end

function Responsive.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	adoptTree(playerGui)
	playerGui.DescendantAdded:Connect(adopt)

	-- billboards cloned into the world (enemy bars, damage numbers, prompts)
	local function watchBillboard(gui: Instance)
		if gui:IsA("BillboardGui") then
			adoptTree(gui)
			gui.DescendantAdded:Connect(adopt)
		end
	end
	for _, d in Workspace:GetDescendants() do
		watchBillboard(d)
	end
	Workspace.DescendantAdded:Connect(watchBillboard)

	local function watchCamera()
		local camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
		end
		refresh()
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()
end

return Responsive
