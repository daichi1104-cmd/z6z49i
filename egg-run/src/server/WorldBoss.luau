-- みんなのボス：決まった時間に 空の上の闘技場に 大きなボスが出る。サーバーの全員で いっしょに戦う
-- ・ベースのうしろの「光の門」から入る（ボスが出ている間だけ）
-- ・たおすと、ダメージを与えた人 全員が ごほうびをもらえる（いちばん活やくした人は 多め）
-- ・時間内に たおせないと、ボスは にげる

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Sounds = require(Shared:WaitForChild("Sounds"))
local Enemies = require(script.Parent:WaitForChild("Enemies"))

local WorldBoss = {}

local WB = Config.WorldBoss
local BOSS_NAME = "大魔竜"
local STONE = Color3.fromRGB(92, 70, 70)
local FIRE = Color3.fromRGB(255, 110, 60)

-- Main が登録する
local handlers = {
	notify = function(_player: Player, _msg: string, _good: boolean?) end,
	home = function(_player: Player) end,
	-- その人の「1秒あたりのこうげき力」
	power = function(_player: Player): number
		return 10
	end,
	-- ごほうびをわたす（share = 与えたダメージの割合 0〜1、mvp = いちばん活やくしたか）
	reward = function(_player: Player, _share: number, _mvp: boolean) end,
}

local inside: { [Player]: boolean } = {}
local boss: any = nil
local bossWindow = -1 -- ボスを出した回（同じ回に 2度 出さない）
local sign: TextLabel
local gateText: TextLabel
local enemyFolder: Folder

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function billboard(adornee: BasePart, width: number, height: number, color: Color3): TextLabel
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(width, 0, height, 0)
	bb.LightInfluence = 0
	bb.MaxDistance = 600
	bb.Adornee = adornee
	bb.Parent = adornee
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.TextColor3 = color
	text.TextStrokeTransparency = 0.2
	text.Parent = bb
	return text
