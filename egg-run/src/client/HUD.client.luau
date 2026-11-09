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
local dailyAction = remotes:WaitForChild("DailyAction") :: RemoteFunction
local useSkill = remotes:WaitForChild("UseSkill") :: RemoteFunction
local weaponAction = remotes:WaitForChild("WeaponAction") :: RemoteFunction

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
-- 一度でも仲間にしたドラゴン（図鑑に出る）
local function seen(): { [string]: boolean }
	return decode("Seen")
end
-- ついて来ているドラゴン（id の並び）
local function team(): { string }
	return decode("Team")
end
local function levelOf(id: string): number
	return Config.levelFor(decode("Xp")[id] or 0)
end
-- 毎日のごほうび・実績など
local function profile(): any
	return decode("Profile")
end
local function nowTime(): number
	return workspace:GetServerTimeNow()
end
local function longClock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return string.format("%d:%02d:%02d", seconds // 3600, seconds % 3600 // 60, seconds % 60)
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end
local function short(n: number): string
	if n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(math.floor(n))
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
	local floor = player:GetAttribute("TowerFloor")
	carryBanner.Visible = zone ~= nil or floor ~= nil
	if floor then
		carryBanner.BackgroundColor3 = Color3.fromRGB(150, 110, 255)
		carryText.Text = string.format("🗼 塔 %d階　敵を全部たおそう！", floor)
	elseif zone then
		carryBanner.BackgroundColor3 = if zone == "gold"
			then Color3.fromRGB(255, 215, 60)
			else Color3.fromRGB(255, 170, 40)
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
sizeLimit.MaxSize = Vector2.new(460, 560)
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
-- タブは 2段（上に 4つ、下に 3つ）
local function makeTab(label: string, column: number, line: number)
	local perLine = if line == 1 then 4 else 3
	local b = Instance.new("TextButton")
	b.Position = UDim2.new(column / perLine, 4, 0, 44 + (line - 1) * 36)
	b.Size = UDim2.new(1 / perLine, -8, 0, 32)
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = label
	b.ZIndex = 6
	b.Parent = shop
	corner(b, 8)
	return b
end
tabs.items = makeTab("👟 道具", 0, 1)
tabs.weapons = makeTab("⚔️ 武器", 1, 1)
tabs.dragons = makeTab("🐉 仲間", 2, 1)
tabs.book = makeTab("📖 図鑑", 3, 1)
tabs.cage = makeTab("🥚 檻", 0, 2)
tabs.daily = makeTab("📅 毎日", 1, 2)
tabs.trophy = makeTab("🏆 実績", 2, 2)

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.new(0, 8, 0, 120)
list.Size = UDim2.new(1, -16, 1, -128)
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
local ORANGE = Color3.fromRGB(220, 130, 40)
local PURPLE = Color3.fromRGB(150, 80, 210)

-- 開いているタブの中で、毎秒書きかえるもの（残り時間など）
local liveUpdaters: { () -> () } = {}

-- ボタンが2つ以上ある行。buttons = { { text, color, enabled, onClick } }（右から順にならぶ）
type RowButton = { text: string, color: Color3, enabled: boolean, onClick: () -> () }
local function actionRow(
	order: number,
	name: string,
	desc: string,
	nameColor: Color3?,
	buttons: { RowButton }
): { TextButton }
	local f = Instance.new("Frame")
	f.LayoutOrder = order
	f.Size = UDim2.new(1, -8, 0, 66)
	f.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
	f.ZIndex = 6
	f.Parent = list
	corner(f, 10)
	local bw = if #buttons >= 3 then 64 elseif #buttons == 2 then 84 else 110
	local used = #buttons * (bw + 6) + 6
	text(f, {
		Position = UDim2.new(0, 10, 0, 6),
		Size = UDim2.new(1, -used - 14, 0, 26),
		Text = name,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = nameColor or Color3.new(1, 1, 1),
		ZIndex = 7,
	})
	text(f, {
		Position = UDim2.new(0, 10, 0, 34),
		Size = UDim2.new(1, -used - 14, 0, 24),
		Text = desc,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(200, 200, 220),
		Font = Enum.Font.Gotham,
		ZIndex = 7,
	})
	local made = {}
	for i, info in buttons do
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -6 - (i - 1) * (bw + 6), 0.5, 0)
		b.Size = UDim2.new(0, bw, 0, 46)
		b.BackgroundColor3 = if info.enabled then info.color else GRAY
		b.AutoButtonColor = info.enabled
		b.Font = Enum.Font.GothamBold
		b.TextScaled = true
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Text = info.text
		b.ZIndex = 7
		b.Parent = f
		corner(b, 8)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 4)
		pad.PaddingRight = UDim.new(0, 4)
		pad.PaddingTop = UDim.new(0, 4)
		pad.PaddingBottom = UDim.new(0, 4)
		pad.Parent = b
		if info.enabled then
			b.Activated:Connect(function()
				if busy then
					return
				end
				busy = true
				info.onClick()
				busy = false
				render()
			end)
		end
		table.insert(made, b)
	end
	return made
