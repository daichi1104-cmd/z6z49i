-- 画面表示：ステータス、たまごの案内、ボタン、ショップ（アイテム・ドラゴン）、お知らせ

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local notifyEvent = remotes:WaitForChild("Notify") :: RemoteEvent
local trainGain = remotes:WaitForChild("TrainGain") :: RemoteEvent
local openShopEvent = remotes:WaitForChild("OpenShop") :: RemoteEvent
local goHome = remotes:WaitForChild("GoHome") :: RemoteEvent
local buyItem = remotes:WaitForChild("BuyItem") :: RemoteFunction
local knockback = remotes:WaitForChild("Knockback") :: RemoteEvent
local dragonAction = remotes:WaitForChild("DragonAction") :: RemoteFunction

local player = Players.LocalPlayer
local stats = player:WaitForChild("leaderstats")
local speedValue = stats:WaitForChild("スピード") :: IntValue
local coinValue = stats:WaitForChild("コイン") :: IntValue
local eggValue = stats:WaitForChild("たまご") :: IntValue
local ownedItems = player:WaitForChild("OwnedItems")

local NEST = Vector3.new(0, 0, -50)

local gui = Instance.new("ScreenGui")
gui.Name = "HUD"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	for k, v in props do
		(t :: any)[k] = v
	end
	t.Parent = parent
	return t
end

-- 上のステータス
local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, 6)
panel.Size = UDim2.new(0, 300, 0, 60)
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
panel.BackgroundTransparency = 0.25
panel.Parent = gui
corner(panel, 12)

local speedLabel = text(panel, {
	Position = UDim2.new(0, 10, 0, 4),
	Size = UDim2.new(1, -20, 0, 28),
	TextColor3 = Color3.fromRGB(120, 230, 255),
})
local moneyLabel = text(panel, {
	Position = UDim2.new(0, 10, 0, 33),
	Size = UDim2.new(1, -20, 0, 22),
	TextColor3 = Color3.fromRGB(255, 225, 110),
})

local function refreshStats()
	local ws = player:GetAttribute("WalkSpeed") or 16
	speedLabel.Text = string.format("⚡ スピード %d（はやさ %d）", speedValue.Value, ws)
	moneyLabel.Text = string.format("🪙 %d コイン　🥚 %d こ", coinValue.Value, eggValue.Value)
end
speedValue.Changed:Connect(refreshStats)
coinValue.Changed:Connect(refreshStats)
eggValue.Changed:Connect(refreshStats)
player:GetAttributeChangedSignal("WalkSpeed"):Connect(refreshStats)
refreshStats()

-- たまごを運んでいる間の案内
local carryBanner = Instance.new("Frame")
carryBanner.AnchorPoint = Vector2.new(0.5, 0)
carryBanner.Position = UDim2.new(0.5, 0, 0, 72)
carryBanner.Size = UDim2.new(0, 280, 0, 36)
carryBanner.BackgroundColor3 = Color3.fromRGB(255, 170, 40)
carryBanner.Visible = false
carryBanner.Parent = gui
corner(carryBanner, 10)
local carryText = text(carryBanner, {
	Position = UDim2.new(0, 8, 0, 4),
	Size = UDim2.new(1, -16, 1, -8),
	TextColor3 = Color3.fromRGB(40, 25, 10),
})

RunService.RenderStepped:Connect(function()
	local zone = player:GetAttribute("CarryingZone")
	carryBanner.Visible = zone ~= nil
	if zone then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local d = (Vector3.new(root.Position.X, 0, root.Position.Z) - NEST).Magnitude
			carryText.Text = string.format("🥚 巣まで あと %dm　にげろ！", math.floor(d))
		end
	end
end)

-- お知らせ
local toastHolder = Instance.new("Frame")
toastHolder.AnchorPoint = Vector2.new(0.5, 0)
toastHolder.Position = UDim2.new(0.5, 0, 0, 114)
toastHolder.Size = UDim2.new(0, 340, 0, 140)
toastHolder.BackgroundTransparency = 1
toastHolder.Parent = gui
local toastLayout = Instance.new("UIListLayout")
toastLayout.Padding = UDim.new(0, 4)
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.Parent = toastHolder

