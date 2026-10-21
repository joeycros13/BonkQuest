--!strict
-- FadeController: fades the screen to black and back around a teleport
-- (Remotes.TeleportFade from PortalService). The fade is the hand-built
-- StarterGui/ScreenFade: a full-screen Black frame kept transparent until used.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local FadeController = {}

local deps: any = nil
local tween: Tween? = nil

local function blackFrame(): Frame?
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("ScreenFade", 10)
	local frame = gui and gui:FindFirstChild("Black")
	return if frame and frame:IsA("Frame") then frame else nil
end

function FadeController.fade(phase: string, seconds: number?)
	local frame = blackFrame()
	if not frame then
		return
	end
	if tween then
		tween:Cancel()
	end
	local goal = if phase == "out" then 0 else 1
	tween = TweenService:Create(frame, TweenInfo.new(seconds or 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { BackgroundTransparency = goal })
	;(tween :: Tween):Play()
end

function FadeController.init(injected: any)
	deps = injected
end

function FadeController.start()
	deps.Remotes.getEvent("TeleportFade").OnClientEvent:Connect(function(phase: string, seconds: number?)
		-- the new place's lighting first, so it is right when the screen clears
		local ambience = deps.Controllers and deps.Controllers.AmbienceController
		if phase == "in" and ambience and ambience.refresh then
			ambience.refresh()
		end
		FadeController.fade(phase, seconds)
	end)
end

return FadeController
