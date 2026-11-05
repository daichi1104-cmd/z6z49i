-- ゲームの進行管理：チェックポイント、リスポーン、即死ブロック、消える床、記録の保存

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local CourseBuilder = require(script.Parent:WaitForChild("CourseBuilder"))

CourseBuilder.build()

-- クライアントへの通知用
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage
local stageReached = Instance.new("RemoteEvent")
stageReached.Name = "StageReached"
stageReached.Parent = remotes
local resetRequest = Instance.new("RemoteEvent")
resetRequest.Name = "ResetRequest"
resetRequest.Parent = remotes

-- DataStore は Studio で API アクセスが無効だと失敗するので pcall で守る
local store
pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName)
end)

local function getStageValue(player: Player): IntValue?
	local stats = player:FindFirstChild("leaderstats")
	return stats and stats:FindFirstChild("ステージ") :: IntValue?
end

local function loadStage(player: Player): number
	if not store then
		return 0
	end
	local ok, value = pcall(function()
		return store:GetAsync("player_" .. player.UserId)
	end)
	if ok and typeof(value) == "number" then
		return math.clamp(value, 0, Config.TotalStages)
	end
	return 0
end

local function saveStage(player: Player)
	local stage = getStageValue(player)
	if not store or not stage then
		return
	end
	pcall(function()
		store:SetAsync("player_" .. player.UserId, stage.Value)
	end)
end

local function moveToCheckpoint(character: Model, stage: number)
	local pad = CourseBuilder.getCheckpoint(stage)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if root and pad then
		task.wait() -- 標準のスポーン処理が終わってから移動する
		character:PivotTo(CFrame.new(pad.Position + Vector3.new(0, 5, 0)) * CFrame.Angles(0, math.pi, 0))
	end
end

Players.PlayerAdded:Connect(function(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local stage = Instance.new("IntValue")
	stage.Name = "ステージ"
	stage.Value = loadStage(player)
	stage.Parent = stats
	stats.Parent = player

	player.CharacterAdded:Connect(function(character)
		moveToCheckpoint(character, stage.Value)
	end)
	if player.Character then
		moveToCheckpoint(player.Character, stage.Value)
	end
end)

Players.PlayerRemoving:Connect(saveStage)
game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		task.spawn(saveStage, player)
	end
	task.wait(2)
end)

-- 「最初からやり直す」ボタン（resetToStart = true）と「チェックポイントへ戻る」ボタン
resetRequest.OnServerEvent:Connect(function(player, resetToStart)
	local stage = getStageValue(player)
	if resetToStart == true and stage then
		stage.Value = 0
	end
	if player.Character and stage then
		moveToCheckpoint(player.Character, stage.Value)
	end
end)

local function playerFromHit(hit: BasePart): (Player?, Humanoid?)
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local player = Players:GetPlayerFromCharacter(character)
	return player, humanoid
end

-- チェックポイント
local function setupCheckpoint(pad: BasePart)
	local padStage = pad:GetAttribute("Stage") :: number
	pad.Touched:Connect(function(hit)
		local player, humanoid = playerFromHit(hit)
		if not player or not humanoid or humanoid.Health <= 0 then
			return
		end
		local stage = getStageValue(player)
		if stage and padStage > stage.Value then
			stage.Value = padStage
			stageReached:FireAllClients(player, padStage)
			if padStage == Config.TotalStages then
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root and not root:FindFirstChild("GoalSparkles") then
					local sparkles = Instance.new("Sparkles")
					sparkles.Name = "GoalSparkles"
					sparkles.Parent = root
				end
			end
			task.spawn(saveStage, player)
		end
	end)
end

-- 即死ブロック（溶岩・回転バー）
local function setupKill(part: BasePart)
	part.Touched:Connect(function(hit)
		local _, humanoid = playerFromHit(hit)
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end)
end

-- 乗ると消えて、しばらくすると戻る床
local function setupVanish(tile: BasePart)
	local busy = false
	local baseTransparency = tile.Transparency
	tile.Touched:Connect(function(hit)
		if busy then
			return
		end
		local player = playerFromHit(hit)
		if not player then
			return
		end
		busy = true
		TweenService:Create(tile, TweenInfo.new(0.6), { Transparency = 0.85 }):Play()
		task.wait(0.6)
		tile.CanCollide = false
		task.wait(2.5)
		tile.CanCollide = true
		TweenService:Create(tile, TweenInfo.new(0.3), { Transparency = baseTransparency }):Play()
		task.wait(0.3)
		busy = false
	end)
end

for tag, setup in { Checkpoint = setupCheckpoint, Kill = setupKill, Vanish = setupVanish } do
	for _, part in CollectionService:GetTagged(tag) do
		setup(part)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(setup)
end
