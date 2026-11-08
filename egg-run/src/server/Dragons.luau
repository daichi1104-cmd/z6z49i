-- ドラゴンの仲間：選んだドラゴンの模型を作り、プレイヤーの後ろをふわふわついて来させる

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Enemies = require(script.Parent:WaitForChild("Enemies"))

local Dragons = {}

local folder: Folder
type Follower = {
	model: Model,
	cf: CFrame,
	scale: number,
	dragon: any,
	lastAttack: number,
	target: any?,
}
local followers: { [Player]: Follower } = {}

function Dragons.find(id: string?)
	for _, d in Config.Dragons do
		if d.id == id then
			return d
		end
	end
	return nil
end

-- 模型づくり（-Z 方向が前、原点が体の中心）
local function makeBuilder(model: Model, scale: number)
	return function(
		shape: Enum.PartType,
		size: Vector3,
		offset: Vector3,
		color: Color3,
		rot: Vector3?,
		material: Enum.Material?
	)
		local p = Instance.new("Part")
		p.Shape = shape
		p.Size = size * scale
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		local r = rot or Vector3.zero
		p.CFrame = CFrame.new(offset * scale) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
		p.Parent = model
		return p
	end
end

local BALL = Enum.PartType.Ball
local BLOCK = Enum.PartType.Block
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.fromRGB(20, 20, 20)

local function eyes(add, headPos: Vector3, headSize: number)
	for _, s in { -1, 1 } do
		add(
			BALL,
			Vector3.one * headSize * 0.3,
			headPos + Vector3.new(s * headSize * 0.25, headSize * 0.15, -headSize * 0.38),
			WHITE
		)
		add(
			BALL,
			Vector3.one * headSize * 0.15,
			headPos + Vector3.new(s * headSize * 0.25, headSize * 0.15, -headSize * 0.5),
			BLACK
		)
	end
end

local function wings(add, y: number, span: number, color: Color3)
	for _, s in { -1, 1 } do
		add(
			BLOCK,
			Vector3.new(span, 0.2, span * 0.6),
			Vector3.new(s * (span / 2 + 0.8), y, 0.3),
			color,
			Vector3.new(0, 0, s * 20)
		)
	end
end

local function head(add, pos: Vector3, size: number, color: Color3, horn: Color3)
	add(BALL, Vector3.one * size, pos, color)
	add(BLOCK, Vector3.new(size * 0.6, size * 0.4, size * 0.6), pos + Vector3.new(0, -size * 0.15, -size * 0.45), color)
	eyes(add, pos, size)
	for _, s in { -1, 1 } do
		add(
			BLOCK,
			Vector3.new(0.25, size * 0.5, 0.25),
			pos + Vector3.new(s * size * 0.25, size * 0.5, size * 0.1),
			horn,
			Vector3.new(-25, 0, 0)
		)
	end
end

local BUILDERS = {}

BUILDERS.small = function(add, c: Color3)
	add(BALL, Vector3.one * 2.4, Vector3.zero, c)
	add(BALL, Vector3.new(1.6, 1.6, 1.6), Vector3.new(0, -0.1, -0.5), Color3.fromRGB(255, 245, 210))
	head(add, Vector3.new(0, 1.4, -1), 1.8, c, WHITE)
	wings(add, 0.6, 1.8, c:Lerp(WHITE, 0.4))
	add(BLOCK, Vector3.new(0.5, 0.5, 2), Vector3.new(0, -0.4, 1.8), c, Vector3.new(20, 0, 0))
end

BUILDERS.winged = function(add, c: Color3)
	add(BLOCK, Vector3.new(2.6, 2.4, 4), Vector3.zero, c)
	head(add, Vector3.new(0, 1.6, -2.4), 2, c, Color3.fromRGB(80, 60, 200))
	wings(add, 0.8, 4.5, Color3.fromRGB(255, 255, 160))
	add(BLOCK, Vector3.new(0.6, 0.6, 3.5), Vector3.new(0, 0, 3.4), c, Vector3.new(10, 0, 0))
	-- いなずま模様
	add(
		BLOCK,
		Vector3.new(2.7, 0.3, 0.6),
		Vector3.new(0, 0.6, -0.5),
		Color3.fromRGB(80, 200, 255),
		Vector3.new(0, 25, 0),
		Enum.Material.Neon
	)
	add(
		BLOCK,
		Vector3.new(2.7, 0.3, 0.6),
		Vector3.new(0, 0.6, 0.8),
		Color3.fromRGB(80, 200, 255),
		Vector3.new(0, -25, 0),
		Enum.Material.Neon
	)
end

