--!strict
-- RobuxShopUI: wires the hand-built Robux shop, StarterGui/RobuxShop (Panel
-- "RobuxShop", Layout B "storefront" from the design canvas, 2026-10-09), and
-- its HUD button, WeaponHud/ShopButton (the market stall, under Index).
--
-- The items sit in the window's scrolling "Content" (v2, 2026-10-10: bigger,
-- louder cards so they look buyable). Every item is a hand-placed frame with
-- "ShopKind" ("Bundle" | "Pass" | "Boost" | "Starter") and "ShopId" (its key
-- in Config/Shop) attributes, holding a "Buy" button: Skin, and a "Price"
-- frame whose UIListLayout centres the Robux icon and the Label together (the
-- label's TextSize follows the button's height x its "TextScale"). This fills in:
--   * every Buy label from the button's PriceFormat ("%d", next to the Robux
--     icon) and Config/Shop's price, or OwnedText with the SkinOwned image (and
--     no Robux icon) for a pass or starter pack already bought;
--   * a bundle's "Amount": its coins x the world scale for the player's
--     "HighestWorld", the window's "WorldNote" from its Format, and its "Bonus"
--     badge: how many more coins per Robux than the smallest bundle, from the
--     badge's Format ("+%d%% extra"; hidden when there is none);
--   * a boost's "Timer": IdleText, or ActiveFormat (minutes, seconds) /
--     ActiveHourFormat (hours, minutes, seconds, once stacked boosts pass an
--     hour) in ActiveColor while one runs ("Boost_<id>", seconds left);
--   * "Balance/Amount": the player's coins.
-- A Buy press fires Remotes.ShopBuy { kind, id }; ShopService opens Roblox's
-- prompt (or grants a Studio test purchase while the item's id is 0).
-- Luckiest Guy labels are centred by Util.FontDrop (each has a UIPadding).
-- Motion while the shop is open: every "Rays" image turns slowly (RAYS_TURN
-- seconds a turn), a card grows a little under the pointer (its "HoverScale"),
-- and every button grows on hover and squashes on a press (Util.ButtonFx, its "FxScale").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Shop = require(Shared:WaitForChild("Config"):WaitForChild("Shop"))

local RobuxShopUI = {}

local PANEL_ID = "RobuxShop"
local GUI_TIMEOUT = 15
local RAYS_TURN = 14
local CARD_HOVER = 1.04
local player = Players.LocalPlayer

local deps: any = nil
local PanelWindow: any = nil
local buyRemote: RemoteEvent? = nil
local panel: ScreenGui? = nil

local function attribute(inst: Instance, name: string, fallback: any): any
	local value = inst:GetAttribute(name)
	return if value ~= nil then value else fallback
end

local function ownsPass(id: string): boolean
	local list = player:GetAttribute("OwnedPasses")
	return type(list) == "string" and ("," .. list .. ","):find("," .. id .. ",", 1, true) ~= nil
end

-- Price and whether it is already owned, for one item.
local function itemInfo(kind: string, id: string): (number?, boolean)
	if kind == "Bundle" then
		local bundle = Shop.Bundles[id]
		return bundle and bundle.price, false
	elseif kind == "Pass" then
		local pass = Shop.Passes[id]
		return pass and pass.price, ownsPass(id)
	elseif kind == "Boost" then
		local boost = Shop.Boosts[id]
		return boost and boost.price, false
	elseif kind == "Starter" then
		return Shop.StarterPack.price, player:GetAttribute("StarterPackBought") == true
	end
	return nil, false
end

local function styleBuy(button: Instance, price: number?, owned: boolean)
	local label = button:FindFirstChild("Label", true)
	local skin = button:FindFirstChild("Skin")
	local robux = button:FindFirstChild("Robux", true)
	if label and label:IsA("TextLabel") then
		label.Text = if owned then attribute(button, "OwnedText", "Owned") else (attribute(button, "PriceFormat", "%d") :: string):format(price or 0)
	end
	-- "Owned" has no Robux icon; the Price layout keeps whatever is left centred
	if robux and robux:IsA("GuiObject") then
		robux.Visible = not owned
	end
	if skin and skin:IsA("ImageLabel") then
		skin.Image = attribute(button, if owned then "SkinOwned" else "SkinBuy", skin.Image)
	end
	-- an owned pass can't be bought again: no hover or press (Util.ButtonFx)
	button.Active = not owned
end

-- How many more coins per Robux a bundle gives than the smallest one, in %.
local function bonusOf(id: string): number
	local base: Shop.Bundle? = nil
	for _, bundle in Shop.Bundles do
		if not base or bundle.order < base.order then
			base = bundle
		end
	end
	local bundle = Shop.Bundles[id]
	if not (base and bundle) or base.price <= 0 or bundle.price <= 0 then
		return 0
	end
	local ratio = (bundle.coins / bundle.price) / (base.coins / base.price)
	return math.floor((ratio - 1) * 100 + 0.5)
end

local function items(): { Instance }
	local list = {}
	if panel then
		for _, d in panel:GetDescendants() do
			if type(d:GetAttribute("ShopKind")) == "string" then
				table.insert(list, d)
			end
		end
	end
	return list
end

local function renderTimer(item: Instance, id: string)
	local timer = item:FindFirstChild("Timer")
	if not (timer and timer:IsA("TextLabel")) then
		return
	end
	local left = player:GetAttribute("Boost_" .. id)
	if type(left) == "number" and left >= 3600 then
		timer.Text = (attribute(timer, "ActiveHourFormat", "Active %d:%02d:%02d") :: string):format(left // 3600, (left % 3600) // 60, left % 60)
		timer.TextColor3 = attribute(timer, "ActiveColor", timer.TextColor3)
	elseif type(left) == "number" and left > 0 then
		timer.Text = (attribute(timer, "ActiveFormat", "Active %d:%02d") :: string):format(left // 60, left % 60)
		timer.TextColor3 = attribute(timer, "ActiveColor", timer.TextColor3)
	else
		timer.Text = attribute(timer, "IdleText", "")
		timer.TextColor3 = attribute(timer, "IdleColor", timer.TextColor3)
	end
end

local function render()
	if not panel then
		return
	end
	local world = player:GetAttribute("HighestWorld")
	world = if type(world) == "number" then world else 1
	for _, item in items() do
		local kind, id = item:GetAttribute("ShopKind"), item:GetAttribute("ShopId")
		local price, owned = itemInfo(kind, id)
		local button = item:FindFirstChild("Buy")
		if button then
			styleBuy(button, price, owned)
		end
		if kind == "Bundle" and Shop.Bundles[id] then
			local amount = item:FindFirstChild("Amount")
			if amount and amount:IsA("TextLabel") then
				amount.Text = deps.Util.Format.coins(Shop.bundleCoins(Shop.Bundles[id], world))
			end
			local bonus = item:FindFirstChild("Bonus")
			if bonus and bonus:IsA("GuiObject") then
				local pct = bonusOf(id)
				bonus.Visible = pct > 0
				local label = bonus:FindFirstChild("Label")
				if label and label:IsA("TextLabel") then
					label.Text = (attribute(bonus, "Format", "+%d%%") :: string):format(pct)
				end
			end
		elseif kind == "Boost" then
			renderTimer(item, id)
		end
	end
	local note = panel:FindFirstChild("WorldNote", true)
	local noteLabel = note and note:FindFirstChild("Label")
	if note and noteLabel and noteLabel:IsA("TextLabel") then
		noteLabel.Text = (attribute(note, "Format", "World %d amounts") :: string):format(world)
	end
	local balance = panel:FindFirstChild("Balance", true)
	local amount = balance and balance:FindFirstChild("Amount", true)
	if amount and amount:IsA("TextLabel") then
		local coins = player:GetAttribute("Coins")
		amount.Text = deps.Util.Format.coins(if type(coins) == "number" then coins else 0)
	end
end

local function tweenScale(scale: Instance?, target: number, time: number)
	if scale and scale:IsA("UIScale") then
		TweenService:Create(scale, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = target }):Play()
	end
end

local Responsive = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Responsive"))

local function wireItems()
	for _, item in items() do
		if item:IsA("GuiObject") then
			local hover = item:FindFirstChild("HoverScale")
			item.MouseEnter:Connect(function()
				tweenScale(hover, CARD_HOVER, 0.12)
			end)
			item.MouseLeave:Connect(function()
				tweenScale(hover, 1, 0.12)
			end)
		end
		local button = item:FindFirstChild("Buy")
		if button and button:IsA("GuiButton") then
			-- the price text follows the button's height (TextScaled can't sit in a
			-- layout beside the icon)
			local label = button:FindFirstChild("Label", true)
			local price = button:FindFirstChild("Price")
			local robux = button:FindFirstChild("Robux", true)
			local function fit()
				if label and label:IsA("TextLabel") then
					local size = math.max(1, math.floor(button.AbsoluteSize.Y * attribute(button, "TextScale", 0.46)))
					label.TextSize = size
					-- Price covers only the green face: the skin's ink rim and lip are
					-- 9-slice borders, drawn in pixels (FaceTop / FaceBottom, authored for
					-- the reference screen; Responsive scales the border and these with
					-- it), so a scale position would drift with screen size. Beside the Robux icon,
					-- Luckiest Guy's side bearing pushes the group right; pull it back by
					-- a tenth of the text size ("Owned" on its own is already centred).
					if price and price:IsA("GuiObject") then
						local top = Responsive.px(attribute(button, "FaceTop", 0))
						local bottom = Responsive.px(attribute(button, "FaceBottom", 0))
						-- a pill skin's borders follow its own height (its PillSlice source rows), so
						-- FaceTop / FaceBottom are source rows of the skin's height (2026-10-20)
						local skin = button:FindFirstChild("Skin")
						local rows = skin and skin:GetAttribute("PillSlice")
						if skin and skin:IsA("GuiObject") and type(rows) == "number" then
							top = skin.AbsoluteSize.Y * attribute(button, "FaceTop", 0) / rows
							bottom = skin.AbsoluteSize.Y * attribute(button, "FaceBottom", 0) / rows
						end
						local withIcon = robux ~= nil and robux:IsA("GuiObject") and robux.Visible
						price.Position = UDim2.new(0, if withIcon then -math.floor(size * 0.1 + 0.5) else 0, 0, top)
						price.Size = UDim2.new(1, 0, 1, -(top + bottom))
					end
				end
			end
			button:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
			Responsive.onChanged(fit)
			if robux then
				robux:GetPropertyChangedSignal("Visible"):Connect(fit)
			end
			fit()
			-- its hover grow and press squash: Util.ButtonFx (its FxScale)
			button.Activated:Connect(function()
				local kind, id = item:GetAttribute("ShopKind"), item:GetAttribute("ShopId")
				local _, owned = itemInfo(kind, id)
				if not owned and buyRemote then
					buyRemote:FireServer({ kind = kind, id = id })
				end
			end)
		end
	end
end

-- The HUD's stall button: opens and closes the shop, and grows a little while
-- hovered (its Content's HoverScale, like the Inventory and Index buttons).
local function wireHudButton(button: GuiButton)
	local content = button:FindFirstChild("Content")
	local scale = content and content:FindFirstChild("HoverScale")
	if scale and scale:IsA("UIScale") then
		local tween: Tween? = nil
		local function to(target: number, time: number)
			if tween then
				tween:Cancel()
			end
			tween = TweenService:Create(scale, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = target })
			;(tween :: Tween):Play()
		end
		button.MouseEnter:Connect(function()
			to(attribute(button, "HoverScale", 1.15), 0.12)
		end)
		button.MouseLeave:Connect(function()
			to(1, 0.1)
		end)
	end
	button.Activated:Connect(function()
		if PanelWindow.isPanelOpen(PANEL_ID) then
			PanelWindow.hidePanel()
		else
			PanelWindow.showPanel(PANEL_ID)
		end
	end)
end

function RobuxShopUI.init(injected: any)
	deps = injected
	PanelWindow = deps.UI.PanelWindow
	buyRemote = deps.Remotes.getEvent("ShopBuy")
end

function RobuxShopUI.start()
	task.spawn(function()
		local hud = player:WaitForChild("PlayerGui"):WaitForChild("WeaponHud", GUI_TIMEOUT)
		local button = hud and hud:FindFirstChild("ShopButton", true)
		if button and button:IsA("GuiButton") then
			wireHudButton(button)
		else
			warn("[RobuxShopUI] no WeaponHud/ShopButton")
		end
		panel = PanelWindow.getPanel(PANEL_ID, GUI_TIMEOUT)
		if not panel then
			warn('[RobuxShopUI] no ScreenGui in StarterGui has Panel = "RobuxShop"')
			return
		end
		-- every Luckiest Guy label with a UIPadding (card names, badges, ribbons,
		-- chips, prices) gets its letters moved to the middle of its box
		deps.Util.FontDrop.watch(panel)
		wireItems()
		render()
		-- the rays behind every item turn while the shop is open
		local spins: { Tween } = {}
		local function setSpinning(on: boolean)
			for _, tween in spins do
				tween:Cancel()
			end
			table.clear(spins)
			if not on then
				return
			end
			for _, d in (panel :: ScreenGui):GetDescendants() do
				if d.Name == "Rays" and d:IsA("GuiObject") then
					d.Rotation = 0
					local tween = TweenService:Create(d, TweenInfo.new(RAYS_TURN, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 360 })
					tween:Play()
					table.insert(spins, tween)
				end
			end
		end
		(panel :: ScreenGui):GetPropertyChangedSignal("Enabled"):Connect(function()
			setSpinning((panel :: ScreenGui).Enabled)
		end)
		setSpinning(panel.Enabled)
		local names = { "Coins", "OwnedPasses", "StarterPackBought", "HighestWorld" }
		for id in Shop.Boosts do
			table.insert(names, "Boost_" .. id)
		end
		for _, name in names do
			player:GetAttributeChangedSignal(name):Connect(render)
		end
	end)
end

return RobuxShopUI
