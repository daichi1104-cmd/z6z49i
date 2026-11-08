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
	flash: Highlight,
	joints: { [string]: Rig.Joint },
	look: Look,
	walk: number,
}

local active: { Enemy } = {}
local defeatHandler: ((Player?, Enemy) -> ())? = nil

local Rig = require(script.Parent:WaitForChild("Rig"))
local A = require(script.Parent:WaitForChild("Anatomy"))
local v, shade, tint = A.v, A.shade, A.tint
local IVORY, BLACK, MOUTH, GLOW = A.IVORY, A.BLACK, A.MOUTH, A.GLOW

-- 模型の大きさは「高さ 1」で作り、敵の size を掛ける。足のうらが y = -0.5
-- 動かす足の骨：{ name = 骨の名前, phase = 歩くリズムのずれ, axis = "x"（前後）/"y"（左右） }
type LegInfo = { name: string, phase: number, axis: string }
type Look = { legs: { LegInfo } }

type BeastOpts = {
	color: Color3,
	belly: Color3,
	mat: Enum.Material?,
	eye: Color3,
	snout: number,
	ears: boolean?,
	frill: boolean?,
	ruff: boolean?,
	horns: Color3?,
	spikes: Color3?,
	cracks: Color3?,
	tailLen: number,
	tailW: number,
	wings: boolean?,
	boss: boolean?,
}

