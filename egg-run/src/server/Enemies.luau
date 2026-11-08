-- たまごを守る敵：近づいたプレイヤーを追いかけ、ぶつかるとダメージ
-- たまごから一定以上はなれると、あきらめて持ち場に戻る

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Enemies = {}

type Enemy = {
	model: Model,
	home: Vector3,
	pos: Vector3,
	facing: Vector3,
	speed: number,
	damage: number,
	size: number,
	phase: number,
	lastHit: { [Player]: number },
	zoneIndex: number,
	boss: boolean,
	hp: number,
	maxHp: number,
	dead: boolean,
	respawnAt: number,
	parent: Instance,
	body: BasePart,
	baseColor: Color3,
	bar: Frame,
}

local active: { Enemy } = {}
local defeatHandler: ((Player?, Enemy) -> ())? = nil

local function piece(
	model: Model,
	shape: Enum.PartType,
	size: Vector3,
	offset: Vector3,
	color: Color3,
	material: Enum.Material?
)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CFrame = CFrame.new(offset)
	p.Parent = model
	return p
end

function Enemies.spawn(home: Vector3, zoneIndex: number, boss: boolean, parent: Instance)
	local zone = Config.Zones[zoneIndex]
	local size = if boss then 12 else 4 + zoneIndex * 0.6

	local model = Instance.new("Model")
	model.Name = if boss then "Boss" else "Enemy"
	local body = piece(model, Enum.PartType.Ball, Vector3.one * size, Vector3.zero, zone.enemyColor)
	body.Name = "Body"
	-- 目（-Z 方向が前）
	for _, side in { -1, 1 } do
		piece(
			model,
			Enum.PartType.Ball,
			Vector3.one * size * 0.28,
			Vector3.new(side * size * 0.2, size * 0.15, -size * 0.4),
			Color3.new(1, 1, 1)
		)
		piece(
			model,
			Enum.PartType.Ball,
			Vector3.one * size * 0.14,
			Vector3.new(side * size * 0.2, size * 0.15, -size * 0.52),
			Color3.fromRGB(20, 20, 20)
		)
		-- 角
		piece(
			model,
			Enum.PartType.Block,
			Vector3.new(size * 0.12, size * 0.35, size * 0.12),
			Vector3.new(side * size * 0.25, size * 0.5, -size * 0.1),
			Color3.fromRGB(40, 30, 30)
		)
	end
	model.PrimaryPart = body
	model:PivotTo(CFrame.new(home + Vector3.new(0, size / 2, 0)))
	model.Parent = parent

	if boss then
		local light = Instance.new("PointLight")
		light.Color = zone.enemyColor
		light.Range = 20
		light.Parent = body
	end

	-- 体力ゲージ
	local gauge = Instance.new("BillboardGui")
	gauge.Size = UDim2.new(size * 0.9, 0, 0.5 + size * 0.04, 0)
	gauge.StudsOffset = Vector3.new(0, size * 0.75, 0)
	gauge.MaxDistance = 120
	gauge.LightInfluence = 0
	gauge.Adornee = body
	gauge.Parent = model
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(40, 20, 20)
	back.BorderSizePixel = 0
	back.Parent = gauge
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
	bar.BorderSizePixel = 0
	bar.Parent = back

	local maxHp = zone.enemyHealth * (if boss then Config.BossHealthMult else 1)
	table.insert(active, {
		model = model,
		home = home,
		pos = home,
		facing = Vector3.new(0, 0, 1),
		speed = if boss then zone.enemySpeed * 0.9 else zone.enemySpeed,
		damage = if boss then zone.damage * 1.5 else zone.damage,
		size = size,
		phase = math.random() * 10,
		lastHit = {},
		zoneIndex = zoneIndex,
		boss = boss,
		hp = maxHp,
		maxHp = maxHp,
		dead = false,
		respawnAt = 0,
		parent = parent,
		body = body,
		baseColor = zone.enemyColor,
		bar = bar,
	})
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function centerOf(e: Enemy): Vector3
	return e.body.Position
end
Enemies.centerOf = centerOf