local function toast(message: string, good: boolean?)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, 32)
	f.BackgroundColor3 = if good then Color3.fromRGB(40, 150, 70) else Color3.fromRGB(25, 25, 40)
	f.BackgroundTransparency = 0.15
	f.Parent = toastHolder
	corner(f, 8)
	local t = text(f, { Position = UDim2.new(0, 8, 0, 4), Size = UDim2.new(1, -16, 1, -8), Text = message })
	task.delay(3, function()
		TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(t, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.4)
		f:Destroy()
	end)
	-- 4件より多くならないように古いものを消す
	local frames = {}
	for _, c in toastHolder:GetChildren() do
		if c:IsA("Frame") then
			table.insert(frames, c)
		end
	end
	if #frames > 4 then
		frames[1]:Destroy()
	end
end
notifyEvent.OnClientEvent:Connect(toast)

-- トレーニングで増えたスピードを、ふわっと表示
trainGain.OnClientEvent:Connect(function(gain: number)
	local t = text(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, math.random(-40, 40), 0.45, 0),
		Size = UDim2.new(0, 120, 0, 34),
		Text = string.format("+%s ⚡", if gain >= 10 then tostring(math.floor(gain)) else string.format("%.1f", gain)),
		TextColor3 = Color3.fromRGB(120, 230, 255),
		TextStrokeTransparency = 0.2,
	})
	TweenService:Create(t, TweenInfo.new(0.9), {
		Position = t.Position - UDim2.new(0, 0, 0, 70),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(0.9, function()
		t:Destroy()
	end)
end)

-- 敵にぶつかったら、はじき飛ばされる
knockback.OnClientEvent:Connect(function(direction: Vector3)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.AssemblyLinearVelocity = direction * 70 + Vector3.new(0, 40, 0)
	end
end)

-- ショップ
local shop = Instance.new("Frame")
shop.AnchorPoint = Vector2.new(0.5, 0.5)
shop.Position = UDim2.fromScale(0.5, 0.52)
shop.Size = UDim2.fromScale(0.92, 0.8)
shop.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
shop.Visible = false
shop.ZIndex = 5
shop.Parent = gui
corner(shop, 14)
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(460, 520)
sizeLimit.Parent = shop

local shopTitle = text(shop, {
	Position = UDim2.new(0, 14, 0, 8),
	Size = UDim2.new(1, -70, 0, 30),
	Text = "🛒 ショップ",
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 6,
})
local closeButton = Instance.new("TextButton")
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -8, 0, 8)
closeButton.Size = UDim2.new(0, 40, 0, 32)
closeButton.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextScaled = true
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.Text = "✕"
closeButton.ZIndex = 6
closeButton.Parent = shop
corner(closeButton, 8)

local tabs = {}
local function makeTab(label: string, x: number)
	local b = Instance.new("TextButton")
	b.Position = UDim2.new(x, 8, 0, 46)
	b.Size = UDim2.new(0.5, -12, 0, 34)
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = label
	b.ZIndex = 6
	b.Parent = shop
	corner(b, 8)
	return b
end
tabs.items = makeTab("👟 アイテム", 0)
tabs.dragons = makeTab("🐉 ドラゴン", 0.5)

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.new(0, 8, 0, 88)
list.Size = UDim2.new(1, -16, 1, -96)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.ZIndex = 6
list.Parent = shop
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

local currentTab = "items"
local busy = false
local render: () -> ()

local function row(
	order: number,
	name: string,
	desc: string,
	buttonText: string,
	buttonColor: Color3,
	enabled: boolean,
	onClick: () -> ()
)
	local f = Instance.new("Frame")
	f.LayoutOrder = order
	f.Size = UDim2.new(1, -8, 0, 62)
	f.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
	f.ZIndex = 6
	f.Parent = list
	corner(f, 10)
	text(f, {
		Position = UDim2.new(0, 10, 0, 6),
		Size = UDim2.new(1, -130, 0, 26),
		Text = name,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	})
	text(f, {
		Position = UDim2.new(0, 10, 0, 34),
		Size = UDim2.new(1, -130, 0, 20),
		Text = desc,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(200, 200, 220),
		Font = Enum.Font.Gotham,
		ZIndex = 7,
	})
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -8, 0.5, 0)
	b.Size = UDim2.new(0, 110, 0, 42)
	b.BackgroundColor3 = buttonColor
	b.AutoButtonColor = enabled
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = buttonText
	b.ZIndex = 7
	b.Parent = f
	corner(b, 8)
	if enabled then
		b.Activated:Connect(function()
			if busy then
				return
			end
			busy = true
			onClick()
			busy = false
			render()
		end)
	end