-- 4本足の生き物（トカゲ・オオカミ・サンショウウオ・竜）
local function beast(r, o: BeastOpts): Look
	local c, m = o.color, o.mat
	r:ell(v(0.62, 0.46, 1.1), v(0, 0.02, 0.08), c, nil, m)
	r:ell(v(0.56, 0.5, 0.6), v(0, 0.05, -0.32), c, nil, m)
	r:ell(v(0.42, 0.3, 0.9), v(0, -0.1, -0.05), o.belly, nil, m)
	if o.ruff then
		-- 首まわりのふさふさの毛
		r:ell(v(0.66, 0.62, 0.42), v(0, 0.14, -0.48), tint(c, 0.4), nil, m)
	end
	if o.cracks then
		for i = -1, 1 do
			r:ell(v(0.6, 0.05, 0.08), v(0, 0.2, i * 0.3), o.cracks, v(0, i * 12, 0), GLOW)
		end
	end
	r:seg(v(0, 0.12, -0.45), v(0, 0.24, -0.62), 0.34, 0.32, c, m)
	-- 頭
	r:bone("Head", "Root", v(0, 0.22, -0.6))
	local hp = v(0, 0.29, -0.78)
	r:ell(v(0.42, 0.34, 0.44), hp, c, nil, m)
	r:seg(hp + v(0, -0.04, -0.12), hp + v(0, -0.1, -0.16 - o.snout), 0.27, 0.2, c, m)
	r:ell(v(0.26, 0.06, 0.3), hp + v(0, -0.15, -0.12 - o.snout * 0.5), MOUTH)
	for _, s in { -1, 1 } do
		-- 光る目と、するどいまゆ
		r:ball(0.1, hp + v(s * 0.15, 0.06, -0.15), o.eye, GLOW)
		r:ball(0.035, hp + v(s * 0.17, 0.08, -0.2), BLACK)
		r:ell(v(0.14, 0.05, 0.16), hp + v(s * 0.14, 0.13, -0.13), shade(c, 0.35), v(0, 0, s * -20), m)
		r:ball(0.04, hp + v(s * 0.06, -0.04, -0.2 - o.snout), BLACK)
		for i = 0, 1 do
			local z = -0.22 - o.snout * (0.4 + i * 0.35)
			r:spike(hp + v(s * 0.1, -0.13, z), hp + v(s * 0.1, -0.22, z), 0.04, IVORY)
		end
		if o.ears then
			r:spike(hp + v(s * 0.13, 0.12, 0.04), hp + v(s * 0.17, 0.32, 0.08), 0.13, c, m)
		end
		if o.horns then
			local h0 = hp + v(s * 0.12, 0.14, 0)
			local h1 = hp + v(s * 0.2, 0.3, 0.14)
			local h2 = hp + v(s * 0.22, 0.36, 0.34)
			r:limb(h0, h1, 0.07, o.horns)
			r:limb(h1, h2, 0.045, o.horns)
			if o.boss then
				r:spike(hp + v(s * 0.06, 0.16, -0.04), hp + v(s * 0.08, 0.34, -0.02), 0.06, o.horns, GLOW)
			end
		end
		if o.frill then
			for i = 0, 2 do
				local base = hp + v(s * 0.18, 0.02 - i * 0.08, 0.12)
				r:spike(base, base + v(s * 0.2, 0.1 - i * 0.08, 0.08), 0.1, tint(c, 0.3), m)
			end
		end
	end
	r:bone("Jaw", "Head", hp + v(0, -0.12, -0.04))
	r:seg(hp + v(0, -0.15, -0.08), hp + v(0, -0.17, -0.12 - o.snout * 0.9), 0.22, 0.09, o.belly, m)
	r:use("Root")
	-- 足（前右と後ろ左、前左と後ろ右が同じリズム）
	local legs = {}
	for _, s in { -1, 1 } do
		for _, z in { -0.34, 0.42 } do
			local front = z < 0
			local name = "Leg" .. (if front then "F" else "B") .. (if s < 0 then "L" else "R")
			local hip = v(s * 0.24, -0.05, z)
			r:bone(name, "Root", hip)
			local knee = v(s * 0.28, -0.28, z - 0.06)
			local ankle = v(s * 0.28, -0.45, z + 0.02)
			r:seg(hip, knee, 0.2, 0.19, c, m)
			r:seg(knee, ankle, 0.13, 0.13, c, m)
			r:ell(v(0.14, 0.06, 0.2), v(s * 0.28, -0.47, z - 0.05), c, nil, m)
			for _, x in { -1, 0, 1 } do
				local toe = v(s * 0.28 + x * 0.04, -0.47, z - 0.14)
				r:spike(toe, toe + v(0, -0.03, -0.07), 0.035, IVORY)
			end
			local inPhase = (front and s > 0) or (not front and s < 0)
			table.insert(legs, { name = name, phase = if inPhase then 0 else math.pi, axis = "x" })
		end
	end
	r:use("Root")
	if o.spikes then
		A.spines(r, v(0, 0.27, -0.35), v(0, 0.2, 0.5), 5, 0.14, 0.09, o.spikes, m)
	end
	A.tail(r, "Tail", v(0, 0.02, 0.6), v(0, -0.25, 1), 3, o.tailLen, o.tailW, c, m, o.spikes)
	r:use("Root")
	if o.wings then
		for _, s in { -1, 1 } do
			A.wing(r, s, if s < 0 then "WingL" else "WingR", {
				shoulder = v(s * 0.22, 0.22, -0.25),
				span = if o.boss then 1.6 else 1.2,
				chord = 0.75,
				bone = shade(c, 0.3),
				skin = c:Lerp(Color3.fromRGB(40, 0, 60), 0.35),
				mat = m,
			})
		end
	end
	return { legs = legs }
end

