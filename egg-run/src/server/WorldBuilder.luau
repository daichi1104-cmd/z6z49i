-- マップを組み立てる：ベース（ルームランナー・ショップ・巣）と、遠くへ続くたまごの道
-- ベースの中心は原点。道は -Z 方向（スポーンしたときに向いている方向）へ伸びる

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local WorldBuilder = {}

local HUB_HALF = 80 -- ベースの半分の大きさ
local TRACK_WIDTH = 90
local ROAD_WIDTH = 24

local world: Folder
-- ゆっくり回る・浮かぶもの（たまごと結晶）
local spinners: { { egg: BasePart, eggCenter: Vector3, crystals: { any } } } = {}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		if key ~= "Parent" then
			(p :: any)[key] = value
		end
	end
	p.Parent = props.Parent or world
	return p
end

-- 空中に浮かぶ文字（大きさはスタッド単位なので遠くからでも読める）
local function label(adornee: BasePart, text: string, offsetY: number, width: number, height: number, color: Color3?)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(width, 0, height, 0)
	bb.StudsOffset = Vector3.new(0, offsetY, 0)
	bb.LightInfluence = 0
	bb.MaxDistance = 250
	bb.Adornee = adornee
	bb.Parent = adornee

	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.2
	t.Text = text
	t.Parent = bb
	return t
end

-- 横向きの円柱（Roblox の円柱は X 軸方向に伸びるので、立てるには Z 軸で 90 度回す）
local function cylinder(position: Vector3, diameter: number, height: number, props: { [string]: any }): Part
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, diameter, diameter)
	props.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	return part(props)
end

local function buildHub(): (SpawnLocation, Vector3)
	part({
		Name = "HubGround",
		Size = Vector3.new(HUB_HALF * 2, 4, HUB_HALF * 2),
		Position = Vector3.new(0, -2, 0),
		Color = Color3.fromRGB(95, 175, 85),
		Material = Enum.Material.Grass,
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, 0.5, 35)
	spawn.Color = Color3.fromRGB(255, 220, 90)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = world

	-- たまごを届ける巣
	local nestPos = Vector3.new(0, 0, -50)
	local nest = cylinder(nestPos + Vector3.new(0, 0.6, 0), 14, 1.2, {
		Name = "Nest",
		Color = Color3.fromRGB(215, 180, 90),
		Material = Enum.Material.Fabric,
		CanCollide = false,
	})
	for i = 1, 12 do
		local a = i / 12 * math.pi * 2
		part({
			Name = "NestTwig",
			Size = Vector3.new(4.5, 1.6, 1.6),
			CFrame = CFrame.new(nestPos + Vector3.new(math.cos(a) * 7, 1, math.sin(a) * 7))
				* CFrame.Angles(0, -a + math.pi / 2, 0),
			Color = Color3.fromRGB(120, 80, 45),
			Material = Enum.Material.Wood,
		})
	end
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 230, 150)
	glow.Range = 18
	glow.Brightness = 2
	glow.Parent = nest
	label(nest, "🪺 たまごを ここへ とどけよう！", 7, 22, 3, Color3.fromRGB(255, 240, 160))

	-- 道への入口のアーチ
	local archZ = -HUB_HALF + 2
	for _, x in { -16, 16 } do
		part({
			Name = "GatePillar",
			Size = Vector3.new(3, 18, 3),
			Position = Vector3.new(x, 9, archZ),
			Color = Color3.fromRGB(240, 240, 240),
		})
	end
	local beam = part({
		Name = "GateBeam",
		Size = Vector3.new(35, 3, 3),
		Position = Vector3.new(0, 19.5, archZ),
		Color = Color3.fromRGB(255, 120, 80),
	})
	label(beam, "🥚 たまごの道 →  遠いほど 強い敵と 高いごほうび", 4, 34, 4)

	return spawn, nestPos
end

