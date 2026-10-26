--!strict
-- MaterialToastUI: a toast on the right side for every crafting material picked
-- up (Remotes.MaterialsDropped from MaterialService): the material's icon on a
-- tile, "+2" and its name. The user's call (2026-10-12): it only says what you
-- got -- never what it's for, players work out the recipes themselves -- and
-- materials don't spill into the world like coins.
--
-- Hand-built: StarterGui/MaterialToasts, with Stack (a UIListLayout, newest on
-- top) and Templates/Toast (a CanvasGroup: Body/Card/Content, a centred row
-- (Util.CenterRow) of Slot/Icon, Amount and ItemName). The Toast's attributes set the motion: SlideFrom (how far right
-- it starts, a fraction of its width), InSeconds, HoldSeconds, OutSeconds and
-- MaxShown. Every pickup gets its own card, even the same material twice in a row (the user,
-- 2026-10-26: back-to-back drops stacked on one card, so it wasn't clear where each came from).
-- A quest item (afterTalk) waits for the conversation to close, like the reward coins.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Materials = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Materials"))

local Util = script.Parent.Parent:WaitForChild("Util")
local Format = require(Util:WaitForChild("Format"))
local WeaponTile = require(Util:WaitForChild("WeaponTile"))

local MaterialToastUI = {}

local GUI_TIMEOUT = 15
local player = Players.LocalPlayer

type Live = { toast: any, amount: number, token: number }

local deps: any = nil
local gui: ScreenGui? = nil
local live: { [string]: Live } = {}
local order = 0

local function setting(template: Instance, name: string, fallback: number): number
	local value = template:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function remove(id: string, entry: Live, fade: boolean)
	if live[id] == entry then
		live[id] = nil
	end
	local toast = entry.toast
	if not fade then
		toast:Destroy()
		return
	end
	local seconds = setting(toast, "OutSeconds", 0.35)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(toast, info, { GroupTransparency = 1 }):Play()
	TweenService:Create(toast.Body, info, { Position = UDim2.fromScale(0.2, 0) }):Play()
	task.delay(seconds, function()
		toast:Destroy()
	end)
end

-- Count down this toast's hold; a newer pickup of the same material restarts it.
local function hold(id: string, entry: Live)
	entry.token += 1
	local token = entry.token
	task.delay(setting(entry.toast, "HoldSeconds", 2.6), function()
		if entry.token == token and live[id] == entry then
			remove(id, entry, true)
		end
	end)
end

local function show(id: string, amount: number)
	local def = Materials.get(id)
	local stack = gui and gui:FindFirstChild("Stack")
	local templates = gui and gui:FindFirstChild("Templates")
	local template = templates and templates:FindFirstChild("Toast")
	if not (def and stack and template) then
		return
	end
	-- make room: the oldest goes first
	local shown = {}
	for otherId, other in live do
		table.insert(shown, { id = otherId, entry = other })
	end
	if #shown >= setting(template, "MaxShown", 4) then
		table.sort(shown, function(a, b)
			return a.entry.toast.LayoutOrder > b.entry.toast.LayoutOrder
		end)
		remove(shown[1].id, shown[1].entry, false)
	end

	local toast = template:Clone() :: any
	order += 1
	toast.Name = id
	toast.LayoutOrder = -order
	toast.Visible = true
	local card = toast.Body.Card.Content
	card.Slot.Image = WeaponTile.skin(def.rarity)
	card.Slot.Icon.Image = def.icon or ""
	card.ItemName.Text = def.name
	card.Amount.Text = "+" .. Format.commas(amount)
	toast.GroupTransparency = 1
	toast.Body.Position = UDim2.fromScale(setting(template, "SlideFrom", 0.35), 0)
	toast.Parent = stack
	-- no overshoot: the CanvasGroup clips anything that slides past its edge
	local info = TweenInfo.new(setting(template, "InSeconds", 0.25), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(toast, info, { GroupTransparency = 0 }):Play()
	TweenService:Create(toast.Body, info, { Position = UDim2.fromScale(0, 0) }):Play()

	-- each card is its own entry, keyed by its order, never merged with another
	local key = tostring(order)
	local entry: Live = { toast = toast, amount = amount, token = 0 }
	live[key] = entry
	hold(key, entry)
end

local function onDropped(info: any)
	if type(info) ~= "table" or type(info.items) ~= "table" then
		return
	end
	local function run()
		for _, item in info.items do
			if type(item) == "table" and type(item.id) == "string" and type(item.amount) == "number" then
				show(item.id, item.amount)
			end
		end
	end
	if info.afterTalk and player:GetAttribute("InputLocked") == true then
		task.spawn(function()
			while player:GetAttribute("InputLocked") == true do
				player:GetAttributeChangedSignal("InputLocked"):Wait()
			end
			task.wait(0.35)
			run()
		end)
	else
		run()
	end
end

function MaterialToastUI.init(injected: any)
	deps = injected
end

function MaterialToastUI.start()
	deps.Remotes.getEvent("MaterialsDropped").OnClientEvent:Connect(onDropped)
	task.spawn(function()
		local found = player:WaitForChild("PlayerGui"):WaitForChild("MaterialToasts", GUI_TIMEOUT)
		if found and found:IsA("ScreenGui") then
			gui = found
		else
			warn("[MaterialToastUI] no MaterialToasts ScreenGui in StarterGui")
		end
	end)
end

return MaterialToastUI
