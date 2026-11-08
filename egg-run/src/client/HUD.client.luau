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

-- 右上のステータス（じゃまにならないよう小さめ）
local StarterGui = game:GetService("StarterGui")
-- Roblox の体力表示と、右上の参加者リストは、このステータスと重なるので消す
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -8, 0, 6)
panel.Size = UDim2.new(0, 210, 0, 74)
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
panel.BackgroundTransparency = 0.35
panel.Parent = gui
corner(panel, 10)

local speedLabel = text(panel, {
	Position = UDim2.new(0, 8, 0, 4),
	Size = UDim2.new(1, -16, 0, 20),
	TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = Color3.fromRGB(120, 230, 255),
})
local moneyLabel = text(panel, {
	Position = UDim2.new(0, 8, 0, 25),
	Size = UDim2.new(1, -16, 0, 18),
	TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = Color3.fromRGB(255, 225, 110),
})

-- 自分の体力ゲージ
local hpBack = Instance.new("Frame")
hpBack.Position = UDim2.new(0, 8, 0, 48)
hpBack.Size = UDim2.new(1, -16, 0, 20)
hpBack.BackgroundColor3 = Color3.fromRGB(60, 20, 25)
hpBack.Parent = panel
corner(hpBack, 6)
local hpBar = Instance.new("Frame")
hpBar.Size = UDim2.fromScale(1, 1)
hpBar.BackgroundColor3 = Color3.fromRGB(80, 220, 90)
hpBar.Parent = hpBack
corner(hpBar, 6)
local hpText = text(hpBack, {
	Size = UDim2.fromScale(1, 1),
	ZIndex = 2,
	TextStrokeTransparency = 0.3,
})

local lastHealth = nil
local function refreshHealth(humanoid: Humanoid)
	local hp = math.max(0, humanoid.Health)
	local ratio = if humanoid.MaxHealth > 0 then hp / humanoid.MaxHealth else 0
	hpText.Text = string.format("❤️ %d / %d", math.ceil(hp), humanoid.MaxHealth)
	TweenService:Create(hpBar, TweenInfo.new(0.2), { Size = UDim2.fromScale(ratio, 1) }):Play()
	-- 多いと緑、へると黄色、少ないと赤
	hpBar.BackgroundColor3 = if ratio > 0.5
		then Color3.fromRGB(80, 220, 90)
		elseif ratio > 0.25 then Color3.fromRGB(255, 200, 50)
		else Color3.fromRGB(255, 60, 60)
	-- ダメージを受けたら、ゲージのまわりが一瞬赤く光る
	if lastHealth and hp < lastHealth then
		hpBack.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
		TweenService:Create(hpBack, TweenInfo.new(0.4), { BackgroundColor3 = Color3.fromRGB(60, 20, 25) }):Play()
	end
	lastHealth = hp
end
local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	lastHealth = nil
	refreshHealth(humanoid)
	humanoid.HealthChanged:Connect(function()
		refreshHealth(humanoid)
	end)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		refreshHealth(humanoid)
	end)
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	task.spawn(watchCharacter, player.Character)
end

local function refreshStats()
	local ws = player:GetAttribute("WalkSpeed") or 16
	speedLabel.Text = string.format("⚡ %d（はやさ %d）", speedValue.Value, ws)
	moneyLabel.Text = string.format("🪙 %d　🥚 %d", coinValue.Value, eggValue.Value)
end
speedValue.Changed:Connect(refreshStats)
coinValue.Changed:Connect(refreshStats)
eggValue.Changed:Connect(refreshStats)
player:GetAttributeChangedSignal("WalkSpeed"):Connect(refreshStats)
refreshStats()

-- たまごを運んでいる間の案内
local carryBanner = Instance.new("Frame")
carryBanner.AnchorPoint = Vector2.new(0.5, 0)
carryBanner.Position = UDim2.new(0.5, 0, 0, 6)
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
toastHolder.Position = UDim2.new(0.5, 0, 0, 48)
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
	b.Size = UDim2.new(1 / 4, -10, 0, 34)
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
tabs.dragons = makeTab("🐉 仲間", 1 / 4)
tabs.book = makeTab("📖 図鑑", 2 / 4)
tabs.cage = makeTab("🥚 檻", 3 / 4)

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

