-- 「いまのボーナス」の表示と、転生の画面
-- 右上のステータスの下に 1行の帯を出す（天気 → あたりゾーン → れんぞく配達 を順番に）。
-- 帯を押すと、くわしい画面（天気・あたりゾーン・れんぞく・タイムアタックの記録・転生）が開く

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Sounds"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local rebirthAction = remotes:WaitForChild("Rebirth") :: RemoteFunction

local player = Players.LocalPlayer
local stats = player:WaitForChild("leaderstats")
local speedValue = stats:WaitForChild("スピード") :: IntValue

local GOLD = Color3.fromRGB(255, 215, 90)

local function now(): number
	return workspace:GetServerTimeNow()
end

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function short(n: number): string
	if n >= 1e9 then
		return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(math.floor(n))
end

local function rebirths(): number
	return player:GetAttribute("Rebirths") or 0
end

local function bestTimes(): { [string]: number }
	local ok, value = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute("Best") or "{}")
	end)
	return if ok and typeof(value) == "table" then value else {}
end

local gui = Instance.new("ScreenGui")
gui.Name = "Adventure"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 2
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.6
	for key, value in props do
		if key ~= "MaxTextSize" then
			(t :: any)[key] = value
		end
	end
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = props.MaxTextSize or 18
	limit.Parent = t
	t.Parent = parent
	return t
end

--------------------------------------------------------------------------------
-- 右上の帯
--------------------------------------------------------------------------------

local chip = Instance.new("TextButton")
chip.AnchorPoint = Vector2.new(1, 0)
chip.Position = UDim2.new(1, -8, 0, 84)
chip.Size = UDim2.new(0, 210, 0, 24)
chip.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
chip.BackgroundTransparency = 0.3
chip.AutoButtonColor = true
chip.Text = ""
chip.Parent = gui
corner(chip, 8)
local chipStroke = Instance.new("UIStroke")
chipStroke.Thickness = 1.5
chipStroke.Color = Color3.fromRGB(255, 255, 255)
chipStroke.Transparency = 0.7
chipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
chipStroke.Parent = chip
local chipText = label(chip, {
	Position = UDim2.new(0, 6, 0, 3),
	Size = UDim2.new(1, -12, 1, -6),
	MaxTextSize = 15,
})

local function canRebirth(): boolean
	return speedValue.Value >= Config.rebirthNeed(rebirths())
end

-- 帯に出す文（順番に切りかえる）
local function chipLines(): { string }
	local t = now()
	local lines = {}
	local weather = Config.weatherAt(t)
	table.insert(lines, string.format("%s %s：%s", weather.icon, weather.name, weather.desc))
	local lucky, luckyEnd = Config.luckyZone(t)
	table.insert(
		lines,
		string.format(
			"🎯 あたり：%s ×%d（あと %s）",
			Config.Zones[lucky].name,
			Config.Lucky.mult,
			clock(luckyEnd - t)
		)
	)
	local streak = player:GetAttribute("Streak") or 0
	if streak >= 1 then
		table.insert(
			lines,
			string.format(
				"🔥 れんぞく %d回（つぎ +%d%%）",
				streak,
				math.floor((Config.comboMult(streak + 1) - 1) * 100 + 0.5)
			)
		)
	end
	if rebirths() > 0 then
		table.insert(lines, string.format("🌟 %s（転生 %d回）", Config.rebirthTitle(rebirths()), rebirths()))
	end
	return lines
end