-- サソリ：8本の足、大きなはさみ、上に巻いたしっぽの毒ばり
local function scorpion(r, c: Color3): Look
	local m = Enum.Material.Slate
	local dark = shade(c, 0.35)
	r:ell(v(0.62, 0.26, 0.55), v(0, -0.12, -0.35), c, nil, m)
	for i = 0, 3 do
		local w = 0.64 - i * 0.04
		r:ell(v(w, 0.25, 0.3), v(0, -0.12, -0.05 + i * 0.17), if i % 2 == 0 then c else dark, nil, m)
	end
	for _, s in { -1, 1 } do
		r:ball(0.06, v(s * 0.07, 0.02, -0.52), Color3.fromRGB(255, 60, 40), GLOW)
	end
	local legs = {}
	for _, s in { -1, 1 } do
		for i, z in { -0.38, -0.2, -0.02, 0.16 } do
			local name = "Leg" .. (if s < 0 then "L" else "R") .. i
			local hip = v(s * 0.26, -0.13, z)
			r:bone(name, "Root", hip)
			local knee = v(s * 0.55, 0.06, z + (i - 2.5) * 0.06)
			local foot = v(s * 0.72, -0.5, z + (i - 2.5) * 0.12)
			r:seg(hip, knee, 0.08, 0.07, c, m)
			r:seg(knee, foot, 0.06, 0.055, dark, m)
			local inPhase = (i % 2 == 1) == (s < 0)
			table.insert(legs, { name = name, phase = if inPhase then 0 else math.pi, axis = "y" })
		end
		-- はさみ
		local name = if s < 0 then "ClawL" else "ClawR"
		local base = v(s * 0.2, -0.1, -0.58)
		r:bone(name, "Root", base)
		local elbow = v(s * 0.42, -0.04, -0.82)
		local wrist = v(s * 0.36, -0.05, -1.04)
		r:seg(base, elbow, 0.12, 0.1, c, m)
		r:seg(elbow, wrist, 0.11, 0.1, c, m)
		r:ell(v(0.24, 0.14, 0.32), wrist + v(0, 0, -0.12), c, nil, m)
		r:spike(wrist + v(s * -0.05, 0, -0.24), wrist + v(s * -0.08, 0, -0.44), 0.07, dark, m)
		r:spike(wrist + v(s * 0.06, 0, -0.24), wrist + v(s * 0.02, 0, -0.42), 0.07, dark, m)
		table.insert(legs, { name = name, phase = if s < 0 then 0 else math.pi, axis = "claw" })
	end
	-- しっぽ：後ろから上へ、前へと巻く
	local dirs = { v(0, 0.55, 1), v(0, 1, 0.45), v(0, 1, -0.25), v(0, 0.55, -1), v(0, -0.1, -1) }
	local p = v(0, -0.08, 0.6)
	local parent = "Root"
	for i, d in dirs do
		local name = "Tail" .. i
		r:bone(name, parent, p)
		local q = p + d.Unit * 0.22
		local w = 0.2 - i * 0.015
		r:seg(p, q, w, w * 0.9, if i % 2 == 0 then dark else c, m)
		parent = name
		p = q
	end
	r:ell(v(0.14, 0.14, 0.18), p + v(0, -0.02, -0.06), dark, nil, m)
	r:spike(p + v(0, -0.04, -0.12), p + v(0, -0.16, -0.26), 0.06, BLACK)
	r:use("Root")
	return { legs = legs }
end

local function buildEnemy(zoneIndex: number, boss: boolean, size: number, color: Color3)
	local r = Rig.new(if boss then "Boss" else "Enemy", size)
	local look: Look
	if zoneIndex == 1 then
		-- 草原：えりまきのある大トカゲ
		look = beast(r, {
			color = color,
			belly = tint(color, 0.55),
			mat = Enum.Material.Slate,
			eye = Color3.fromRGB(255, 220, 40),
			snout = 0.28,
			frill = true,
			spikes = shade(color, 0.35),
			tailLen = 1.1,
			tailW = 0.3,
		})
	elseif zoneIndex == 2 then
		-- 砂漠：大サソリ
		look = scorpion(r, color)
	elseif zoneIndex == 3 then
		-- 雪原：こおりのオオカミ
		look = beast(r, {
			color = color:Lerp(Color3.new(1, 1, 1), 0.45),
			belly = Color3.fromRGB(240, 248, 255),
			mat = Enum.Material.Sand,
			eye = Color3.fromRGB(120, 230, 255),
			snout = 0.34,
			ears = true,
			ruff = true,
			tailLen = 0.75,
			tailW = 0.32,
		})
	elseif zoneIndex == 4 then
		-- 火山：ようがんのサンショウウオ
		look = beast(r, {
			color = Color3.fromRGB(55, 40, 38),
			belly = shade(color, 0.3),
			mat = Enum.Material.Basalt,
			eye = Color3.fromRGB(255, 170, 40),
			snout = 0.24,
			horns = Color3.fromRGB(35, 25, 25),
			spikes = color,
			cracks = color,
			tailLen = 1,
			tailW = 0.34,
		})
	else
		-- 雲の上：あらしの竜（ボスはさらに大きなつばさと光る角）
		look = beast(r, {
			color = color,
			belly = tint(color, 0.4),
			mat = Enum.Material.Slate,
			eye = Color3.fromRGB(255, 90, 220),
			snout = 0.36,
			horns = Color3.fromRGB(240, 230, 255),
			spikes = Color3.fromRGB(240, 230, 255),
			tailLen = 1.2,
			tailW = 0.26,
			wings = true,
			boss = boss,
		})
	end
	return r:finish(), r.root, r.joints, look