BUILDERS.magma = function(add, c: Color3)
	local rock = Color3.fromRGB(70, 40, 35)
	add(BLOCK, Vector3.new(4, 3.4, 5.5), Vector3.zero, c, nil, Enum.Material.Basalt)
	head(add, Vector3.new(0, 1.2, -3.4), 2.6, c, rock)
	for _, x in { -1.6, 1.6 } do
		for _, z in { -1.8, 1.8 } do
			add(BLOCK, Vector3.new(1.2, 2.2, 1.2), Vector3.new(x, -2.2, z), rock, nil, Enum.Material.Basalt)
		end
	end
	-- 背中の岩とマグマのすじ
	for i = -1, 1 do
		add(
			BLOCK,
			Vector3.new(1.4, 1.4, 1.4),
			Vector3.new(0, 2, i * 1.6),
			rock,
			Vector3.new(45, 0, 45),
			Enum.Material.Basalt
		)
		add(
			BLOCK,
			Vector3.new(4.1, 0.3, 0.4),
			Vector3.new(0, 0.5, i * 1.7),
			Color3.fromRGB(255, 140, 30),
			nil,
			Enum.Material.Neon
		)
	end
	add(BLOCK, Vector3.new(1, 1, 3.5), Vector3.new(0, -0.6, 4), c, Vector3.new(15, 0, 0), Enum.Material.Basalt)
end

BUILDERS.triple = function(add, c: Color3)
	add(BLOCK, Vector3.new(3.6, 3, 4.6), Vector3.zero, c, nil, Enum.Material.Metal)
	wings(add, 1.2, 5, c:Lerp(Color3.fromRGB(255, 120, 40), 0.3))
	-- 三つの首と頭
	for i, x in { -1.6, 0, 1.6 } do
		local tilt = (i - 2) * -20
		add(
			BLOCK,
			Vector3.new(0.8, 3, 0.8),
			Vector3.new(x * 1.2, 2.4, -2),
			c,
			Vector3.new(-30, 0, tilt),
			Enum.Material.Metal
		)
		head(add, Vector3.new(x * 1.8, 3.8, -2.8), 1.6, c, WHITE)
	end
	for _, x in { -0.8, 0.8 } do
		add(
			BLOCK,
			Vector3.new(0.6, 0.6, 4),
			Vector3.new(x, -0.3, 4),
			c,
			Vector3.new(10, x * 20, 0),
			Enum.Material.Metal
		)
	end
end

BUILDERS.giant = function(add, c: Color3)
	local belly = c:Lerp(Color3.fromRGB(230, 220, 170), 0.5)
	add(BLOCK, Vector3.new(4.4, 6, 4), Vector3.new(0, 0.5, 0), c, Vector3.new(-12, 0, 0), Enum.Material.Slate)
	add(BLOCK, Vector3.new(3, 4.5, 1), Vector3.new(0, 0.3, -1.8), belly, Vector3.new(-12, 0, 0))
	head(add, Vector3.new(0, 4.6, -1.8), 2.8, c, Color3.fromRGB(230, 230, 210))
	for _, s in { -1, 1 } do
		add(BLOCK, Vector3.new(1.8, 3.4, 2), Vector3.new(s * 1.8, -3.4, 0), c, nil, Enum.Material.Slate)
		add(BLOCK, Vector3.new(0.9, 2.4, 0.9), Vector3.new(s * 2.6, 1.2, -1.4), c, Vector3.new(-50, 0, 0))
	end
	-- 背中のとげ
	for i = 0, 3 do
		add(
			BLOCK,
			Vector3.new(0.5, 1.6 - i * 0.2, 1.4),
			Vector3.new(0, 4 - i * 1.5, 1.8 + i * 0.6),
			Color3.fromRGB(180, 170, 140),
			Vector3.new(30, 0, 0)
		)
	end
	add(BLOCK, Vector3.new(1.6, 1.6, 6), Vector3.new(0, -2.4, 4.4), c, Vector3.new(20, 0, 0), Enum.Material.Slate)
end

local SCALE = { small = 1, winged = 1, magma = 1, triple = 1, giant = 1.4 }

local function build(dragon): Model
	local model = Instance.new("Model")
	model.Name = dragon.name
	local scale = SCALE[dragon.shape] or 1
	local add = makeBuilder(model, scale)
	local builder = BUILDERS[dragon.shape] or BUILDERS.small
	builder(add, dragon.color)
	local nameTag = Instance.new("BillboardGui")
	nameTag.Size = UDim2.new(8, 0, 1.5, 0)
	nameTag.StudsOffset = Vector3.new(0, 4 * scale, 0)
	nameTag.MaxDistance = 80
	nameTag.LightInfluence = 0
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.Text = dragon.name
	text.Parent = nameTag
	local first = model:FindFirstChildWhichIsA("BasePart")
	model.PrimaryPart = first
	nameTag.Adornee = first
	nameTag.Parent = model
	return model