end

local GREEN = Color3.fromRGB(50, 170, 80)
local GRAY = Color3.fromRGB(90, 90, 105)
local BLUE = Color3.fromRGB(60, 120, 220)

-- ドラゴンの説明に、こうげき力をつけ足す
local function dragonDesc(dragon): string
	local a = dragon.attack
	if not a then
		return dragon.desc
	end
	local shots = if a.shots > 1 then string.format("×%d", a.shots) else ""
	return string.format("%s ／ ⚔️%d%s", dragon.desc, a.damage, shots)
end

render = function()
	for _, c in list:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	tabs.items.BackgroundColor3 = if currentTab == "items" then BLUE else GRAY
	tabs.dragons.BackgroundColor3 = if currentTab == "dragons" then BLUE else GRAY
	shopTitle.Text = string.format("🛒 ショップ　🪙 %d", coinValue.Value)

	if currentTab == "items" then
		for i, item in Config.Items do
			local owned = ownedItems:FindFirstChild(item.id) ~= nil
			local canBuy = not owned and coinValue.Value >= item.price
			local label = if owned then "持っている" else string.format("🪙 %d", item.price)
			row(
				i,
				item.name,
				item.desc,
				label,
				if owned then GRAY elseif canBuy then GREEN else Color3.fromRGB(150, 90, 60),
				not owned,
				function()
					local ok, msg = buyItem:InvokeServer(item.id)
					toast(msg, ok)
				end
			)
		end
	else
		local equipped = player:GetAttribute("Dragon")
		for i, dragon in Config.Dragons do
			if dragon.id == equipped then
				row(
					i,
					"🐉 " .. dragon.name,
					dragonDesc(dragon),
					"お休み",
					Color3.fromRGB(200, 120, 40),
					true,
					function()
						local ok, msg = dragonAction:InvokeServer("unequip")
						toast(msg, ok)
					end
				)
			else
				row(i, "🐉 " .. dragon.name, dragonDesc(dragon), "つれていく", BLUE, true, function()
					local ok, msg = dragonAction:InvokeServer("equip", dragon.id)
					toast(msg, ok)
				end)
			end
		end
	end
end

local function openShop(tab: string?)
	if tab then
		currentTab = tab
	end
	shop.Visible = true
	render()
end
openShopEvent.OnClientEvent:Connect(function()
	openShop()
end)
closeButton.Activated:Connect(function()
	shop.Visible = false
end)
tabs.items.Activated:Connect(function()
	currentTab = "items"
	render()
end)
tabs.dragons.Activated:Connect(function()
	currentTab = "dragons"
	render()
end)
coinValue.Changed:Connect(function()
	if shop.Visible then
		render()
	end
end)
player:GetAttributeChangedSignal("Dragon"):Connect(function()
	if shop.Visible then
		render()
	end
end)

-- 左のボタン（スマホのジャンプボタンと重ならない位置）
local function sideButton(label: string, y: number, color: Color3, onClick: () -> ())
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0, 0.5)
	b.Position = UDim2.new(0, 10, 0.4, y)
	b.Size = UDim2.new(0, 120, 0, 42)
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = label
	b.Parent = gui
	corner(b, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = b
	b.Activated:Connect(onClick)
end

sideButton("🛒 ショップ", -50, GREEN, function()
	if shop.Visible then
		shop.Visible = false
	else
		openShop("items")
	end
end)
sideButton("🐉 ドラゴン", 0, Color3.fromRGB(140, 70, 200), function()
	openShop("dragons")
end)
sideButton("🏠 ベースへ", 50, BLUE, function()
	goHome:FireServer()
end)

task.delay(2, function()
	toast("ようこそ「" .. Config.GameTitle .. "」へ！ ルームランナーで足をきたえよう")
	task.wait(1.5)
	toast("速くなったら、遠くのたまごを取って巣まで運ぼう！")
end)