end

-- 見出し（タブの中の区切り）
local function heading(order: number, label: string)
	local f = Instance.new("Frame")
	f.LayoutOrder = order
	f.Size = UDim2.new(1, -8, 0, 26)
	f.BackgroundTransparency = 1
	f.ZIndex = 6
	f.Parent = list
	text(f, {
		Size = UDim2.fromScale(1, 1),
		Text = label,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 225, 130),
		ZIndex = 7,
	})
end

-- 檻のタブの、残り時間を毎秒書きかえるための表
local cageRows: { { desc: TextLabel, button: TextButton, slot: number } } = {}
local updateCageRows: () -> ()
local showHatch: (string, boolean, string?) -> ()

-- ドラゴンの説明に、こうげき力をつけ足す（level があれば、レベルで強くなった数字）
local function dragonDesc(dragon, level: number?): string
	local a = dragon.attack
	if not a then
		return dragon.desc
	end
	local shots = if a.shots > 1 then string.format("×%d", a.shots) else ""
	local damage = a.damage * Config.levelPower(level or 1)
	return string.format("%s ／ ⚔️%d%s", dragon.desc, math.floor(damage + 0.5), shots)
end

-- わざの説明（まだ覚えていなければ、何レベルで覚えるか）
local function skillDesc(dragon, level: number): string
	local skill = Config.Skills[dragon.shape]
	if not skill then
		return ""
	end
	if level >= Config.SkillLevel then
		return string.format("✨%s：%s", skill.name, skill.desc)
	end
	return string.format("✨%s（Lv%dで覚える）", skill.name, Config.SkillLevel)
end

-- 図鑑：ドラゴンの絵を、四角と丸の部品で描く（右向き、正方形の中に 0〜1 の位置で置く）
-- tone は "body"（体の色）/ "dark"（つばさ・とげ）/ "light"（おなか）/ "eye"
-- レア度の飾り："horn"（銀・金の角）/ "gem"（胸の宝石）/ "halo"（★5 の光の輪）
type Piece = { tone: string, x: number, y: number, w: number, h: number, rot: number, round: number }
local SHADOW = Color3.fromRGB(10, 10, 18)