-- 図鑑：ドラゴンの絵を、四角と丸の部品で描く（右向き、正方形の中に 0〜1 の位置で置く）
-- tone は "body"（体の色）/ "dark"（つばさ・とげ）/ "light"（おなか）/ "eye"
type Piece = { tone: string, x: number, y: number, w: number, h: number, rot: number, round: number }
local SHADOW = Color3.fromRGB(10, 10, 18)

local function dragonPieces(shape: string): { Piece }
	local list: { Piece } = {}
	local function add(tone: string, x: number, y: number, w: number, h: number, rot: number?, round: number?)
		table.insert(list, { tone = tone, x = x, y = y, w = w, h = h, rot = rot or 0, round = round or 0.5 })
	end
	-- 2点を結ぶ棒（首やしっぽ）
	local function limb(tone: string, x1: number, y1: number, x2: number, y2: number, thick: number)
		local dx, dy = x2 - x1, y2 - y1
		add(tone, (x1 + x2) / 2, (y1 + y2) / 2, math.sqrt(dx * dx + dy * dy), thick, math.deg(math.atan2(dy, dx)))
	end
	local function eye(x: number, y: number, size: number?)
		local s = size or 0.07
		add("eye", x, y, s, s)
		add("pupil", x + s * 0.2, y, s * 0.5, s * 0.5)
	end
	local function legs(y: number, w: number, h: number, x1: number, x2: number)
		add("body", x1, y, w, h, 0, 0.3)
		add("body", x2, y, w, h, 0, 0.3)
	end

	if shape == "small" then
		add("dark", 0.6, 0.4, 0.24, 0.12, -35)
		limb("body", 0.35, 0.68, 0.1, 0.62, 0.09)
		add("body", 0.48, 0.64, 0.44, 0.36)
		add("light", 0.52, 0.68, 0.26, 0.22)
		legs(0.85, 0.1, 0.14, 0.38, 0.58)
		add("dark", 0.66, 0.23, 0.05, 0.13, -20, 0.3)
		add("body", 0.72, 0.4, 0.34, 0.3)
		eye(0.8, 0.37, 0.08)
		add("dark", 0.5, 0.44, 0.2, 0.1, -45)
	elseif shape == "winged" then
		add("dark", 0.46, 0.3, 0.52, 0.15, -25)
		limb("body", 0.3, 0.6, 0.04, 0.68, 0.07)
		add("body", 0.46, 0.58, 0.42, 0.22)
		add("light", 0.48, 0.63, 0.28, 0.1)
		legs(0.75, 0.07, 0.16, 0.36, 0.56)
		limb("body", 0.6, 0.54, 0.78, 0.34, 0.1)
		add("dark", 0.75, 0.21, 0.04, 0.11, -35, 0.3)
		add("body", 0.82, 0.31, 0.22, 0.14)
		eye(0.84, 0.29, 0.06)
		add("dark", 0.38, 0.32, 0.5, 0.14, -60)
	elseif shape == "magma" then
		limb("body", 0.3, 0.66, 0.04, 0.78, 0.11)
		for i, x in { 0.3, 0.42, 0.54, 0.66 } do
			add("dark", x, 0.45 + (i == 1 and 0.03 or 0), 0.1, 0.1, 45, 0.15)
		end
		add("body", 0.48, 0.63, 0.52, 0.36)
		add("light", 0.5, 0.7, 0.34, 0.16)
		legs(0.85, 0.13, 0.18, 0.34, 0.6)
		add("dark", 0.78, 0.36, 0.05, 0.12, 30, 0.3)
		add("body", 0.8, 0.52, 0.28, 0.22)
		eye(0.84, 0.48, 0.07)
	elseif shape == "phoenix" then
		add("dark", 0.42, 0.3, 0.42, 0.12, -55)
		add("dark", 0.5, 0.3, 0.42, 0.12, -30)
		limb("dark", 0.36, 0.64, 0.02, 0.5, 0.07)
		limb("dark", 0.36, 0.66, 0.0, 0.66, 0.07)
		limb("dark", 0.36, 0.68, 0.02, 0.82, 0.07)
		add("body", 0.5, 0.62, 0.36, 0.24)
		add("light", 0.52, 0.66, 0.22, 0.12)
		legs(0.8, 0.05, 0.16, 0.44, 0.56)
		limb("body", 0.6, 0.56, 0.74, 0.38, 0.09)
		add("dark", 0.7, 0.22, 0.04, 0.13, -30)
		add("dark", 0.75, 0.21, 0.04, 0.12, -10)
		add("light", 0.88, 0.35, 0.09, 0.04, 10)
		add("body", 0.78, 0.33, 0.18, 0.15)
		eye(0.8, 0.31, 0.06)
		add("dark", 0.42, 0.4, 0.42, 0.12, -35)
	elseif shape == "triple" then
		add("dark", 0.38, 0.4, 0.36, 0.13, -40)
		limb("body", 0.25, 0.7, 0.02, 0.78, 0.08)
		add("body", 0.4, 0.66, 0.42, 0.28)
		add("light", 0.43, 0.71, 0.26, 0.12)
		legs(0.84, 0.09, 0.15, 0.32, 0.5)
		for _, head in { { 0.58, 0.2 }, { 0.82, 0.3 }, { 0.84, 0.56 } } do
			limb("body", 0.52, 0.58, head[1], head[2], 0.08)
			add("body", head[1], head[2], 0.18, 0.12)
			eye(head[1] + 0.03, head[2] - 0.01, 0.05)
		end
	else -- giant
		limb("body", 0.46, 0.68, 0.08, 0.88, 0.13)
		for i, y in { 0.42, 0.55, 0.68 } do
			add("dark", 0.32 - (i - 2) * 0.01, y, 0.1, 0.1, 45, 0.15)
		end
		add("body", 0.5, 0.58, 0.36, 0.44)
		add("light", 0.56, 0.62, 0.18, 0.3)
		legs(0.86, 0.14, 0.2, 0.42, 0.6)
		limb("body", 0.62, 0.55, 0.74, 0.62, 0.05)
		limb("body", 0.54, 0.42, 0.66, 0.26, 0.15)
		add("dark", 0.66, 0.1, 0.05, 0.12, -20, 0.3)
		add("body", 0.73, 0.22, 0.28, 0.18)
		eye(0.77, 0.18, 0.06)
	end
	return list
