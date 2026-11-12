-- 塔のぼりモード：1階ずつ敵をたおして上をめざす（5階ごとにボス）
-- 部屋は空の高いところに、プレイヤーごとに作る（ほかの人とは会わない）

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Enemies = require(script.Parent:WaitForChild("Enemies"))

local Tower = {}

type Run = {
	slot: number,
	floor: number,
	center: Vector3,
	arena: Model,
	enemies: { any },
	sign: TextLabel,
	clearing: boolean,
}

local runs: { [Player]: Run } = {}
local usedSlots: { [number]: boolean } = {}
local folder: Folder
local enemyFolder: Folder

-- Main が登録する：階をクリアしたとき・塔を出たとき
local handlers = {
	cleared = function(_player: Player, _floor: number, _reward: number) end,
	ended = function(_player: Player, _floor: number) end,
	notify = function(_player: Player, _msg: string, _good: boolean?) end,
	home = function(_player: Player) end,
}

function Tower.init(h)
	for k, fn in h do
		handlers[k] = fn
	end
	folder = Instance.new("Folder")
	folder.Name = "Tower"
	folder.Parent = workspace
	enemyFolder = Instance.new("Folder")
	enemyFolder.Name = "TowerEnemies"
	enemyFolder.Parent = workspace
end

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

-- 塔の部屋：石の床、光るもようの円、まわりの柱と見えない壁
local function buildArena(center: Vector3): (Model, TextLabel)
	local model = Instance.new("Model")
	model.Name = "Arena"
	local size = Config.Tower.size
	part({
		Name = "Floor",
		Size = Vector3.new(size, 4, size),
		CFrame = CFrame.new(center - Vector3.new(0, 2, 0)),
		Color = Color3.fromRGB(80, 78, 95),
		Material = Enum.Material.Slate,
	}, model)
	local ring = part({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, size * 0.7, size * 0.7),
		CFrame = CFrame.new(center + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(150, 110, 255),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = 0.4,
	}, model)
	ring.CastShadow = false
	part({
		Name = "Inner",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.25, size * 0.66, size * 0.66),
		CFrame = CFrame.new(center + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(70, 68, 85),
		Material = Enum.Material.Slate,
		CanCollide = false,
	}, model)
	-- まわりの柱（上に光る火）と、低いへい
	for i = 0, 31 do
		local a = i / 32 * math.pi * 2
		local pos = center + Vector3.new(math.cos(a), 0, math.sin(a)) * (size / 2 - 4)
		part({
			Name = "Pillar",
			Size = Vector3.new(4, 24, 4),
			CFrame = CFrame.new(pos + Vector3.new(0, 12, 0)),
			Color = Color3.fromRGB(110, 105, 125),
			Material = Enum.Material.Cobblestone,
		}, model)
		local flame = part({
			Name = "Flame",
			Size = Vector3.new(2, 2, 2),
			CFrame = CFrame.new(pos + Vector3.new(0, 25, 0)),
			Color = Color3.fromRGB(170, 120, 255),
			Material = Enum.Material.Neon,
			CanCollide = false,
		}, model)
		local light = Instance.new("PointLight")
		light.Color = flame.Color
		light.Range = 30
		light.Brightness = 2
		light.Parent = flame
	end
	-- 広い部屋が 暗くならないように、うかぶ明かりを ます目に ならべる
	local lamps = math.max(2, math.floor(size / 80))
	local gap = size / lamps
	for ix = 1, lamps do
		for iz = 1, lamps do
			local offset = Vector3.new((ix - 0.5) * gap - size / 2, 34, (iz - 0.5) * gap - size / 2)
			local lamp = part({
				Name = "Lamp",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(3, 3, 3),
				CFrame = CFrame.new(center + offset),
				Color = Color3.fromRGB(190, 150, 255),
				Material = Enum.Material.Neon,
				CanCollide = false,
			}, model)
			lamp.CastShadow = false
			local lampLight = Instance.new("PointLight")
			lampLight.Color = lamp.Color
			lampLight.Range = 60
			lampLight.Brightness = 1.5
			lampLight.Parent = lamp
		end
	end
	for _, d in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local along = Vector3.new(math.abs(d.Z), 0, math.abs(d.X))
		part({
			Name = "Rim",
			Size = along * size + Vector3.new(2, 3, 2),
			CFrame = CFrame.new(center + d * (size / 2) + Vector3.new(0, 1.5, 0)),
			Color = Color3.fromRGB(95, 90, 110),
			Material = Enum.Material.Cobblestone,
		}, model)
		part({
			Name = "Wall",
			Size = along * size + Vector3.new(2, 80, 2),
			CFrame = CFrame.new(center + d * (size / 2) + Vector3.new(0, 40, 0)),
			Transparency = 1,
		}, model)
	end
	part({
		Name = "Ceiling",
		Size = Vector3.new(size, 2, size),
		CFrame = CFrame.new(center + Vector3.new(0, 80, 0)),
		Transparency = 1,
	}, model)
	-- 何階かを出す看板
	local signPart = part({
		Name = "Sign",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(center + Vector3.new(0, 20 + size / 12, -size / 2 + 6)),
		Transparency = 1,
		CanCollide = false,
	}, model)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(size / 4, 0, size / 20, 0)
	bb.LightInfluence = 0
	bb.MaxDistance = 1200
	bb.Adornee = signPart
	bb.Parent = signPart
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(220, 200, 255)
	text.TextStrokeTransparency = 0.2
	text.Parent = bb
	model.Parent = folder
	return model, text
