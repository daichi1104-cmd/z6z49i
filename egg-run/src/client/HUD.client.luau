-- 画面表示：ステータス、たまごの案内、ボタン、ショップ（アイテム・ドラゴン・檻）、ふ化の演出、お知らせ

local HttpService = game:GetService("HttpService")
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
local hatchEgg = remotes:WaitForChild("HatchEgg") :: RemoteFunction

local player = Players.LocalPlayer
local stats = player:WaitForChild("leaderstats")
local speedValue = stats:WaitForChild("スピード") :: IntValue
local coinValue = stats:WaitForChild("コイン") :: IntValue
local eggValue = stats:WaitForChild("たまご") :: IntValue
local ownedItems = player:WaitForChild("OwnedItems")

local NEST = Vector3.new(0, 0, -50)

-- 檻と図鑑の中身（サーバーが文字にして渡してくる）
local function decode(attr: string): any
	local raw = player:GetAttribute(attr)
	if typeof(raw) ~= "string" then
		return {}
	end
	local ok, value = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok and typeof(value) == "table" then value else {}
end
local function incubator(): { { zone: number, readyAt: number } }
	return decode("Incubator")
end
local function collection(): { [string]: number }
	return decode("Collection")
end
local function secondsLeft(egg): number
	return math.max(0, math.ceil(egg.readyAt - workspace:GetServerTimeNow()))