end

-- parent の中に、正方形の絵を描く。持っていないドラゴンは、真っ黒な影にする
local function drawDragon(parent: GuiObject, dragon, known: boolean, z: number)
	local canvas = Instance.new("Frame")
	canvas.Name = "Picture"
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.BackgroundTransparency = 1
	canvas.ZIndex = z
	canvas.Parent = parent
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = canvas
	local c = dragon.color
	local tones = {
		body = c,
		dark = c:Lerp(Color3.new(0, 0, 0), 0.35),
		light = c:Lerp(Color3.new(1, 1, 1), 0.45),
		eye = Color3.new(1, 1, 1),
		pupil = Color3.fromRGB(20, 20, 30),
	}
	for _, p in dragonPieces(dragon.shape) do
		if not known and (p.tone == "eye" or p.tone == "pupil") then
			continue
		end
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(p.x, p.y)
		f.Size = UDim2.fromScale(p.w, p.h)
		f.Rotation = p.rot
		f.BorderSizePixel = 0
		f.BackgroundColor3 = if known then tones[p.tone] else SHADOW
		f.ZIndex = z + 1
		f.Parent = canvas
		if p.round > 0 then
			local r = Instance.new("UICorner")
			r.CornerRadius = UDim.new(p.round, 0)
			r.Parent = f
		end
	end
	return canvas
end

-- まだ出会っていないドラゴンが、どこのたまごから生まれるか
local function hatchHint(rarity: number): string
	for z, odds in Config.HatchOdds do
		if (odds[rarity] or 0) > 0 then
			local zone = Config.Zones[z]
			return if z == 1
				then "どのたまごからでも 生まれるよ"
				else zone.name .. "より遠くの たまごから 生まれるよ"
		end
	end
	return ""
end

local bookSelected: string? = nil