end

local function clearEnemies(run: Run)
	for _, e in run.enemies do
		Enemies.remove(e)
	end
	table.clear(run.enemies)
end

local function spawnFloor(player: Player, run: Run)
	local info = Config.towerFloor(run.floor)
	run.clearing = false
	run.sign.Text = if info.boss
		then string.format("🗼 %d階　👑 ボスの部屋", run.floor)
		else string.format("🗼 %d階", run.floor)
	local zone = Config.Zones[info.look]
	for i = 1, info.count do
		local isBoss = info.boss and i == 1
		local a = (i / info.count) * math.pi * 2
		-- 敵は まん中の近くに出す（部屋が広くても 遠くなりすぎないように）
		local s = math.min(Config.Tower.size / 120, 2)
		local offset = if info.count == 1
			then Vector3.new(0, 0, -30 * s)
			else Vector3.new(math.cos(a) * 28 * s, 0, (-20 + math.sin(a) * 18) * s)
		local e = Enemies.spawn(run.center + offset, info.look, isBoss, enemyFolder, {
			hp = if isBoss then info.hp * 6 else info.hp,
			speed = info.speed,
			damage = if isBoss then info.damage * 1.5 else info.damage,
			size = if isBoss then 12 else 4 + math.min(run.floor, 20) * 0.15,
			noRespawn = true,
			aggro = 400,
			leash = 400,
			tag = "tower",
			owner = player,
			name = if isBoss
				then string.format("👑 塔のぬし（%s）", zone.enemyName or zone.name)
				else "塔の" .. (zone.enemyName or zone.name),
		})
		table.insert(run.enemies, e)
	end
	handlers.notify(
		player,
		if info.boss
			then string.format("👑 %d階：ボスがあらわれた！", run.floor)
			else string.format("🗼 %d階：敵を %d 体 たおそう", run.floor, info.count)
	)
end

function Tower.isInside(player: Player): boolean
	return runs[player] ~= nil
end

function Tower.floorOf(player: Player): number?
	local run = runs[player]
	return if run then run.floor else nil
end

function Tower.enter(player: Player): (boolean, string)
	if runs[player] then
		return false, "もう塔の中にいます"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false, "いまは入れません"
	end
	local slot = 1
	while usedSlots[slot] do
		slot += 1
	end
	usedSlots[slot] = true
	local center = Vector3.new(2000 + slot * Config.Tower.spacing, Config.Tower.arenaY, 0)
	local arena, sign = buildArena(center)
	local run: Run = {
		slot = slot,
		floor = 1,
		center = center,
		arena = arena,
		enemies = {},
		sign = sign,
		clearing = false,
	}
	runs[player] = run
	character:PivotTo(
		CFrame.new(center + Vector3.new(0, 4, math.min(Config.Tower.size / 3, 80))) * CFrame.Angles(0, 0, 0)
	)
	player:SetAttribute("TowerFloor", 1)
	spawnFloor(player, run)
	return true, "🗼 塔に入った！ 上をめざそう（🏠 ベースへ で出られる）"
end

-- 塔を出る（やられた・ベースへ戻る・ゲームを出た）
function Tower.leave(player: Player, sendHome: boolean)
	local run = runs[player]
	if not run then
		return
	end
	runs[player] = nil
	clearEnemies(run)
	run.arena:Destroy()
	usedSlots[run.slot] = nil
	if player.Parent then
		player:SetAttribute("TowerFloor", nil)
	end
	handlers.ended(player, run.floor - 1)
	if sendHome then
		handlers.home(player)
	end
end

-- 敵がたおされたら呼ぶ。その階の敵が全部いなくなったら、次の階へ
function Tower.onEnemyDefeated(enemy)
	local player = enemy.owner
	local run = player and runs[player]
	if not run or run.clearing then
		return
	end
	for _, e in run.enemies do
		if e ~= enemy and Enemies.isAlive(e) then
			return
		end
	end
	run.clearing = true
	local floor = run.floor
	local reward = Config.towerFloor(floor).reward
	handlers.cleared(player, floor, reward)
	run.sign.Text = string.format("🎉 %d階 クリア！", floor)
	task.delay(Config.Tower.rest, function()
		if runs[player] ~= run then
			return
		end
		table.clear(run.enemies)
		run.floor = floor + 1
		player:SetAttribute("TowerFloor", run.floor)
		spawnFloor(player, run)
	end)
end

-- 部屋から落ちたら、塔を出る
task.spawn(function()
	while true do
		task.wait(1)
		for player, run in runs do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and root.Position.Y < run.center.Y - 40 then
				Tower.leave(player, true)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	Tower.leave(player, false)
end)

return Tower