local function dragonPieces(shape: string, rarity: number): { Piece }
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

	-- 頭のまん中の x、頭のてっぺんの y、胸の位置（レア度の飾りをつける場所）
	local hx, top, cx, cy = 0.72, 0.25, 0.66, 0.62
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
		hx, top, cx, cy = 0.82, 0.24, 0.64, 0.6
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
		hx, top, cx, cy = 0.8, 0.41, 0.7, 0.68
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
		hx, top, cx, cy = 0.78, 0.255, 0.64, 0.64
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
		hx, top, cx, cy = 0.58, 0.14, 0.58, 0.68
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
		hx, top, cx, cy = 0.73, 0.13, 0.64, 0.5
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

	-- レアなほど、頭の上の角がふえる。★3 から胸に宝石、★5 は光の輪
	local crown = if rarity >= 4 then 3 elseif rarity >= 2 then rarity - 1 else 0
	for k = 1, crown do
		local len = 0.08 + 0.02 * rarity
		local offset = (k - (crown + 1) / 2) * 0.06
		add("horn", hx + offset, top - len / 2 + 0.03, 0.035, len, offset * 300, 0.3)
	end
	if rarity >= 3 then
		add("gem", cx, cy, 0.07, 0.07, 45, 0.2)
	end
	if rarity >= 5 then
		add("halo", hx, math.max(0.05, top - 0.13), 0.22, 0.07)
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
		horn = if (dragon.rarity or 0) >= 4 then Color3.fromRGB(255, 200, 60) else Color3.fromRGB(215, 222, 235),
		gem = Config.Rarities[dragon.rarity or 1].color,
		halo = Config.Rarities[dragon.rarity or 1].color,
	}
	for _, p in dragonPieces(dragon.shape, dragon.rarity or 0) do
		if not known and (p.tone == "eye" or p.tone == "pupil" or p.tone == "gem") then
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
		if p.tone == "halo" then
			-- 輪：中をすかして、ふちだけ見せる
			f.BackgroundTransparency = 1
			local ring = Instance.new("UIStroke")
			ring.Thickness = 2
			ring.Color = if known then tones.halo else SHADOW
			ring.Parent = f
		end
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
	local met = seen()
	local found = 0
	for _, dragon in Config.HatchDragons do
		if met[dragon.id] then
			found += 1
		end
	end
	shopTitle.Text = string.format("📖 ドラゴン図鑑　%d / %d", found, #Config.HatchDragons)

	-- 図鑑ボーナス：次は何種類で、いくらもらえるか
	local nextGoal
	for _, a in Config.Achievements do
		if a.stat == "book" and found < a.goal then
			nextGoal = a
			break
		end
	end
	heading(
		-1,
		if nextGoal
			then string.format(
				"🎁 図鑑ボーナス：%d種類で 🪙%s（あと %d）",
				nextGoal.goal,
				short(nextGoal.reward),
				nextGoal.goal - found
			)
			else "🎁 図鑑ボーナス：コンプリート！ おめでとう！"
	)

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
		local known = met[dragon.id] == true
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
		local known = met[dragon.id] == true
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

-- 交配にえらんでいる 2匹（檻のタブ）
local breedPick: { string? } = { nil, nil }

local function renderDragons()
	local owned = collection()
	local members = team()
	local slots = player:GetAttribute("TeamSlots") or Config.TeamSlots

	local function dragonRow(order: number, dragon, count: number?)
		local rarity = dragon.rarity and Config.Rarities[dragon.rarity]
		local level = levelOf(dragon.id)
		local name = string.format("Lv.%d %s", level, dragon.name)
		if rarity then
			name = string.rep("★", dragon.rarity) .. " " .. name
		end
		if count and count > 1 then
			name ..= string.format(" ×%d", count)
		end
		local inTeam = table.find(members, dragon.id) ~= nil
		if inTeam then
			name = "⭐" .. name
		end
		local desc = dragonDesc(dragon, level) .. "　" .. skillDesc(dragon, level)
		local buttons: { RowButton } = {}
		if inTeam then
			table.insert(buttons, {
				text = "お休み",
				color = ORANGE,
				enabled = true,
				onClick = function()
					local ok, msg = dragonAction:InvokeServer("unequip", dragon.id)
					toast(msg, ok)
				end,
			})
		else
			table.insert(buttons, {
				text = if #members >= slots then "交代" else "つれていく",
				color = BLUE,
				enabled = true,
				onClick = function()
					local ok, msg = dragonAction:InvokeServer("equip", dragon.id)
					toast(msg, ok)
				end,
			})
		end
		-- 生まれたドラゴンだけ：進化（同じのが3体）と卒業
		if dragon.rarity then
			local c = count or 0
			table.insert(buttons, {
				text = if dragon.rarity >= 5
					then "進化 ー"
					else string.format("進化 %d/%d", math.min(c, Config.MergeCount), Config.MergeCount),
				color = PURPLE,
				enabled = dragon.rarity < 5 and c >= Config.MergeCount,
				onClick = function()
					local ok, msg, id, isNew = dragonAction:InvokeServer("merge", dragon.id)
					toast(msg, ok)
					if ok and id then
						showHatch(id, isNew, "✨ 進化した！")
					end
				end,
			})
			table.insert(buttons, {
				text = string.format("卒業 🪙%s", short(Config.GraduateCoins[dragon.rarity])),
				color = Color3.fromRGB(170, 110, 60),
				enabled = true,
				onClick = function()
					local ok, msg = dragonAction:InvokeServer("graduate", dragon.id)
					toast(msg, ok)
				end,
			})
		end
		actionRow(order, name, desc, if rarity then rarity.color else nil, buttons)
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
	shopTitle.Text = string.format("🐉 仲間（ついて来る %d / %d 匹）", #members, slots)
	heading(
		-1,
		if slots < 3
			then "ショップの「仲間の席」で、いっしょに連れていける数が増える"
			else "⭐ = ついて来ている。同じドラゴン 3体で 進化！"
	)
	-- いまついて来ている仲間を一番上に、そのあと 生まれた仲間、はじめの仲間
	for i, dragon in hatched do
		local slot = table.find(members, dragon.id)
		dragonRow(if slot then slot - 10 else i, dragon, owned[dragon.id])
	end
	for i, dragon in Config.Dragons do
		local slot = table.find(members, dragon.id)
		dragonRow(if slot then slot - 10 else 1000 + i, dragon)
	end
end

local function renderCage()
	local eggs = incubator()
	local slots = player:GetAttribute("IncubatorSlots") or Config.IncubatorSlots
	shopTitle.Text = string.format("🥚 ふ化の檻 %d / %d", #eggs, slots)
	for slot = 1, slots do
		local egg = eggs[slot]
		if egg then
			local info = Config.eggInfo(egg.zone)
			local label = if info then info.name .. "のたまご" else "たまご"
			local desc, button = row(slot, label, "", "", GRAY, true, function()
				if secondsLeft(egg) > 0 then
					toast(string.format("あと %s でかえるよ", clock(secondsLeft(egg))))
					return
				end
				local ok, id, isNew = hatchEgg:InvokeServer(slot)
				if ok then
					showHatch(id, isNew)
				end
			end, if info then info.color else nil)
			table.insert(cageRows, { desc = desc, button = button, slot = slot })
		else
			row(slot, "あき", "巣にたまごを届けると ここに入る", "ー", GRAY, false, function() end)
		end
	end

	-- 交配：2匹をえらぶと、片方の「体の形」と、もう片方の「属性」をあわせた子どものたまごができる
	heading(100, "🧬 交配（親は いなくならない）")
	local owned = collection()
	local choices = {}
	for _, dragon in Config.HatchDragons do
		if (owned[dragon.id] or 0) > 0 then
			table.insert(choices, dragon)
		end
	end
	if #choices == 0 then
		row(
			101,
			"交配",
			"たまごから生まれたドラゴンが いると 交配できる",
			"ー",
			GRAY,
			false,
			function() end
		)
		return
	end
	local function picked(i: number)
		local id = breedPick[i]
		for k, d in choices do
			if d.id == id then
				return d, k
			end
		end
		breedPick[i] = choices[1].id
		return choices[1], 1
	end
	for i = 1, 2 do
		local dragon, k = picked(i)
		local rarity = Config.Rarities[dragon.rarity]
		actionRow(
			100 + i,
			string.format("親%d：%s %s", i, string.rep("★", dragon.rarity), dragon.name),
			string.format("形：%s　属性：%s", dragon.noun, dragon.element),
			rarity.color,
			{
				{
					text = "▶",
					color = BLUE,
					enabled = #choices > 1,
					onClick = function()
						breedPick[i] = choices[k % #choices + 1].id
					end,
				},
				{
					text = "◀",
					color = BLUE,
					enabled = #choices > 1,
					onClick = function()
						breedPick[i] = choices[(k - 2) % #choices + 1].id
					end,
				},
			}
		)
	end
	local a, b = picked(1), picked(2)
	local cost = Config.breedCost(a.rarity, b.rarity)
	local guess = {}
	for _, pair in { { a, b }, { b, a } } do
		local child = Config.findDragonByName(pair[2].element .. pair[1].noun)
		if child and not table.find(guess, child.element .. child.noun) then
			table.insert(guess, child.element .. child.noun)
		end
	end
	local met = seen()
	local hints = {}
	for _, name in guess do
		local child = Config.findDragonByName(name)
		table.insert(hints, if child and met[child.id] then child.name else "？？？")
	end
	row(
		103,
		"交配する",
		"生まれるかも：" .. (if #hints > 0 then table.concat(hints, " / ") else a.name),
		string.format("🪙 %s", short(cost)),
		if coinValue.Value >= cost then GREEN else Color3.fromRGB(150, 90, 60),
		true,
		function()
			local ok, msg = dragonAction:InvokeServer("breed", a.id, b.id)
			toast(msg, ok)
		end,
		Color3.fromRGB(255, 170, 215)
	)
end

local function renderDaily()
	local p = profile()
	shopTitle.Text = "📅 毎日のごほうび"
	local login = p.login or { canClaim = false, day = 1, streak = 0 }
	local base = p.loginBase or 50

	-- ログインボーナス（7日でひとまわり）
	heading(1, string.format("📅 ログインボーナス（連続 %d日）", login.streak or 0))
	local strip = Instance.new("Frame")
	strip.LayoutOrder = 2
	strip.Size = UDim2.new(1, -8, 0, 64)
	strip.BackgroundTransparency = 1
	strip.ZIndex = 6
	strip.Parent = list
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / 7, -4, 1, 0)
	grid.CellPadding = UDim2.new(0, 4, 0, 0)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = strip
	for day, reward in Config.LoginRewards do
		local cell = Instance.new("Frame")
		cell.LayoutOrder = day
		local isToday = day == login.day
		local done = day < login.day or (isToday and not login.canClaim)
		cell.BackgroundColor3 = if isToday and login.canClaim
			then Color3.fromRGB(60, 160, 80)
			elseif done then Color3.fromRGB(45, 45, 60)
			else Color3.fromRGB(60, 60, 85)
		cell.ZIndex = 7
		cell.Parent = strip
		corner(cell, 8)
		text(cell, {
			Position = UDim2.new(0, 2, 0, 2),
			Size = UDim2.new(1, -4, 0, 16),
			Text = string.format("%d日目", day),
			Font = Enum.Font.Gotham,
			ZIndex = 8,
		})
		text(cell, {
			Position = UDim2.new(0, 2, 0, 20),
			Size = UDim2.new(1, -4, 0, 22),
			Text = if done then "✅" elseif reward.egg then "🥚" else "🪙",
			ZIndex = 8,
		})
		text(cell, {
			Position = UDim2.new(0, 2, 0, 44),
			Size = UDim2.new(1, -4, 0, 16),
			Text = short(reward.coins * base),
			TextColor3 = Color3.fromRGB(255, 225, 110),
			ZIndex = 8,
		})
	end
	row(
		3,
		if login.canClaim
			then string.format("今日は %d日目！", login.day)
			else "今日のぶんは もらったよ",
		"7日目は ふしぎなたまご つき。1日休むと 1日目から",
		if login.canClaim then "受け取る" else "また明日",
		if login.canClaim then GREEN else GRAY,
		login.canClaim,
		function()
			local ok, msg, id, isNew = dailyAction:InvokeServer("login")
			toast(msg, ok)
			if ok and id then
				showHatch(id, isNew, "🥚 ふしぎなたまごが かえった！")
			end
		end
	)

	-- 無料のたまごと、黄金のたまごイベント
	heading(10, "🎰 たまご")
	local freeAt = p.freeEggAt or 0
	local _, freeButton = row(
		11,
		"🎰 無料のたまご",
		"4時間ごとに 1回、その場で かえる",
		"",
		GREEN,
		true,
		function()
			local ok, msg, id, isNew = dailyAction:InvokeServer("free")
			toast(msg, ok)
			if ok and id then
				showHatch(id, isNew, "🎰 無料のたまごが かえった！")
			end
		end
	)
	local goldDesc, goldButton = row(
		12,
		"🌟 黄金のたまごイベント",
		"",
		"",
		GRAY,
		false,
		function() end,
		Color3.fromRGB(255, 215, 60)
	)
	local function updateEggs()
		local left = freeAt - nowTime()
		freeButton.Text = if left <= 0 then "ひく！" else "⏳ " .. longClock(left)
		freeButton.BackgroundColor3 = if left <= 0 then GREEN else GRAY
		local goldEnd = workspace:GetAttribute("GoldenEnd") or 0
		local goldNext = workspace:GetAttribute("GoldenNext") or 0
		if nowTime() < goldEnd then
			goldDesc.Text = "道のどこかの 光の柱へ！ 運ぶとレアが出やすい"
			goldButton.Text = "開催中 " .. longClock(goldEnd - nowTime())
			goldButton.BackgroundColor3 = Color3.fromRGB(200, 160, 30)
		else
			goldDesc.Text = "30分ごとに 3分間、道に 黄金のたまごが出る"
			goldButton.Text = "あと " .. longClock(goldNext - nowTime())
			goldButton.BackgroundColor3 = GRAY
		end
	end
	updateEggs()
	table.insert(liveUpdaters, updateEggs)

	-- 今日のミッション
	heading(20, string.format("📋 今日のミッション（1つ 🪙%s）", short(p.missionReward or 0)))
	local allDone = true
	for i, m in p.missions or {} do
		local complete = m.progress >= m.target
		if not m.claimed then
			allDone = false
		end
		row(
			20 + i,
			m.text,
			string.format("%s / %s", short(m.progress), short(m.target)),
			if m.claimed then "受け取りずみ" elseif complete then "受け取る" else "がんばろう",
			if m.claimed then GRAY elseif complete then GREEN else GRAY,
			complete and not m.claimed,
			function()
				local ok, msg = dailyAction:InvokeServer("mission", i)
				toast(msg, ok)
			end
		)
	end
	local canBonus = allDone and not p.bonus and #(p.missions or {}) > 0
	row(
		30,
		"🎁 3つ全部クリアのごほうび",
		"ふしぎなたまごが 1こ その場で かえる",
		if p.bonus then "受け取りずみ" elseif canBonus then "受け取る" else "🔒",
		if canBonus then GREEN else GRAY,
		canBonus,
		function()
			local ok, msg, id, isNew = dailyAction:InvokeServer("bonus")
			toast(msg, ok)
			if ok and id then
				showHatch(id, isNew, "🎁 ふしぎなたまごが かえった！")
			end
		end
	)
end

local function renderTrophies()
	local p = profile()
	local got = p.achievements or {}
	local stats = p.stats or {}
	local total, done = #Config.Achievements, 0
	for _, a in Config.Achievements do
		if got[a.id] then
			done += 1
		end
	end
	shopTitle.Text = string.format("🏆 実績 %d / %d", done, total)
	-- ひみつの門と、塔の記録
	local open = player:GetAttribute("SecretOpen") == true
	row(
		0,
		if open then "🔓 ひみつの門：開いている" else "🔒 ひみつの門",
		string.format(
			"やみの竜王 %d/%d回　図鑑 %d/%d種類",
			math.min(p.bossKills or 0, Config.SecretZone.bossKills),
			Config.SecretZone.bossKills,
			math.min(stats.book or 0, Config.SecretZone.book),
			Config.SecretZone.book
		),
		if open then "通れる！" else "ー",
		if open then GREEN else GRAY,
		false,
		function() end,
		Color3.fromRGB(150, 255, 200)
	)
	row(
		1,
		"🗼 塔のぼり",
		string.format("さいこう記録 %d階（ベースの左うしろの塔から入れる）", p.towerBest or 0),
		"ー",
		GRAY,
		false,
		function() end,
		Color3.fromRGB(210, 190, 255)
	)
	-- まだの実績を上に、達成したものを下に
	for i, a in Config.Achievements do
		local isDone = got[a.id] == true
		local value = math.min(stats[a.stat] or 0, a.goal)
		row(
			if isDone then 1000 + i else 10 + i,
			(if isDone then "✅ " else "") .. a.desc,
			string.format("%s ／ %s / %s ／ 🪙%s", a.name, short(value), short(a.goal), short(a.reward)),
			if isDone then "達成！" else string.format("%d%%", math.floor(value / a.goal * 100)),
			if isDone then Color3.fromRGB(60, 140, 80) else GRAY,
			false,
			function() end,
			if isDone then Color3.fromRGB(150, 230, 160) else nil
		)
	end
end

-- 武器：形ごとに 5つのレア度をならべる。買う・持ちかえる
local function renderWeapons()
	local owned = decode("Weapons")
	local equipped = player:GetAttribute("Weapon")
	local count = 0
	for _ in owned do
		count += 1
	end
	shopTitle.Text = string.format("⚔️ 武器 %d / %d　🪙 %s", count, #Config.Weapons, short(coinValue.Value))
	local current = Config.findWeapon(equipped)
	heading(
		0,
		if current
			then string.format(
				"手に持つ：%s %s（クリック・タップで こうげき）",
				string.rep("★", current.rarity),
				current.name
			)
			else "武器を えらぼう"
	)
	for si, shape in Config.WeaponShapes do
		heading(si * 10, string.format("%s　%s", shape.noun, shape.desc))
		for _, w in Config.Weapons do
			if w.shape ~= shape.shape then
				continue
			end
			local rarity = Config.Rarities[w.rarity]
			local has = owned[w.id] == true
			local isOn = w.id == equipped
			local detail =
				string.format("⚔️%s ／ %s秒 ／ とどく %d", short(w.damage), tostring(w.cooldown), w.range)
			local label, color, enabled
			if isOn then
				label, color, enabled = "持っている", GRAY, false
			elseif has then
				label, color, enabled = "持つ", BLUE, true
			else
				label = "🪙 " .. short(w.price)
				color = if coinValue.Value >= w.price then GREEN else Color3.fromRGB(150, 90, 60)
				enabled = true
			end
			row(
				si * 10 + w.rarity,
				string.format("%s%s %s", if isOn then "✋" else "", string.rep("★", w.rarity), w.name),
				detail,
				label,
				color,
				enabled,
				function()
					local ok, msg = weaponAction:InvokeServer(if has then "equip" else "buy", w.id)
					toast(msg, ok)
				end,
				rarity.color
			)
		end
	end
end

render = function()
	for _, c in list:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for name, b in tabs do
		b.BackgroundColor3 = if currentTab == name then BLUE else GRAY
	end
	table.clear(cageRows)
	table.clear(liveUpdaters)
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
		renderDragons()
	elseif currentTab == "book" then
		renderBook()
	elseif currentTab == "daily" then
		renderDaily()
	elseif currentTab == "weapons" then
		renderWeapons()
	elseif currentTab == "trophy" then
		renderTrophies()
	else
		renderCage()
		updateCageRows()
	end
end

-- 檻のタブを開いている間、残り時間を書きかえる
updateCageRows = function()
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
for name, b in tabs do
	b.Activated:Connect(function()
		currentTab = name
		render()
		updateCageRows()
	end)
end
for _, attr in
	{
		"Incubator",
		"Collection",
		"IncubatorSlots",
		"Seen",
		"Team",
		"TeamSlots",
		"Profile",
		"SecretOpen",
		"Weapons",
		"Weapon",
	}
do
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
-- 経験値は走っている間ずっと増えるので、仲間のタブを開いているときだけ書きかえる
player:GetAttributeChangedSignal("Xp"):Connect(function()
	if shop.Visible and currentTab == "dragons" and not busy then
		render()
	end
end)

-- 左のボタン（スマホのジャンプボタンと重ならない位置）
local function sideButton(label: string, y: number, color: Color3, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0, 0.5)
	b.Position = UDim2.new(0, 10, 0.42, y)
	b.Size = UDim2.new(0, 116, 0, 36)
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
	pad.PaddingTop = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 5)
	pad.Parent = b
	b.Activated:Connect(onClick)
	return b
end

sideButton("🛒 ショップ", -105, GREEN, function()
	if shop.Visible then
		shop.Visible = false
	else
		openShop("items")
	end
end)
sideButton("🐉 仲間", -63, Color3.fromRGB(140, 70, 200), function()
	openShop("dragons")
end)
sideButton("📖 図鑑", -21, Color3.fromRGB(40, 150, 160), function()
	openShop("book")
end)
local cageButton = sideButton("🥚 檻", 21, Color3.fromRGB(220, 140, 40), function()
	openShop("cage")
end)
local dailyButton = sideButton("📅 毎日", 63, Color3.fromRGB(220, 80, 120), function()
	openShop("daily")
end)
sideButton("🏠 ベースへ", 105, BLUE, function()
	goHome:FireServer()
end)

-- 右の「✨ わざ」ボタン（連れているドラゴンのうち、レベル 5 以上の全員が使う）
local skillButton = Instance.new("TextButton")
skillButton.AnchorPoint = Vector2.new(1, 0.5)
skillButton.Position = UDim2.new(1, -10, 0.42, 0)
skillButton.Size = UDim2.new(0, 104, 0, 50)
skillButton.BackgroundColor3 = Color3.fromRGB(255, 170, 40)
skillButton.Font = Enum.Font.GothamBlack
skillButton.TextScaled = true
skillButton.TextColor3 = Color3.new(1, 1, 1)
skillButton.TextStrokeTransparency = 0.5
skillButton.Text = "✨ わざ"
skillButton.Parent = gui
corner(skillButton, 25)
do
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(255, 240, 170)
	stroke.Parent = skillButton
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = skillButton
end
local function anySkillLearned(): boolean
	for _, id in team() do
		local dragon = Config.findDragon(id)
		if dragon and Config.Skills[dragon.shape] and levelOf(id) >= Config.SkillLevel then
			return true
		end
	end
	return false
end
local function refreshSkillButton()
	local left = (player:GetAttribute("SkillReadyAt") or 0) - nowTime()
	if not anySkillLearned() then
		skillButton.Text = string.format("✨ Lv%dで", Config.SkillLevel)
		skillButton.BackgroundColor3 = GRAY
	elseif left > 0 then
		skillButton.Text = string.format("✨ %d秒", math.ceil(left))
		skillButton.BackgroundColor3 = GRAY
	else
		skillButton.Text = "✨ わざ"
		skillButton.BackgroundColor3 = Color3.fromRGB(255, 170, 40)
	end
end
local skillBusy = false
skillButton.Activated:Connect(function()
	if skillBusy then
		return
	end
	skillBusy = true
	local ok, msg = useSkill:InvokeServer()
	toast(msg, ok)
	skillBusy = false
	refreshSkillButton()
end)

-- 右上：黄金のたまごイベントの残り時間
local goldenLabel = text(gui, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -8, 0, 84),
	Size = UDim2.new(0, 210, 0, 26),
	BackgroundTransparency = 0.2,
	BackgroundColor3 = Color3.fromRGB(150, 110, 10),
	Visible = false,
	TextColor3 = Color3.fromRGB(255, 240, 170),
})
corner(goldenLabel, 8)

-- 何か受け取れるものがあるか（毎日ボタンに「！」をつける）
local function dailyHasSomething(): boolean
	local p = profile()
	if p.login and p.login.canClaim then
		return true
	end
	if (p.freeEggAt or 0) <= nowTime() then
		return true
	end
	local allClaimed = #(p.missions or {}) > 0
	for _, m in p.missions or {} do
		if not m.claimed then
			allClaimed = false
			if m.progress >= m.target then
				return true
			end
		end
	end
	return allClaimed and not p.bonus
end

-- ひみつの門：開いた人の画面でだけ、通りぬけられる（キャラの動きは自分の画面で計算している）
local function refreshSecretGate()
	local worldFolder = workspace:FindFirstChild("World")
	local gate = worldFolder and worldFolder:FindFirstChild("SecretGate") :: BasePart?
	if gate then
		local open = player:GetAttribute("SecretOpen") == true
		gate.CanCollide = not open
		gate.Transparency = if open then 0.85 else 0.3
	end
end
player:GetAttributeChangedSignal("SecretOpen"):Connect(refreshSecretGate)
task.spawn(function()
	local worldFolder = workspace:WaitForChild("World", 30)
	if worldFolder then
		worldFolder:WaitForChild("SecretGate", 30)
	end
	refreshSecretGate()
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

showHatch = function(id: string, isNew: boolean, title: string?)
	local dragon = Config.findDragon(id)
	if not dragon then
		return
	end
	local rarity = Config.Rarities[dragon.rarity]
	hatchedId = id
	hatchStroke.Color = rarity.color
	hatchTitle.Text = if isNew
		then (title or "🐣") .. " 新しいドラゴン！"
		else title or "🐣 ドラゴンが仲間になった！"
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
			local info = Config.eggInfo(egg.zone)
			local size = 2.2 * (1 + ((if info then info.scale else 1) - 1) * 0.6)
			p.Size = Vector3.one * size
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Color = if info then info.color else Color3.new(1, 1, 1)
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
		if shop.Visible then
			for _, fn in liveUpdaters do
				fn()
			end
		end
		dailyButton.Text = if dailyHasSomething() then "📅 毎日 ❗" else "📅 毎日"
		refreshSkillButton()
		local goldEnd = workspace:GetAttribute("GoldenEnd") or 0
		goldenLabel.Visible = nowTime() < goldEnd
		if goldenLabel.Visible then
			goldenLabel.Text = "🌟 黄金のたまご あと " .. longClock(goldEnd - nowTime())
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
	task.wait(1.5)
	toast("⚔️ 手に持った武器は、クリック（スマホはタップ）で こうげき！")
	-- 今日のログインボーナスがまだなら、毎日のごほうびを開く
	local p = profile()
	if p.login and p.login.canClaim and not shop.Visible then
		openShop("daily")
	end
end)