end

function Enemies.spawn(home: Vector3, zoneIndex: number, boss: boolean, parent: Instance)
	local zone = Config.Zones[zoneIndex]
	local size = if boss then 12 else 4 + zoneIndex * 0.6

	local model, body, joints, look = buildEnemy(zoneIndex, boss, size, zone.enemyColor)
	body.Name = "Body"
	-- 当たったときに白く光らせる
	local flash = Instance.new("Highlight")
	flash.FillColor = Color3.new(1, 1, 1)
	flash.FillTransparency = 0.35
	flash.OutlineTransparency = 1
	flash.Enabled = false
	flash.Parent = model
	body.CFrame = CFrame.new(home + Vector3.new(0, size / 2, 0))
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
		flash = flash,
		joints = joints,
		look = look,
		walk = 0,
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
	e.flash.Enabled = true
	task.delay(0.1, function()
		e.flash.Enabled = false
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

-- 歩く足・ゆれるしっぽ・羽ばたき・かみつくあご
local function animate(e: Enemy, t: number, moving: number, chasing: boolean)
	local time = t + e.phase
	for _, info in e.look.legs do
		local swing = math.sin(e.walk + info.phase) * moving
		local joint = e.joints[info.name]
		if info.axis == "x" then
			Rig.turn(joint, swing * 35, 0, 0)
		elseif info.axis == "y" then
			Rig.turn(joint, 0, swing * 18, math.abs(swing) * 8)
		else
			-- はさみ：ふりあげたり下ろしたり
			Rig.turn(joint, 10 + math.sin(time * 4 + info.phase) * 12, 0, 0)
		end
	end
	for name, joint in e.joints do
		if string.sub(name, 1, 4) == "Tail" then
			local i = tonumber(string.match(name, "(%d+)$")) or 1
			if e.zoneIndex == 2 then
				Rig.turn(joint, math.sin(time * 3 - i * 0.6) * 6, 0, 0)
			else
				Rig.turn(joint, 0, math.sin(time * 3 - i * 0.8) * (10 + i * 4), 0)
			end
		elseif name == "WingL" or name == "WingR" then
			local side = if name == "WingL" then -1 else 1
			Rig.turn(joint, 0, 0, side * math.sin(time * 5) * 30)
		elseif name == "Jaw" then
			local open = if chasing then -10 - (math.sin(time * 8) + 1) * 12 else -3
			Rig.turn(joint, open, 0, 0)
		elseif name == "Head" then
			Rig.turn(joint, math.sin(time * 2) * 4, math.sin(time * 1.3) * 8, 0)
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
					e.body.CFrame = CFrame.new(e.home + Vector3.new(0, e.size / 2, 0))
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
			local moving = 0
			if dist > 0.5 then
				local speed = if target then e.speed else e.speed * 0.6
				local step = math.min(speed * dt, dist)
				e.facing = toGoal.Unit
				e.pos = flat(e.pos) + e.facing * step
				-- 進んだ距離に合わせて足を動かす（大きい敵ほどゆっくり大またで歩く）
				e.walk += step / e.size * 4
				moving = 1
			end

			local bob = math.abs(math.sin(e.walk)) * e.size * 0.04 * moving
			local center = e.pos + Vector3.new(0, e.size / 2 + bob, 0)
			e.body.CFrame = CFrame.lookAt(center, center + e.facing)
			animate(e, t, moving, target ~= nil)

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