end
local function clock(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

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
	b.Position = UDim2.new(x, 6, 0, 46)
	b.Size = UDim2.new(1 / 3, -10, 0, 34)
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
tabs.dragons = makeTab("🐉 ドラゴン", 1 / 3)
tabs.cage = makeTab("🥚 檻", 2 / 3)

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
	onClick: () -> (),
	nameColor: Color3?
): (TextLabel, TextButton)
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
		TextColor3 = nameColor or Color3.new(1, 1, 1),
		ZIndex = 7,
	})
	local descLabel = text(f, {
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
	return descLabel, b
end

local GREEN = Color3.fromRGB(50, 170, 80)
local GRAY = Color3.fromRGB(90, 90, 105)
local BLUE = Color3.fromRGB(60, 120, 220)

-- 檻のタブの、残り時間を毎秒書きかえるための表
local cageRows: { { desc: TextLabel, button: TextButton, slot: number } } = {}
local showHatch: (string, boolean) -> ()

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
	tabs.cage.BackgroundColor3 = if currentTab == "cage" then BLUE else GRAY
	table.clear(cageRows)
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
	elseif currentTab == "dragons" then
		local equipped = player:GetAttribute("Dragon")
		local owned = collection()
		local function dragonRow(order: number, dragon, count: number?)
			local rarity = dragon.rarity and Config.Rarities[dragon.rarity]
			local name = "🐉 " .. dragon.name
			if rarity then
				name = string.format("%s %s", string.rep("★", dragon.rarity), dragon.name)
			end
			if count and count > 1 then
				name ..= string.format(" ×%d", count)
			end
			local color = if rarity then rarity.color else nil
			if dragon.id == equipped then
				row(order, name, dragonDesc(dragon), "お休み", Color3.fromRGB(200, 120, 40), true, function()
					local ok, msg = dragonAction:InvokeServer("unequip")
					toast(msg, ok)
				end, color)
			else
				row(order, name, dragonDesc(dragon), "つれていく", BLUE, true, function()
					local ok, msg = dragonAction:InvokeServer("equip", dragon.id)
					toast(msg, ok)
				end, color)
			end
		end

		-- 生まれたドラゴン（レアな順）を先に、そのあと はじめの仲間
		local hatched = {}
		for _, dragon in Config.HatchDragons do
			if (owned[dragon.id] or 0) > 0 then
				table.insert(hatched, dragon)
			end
		end
		table.sort(hatched, function(x, y)
			if x.rarity ~= y.rarity then
				return x.rarity > y.rarity
			end
			return x.id < y.id
		end)
		shopTitle.Text = string.format("📖 図鑑 %d / %d", #hatched, #Config.HatchDragons)
		for i, dragon in hatched do
			dragonRow(i, dragon, owned[dragon.id])
		end
		for i, dragon in Config.Dragons do
			dragonRow(1000 + i, dragon)
		end
	else
		-- 檻
		local eggs = incubator()
		local slots = player:GetAttribute("IncubatorSlots") or Config.IncubatorSlots
		shopTitle.Text = string.format("🥚 ふ化の檻 %d / %d", #eggs, slots)
		for slot = 1, slots do
			local egg = eggs[slot]
			if egg then
				local zone = Config.Zones[egg.zone]
				local desc, button = row(slot, zone.name .. "のたまご", "", "", GRAY, true, function()
					if secondsLeft(egg) > 0 then
						toast(string.format("あと %s でかえるよ", clock(secondsLeft(egg))))
						return
					end
					local ok, id, isNew = hatchEgg:InvokeServer(slot)
					if ok then
						showHatch(id, isNew)
					end
				end, zone.eggColor)
				table.insert(cageRows, { desc = desc, button = button, slot = slot })
			else
				row(
					slot,
					"あき",
					"巣にたまごを届けると ここに入る",
					"ー",
					GRAY,
					false,
					function() end
				)
			end
		end
	end
end

-- 檻のタブを開いている間、残り時間を書きかえる
local function updateCageRows()
	local eggs = incubator()
	for _, r in cageRows do
		local egg = eggs[r.slot]
		if egg then
			local left = secondsLeft(egg)
			if left > 0 then
				r.desc.Text = string.format("あと %s でかえる", clock(left))
				r.button.Text = "⏳ " .. clock(left)
				r.button.BackgroundColor3 = GRAY
			else
				r.desc.Text = "かえる準備ができた！"
				r.button.Text = "🐣 かえす！"
				r.button.BackgroundColor3 = GREEN
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
	updateCageRows()
end
openShopEvent.OnClientEvent:Connect(function(tab: string?)
	openShop(tab)
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
tabs.cage.Activated:Connect(function()
	currentTab = "cage"
	render()
	updateCageRows()
end)
for _, attr in { "Incubator", "Collection", "IncubatorSlots" } do
	player:GetAttributeChangedSignal(attr):Connect(function()
		if shop.Visible and not busy then
			render()
			updateCageRows()
		end
	end)
end
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
local function sideButton(label: string, y: number, color: Color3, onClick: () -> ()): TextButton
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
	return b
end

sideButton("🛒 ショップ", -75, GREEN, function()
	if shop.Visible then
		shop.Visible = false
	else
		openShop("items")
	end
end)
sideButton("🐉 ドラゴン", -25, Color3.fromRGB(140, 70, 200), function()
	openShop("dragons")
end)
local cageButton = sideButton("🥚 檻", 25, Color3.fromRGB(220, 140, 40), function()
	openShop("cage")
end)
sideButton("🏠 ベースへ", 75, BLUE, function()
	goHome:FireServer()
end)

-- ふ化の演出
local hatchPopup = Instance.new("Frame")
hatchPopup.AnchorPoint = Vector2.new(0.5, 0.5)
hatchPopup.Position = UDim2.fromScale(0.5, 0.5)
hatchPopup.Size = UDim2.new(0, 320, 0, 250)
hatchPopup.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
hatchPopup.Visible = false
hatchPopup.ZIndex = 20
hatchPopup.Parent = gui
corner(hatchPopup, 16)
local hatchStroke = Instance.new("UIStroke")
hatchStroke.Thickness = 4
hatchStroke.Parent = hatchPopup
local hatchTitle =
	text(hatchPopup, { Position = UDim2.new(0, 12, 0, 12), Size = UDim2.new(1, -24, 0, 36), ZIndex = 21 })
local hatchRarity =
	text(hatchPopup, { Position = UDim2.new(0, 12, 0, 54), Size = UDim2.new(1, -24, 0, 30), ZIndex = 21 })
local hatchName = text(hatchPopup, { Position = UDim2.new(0, 12, 0, 88), Size = UDim2.new(1, -24, 0, 44), ZIndex = 21 })
local hatchDesc = text(hatchPopup, {
	Position = UDim2.new(0, 12, 0, 136),
	Size = UDim2.new(1, -24, 0, 24),
	Font = Enum.Font.Gotham,
	TextColor3 = Color3.fromRGB(210, 210, 230),
	ZIndex = 21,
})
local function popupButton(label: string, x: number, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Position = UDim2.new(x, 8, 1, -60)
	b.Size = UDim2.new(0.5, -16, 0, 46)
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = label
	b.ZIndex = 21
	b.Parent = hatchPopup
	corner(b, 10)
	return b
end
local equipNew = popupButton("つれていく", 0, BLUE)
local closePopup = popupButton("とじる", 0.5, GRAY)
local hatchedId: string? = nil

showHatch = function(id: string, isNew: boolean)
	local dragon = Config.findDragon(id)
	if not dragon then
		return
	end
	local rarity = Config.Rarities[dragon.rarity]
	hatchedId = id
	hatchStroke.Color = rarity.color
	hatchTitle.Text = if isNew
		then "🐣 新しいドラゴンが生まれた！"
		else "🐣 ドラゴンが生まれた！"
	hatchRarity.Text = string.rep("★", dragon.rarity) .. " " .. rarity.name
	hatchRarity.TextColor3 = rarity.color
	hatchName.Text = dragon.name
	hatchName.TextColor3 = dragon.color
	hatchDesc.Text = dragonDesc(dragon)
	-- ぽんっと大きくなって出てくる
	hatchPopup.Size = UDim2.new(0, 60, 0, 50)
	hatchPopup.Visible = true
	TweenService:Create(hatchPopup, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.new(0, 320, 0, 250) })
		:Play()
end
equipNew.Activated:Connect(function()
	hatchPopup.Visible = false
	if hatchedId then
		local ok, msg = dragonAction:InvokeServer("equip", hatchedId)
		toast(msg, ok)
	end
end)
closePopup.Activated:Connect(function()
	hatchPopup.Visible = false
end)

-- 檻の中に、自分のたまごを表示する（自分の画面にだけ見える）
local cageModel = workspace:WaitForChild("World"):WaitForChild("Incubator", 30)
local eggParts: { Part } = {}
local function refreshCageEggs()
	for _, p in eggParts do
		p:Destroy()
	end
	table.clear(eggParts)
	if not cageModel then
		return
	end
	for i, egg in incubator() do
		local slot = cageModel:FindFirstChild("Slot" .. i) :: BasePart?
		if slot then
			local p = Instance.new("Part")
			p.Shape = Enum.PartType.Ball
			p.Size = Vector3.one * 2.6
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Color = Config.Zones[egg.zone].eggColor
			p.CFrame = slot.CFrame
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Scale = Vector3.new(1, 1.3, 1)
			mesh.Parent = p
			p:SetAttribute("ReadyAt", egg.readyAt)
			p:SetAttribute("BaseY", slot.Position.Y)
			p.Parent = cageModel
			table.insert(eggParts, p)
		end
	end
end
player:GetAttributeChangedSignal("Incubator"):Connect(refreshCageEggs)
refreshCageEggs()

-- 毎秒：残り時間の表示、かえせるたまごの数、かえせるたまごをゆらす
local lastReady = 0
task.spawn(function()
	while true do
		local ready = 0
		for _, egg in incubator() do
			if secondsLeft(egg) == 0 then
				ready += 1
			end
		end
		cageButton.Text = if ready > 0 then string.format("🐣 檻 (%d)", ready) else "🥚 檻"
		if ready > lastReady then
			toast("🐣 檻のたまごが かえせるよ！", true)
		end
		lastReady = ready
		if shop.Visible and currentTab == "cage" then
			updateCageRows()
		end
		task.wait(1)
	end
end)
RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for _, p in eggParts do
		local readyAt = p:GetAttribute("ReadyAt") :: number
		local baseY = p:GetAttribute("BaseY") :: number
		local pos = p.Position
		if readyAt and workspace:GetServerTimeNow() >= readyAt then
			p.CFrame = CFrame.new(pos.X, baseY, pos.Z) * CFrame.Angles(0, 0, math.sin(t * 12) * 0.25)
		else
			p.CFrame = CFrame.new(pos.X, baseY, pos.Z)
		end
	end
end)

task.delay(2, function()
	toast("ようこそ「" .. Config.GameTitle .. "」へ！ ルームランナーで足をきたえよう")
	task.wait(1.5)
	toast("速くなったら、遠くのたまごを取って巣まで運ぼう！")
end)
