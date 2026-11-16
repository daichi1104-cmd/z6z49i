-- はじめてガイド：はじめて遊ぶ人に「つぎに やること」を 1つずつ教える
-- ・画面の下に やることの文、行き先の上に 大きな矢印、足もとから行き先まで 光の線
-- ・トレーニング → たまごを拾う → 巣へ運ぶ → 檻で かえす、まで終わったら 消える
-- ・進みぐあいは その人の数字（スピード・たまご・かえした数）から決めるので、保存はいらない

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local TRAIN_GOAL = 20 -- さいしょに きたえる スピード
local TREADMILL = Vector3.new(52, 0, 50)
local NEST = Vector3.new(0, 0, -50)
local CAGE = Vector3.new(-52, 0, 5)
local EGG = Vector3.new(0, 0, -Config.Zones[1].distance)
local COLOR = Color3.fromRGB(255, 225, 90)

local player = Players.LocalPlayer
local stats = player:WaitForChild("leaderstats")
local speedValue = stats:WaitForChild("スピード") :: IntValue
local eggsValue = stats:WaitForChild("たまご") :: IntValue

-- かえした数（サーバーが Profile に入れている）
local function hatched(): number
	local raw = player:GetAttribute("Profile")
	if typeof(raw) ~= "string" then
		return -1 -- まだ届いていない
	end
	local ok, profile = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if ok and typeof(profile) == "table" and typeof(profile.stats) == "table" then
		return tonumber(profile.stats.hatched) or 0
	end
	return 0
end

-- データが届くのを待つ
local waited = 0
while hatched() < 0 and waited < 20 do
	waited += task.wait(0.5)
end
-- もう遊んだことのある人には 出さない
local rebirths = player:GetAttribute("Rebirths")
if hatched() ~= 0 or (typeof(rebirths) == "number" and rebirths > 0) or speedValue.Value >= 500 then
	return
end

local gui = Instance.new("ScreenGui")
gui.Name = "Guide"
gui.ResetOnSpawn = false
gui.DisplayOrder = 2
gui.Parent = player:WaitForChild("PlayerGui")

local box = Instance.new("TextLabel")
box.AnchorPoint = Vector2.new(0.5, 1)
box.Position = UDim2.new(0.5, 0, 1, -96)
box.Size = UDim2.new(0.62, 0, 0, 44)
box.BackgroundColor3 = Color3.fromRGB(30, 32, 44)
box.BackgroundTransparency = 0.15
box.Font = Enum.Font.GothamBold
box.TextScaled = true
box.TextColor3 = Color3.new(1, 1, 1)
box.Text = ""
box.Parent = gui
local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(560, 44)
limit.Parent = box
local textLimit = Instance.new("UITextSizeConstraint")
textLimit.MaxTextSize = 20
textLimit.Parent = box
local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 10)
pad.PaddingRight = UDim.new(0, 10)
pad.PaddingTop = UDim.new(0, 5)
pad.PaddingBottom = UDim.new(0, 5)
pad.Parent = box
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = box
local stroke = Instance.new("UIStroke")
stroke.Color = COLOR
stroke.Thickness = 2
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Parent = box

-- 行き先のしるし（自分の画面にだけ出る）
local marker = Instance.new("Part")
marker.Name = "GuideMarker"
marker.Anchored = true
marker.CanCollide = false
marker.CanQuery = false
marker.CanTouch = false
marker.Transparency = 1
marker.Size = Vector3.new(1, 1, 1)
marker.Parent = workspace
local markerAttachment = Instance.new("Attachment")
markerAttachment.Parent = marker
local arrow = Instance.new("BillboardGui")
arrow.Size = UDim2.fromOffset(150, 90)
arrow.AlwaysOnTop = true
arrow.LightInfluence = 0
arrow.MaxDistance = 2000
arrow.Adornee = marker
arrow.Parent = marker
local arrowText = Instance.new("TextLabel")
arrowText.Size = UDim2.fromScale(1, 1)
arrowText.BackgroundTransparency = 1
arrowText.Font = Enum.Font.GothamBlack
arrowText.TextScaled = true
arrowText.TextColor3 = COLOR
arrowText.TextStrokeTransparency = 0
arrowText.Parent = arrow

local beam = Instance.new("Beam")
beam.Color = ColorSequence.new(COLOR)
beam.Width0 = 1.2
beam.Width1 = 1.2
beam.FaceCamera = true
beam.LightEmission = 1
beam.Transparency = NumberSequence.new(0.35)
beam.Attachment1 = markerAttachment
beam.Parent = marker

local function attachBeam()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		beam.Attachment0 = nil
		return
	end
	local a = root:FindFirstChild("GuideAttachment") :: Attachment?
	if not a then
		a = Instance.new("Attachment")
		a.Name = "GuideAttachment"
		a.Position = Vector3.new(0, -2.5, 0)
		a.Parent = root
	end
	beam.Attachment0 = a
end

-- いまの段階：やることの文と、行き先（nil なら 矢印なし）
local function step(): (string, Vector3?)
	if hatched() > 0 then
		return "", nil
	end
	local carrying = player:GetAttribute("CarryingZone") ~= nil
	if eggsValue.Value == 0 and not carrying then
		if speedValue.Value < TRAIN_GOAL then
			return string.format(
				"🏃 ルームランナーに乗って スピードを %d にしよう（いま %d）",
				TRAIN_GOAL,
				speedValue.Value
			),
				TREADMILL
		end
		return "🥚 道の先の 草原で たまごを拾おう（敵に気をつけて）", EGG
	elseif carrying then
		return "🏠 たまごを ベースの巣まで 運ぼう！", NEST
	end
	return "🐣 左の「🥚 檻」を開いて、時間が来たら「かえす！」を押そう", CAGE
end

local finished = false
local t = 0
RunService.Heartbeat:Connect(function(dt)
	if finished then
		return
	end
	t += dt
	local text, target = step()
	if text == "" then
		finished = true
		marker:Destroy()
		box.Text = "🎉 ガイドおわり！ ドラゴンを連れて、もっと遠くの たまごを目ざそう"
		task.delay(8, function()
			gui:Destroy()
		end)
		return
	end
	-- 塔や ボスの闘技場にいる間は かくす
	local away = player:GetAttribute("TowerFloor") ~= nil or player:GetAttribute("InBossArena") == true
	box.Visible = not away
	arrow.Enabled = not away and target ~= nil
	beam.Enabled = arrow.Enabled
	box.Text = text
	if target then
		marker.Position = target + Vector3.new(0, 16 + math.sin(t * 3) * 1.5, 0)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local dist = if root then (root.Position - target).Magnitude else 0
		arrowText.Text = string.format("⬇\n%dm", dist)
		if not beam.Attachment0 or not beam.Attachment0:IsDescendantOf(workspace) then
			attachBeam()
		end
	end
end)
