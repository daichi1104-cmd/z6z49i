-- 画面表示：ステージ表示、進行バー、ボタン、クリア時のお知らせ

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local stageReached = remotes:WaitForChild("StageReached") :: RemoteEvent
local resetRequest = remotes:WaitForChild("ResetRequest") :: RemoteEvent

local player = Players.LocalPlayer
local stageValue = player:WaitForChild("leaderstats"):WaitForChild("ステージ") :: IntValue

local gui = Instance.new("ScreenGui")
gui.Name = "StageUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

-- 上部のステージ表示
local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, 8)
panel.Size = UDim2.new(0, 260, 0, 58)
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
panel.BackgroundTransparency = 0.25
panel.Parent = gui
corner(panel, 12)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 0, 0, 4)
title.Size = UDim2.new(1, 0, 0, 30)
title.Font = Enum.Font.GothamBold
title.TextScaled = true
title.TextColor3 = Color3.new(1, 1, 1)
title.Parent = panel

local barBack = Instance.new("Frame")
barBack.Position = UDim2.new(0, 14, 0, 40)
barBack.Size = UDim2.new(1, -28, 0, 8)
barBack.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
barBack.Parent = panel
corner(barBack, 4)

local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Color3.fromRGB(255, 205, 40)
barFill.Parent = barBack
corner(barFill, 4)

local function refresh()
	local stage = stageValue.Value
	if stage >= Config.TotalStages then
		title.Text = "🏆 クリア！"
	else
		title.Text = string.format("ステージ %d / %d", stage + 1, Config.TotalStages)
	end
	TweenService:Create(barFill, TweenInfo.new(0.4), {
		Size = UDim2.fromScale(stage / Config.TotalStages, 1),
	}):Play()
end
stageValue.Changed:Connect(refresh)
refresh()

-- 左下のボタン（スマホのジャンプボタンと重ならない位置）
local function makeButton(text: string, y: number, color: Color3, onClick: () -> ())
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0, 1)
	b.Position = UDim2.new(0, 12, 0.45, y)
	b.Size = UDim2.new(0, 130, 0, 40)
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.Parent = gui
	corner(b, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = b
	b.Activated:Connect(onClick)
	return b
end

makeButton("↩ 戻る", 0, Color3.fromRGB(60, 140, 255), function()
	resetRequest:FireServer(false)
end)

local confirmUntil = 0
local restartButton
restartButton = makeButton("最初から", 48, Color3.fromRGB(200, 70, 70), function()
	-- 押し間違い防止のため、2回押しで実行
	if os.clock() < confirmUntil then
		confirmUntil = 0
		restartButton.Text = "最初から"
		resetRequest:FireServer(true)
	else
		confirmUntil = os.clock() + 3
		restartButton.Text = "もう一度押す"
		task.delay(3, function()
			if os.clock() >= confirmUntil then
				restartButton.Text = "最初から"
			end
		end)
	end
end)

-- お知らせ表示
local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0.5, 0.5)
toast.Position = UDim2.fromScale(0.5, 0.3)
toast.Size = UDim2.new(0.8, 0, 0, 60)
toast.BackgroundTransparency = 1
toast.Font = Enum.Font.GothamBlack
toast.TextScaled = true
toast.TextColor3 = Color3.fromRGB(255, 230, 90)
toast.TextStrokeTransparency = 0.2
toast.TextTransparency = 1
toast.TextStrokeColor3 = Color3.new(0, 0, 0)
toast.Parent = gui

local toastId = 0
local function showToast(text: string, seconds: number)
	toastId += 1
	local id = toastId
	toast.Text = text
	toast.TextTransparency = 0
	toast.TextStrokeTransparency = 0.2
	task.delay(seconds, function()
		if id == toastId then
			TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

stageReached.OnClientEvent:Connect(function(who: Player, stage: number)
	if stage == Config.TotalStages then
		if who == player then
			showToast("🎉 ゴール！おめでとう！ 🎉", 5)
		else
			showToast(who.DisplayName .. " さんがゴールしました！", 3)
		end
	elseif who == player then
		showToast(string.format("ステージ %d クリア！", stage), 1.5)
	end
end)

showToast(Config.GameTitle, 3)