-- position から range 以内で一番近い、生きている敵
function Enemies.findNearest(position: Vector3, range: number): Enemy?
	local best, bestDist = nil, range
	for _, e in active do
		if not e.dead then
			local d = (centerOf(e) - position).Magnitude
			if d < bestDist then
				best, bestDist = e, d
			end
		end
	end
	return best
end

function Enemies.isAlive(e: Enemy): boolean
	return not e.dead
end

-- たおしたときに呼ばれる関数を登録（だれがたおしたか、どの敵か）
function Enemies.onDefeated(handler: (Player?, Enemy) -> ())
	defeatHandler = handler
end

function Enemies.damage(e: Enemy, amount: number, attacker: Player?)
	if e.dead then
		return
	end
	e.hp = math.max(0, e.hp - amount)
	e.bar.Size = UDim2.fromScale(e.hp / e.maxHp, 1)
	-- 当たったら一瞬白く光る
	e.body.Color = Color3.new(1, 1, 1)
	task.delay(0.1, function()
		e.body.Color = e.baseColor
	end)
	if e.hp <= 0 then
		e.dead = true
		e.respawnAt = os.clock() + (if e.boss then Config.BossRespawnTime else Config.EnemyRespawnTime)
		e.model.Parent = nil
		if defeatHandler then
			defeatHandler(attacker, e)
		end
	end
end

-- getDamageMult(player) は、よろいやドラゴンで減ったあとのダメージ倍率を返す
function Enemies.start(getDamageMult: (Player) -> number, onHit: ((Player, Vector3) -> ())?)
	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		t += dt
		-- 生きているプレイヤーの位置を先に集める
		local targets = {}
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 then
				table.insert(targets, { player = player, root = root, humanoid = humanoid })
			end
		end

		for _, e in active do
			-- たおされた敵は、時間がたつと持ち場で復活する
			if e.dead then
				if os.clock() >= e.respawnAt then
					e.dead = false
					e.hp = e.maxHp
					e.bar.Size = UDim2.fromScale(1, 1)
					e.pos = e.home
					e.model:PivotTo(CFrame.new(e.home + Vector3.new(0, e.size / 2, 0)))
					e.model.Parent = e.parent
				end
				continue
			end
			-- 近くにだれもいない敵は動かさない
			local target = nil
			local best = Config.EnemyAggroRange
			local anyoneNear = false
			for _, info in targets do
				local p = flat(info.root.Position)
				local fromHome = (p - flat(e.home)).Magnitude
				if fromHome < 300 then
					anyoneNear = true
				end
				local d = (p - flat(e.pos)).Magnitude
				if d < best and fromHome < Config.EnemyLeashRange then
					best = d
					target = info
				end
			end
			if not anyoneNear then
				continue
			end

			local goal = if target then flat(target.root.Position) else flat(e.home)
			local toGoal = goal - flat(e.pos)
			local dist = toGoal.Magnitude
			if dist > 0.5 then
				local speed = if target then e.speed else e.speed * 0.6
				local step = math.min(speed * dt, dist)
				e.facing = toGoal.Unit
				e.pos = flat(e.pos) + e.facing * step
			end

			local hop = math.abs(math.sin(t * 7 + e.phase)) * (e.size * 0.25)
			local center = e.pos + Vector3.new(0, e.size / 2 + hop, 0)
			e.model:PivotTo(CFrame.lookAt(center, center + e.facing))

			-- ぶつかったらダメージ（同じ敵からは 1 秒に 1 回まで）
			if target then
				local reach = e.size / 2 + 2.5
				if (target.root.Position - center).Magnitude < reach then
					local now = os.clock()
					if now - (e.lastHit[target.player] or 0) > 1 then
						e.lastHit[target.player] = now
						target.humanoid:TakeDamage(e.damage * getDamageMult(target.player))
						-- はじき飛ばす（キャラの動きはプレイヤー側で計算しているので、向こうで処理する）
						if onHit then
							onHit(target.player, e.facing)
						end
					end
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		for _, e in active do
			e.lastHit[player] = nil
		end
	end)
end

return Enemies