local function buildTreadmill(cfg, index: number, position: Vector3)
	local folder = Instance.new("Model")
	folder.Name = "Treadmill" .. index
	folder.Parent = world

	part({
		Name = "Base",
		Size = Vector3.new(12, 1, 20),
		Position = position + Vector3.new(0, 0.5, 0),
		Color = Color3.fromRGB(45, 45, 55),
		Parent = folder,
	})
	local belt = part({
		Name = "Belt",
		Size = Vector3.new(8, 0.4, 18),
		Position = position + Vector3.new(0, 1.2, 0),
		Color = cfg.color:Lerp(Color3.new(0, 0, 0), 0.45),
		Material = Enum.Material.DiamondPlate,
		Parent = folder,
	})
	for _, x in { -4.6, 4.6 } do
		part({
			Name = "Rail",
			Size = Vector3.new(1, 1, 18),
			Position = position + Vector3.new(x, 3.4, 0),
			Color = cfg.color,
			Material = Enum.Material.Metal,
			Parent = folder,
		})
		part({
			Name = "RailPost",
			Size = Vector3.new(0.6, 2.4, 0.6),
			Position = position + Vector3.new(x, 2.2, -8),
			Color = cfg.color,
			Parent = folder,
		})
	end
	-- 後ろの壁（ベルトに押し戻されても落ちない）と、上の看板
	local back = part({
		Name = "BackWall",
		Size = Vector3.new(12, 7, 1),
		Position = position + Vector3.new(0, 4, 10.5),
		Color = cfg.color,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	local reqText = if cfg.required > 0
		then string.format("必要スピード %d", cfg.required)
		else "だれでも使える"
	label(back, string.format("%s\n+%d スピード/秒\n%s", cfg.name, cfg.gain, reqText), 7, 14, 6, cfg.color)

	return {
		belt = belt,
		gain = cfg.gain,
		required = cfg.required,
		name = cfg.name,
	}
end

-- たまごをかえす檻（中のたまごは、それぞれのプレイヤーの画面にだけ自分の分が表示される）
local function buildIncubator(): ProximityPrompt
	local origin = Vector3.new(-38, 0, -50)
	local model = Instance.new("Model")
	model.Name = "Incubator"
	model.Parent = world

	part({
		Name = "CageFloor",
		Size = Vector3.new(12, 1, 26),
		Position = origin + Vector3.new(0, 0.5, 0),
		Color = Color3.fromRGB(230, 205, 140),
		Material = Enum.Material.Fabric,
		Parent = model,
	})
	-- 格子
	local barColor = Color3.fromRGB(90, 90, 100)
	for z = -12, 12, 2 do
		for _, x in { -5.5, 5.5 } do
			cylinder(
				origin + Vector3.new(x, 5, z),
				0.4,
				8,
				{ Name = "Bar", Color = barColor, Material = Enum.Material.Metal, Parent = model }
			)
		end
	end
	for x = -3.5, 3.5, 2 do
		for _, z in { -12.5, 12.5 } do
			cylinder(
				origin + Vector3.new(x, 5, z),
				0.4,
				8,
				{ Name = "Bar", Color = barColor, Material = Enum.Material.Metal, Parent = model }
			)
		end
	end
	local roof = part({
		Name = "CageRoof",
		Size = Vector3.new(13, 1, 27),
		Position = origin + Vector3.new(0, 9.5, 0),
		Color = Color3.fromRGB(150, 90, 50),
		Material = Enum.Material.WoodPlanks,
		Parent = model,
	})
	label(roof, "🥚 ふ化の檻", 3.5, 16, 3, Color3.fromRGB(255, 240, 160))

	-- たまごを置く場所（見えない目印）
	for i = 1, 5 do
		part({
			Name = "Slot" .. i,
			Size = Vector3.new(1, 1, 1),
			Position = origin + Vector3.new(0, 3.5, (i - 3) * 4.5),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Parent = model,
		})
		local cushion = cylinder(origin + Vector3.new(0, 1.15, (i - 3) * 4.5), 3.6, 0.3, {
			Name = "Cushion",
			Color = Color3.fromRGB(255, 180, 190),
			Material = Enum.Material.Fabric,
			Parent = model,
		})
		cushion.CanCollide = false
	end

	-- 前（ベースの中心側）の看板
	local sign = part({
		Name = "CageSign",
		Size = Vector3.new(1, 4, 6),
		Position = origin + Vector3.new(8, 2, 0),
		Color = Color3.fromRGB(255, 245, 225),
		Parent = model,
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "檻を見る"
	prompt.ObjectText = "ふ化の檻"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = sign
	return prompt
end

local function buildShop(): ProximityPrompt
	local origin = Vector3.new(-52, 0, 5)
	local wallColor = Color3.fromRGB(255, 245, 225)
	part({
		Name = "ShopFloor",
		Size = Vector3.new(22, 1, 26),
		Position = origin + Vector3.new(0, 0.5, 0),
		Color = Color3.fromRGB(160, 110, 70),
		Material = Enum.Material.WoodPlanks,
	})
	part({
		Name = "ShopWall",
		Size = Vector3.new(1, 14, 26),
		Position = origin + Vector3.new(-11, 7, 0),
		Color = wallColor,
	})
	part({
		Name = "ShopWall",
		Size = Vector3.new(22, 14, 1),
		Position = origin + Vector3.new(0, 7, 13),
		Color = wallColor,
	})
	part({
		Name = "ShopWall",
		Size = Vector3.new(22, 14, 1),
		Position = origin + Vector3.new(0, 7, -13),
		Color = wallColor,
	})
	local roof = part({
		Name = "ShopRoof",
		Size = Vector3.new(26, 1.5, 30),
		Position = origin + Vector3.new(1, 14.5, 0),
		Color = Color3.fromRGB(230, 70, 70),
	})
	label(roof, "🛒 ショップ", 5, 18, 4, Color3.fromRGB(255, 230, 120))

	local counter = part({
		Name = "Counter",
		Size = Vector3.new(4, 4, 16),
		Position = origin + Vector3.new(2, 3, 0),
		Color = Color3.fromRGB(120, 80, 50),
		Material = Enum.Material.Wood,
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "ショップを開く"
	prompt.ObjectText = "シューズ・ドラゴン"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	return prompt
end

-- ゾーンの飾り（道の外側に並べる）
local function decorate(kind: string, position: Vector3, rng: Random)
	if kind == "tree" then
		part({
			Name = "Trunk",
			Size = Vector3.new(2, 8, 2),
			Position = position + Vector3.new(0, 4, 0),
			Color = Color3.fromRGB(110, 75, 45),
		})
		part({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * rng:NextNumber(8, 11),
			Position = position + Vector3.new(0, 10, 0),
			Color = Color3.fromRGB(60, 150, 60),
			Material = Enum.Material.Grass,
		})
	elseif kind == "cactus" then
		local h = rng:NextNumber(7, 12)
		local green = Color3.fromRGB(80, 150, 70)
		part({
			Name = "Cactus",
			Size = Vector3.new(2.5, h, 2.5),
			Position = position + Vector3.new(0, h / 2, 0),
			Color = green,
		})
		part({
			Name = "CactusArm",
			Size = Vector3.new(4, 1.5, 1.5),
			Position = position + Vector3.new(2, h * 0.55, 0),
			Color = green,
		})
		part({
			Name = "CactusArm",
			Size = Vector3.new(1.5, 3, 1.5),
			Position = position + Vector3.new(3.3, h * 0.55 + 1.5, 0),
			Color = green,
		})
	elseif kind == "pine" then
		part({
			Name = "Trunk",
			Size = Vector3.new(1.6, 4, 1.6),
			Position = position + Vector3.new(0, 2, 0),
			Color = Color3.fromRGB(100, 70, 45),
		})
		for i, w in { 9, 7, 4.5 } do
			part({
				Name = "PineLayer",
				Size = Vector3.new(w, 3, w),
				Position = position + Vector3.new(0, 2.5 + i * 2.6, 0),
				Color = if i == 3 then Color3.fromRGB(245, 250, 255) else Color3.fromRGB(40, 110, 70),
				Material = if i == 3 then Enum.Material.Snow else Enum.Material.Grass,
			})
		end
	elseif kind == "rock" then
		local s = rng:NextNumber(4, 9)
		part({
			Name = "Rock",
			Size = Vector3.new(s, s * 0.8, s * 1.1),
			CFrame = CFrame.new(position + Vector3.new(0, s * 0.3, 0))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0.2),
			Color = Color3.fromRGB(45, 35, 35),
			Material = Enum.Material.Basalt,
		})
		if rng:NextNumber() < 0.5 then
			cylinder(position + Vector3.new(rng:NextNumber(-4, 4), 0.05, s), rng:NextNumber(5, 9), 0.3, {
				Name = "LavaPool",
				Color = Color3.fromRGB(255, 100, 20),
				Material = Enum.Material.Neon,
				CanCollide = false,
			})
		end
	elseif kind == "cloud" then
		for _ = 1, 3 do
			part({
				Name = "Cloud",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * rng:NextNumber(5, 9),
				Position = position + Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(1, 4), rng:NextNumber(-4, 4)),
				Color = Color3.new(1, 1, 1),
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
			})
		end
	end
end

local function buildZone(index: number, zone, zStart: number, zEnd: number, rng: Random)
	local length = zEnd - zStart
	local centerZ = -(zStart + zEnd) / 2

	part({
		Name = "ZoneGround" .. index,
		Size = Vector3.new(TRACK_WIDTH, 4, length),
		Position = Vector3.new(0, -2, centerZ),
		Color = zone.ground,
		Material = if zone.decor == "pine"
			then Enum.Material.Snow
			elseif zone.decor == "cactus" then Enum.Material.Sand
			else Enum.Material.Grass,
	})
	part({
		Name = "Road" .. index,
		Size = Vector3.new(ROAD_WIDTH, 1, length),
		Position = Vector3.new(0, -0.4, centerZ),
		Color = zone.road,
		Material = Enum.Material.Concrete,
	})
	-- 見えない横の壁（道から外に出ないように）
	for _, x in { -TRACK_WIDTH / 2 - 1, TRACK_WIDTH / 2 + 1 } do
		part({
			Name = "SideWall",
			Size = Vector3.new(2, 40, length),
			Position = Vector3.new(x, 20, centerZ),
			Transparency = 1,
		})
	end

	-- ゾーンの入口のアーチ
	for _, x in { -15, 15 } do
		part({
			Name = "ArchPillar",
			Size = Vector3.new(3, 16, 3),
			Position = Vector3.new(x, 8, -zStart - 2),
			Color = zone.enemyColor,
		})
	end
	local beam = part({
		Name = "ArchBeam",
		Size = Vector3.new(33, 3, 3),
		Position = Vector3.new(0, 17.5, -zStart - 2),
		Color = zone.enemyColor,
	})
	label(
		beam,
		string.format(
			"ゾーン %d：%s\n敵の速さ %d ／ たまご %d コイン",
			index,
			zone.name,
			zone.enemySpeed,
			zone.reward
		),
		5,
		30,
		6
	)

	-- 飾り
	local count = math.floor(length / 35)
	for i = 1, count do
		for _, side in { -1, 1 } do
			local x = side * rng:NextNumber(ROAD_WIDTH / 2 + 8, TRACK_WIDTH / 2 - 6)
			local z = -(zStart + (i - 0.5) * length / count + rng:NextNumber(-8, 8))
			decorate(zone.decor, Vector3.new(x, 0, z), rng)
		end
	end

	-- たまごの台（遠いゾーンほど豪華になる）
	local eggPos = Vector3.new(0, 0, -zone.distance)
	local scale = Config.EggScale[index]
	local glow = zone.eggColor
	local gold = Color3.fromRGB(255, 205, 70)
	local trim = if index >= 5
		then gold
		elseif index >= 3 then Color3.fromRGB(200, 205, 220)
		else Color3.fromRGB(150, 120, 90)
	local trimMat = if index >= 3 then Enum.Material.Metal else Enum.Material.Wood
	local stone = Color3.fromRGB(70, 72, 82)
	local pedestal = Instance.new("Model")
	pedestal.Name = "EggPedestal" .. index
	pedestal.Parent = world
	-- 3段の階段（1段 1 スタッドなので歩いてのぼれる）
	local steps = {
		{ 16, stone, Enum.Material.Slate },
		{ 12.5, Color3.fromRGB(95, 98, 110), Enum.Material.Slate },
		{ 9, Color3.fromRGB(240, 240, 245), Enum.Material.Marble },
	}
	for i, step in steps do
		cylinder(eggPos + Vector3.new(0, i - 0.5, 0), step[1], 1, {
			Name = "Step",
			Color = step[2],
			Material = step[3],
			Parent = pedestal,
		})
		-- 段のふちの金属の帯
		cylinder(eggPos + Vector3.new(0, i - 0.08, 0), step[1] + 0.3, 0.18, {
			Name = "Trim",
			Color = trim,
			Material = trimMat,
			CanCollide = false,
			Parent = pedestal,
		})
	end
	-- いちばん上の、光る輪
	cylinder(eggPos + Vector3.new(0, 3.1, 0), 7, 0.2, {
		Name = "GlowRing",
		Color = glow,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = pedestal,
	})
	cylinder(eggPos + Vector3.new(0, 3.15, 0), 6.2, 0.22, {
		Name = "Inner",
		Color = Color3.fromRGB(240, 240, 245),
		Material = Enum.Material.Marble,
		CanCollide = false,
		Parent = pedestal,
	})
	-- 一番下の段に光るもよう
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		part({
			Name = "Rune",
			Size = Vector3.new(0.3, 0.12, 1.4),
			CFrame = CFrame.new(eggPos + Vector3.new(math.cos(a) * 7, 1.02, math.sin(a) * 7)) * CFrame.Angles(0, -a, 0),
			Color = glow,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = pedestal,
		})
	end
	-- 柱と、その上で回る結晶（ゾーンが進むほど柱がふえて高くなる）
	local crystals = {}
	local pillars = math.min(2 + index, 6)
	local pillarHeight = 4 + index * 1.2
	for i = 1, pillars do
		local a = (i / pillars) * math.pi * 2 + math.pi / pillars
		local base = eggPos + Vector3.new(math.cos(a) * 7.3, 1, math.sin(a) * 7.3)
		cylinder(base + Vector3.new(0, pillarHeight / 2, 0), 1.1, pillarHeight, {
			Name = "Pillar",
			Color = Color3.fromRGB(230, 230, 238),
			Material = Enum.Material.Marble,
			Parent = pedestal,
		})
		cylinder(base + Vector3.new(0, pillarHeight + 0.2, 0), 1.6, 0.4, {
			Name = "Cap",
			Color = trim,
			Material = trimMat,
			Parent = pedestal,
		})
		local crystal = part({
			Name = "Crystal",
			Size = Vector3.new(0.9, 1.6, 0.9),
			CFrame = CFrame.new(base + Vector3.new(0, pillarHeight + 1.6, 0)),
			Color = glow,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
			Parent = pedestal,
		})
		table.insert(crystals, { part = crystal, base = base + Vector3.new(0, pillarHeight + 1.6, 0), phase = i })
	end
	-- 遠くからでも見える光の柱（レアなほど太い）
	if index >= 2 then
		local beam = cylinder(eggPos + Vector3.new(0, 40, 0), 2 + index, 70, {
			Name = "LightBeam",
			Color = glow,
			Material = Enum.Material.Neon,
			Transparency = 0.82,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
			Parent = pedestal,
		})
		beam.CanTouch = false
	end

	local eggSize = 4 * scale
	local eggY = 3.3 + eggSize * 0.65 + 0.8
	local egg = part({
		Name = "Egg" .. index,
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * eggSize,
		CFrame = CFrame.new(eggPos + Vector3.new(0, eggY, 0)),
		Color = zone.eggColor,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.1,
		CanCollide = false,
		Parent = pedestal,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = egg
	local light = Instance.new("PointLight")
	light.Color = zone.eggColor
	light.Range = 14 + index * 3
	light.Brightness = 3
	light.Parent = egg
	if index >= 4 then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = zone.eggColor
		sparkles.Parent = egg
	end
	label(
		egg,
		string.format("🥚 %d コイン", zone.reward),
		eggSize * 0.65 + 2.5,
		12,
		2.5,
		Color3.fromRGB(255, 235, 120)
	)
	table.insert(spinners, { egg = egg, eggCenter = eggPos + Vector3.new(0, eggY, 0), crystals = crystals })

	-- 敵の出てくる場所（たまごを囲む）
	local homes = {}
	for j = 1, zone.enemies do
		local offset
		if zone.enemies == 1 then
			offset = Vector3.new(0, 0, 14)
		else
			local a = (j / zone.enemies) * math.pi * 2
			offset = Vector3.new(math.cos(a) * 15, 0, math.sin(a) * 15)
		end
		table.insert(homes, {
			position = eggPos + offset,
			zoneIndex = index,
			boss = zone.boss == true and j == 1,
		})
	end

	return { position = eggPos + Vector3.new(0, 3, 0), zoneIndex = index, part = egg }, homes
end

-- 道の横の距離表示
local function buildDistanceMarkers(lastZ: number)
	for d = 250, lastZ, 250 do
		local post = part({
			Name = "DistancePost",
			Size = Vector3.new(1, 6, 1),
			Position = Vector3.new(ROAD_WIDTH / 2 + 3, 3, -d),
			Color = Color3.fromRGB(255, 255, 255),
		})
		label(post, string.format("%dm", d), 4, 6, 2, Color3.fromRGB(255, 255, 200))
	end
end

function WorldBuilder.build()
	world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = workspace

	local spawn, nestPos = buildHub()

	local treadmills = {}
	for i, cfg in Config.Treadmills do
		local pos = Vector3.new(52, 0, 50 - (i - 1) * 28)
		table.insert(treadmills, buildTreadmill(cfg, i, pos))
	end

	local shopPrompt = buildShop()
	local incubatorPrompt = buildIncubator()

	local rng = Random.new(20261108)
	local eggs = {}
	local enemyHomes = {}
	local zStart = HUB_HALF
	for i, zone in Config.Zones do
		local zEnd = zone.distance + 60
		local egg, homes = buildZone(i, zone, zStart, zEnd, rng)
		table.insert(eggs, egg)
		for _, h in homes do
			table.insert(enemyHomes, h)
		end
		zStart = zEnd
	end
	-- 道の終わりの壁
	part({
		Name = "EndWall",
		Size = Vector3.new(TRACK_WIDTH, 40, 2),
		Position = Vector3.new(0, 20, -zStart - 1),
		Color = Color3.fromRGB(255, 255, 255),
		Transparency = 0.6,
	})
	buildDistanceMarkers(zStart)

	-- たまごはゆっくり回って浮き、結晶はくるくる回る（1秒に 20 回だけ動かして軽くする）
	local t, acc = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		t += dt
		acc += dt
		if acc < 0.05 then
			return
		end
		acc = 0
		for _, s in spinners do
			s.egg.CFrame = CFrame.new(s.eggCenter + Vector3.new(0, math.sin(t * 1.5) * 0.4, 0))
				* CFrame.Angles(0, t * 0.6, 0)
			for _, c in s.crystals do
				c.part.CFrame = CFrame.new(c.base + Vector3.new(0, math.sin(t * 2 + c.phase) * 0.3, 0))
					* CFrame.Angles(0, t * 1.5 + c.phase, math.rad(15))
			end
		end
	end)

	return {
		folder = world,
		spawn = spawn,
		nest = nestPos,
		treadmills = treadmills,
		eggs = eggs,
		enemyHomes = enemyHomes,
		shopPrompt = shopPrompt,
		incubatorPrompt = incubatorPrompt,
	}
end

return WorldBuilder