local function refreshChip(tick: number)
	local t = now()
	-- 黄金のたまごイベントの表示（HUD）と重ならないように、下へずらす
	local goldenEnd = workspace:GetAttribute("GoldenEnd")
	local golden = typeof(goldenEnd) == "number" and t < goldenEnd
	chip.Position = UDim2.new(1, -8, 0, if golden then 114 else 84)

	local carryStart = player:GetAttribute("CarryStart")
	local zone = player:GetAttribute("CarryingZone")
	if typeof(carryStart) == "number" then
		-- たまごを運んでいる間は、タイムを出す
		local best = if typeof(zone) == "number" then bestTimes()[tostring(zone)] else nil
		chipText.Text = if best
			then string.format("⏱️ %.1f秒（ベスト %.1f秒）", t - carryStart, best)
			else string.format("⏱️ %.1f秒", t - carryStart)
		chipText.TextColor3 = if best and t - carryStart > best
			then Color3.fromRGB(255, 150, 140)
			else Color3.new(1, 1, 1)
		chipStroke.Color = Color3.new(1, 1, 1)
		return
	end
	if canRebirth() then
		chipText.Text = "🌟 転生できる！ ここを押してね"
		chipText.TextColor3 = GOLD
		chipStroke.Color = GOLD
		chipStroke.Transparency = 0.1 + 0.4 * (0.5 + 0.5 * math.sin(os.clock() * 5))
		return
	end
	chipStroke.Color = Color3.new(1, 1, 1)
	chipStroke.Transparency = 0.7
	chipText.TextColor3 = Color3.new(1, 1, 1)
	local lines = chipLines()
	chipText.Text = lines[(tick // 16) % #lines + 1]
end

--------------------------------------------------------------------------------
-- くわしい画面
--------------------------------------------------------------------------------

local dim = Instance.new("TextButton")
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.45
dim.AutoButtonColor = false
dim.Text = ""
dim.Visible = false
dim.ZIndex = 30
dim.Parent = gui

local card = Instance.new("Frame")
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.5)
card.Size = UDim2.new(0.92, 0, 0.92, 0)
card.BackgroundColor3 = Color3.fromRGB(28, 30, 48)
card.ZIndex = 31
card.Parent = dim
corner(card, 16)
do
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(420, 400)
	limit.Parent = card
	local st = Instance.new("UIStroke")
	st.Thickness = 2
	st.Color = GOLD
	st.Transparency = 0.3
	st.Parent = card
end
local cardScale = Instance.new("UIScale")
cardScale.Parent = card

label(card, {
	Position = UDim2.new(0, 14, 0, 8),
	Size = UDim2.new(1, -70, 0, 30),
	Text = "🌍 いまのボーナス",
	TextXAlignment = Enum.TextXAlignment.Left,
	MaxTextSize = 22,
	ZIndex = 32,
})
local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -8, 0, 8)
close.Size = UDim2.new(0, 34, 0, 30)
close.BackgroundColor3 = Color3.fromRGB(200, 60, 70)
close.Font = Enum.Font.GothamBlack
close.TextSize = 18
close.TextColor3 = Color3.new(1, 1, 1)
close.Text = "×"
close.ZIndex = 32
close.Parent = card
corner(close, 8)