local function renderBook()
	local owned = collection()
	local found = 0
	for _, dragon in Config.HatchDragons do
		if (owned[dragon.id] or 0) > 0 then
			found += 1
		end
	end
	shopTitle.Text = string.format("📖 ドラゴン図鑑　%d / %d", found, #Config.HatchDragons)

	-- 上：えらんだドラゴンのくわしい説明
	local detail = Instance.new("Frame")
	detail.LayoutOrder = 0
	detail.Size = UDim2.new(1, -8, 0, 92)
	detail.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
	detail.ZIndex = 6
	detail.Parent = list
	corner(detail, 10)
	local picBox = Instance.new("Frame")
	picBox.Position = UDim2.new(0, 6, 0, 6)
	picBox.Size = UDim2.new(0, 80, 0, 80)
	picBox.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
	picBox.ZIndex = 7
	picBox.Parent = detail
	corner(picBox, 8)
	local function line(y: number, h: number, font: Enum.Font?): TextLabel
		return text(detail, {
			Position = UDim2.new(0, 96, 0, y),
			Size = UDim2.new(1, -104, 0, h),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = font or Enum.Font.GothamBold,
			ZIndex = 7,
		})
	end
	local nameLine = line(8, 26)
	local rarityLine = line(36, 18)
	local descLine = line(58, 26, Enum.Font.Gotham)
	descLine.TextColor3 = Color3.fromRGB(200, 200, 220)

	local function showDetail(dragon)
		local old = picBox:FindFirstChild("Picture")
		if old then
			old:Destroy()
		end
		if not dragon then
			nameLine.Text = "カードをタップすると くわしく見られる"
			nameLine.TextColor3 = Color3.new(1, 1, 1)
			rarityLine.Text = "黒い影は、まだ仲間にしていないドラゴン"
			rarityLine.TextColor3 = Color3.fromRGB(200, 200, 220)
			descLine.Text = "たまごをかえして 100種類 ぜんぶ集めよう！"
			return
		end
		local count = owned[dragon.id] or 0
		local known = count > 0
		local rarity = Config.Rarities[dragon.rarity]
		drawDragon(picBox, dragon, known, 8)
		local number = string.format("No.%03d　", tonumber(string.sub(dragon.id, 2)) or 0)
		rarityLine.Text = string.rep("★", dragon.rarity) .. " " .. rarity.name
		rarityLine.TextColor3 = rarity.color
		if known then
			nameLine.Text = number .. dragon.name .. string.format("　×%d", count)
			nameLine.TextColor3 = dragon.color
			descLine.Text = dragonDesc(dragon)
		else
			nameLine.Text = number .. "？？？"
			nameLine.TextColor3 = Color3.fromRGB(150, 150, 165)
			descLine.Text = hatchHint(dragon.rarity)
		end
	end
	showDetail(if bookSelected then Config.findDragon(bookSelected) else nil)

	-- 下：100種類のカード（番号の順）
	local grid = Instance.new("Frame")
	grid.LayoutOrder = 1
	grid.Size = UDim2.new(1, -8, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.BackgroundTransparency = 1
	grid.ZIndex = 6
	grid.Parent = list
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.25, -6, 0, 112)
	layout.CellPadding = UDim2.new(0, 6, 0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	for i, dragon in Config.HatchDragons do
		local known = (owned[dragon.id] or 0) > 0
		local rarity = Config.Rarities[dragon.rarity]
		local card = Instance.new("TextButton")
		card.LayoutOrder = i
		card.Text = ""
		card.AutoButtonColor = true
		card.BackgroundColor3 = if known then Color3.fromRGB(55, 55, 78) else Color3.fromRGB(36, 36, 48)
		card.ZIndex = 7
		card.Parent = grid
		corner(card, 8)
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = if known then 2 else 1
		stroke.Color = if known then rarity.color else Color3.fromRGB(70, 70, 85)
		stroke.Parent = card
		text(card, {
			Position = UDim2.new(0, 5, 0, 3),
			Size = UDim2.new(1, -10, 0, 12),
			Text = string.format("No.%03d", i),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(170, 170, 190),
			Font = Enum.Font.Gotham,
			ZIndex = 8,
		})
		local picArea = Instance.new("Frame")
		picArea.Position = UDim2.new(0, 4, 0, 16)
		picArea.Size = UDim2.new(1, -8, 1, -50)
		picArea.BackgroundTransparency = 1
		picArea.ZIndex = 8
		picArea.Parent = card
		drawDragon(picArea, dragon, known, 8)
		text(card, {
			Position = UDim2.new(0, 3, 1, -33),
			Size = UDim2.new(1, -6, 0, 17),
			Text = if known then dragon.name else "？？？",
			TextColor3 = if known then Color3.new(1, 1, 1) else Color3.fromRGB(130, 130, 145),
			ZIndex = 8,
		})
		text(card, {
			Position = UDim2.new(0, 3, 1, -15),
			Size = UDim2.new(1, -6, 0, 12),
			Text = string.rep("★", dragon.rarity),
			TextColor3 = if known then rarity.color else Color3.fromRGB(95, 95, 110),
			ZIndex = 8,
		})
		card.Activated:Connect(function()
			bookSelected = dragon.id
			showDetail(dragon)
		end)
	end
end

render = function()
	for _, c in list:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	tabs.items.BackgroundColor3 = if currentTab == "items" then BLUE else GRAY
	tabs.dragons.BackgroundColor3 = if currentTab == "dragons" then BLUE else GRAY
	tabs.book.BackgroundColor3 = if currentTab == "book" then BLUE else GRAY
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
				name = "⭐ついて来ている　" .. name
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
		shopTitle.Text =
			string.format("🐉 仲間（ついて来るのは1匹）図鑑 %d/%d", #hatched, #Config.HatchDragons)
		-- いまついて来ている1匹を一番上に、そのあと 生まれた仲間、はじめの仲間
		for i, dragon in hatched do
			dragonRow(if dragon.id == equipped then 0 else i, dragon, owned[dragon.id])
		end
		for i, dragon in Config.Dragons do
			dragonRow(if dragon.id == equipped then 0 else 1000 + i, dragon)
		end
	elseif currentTab == "book" then
		renderBook()
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
tabs.book.Activated:Connect(function()
	currentTab = "book"
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

sideButton("🛒 ショップ", -100, GREEN, function()
	if shop.Visible then
		shop.Visible = false
	else
		openShop("items")
	end
end)
sideButton("🐉 仲間", -50, Color3.fromRGB(140, 70, 200), function()
	openShop("dragons")
end)
sideButton("📖 図鑑", 0, Color3.fromRGB(40, 150, 160), function()
	openShop("book")
end)
local cageButton = sideButton("🥚 檻", 50, Color3.fromRGB(220, 140, 40), function()
	openShop("cage")
end)
sideButton("🏠 ベースへ", 100, BLUE, function()
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
-- 生まれたドラゴンは仲間の一覧に入る。「つれていく」で、いまの1匹と交代する
local equipNew = popupButton("つれていく", 0, BLUE)
local closePopup = popupButton("あとで", 0.5, GRAY)
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
		then "🐣 新しいドラゴンが仲間になった！"
		else "🐣 ドラゴンが仲間になった！"
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

closePopup.Activated:Connect(function()
	hatchPopup.Visible = false
	toast("「🐉 仲間」から いつでも えらべるよ", true)
end)
equipNew.Activated:Connect(function()
	hatchPopup.Visible = false
	if hatchedId then
		local ok, msg = dragonAction:InvokeServer("equip", hatchedId)
		toast(msg, ok)
	end
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
			-- レアなたまごほど大きい（檻のすき間に入るよう、少しひかえめ）
			local size = 2.2 * (1 + (Config.EggScale[egg.zone] - 1) * 0.6)
			p.Size = Vector3.one * size
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Color = Config.Zones[egg.zone].eggColor
			p.CFrame = CFrame.new(slot.Position.X, 1.3 + size * 0.65, slot.Position.Z)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Scale = Vector3.new(1, 1.3, 1)
			mesh.Parent = p
			p:SetAttribute("ReadyAt", egg.readyAt)
			-- クッション（高さ 1.3）の上にのせる
			p:SetAttribute("BaseY", 1.3 + size * 0.65)
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