end

function Dragons.equip(player: Player, id: string?)
	local old = followers[player]
	if old then
		old.model:Destroy()
		followers[player] = nil
	end
	local dragon = Dragons.find(id)
	if not dragon then
		return
	end
	local model = build(dragon)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local start = if root then root.CFrame else CFrame.new(0, 5, 0)
	model:PivotTo(start)
	model.Parent = folder
	followers[player] = {
		model = model,
		cf = start,
		scale = SCALE[dragon.shape] or 1,
		dragon = dragon,
		lastAttack = 0,
		target = nil,
	}
end

-- 当たったところで、光がふくらんで消える
local function burst(position: Vector3, color: Color3, size: number)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.CFrame = CFrame.new(position)
	p.Parent = folder
	TweenService:Create(p, TweenInfo.new(0.3), { Size = Vector3.one * size, Transparency = 1 }):Play()
	task.delay(0.3, function()
		p:Destroy()
	end)
end

-- 口から敵へ、光の玉を飛ばす
local function shoot(player: Player, f: Follower, enemy, headOffsetX: number)
	local attack = f.dragon.attack
	if not Enemies.isAlive(enemy) or not f.model.Parent then
		return
	end
	local from = (f.cf * CFrame.new(headOffsetX * f.scale, 1.5 * f.scale, -2.5 * f.scale)).Position
	local to = Enemies.centerOf(enemy)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * (0.8 + attack.damage / 40)
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Material = Enum.Material.Neon
	ball.Color = attack.color
	ball.CFrame = CFrame.new(from)
	local light = Instance.new("PointLight")
	light.Color = attack.color
	light.Range = 8
	light.Parent = ball
	ball.Parent = folder
	local travel = math.clamp((to - from).Magnitude / 120, 0.08, 0.45)
	TweenService:Create(ball, TweenInfo.new(travel, Enum.EasingStyle.Linear), { CFrame = CFrame.new(to) }):Play()
	task.delay(travel, function()
		ball:Destroy()
		if Enemies.isAlive(enemy) then
			burst(Enemies.centerOf(enemy), attack.color, 3 + attack.damage / 15)
			Enemies.damage(enemy, attack.damage, player)
		end
	end)
end

local TRIPLE_HEADS = { -1.8, 0, 1.8 }

local function tryAttack(player: Player, f: Follower)
	local attack = f.dragon.attack
	if not attack then
		return
	end
	local now = os.clock()
	if now - f.lastAttack < attack.cooldown then
		return
	end
	local enemy = Enemies.findNearest(f.cf.Position, attack.range)
	f.target = enemy
	if not enemy then
		return
	end
	f.lastAttack = now
	for i = 1, attack.shots do
		local headX = if attack.shots == 3 then TRIPLE_HEADS[i] else 0
		task.delay((i - 1) * 0.12, shoot, player, f, enemy, headX)
	end
end

function Dragons.start()
	folder = Instance.new("Folder")
	folder.Name = "Dragons"
	folder.Parent = workspace

	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		t += dt
		for player, f in followers do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if not root then
				continue
			end
			-- 近くの敵を自動でこうげき（持ち主が生きている間だけ）
			if humanoid and humanoid.Health > 0 then
				tryAttack(player, f)
			end
			-- 右うしろ上に浮かぶ
			local look = root.CFrame.LookVector
			local flatLook = Vector3.new(look.X, 0, look.Z)
			if flatLook.Magnitude < 0.01 then
				flatLook = Vector3.new(0, 0, -1)
			end
			flatLook = flatLook.Unit
			local right = flatLook:Cross(Vector3.yAxis)
			local bob = math.sin(t * 3) * 0.6
			local goalPos = root.Position
				+ right * (4 + f.scale * 2)
				- flatLook * (4 + f.scale * 2)
				+ Vector3.new(0, 2 + f.scale + bob, 0)
			-- 敵をねらっている間は、そちらを向く
			local faceDir = flatLook
			if f.target and Enemies.isAlive(f.target) then
				local toEnemy = Enemies.centerOf(f.target) - goalPos
				toEnemy = Vector3.new(toEnemy.X, 0, toEnemy.Z)
				if toEnemy.Magnitude > 0.1 then
					faceDir = toEnemy.Unit
				end
			end
			local goal = CFrame.lookAt(goalPos, goalPos + faceDir)
			-- 遠すぎたら瞬間移動、ふだんはなめらかに追う
			if (f.cf.Position - goalPos).Magnitude > 80 then
				f.cf = goal
			else
				f.cf = f.cf:Lerp(goal, math.min(1, dt * 8))
			end
			f.model:PivotTo(f.cf)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		Dragons.equip(player, nil)
	end)
end

return Dragons