-- 行を上から順にならべる（y は 0〜1 の割合：小さい画面でも はみ出さない）
local ROWS = 7
local rowLabels: { TextLabel } = {}
for i = 1, ROWS do
	rowLabels[i] = label(card, {
		Position = UDim2.new(0, 14, 0.12 + (i - 1) * 0.085, 0),
		Size = UDim2.new(1, -28, 0.08, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 16,
		ZIndex = 32,
	})
end

-- 転生のところ
local rebirthBox = Instance.new("Frame")
rebirthBox.Position = UDim2.new(0, 10, 0.73, 0)
rebirthBox.Size = UDim2.new(1, -20, 0.25, 0)
rebirthBox.BackgroundColor3 = Color3.fromRGB(48, 40, 78)
rebirthBox.ZIndex = 32
rebirthBox.Parent = card
corner(rebirthBox, 12)
local rebirthInfo = label(rebirthBox, {
	Position = UDim2.new(0, 10, 0, 4),
	Size = UDim2.new(1, -150, 1, -8),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextWrapped = true,
	MaxTextSize = 14,
	ZIndex = 33,
})
local rebirthButton = Instance.new("TextButton")
rebirthButton.AnchorPoint = Vector2.new(1, 0.5)
rebirthButton.Position = UDim2.new(1, -8, 0.5, 0)
rebirthButton.Size = UDim2.new(0, 124, 0.76, 0)
rebirthButton.Font = Enum.Font.GothamBlack
rebirthButton.TextScaled = true
rebirthButton.TextColor3 = Color3.new(1, 1, 1)
rebirthButton.TextStrokeTransparency = 0.5
rebirthButton.ZIndex = 33
rebirthButton.Parent = rebirthBox
corner(rebirthButton, 12)
do
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = rebirthButton
end

local confirmUntil = 0 -- 「ほんとうに？」を出している間
local busy = false
local message: string? = nil
local messageUntil = 0

local function refreshCard()
	local t = now()
	local weather, weatherEnd = Config.weatherAt(t)
	local lucky, luckyEnd = Config.luckyZone(t)
	local streak = player:GetAttribute("Streak") or 0
	local count = rebirths()
	rowLabels[1].Text = string.format(
		"%s 天気：%s ― %s（あと %s）",
		weather.icon,
		weather.name,
		weather.desc,
		clock(weatherEnd - t)
	)
	rowLabels[2].Text = string.format(
		"🎯 あたりゾーン：%s のたまごは コイン %d倍（あと %s）",
		Config.Zones[lucky].name,
		Config.Lucky.mult,
		clock(luckyEnd - t)
	)
	rowLabels[3].Text = if streak >= 1
		then string.format(
			"🔥 れんぞく配達 %d回：つぎのたまごは コイン +%d%%（やられると 0 にもどる）",
			streak,
			math.floor((Config.comboMult(streak + 1) - 1) * 100 + 0.5)
		)
		else "🔥 れんぞく配達：やられずに続けて届けると、コインが +10% ずつ ふえる"
	rowLabels[4].Text =
		"🧰 宝箱：道のどこかに ときどき出る。さわると コイン（まれに 大当たり）"
	rowLabels[5].Text = "🏞️ 空：いつも明るい（夜には ならない）"

	-- タイムアタックの記録
	local best = bestTimes()
	local parts = {}
	for i, zone in Config.Zones do
		local seconds = best[tostring(i)]
		if seconds then
			table.insert(parts, string.format("%s %.1f秒", zone.name, seconds))
		end
	end
	rowLabels[6].Text = "⏱️ タイムアタック：記録をぬりかえると コインのおまけ"
	rowLabels[7].Text = if #parts > 0
		then "　" .. table.concat(parts, " ／ ")
		else "　まだ記録がないよ。たまごを届けてみよう"
	rowLabels[7].TextColor3 = Color3.fromRGB(190, 220, 255)

	-- 転生
	local need = Config.rebirthNeed(count)
	local ready = speedValue.Value >= need
	if message and os.clock() < messageUntil then
		rebirthInfo.Text = message
	else
		rebirthInfo.Text = string.format(
			"🌟 転生 %d回（%s）　いま：トレーニング ×%s・コイン ×%s\nつぎ：スピード %s で転生 → ×%s・×%s（スピードとコインは 0 にもどる。ドラゴンや武器は のこる）",
			count,
			Config.rebirthTitle(count),
			tostring(Config.rebirthTrainMult(count)),
			tostring(Config.rebirthCoinMult(count)),
			short(need),
			tostring(Config.rebirthTrainMult(count + 1)),
			tostring(Config.rebirthCoinMult(count + 1))
		)
	end
	if not ready then
		rebirthButton.Text = string.format("あと %s", short(need - speedValue.Value))
		rebirthButton.BackgroundColor3 = Color3.fromRGB(90, 90, 105)
	elseif os.clock() < confirmUntil then
		rebirthButton.Text = "ほんとうに？\nもう一度 押す"
		rebirthButton.BackgroundColor3 = Color3.fromRGB(230, 90, 60)
	else
		rebirthButton.Text = "🌟 転生する"
		rebirthButton.BackgroundColor3 = Color3.fromRGB(220, 160, 30)
	end
end

local function openCard()
	confirmUntil = 0
	refreshCard()
	dim.Visible = true
	cardScale.Scale = 0.8
	TweenService:Create(cardScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

chip.Activated:Connect(function()
	if dim.Visible then
		dim.Visible = false
	else
		openCard()
	end
end)
close.Activated:Connect(function()
	dim.Visible = false
end)
dim.Activated:Connect(function()
	dim.Visible = false
end)

rebirthButton.Activated:Connect(function()
	if busy or not canRebirth() then
		return
	end
	if os.clock() > confirmUntil then
		-- 1回目：たしかめる（3秒のあいだに もう一度 押すと 転生する）
		confirmUntil = os.clock() + 3
		refreshCard()
		return
	end
	busy = true
	confirmUntil = 0
	local ok, success, msg = pcall(function()
		return rebirthAction:InvokeServer()
	end)
	busy = false
	if ok and typeof(msg) == "string" then
		message = msg
		messageUntil = os.clock() + 6
	end
	if ok and success then
		Sounds.ui("rebirth")
		Sounds.ui("fanfare")
		-- おいわい：カードが 金色に光って はずむ
		cardScale.Scale = 1.12
		TweenService:Create(cardScale, TweenInfo.new(0.6, Enum.EasingStyle.Elastic), { Scale = 1 }):Play()
	end
	refreshCard()
end)

-- 0.25秒ごとに書きかえる
task.spawn(function()
	local tick = 0
	while true do
		tick += 1
		refreshChip(tick)
		if dim.Visible then
			refreshCard()
		end
		task.wait(0.25)
	end
end)