end

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- 空の上の闘技場：石の床、赤く光る円、まわりの柱、見えない壁、明かり
local function buildArena(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "BossArena"
	local center = WB.center
	local size = WB.arena
	part({
		Name = "Floor",
		Size = Vector3.new(size, 4, size),
		CFrame = CFrame.new(center - Vector3.new(0, 2, 0)),
		Color = STONE,
		Material = Enum.Material.Slate,
	}, model)
	local ring = part({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, size * 0.5, size * 0.5),
		CFrame = CFrame.new(center + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = FIRE,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = 0.45,
	}, model)
	ring.CastShadow = false
	part({
		Name = "Inner",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.25, size * 0.47, size * 0.47),
		CFrame = CFrame.new(center + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(80, 60, 60),
		Material = Enum.Material.Slate,
		CanCollide = false,
	}, model)
	for i = 0, 19 do
		local a = i / 20 * math.pi * 2
		local pos = center + Vector3.new(math.cos(a), 0, math.sin(a)) * (size / 2 - 4)
		part({
			Name = "Pillar",
			Size = Vector3.new(5, 30, 5),
			CFrame = CFrame.new(pos + Vector3.new(0, 15, 0)),
			Color = Color3.fromRGB(120, 100, 100),
			Material = Enum.Material.Cobblestone,
		}, model)
		local flame = part({
			Name = "Flame",
			Size = Vector3.new(3, 3, 3),
			CFrame = CFrame.new(pos + Vector3.new(0, 32, 0)),
			Color = FIRE,
			Material = Enum.Material.Neon,
			CanCollide = false,
		}, model)
		local light = Instance.new("PointLight")
		light.Color = FIRE
		light.Range = 40
		light.Brightness = 2
		light.Parent = flame
	end
	-- まん中が暗くならないように、うかぶ明かりを ます目に ならべる
	local lamps = math.max(2, math.floor(size / 65))
	local gap = size / lamps
	for ix = 1, lamps do
		for iz = 1, lamps do
			local offset = Vector3.new((ix - 0.5) * gap - size / 2, 38, (iz - 0.5) * gap - size / 2)
			local lamp = part({
				Name = "Lamp",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(3, 3, 3),
				CFrame = CFrame.new(center + offset),
				Color = Color3.fromRGB(255, 190, 140),
				Material = Enum.Material.Neon,
				CanCollide = false,
			}, model)
			lamp.CastShadow = false
			local lampLight = Instance.new("PointLight")
			lampLight.Color = lamp.Color
			lampLight.Range = 60
			lampLight.Brightness = 1.6
			lampLight.Parent = lamp
		end
	end
	for _, d in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local along = Vector3.new(math.abs(d.Z), 0, math.abs(d.X))
		part({
			Name = "Rim",
			Size = along * size + Vector3.new(2, 3, 2),
			CFrame = CFrame.new(center + d * (size / 2) + Vector3.new(0, 1.5, 0)),
			Color = Color3.fromRGB(110, 90, 90),
			Material = Enum.Material.Cobblestone,
		}, model)
		part({
			Name = "Wall",
			Size = along * size + Vector3.new(2, 90, 2),
			CFrame = CFrame.new(center + d * (size / 2) + Vector3.new(0, 45, 0)),
			Transparency = 1,
		}, model)
	end
	part({
		Name = "Ceiling",
		Size = Vector3.new(size, 2, size),
		CFrame = CFrame.new(center + Vector3.new(0, 90, 0)),
		Transparency = 1,
	}, model)
	local signPart = part({
		Name = "Sign",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(center + Vector3.new(0, 48, -size / 2 + 6)),
		Transparency = 1,
		CanCollide = false,
	}, model)
	sign = billboard(signPart, 90, 14, Color3.fromRGB(255, 210, 190))
	model.Parent = parent
end

-- ベースにある 入口の門：石のアーチと 赤く光る まく。近づいてボタンを長押しで 入る
local function buildGate(parent: Instance): ProximityPrompt
	local model = Instance.new("Model")
	model.Name = "BossGate"
	local origin = WB.gate
	part({
		Name = "Base",
		Size = Vector3.new(16, 1, 8),
		CFrame = CFrame.new(origin + Vector3.new(0, 0.5, 0)),
		Color = STONE,
		Material = Enum.Material.Cobblestone,
	}, model)
	for _, x in { -6, 6 } do
		part({
			Name = "Post",
			Size = Vector3.new(3, 14, 3),
			CFrame = CFrame.new(origin + Vector3.new(x, 8, 0)),
			Color = Color3.fromRGB(120, 100, 100),
			Material = Enum.Material.Cobblestone,
		}, model)
		local flame = part({
			Name = "Flame",
			Size = Vector3.new(2, 2, 2),
			CFrame = CFrame.new(origin + Vector3.new(x, 18.5, 0)),
			Color = FIRE,
			Material = Enum.Material.Neon,
			CanCollide = false,
		}, model)
		local light = Instance.new("PointLight")
		light.Color = FIRE
		light.Range = 24
		light.Brightness = 2
		light.Parent = flame
	end
	part({
		Name = "Top",
		Size = Vector3.new(17, 3, 4),
		CFrame = CFrame.new(origin + Vector3.new(0, 16.5, 0)),
		Color = STONE,
		Material = Enum.Material.Cobblestone,
	}, model)
	local veil = part({
		Name = "Veil",
		Size = Vector3.new(9, 14, 0.6),
		CFrame = CFrame.new(origin + Vector3.new(0, 8, 0)),
		Color = FIRE,
		Material = Enum.Material.Neon,
		Transparency = 0.5,
		CanCollide = false,
	}, model)
	veil.CastShadow = false
	local title = part({
		Name = "Title",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(origin + Vector3.new(0, 23, 0)),
		Transparency = 1,
		CanCollide = false,
	}, model)
	gateText = billboard(title, 26, 6, Color3.fromRGB(255, 200, 180))
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "ボスと戦う"
	prompt.ObjectText = "みんなのボス（全員で たおして ごほうび）"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = veil
	model.Parent = parent
	return prompt
end

function WorldBoss.isInside(player: Player): boolean
	return inside[player] == true
end

-- 闘技場を出る（やられた・ベースへ戻る・ボスがいなくなった）
function WorldBoss.leave(player: Player, sendHome: boolean)
	if not inside[player] then
		return
	end
	inside[player] = nil
	if player.Parent then
		player:SetAttribute("InBossArena", nil)
		if sendHome then
			handlers.home(player)
		end
	end
end

function WorldBoss.enter(player: Player): (boolean, string)
	if inside[player] then
		return false, "もう闘技場にいます"
	end
	if not boss or not Enemies.isAlive(boss) then
		local _, nextStart = Config.worldBossWindow(os.time())
		return false,
			string.format("👑 ボスは まだ出ていません（あと %s）", clock(nextStart - os.time()))
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false, "いまは入れません"
	end
	inside[player] = true
	player:SetAttribute("InBossArena", true)
	-- 入口は はしのほう。ボスは まん中にいる
	local spot = WB.center + Vector3.new(math.random(-30, 30), 4, WB.arena / 2 - 30)
	character:PivotTo(CFrame.lookAt(spot, Vector3.new(WB.center.X, spot.Y, WB.center.Z)))
	return true,
		string.format(
			"👑 %sとの戦い！ みんなで力を合わせよう（🏠 ベースへ で出られる）",
			BOSS_NAME
		)
end

local function everyone(msg: string, good: boolean?)
	for _, player in Players:GetPlayers() do
		handlers.notify(player, msg, good)
	end
end

-- 少し待ってから、闘技場にいる全員を ベースへ帰す
local function sendAllHome(delaySeconds: number)
	task.delay(delaySeconds, function()
		if boss then
			return -- 次のボスが もう出ている
		end
		for player in inside do
			WorldBoss.leave(player, true)
		end
	end)
end

local function spawnBoss()
	local total = 0
	for _, player in Players:GetPlayers() do
		total += handlers.power(player)
	end
	local hp = math.max(WB.minHp, math.floor(total * WB.fightSeconds))
	boss = Enemies.spawn(WB.center, 5, true, enemyFolder, {
		hp = hp,
		speed = WB.speed,
		damage = WB.damage,
		size = WB.size,
		noRespawn = true,
		aggro = 600,
		leash = 600,
		tag = "world",
		name = "👑 " .. BOSS_NAME,
	})
	Sounds.at(WB.gate + Vector3.new(0, 8, 0), "roar")
	everyone(
		string.format(
			"👑 みんなのボス「%s」が あらわれた！ ベースのうしろの 赤い門から 行こう",
			BOSS_NAME
		),
		true
	)
end

-- ボスがたおされたら Main から呼ぶ：ダメージを与えた全員に ごほうび
function WorldBoss.onDefeated(enemy: any)
	if enemy ~= boss then
		return
	end
	boss = nil
	local total = 0
	local mvp: Player? = nil
	local best = 0
	for player, amount in enemy.dealt do
		if player.Parent then
			total += amount
			if amount > best then
				best = amount
				mvp = player
			end
		end
	end
	for player, amount in enemy.dealt do
		if player.Parent and amount > 0 then
			handlers.reward(player, amount / math.max(total, 1), player == mvp)
		end
	end
	sign.Text = string.format("🎉 %sを たおした！", BOSS_NAME)
	everyone(
		if mvp
			then string.format(
				"👑 みんなのボス「%s」を たおした！ いちばんの活やく：%s",
				BOSS_NAME,
				mvp.DisplayName
			)
			else string.format("👑 みんなのボス「%s」を たおした！", BOSS_NAME),
		true
	)
	sendAllHome(8)
end

function WorldBoss.init(h, parent: Instance, enemies: Folder): ProximityPrompt
	for k, fn in h do
		handlers[k] = fn
	end
	enemyFolder = enemies
	buildArena(parent)
	local prompt = buildGate(parent)

	task.spawn(function()
		while true do
			local now = os.time()
			local start, nextStart = Config.worldBossWindow(now)
			local open = now - start < WB.duration
			workspace:SetAttribute("BossNext", nextStart)
			if open and bossWindow ~= start and #Players:GetPlayers() > 0 then
				bossWindow = start
				spawnBoss()
			elseif not open and boss then
				-- 時間切れ：ボスは にげる
				Enemies.remove(boss)
				boss = nil
				sign.Text = "💨 ボスは にげていった…"
				everyone(
					string.format(
						"💨 みんなのボス「%s」は にげていった… 次こそ たおそう",
						BOSS_NAME
					)
				)
				sendAllHome(5)
			end
			local alive = boss ~= nil and Enemies.isAlive(boss)
			workspace:SetAttribute("BossEnd", if alive then start + WB.duration else 0)
			if alive then
				local left = clock(start + WB.duration - now)
				sign.Text = string.format(
					"👑 %s　のこり %d%%　⏳ %s",
					BOSS_NAME,
					math.ceil(boss.hp / boss.maxHp * 100),
					left
				)
				gateText.Text = string.format("👑 ボス出現中！ ⏳ %s", left)
			else
				gateText.Text = string.format("👑 みんなのボス　あと %s", clock(nextStart - now))
			end
			-- 闘技場から落ちた人は ベースへ
			for player in inside do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and root.Position.Y < WB.center.Y - 40 then
					WorldBoss.leave(player, true)
				end
			end
			task.wait(0.5)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		inside[player] = nil
	end)
	return prompt
end

return WorldBoss
