--!strict
-- HudFly: send a copy of a hand-built HUD template (a FlyingCoin, a
-- FlyingStar) from a point on screen to a HUD element along a curve, then
-- remove it. Used by the loot spill: CoinsUI flies coins to the coin counter,
-- PlayerCardUI flies EXP stars to the EXP bar.

local TweenService = game:GetService("TweenService")

local HudFly = {}

-- `from` is a viewport point in pixels (Camera:WorldToViewportPoint). The copy
-- is parented to `gui`, flies for `seconds` and lands on `target`'s centre;
-- `landed` runs when it arrives.
function HudFly.fly(gui: ScreenGui, template: GuiObject, from: Vector2, target: GuiObject, seconds: number, landed: (() -> ())?)
	local item = template:Clone()
	item.Visible = true
	local origin = gui.AbsolutePosition
	local a = from - origin
	local b = target.AbsolutePosition + target.AbsoluteSize / 2 - origin
	-- curve out to the side and up, like it's being pulled in (the bulge is a
	-- share of the screen, so it looks the same on a phone)
	local screen = gui.AbsoluteSize
	local c = Vector2.new(a.X + (b.X - a.X) * 0.25 + screen.Y * 0.055, math.min(a.Y, b.Y) - screen.Y * 0.075)
	item.Position = UDim2.fromOffset(a.X, a.Y)
	item.Parent = gui
	local t = Instance.new("NumberValue")
	t.Changed:Connect(function(u: number)
		local p = a:Lerp(c, u):Lerp(c:Lerp(b, u), u)
		item.Position = UDim2.fromOffset(p.X, p.Y)
	end)
	local tween = TweenService:Create(t, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 1 })
	tween.Completed:Connect(function()
		item:Destroy()
		t:Destroy()
		if landed then
			landed()
		end
	end)
	tween:Play()
end

-- Pop a UIScale named "Bump" up to `scale` and let it settle back.
function HudFly.bump(target: Instance?, scale: number)
	local bump = target and target:FindFirstChild("Bump")
	if not (bump and bump:IsA("UIScale")) then
		return
	end
	bump.Scale = scale
	TweenService:Create(bump, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function HudFly.init(_injected: any) end
function HudFly.start() end

return HudFly
