-- マップを組み立てる：ベース（ルームランナー・ショップ・巣）と、遠くへ続くたまごの道
-- ベースの中心は原点。道は -Z 方向（スポーンしたときに向いている方向）へ伸びる

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Scenery = require(script.Parent:WaitForChild("Scenery"))

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
		-- 見た目は下の地形（草がゆれる）。この部品は歩く床としてだけ使う
		Transparency = 1,
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

-- 2点を結ぶ丸い棒（手すり・柱）
local function rod(a: Vector3, b: Vector3, diameter: number, props: { [string]: any }): Part
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new((b - a).Magnitude, diameter, diameter)
	-- まっすぐ上を向く棒は、上の向きを横にしておく（向きが決まらなくなるのを ふせぐ）
	local dir = (b - a).Unit
	local up = if math.abs(dir.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	props.CFrame = CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.pi / 2, 0)
	return part(props)
end

-- ルームランナー（ジムにある本物に近い形）。前は -Z（操作パネルがある方）、ベルトは後ろ（+Z）へ流れる
-- 乗るときは、後ろ半分の横にある ふみ台から
local function buildTreadmill(cfg, index: number, position: Vector3)
	local folder = Instance.new("Model")
	folder.Name = "Treadmill" .. index
	folder.Parent = world

	local DARK = Color3.fromRGB(38, 38, 46)
	local FRAME = Color3.fromRGB(58, 60, 70)
	local SILVER = Color3.fromRGB(190, 195, 205)
	local RUBBER = Color3.fromRGB(22, 22, 26)
	local function at(x: number, y: number, z: number): Vector3
		return position + Vector3.new(x, y, z)
	end

	-- 下にしくマット
	part({
		Name = "Mat",
		Size = Vector3.new(16, 0.12, 26),
		Position = at(0, 0.06, 0),
		Color = cfg.color:Lerp(Color3.new(0, 0, 0), 0.7),
		Material = Enum.Material.Rubber,
		Parent = folder,
	})

	-- 走る台：ベルトの下の板と、左右のフレーム（上は すべり止めの ふみ板）
	part({
		Name = "Deck",
		Size = Vector3.new(8, 0.8, 18.6),
		Position = at(0, 0.6, 0),
		Color = DARK,
		Material = Enum.Material.Metal,
		Parent = folder,
	})
	local belt = part({
		Name = "Belt",
		Size = Vector3.new(8, 0.4, 18),
		Position = at(0, 1.2, 0),
		Color = RUBBER,
		Material = Enum.Material.Rubber,
		Parent = folder,
	})
	for _, x in { -4.8, 4.8 } do
		part({
			Name = "SideFrame",
			Size = Vector3.new(1.6, 1.2, 21),
			Position = at(x, 0.8, -0.4),
			Color = FRAME,
			Material = Enum.Material.Metal,
			Parent = folder,
		})
		part({
			Name = "FootRail",
			Size = Vector3.new(1.4, 0.12, 18.6),
			Position = at(x, 1.46, 0),
			Color = SILVER,
			Material = Enum.Material.DiamondPlate,
			Parent = folder,
		})
		-- マシンの色の線（どのマシンか 色でわかる）
		part({
			Name = "Accent",
			Size = Vector3.new(0.12, 0.3, 20.6),
			Position = at(x + (if x > 0 then 0.8 else -0.8), 0.95, -0.4),
			Color = cfg.color,
			Material = Enum.Material.Neon,
			Parent = folder,
		})
		-- 後ろ半分の横の ふみ台（ここから乗る）
		part({
			Name = "Step",
			Size = Vector3.new(2.4, 0.7, 9),
			Position = at(x + (if x > 0 then 2 else -2), 0.35, 5),
			Color = DARK,
			Material = Enum.Material.DiamondPlate,
			Parent = folder,
		})
		-- 足（ゴム）
		for _, z in { -9.5, 9 } do
			part({
				Name = "Foot",
				Size = Vector3.new(1.9, 0.3, 1.4),
				Position = at(x, 0.15, z),
				Color = RUBBER,
				Material = Enum.Material.Rubber,
				Parent = folder,
			})
		end
	end
	-- ベルトを回す 前と後ろのローラー
	for _, z in { -9.1, 9.1 } do
		part({
			Name = "Roller",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(8, 1.1, 1.1),
			Position = at(0, 0.88, z),
			Color = SILVER,
			Material = Enum.Material.Metal,
			Parent = folder,
		})
	end
	-- ベルトの白い線（それぞれの画面で 後ろへ流れて見える。動かすのは Treadmill.client）
	for i = 0, 5 do
		part({
			Name = "Stripe",
			Size = Vector3.new(7.4, 0.04, 0.3),
			Position = at(0, 1.41, -7.5 + i * 3),
			Color = Color3.fromRGB(85, 85, 92),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = folder,
		})
	end

	-- 前のモーターカバー
	part({
		Name = "MotorCover",
		Size = Vector3.new(11.2, 1.7, 3.2),
		Position = at(0, 1.05, -10.8),
		Color = DARK,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	part({
		Name = "MotorSlope",
		Size = Vector3.new(11.2, 0.3, 2.4),
		CFrame = CFrame.new(at(0, 1.75, -9.5)) * CFrame.Angles(math.rad(22), 0, 0),
		Color = FRAME,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	part({
		Name = "MotorAccent",
		Size = Vector3.new(11.3, 0.25, 0.2),
		Position = at(0, 1.6, -12.4),
		Color = cfg.color,
		Material = Enum.Material.Neon,
		Parent = folder,
	})
	for i = -2, 2 do
		part({
			Name = "Vent",
			Size = Vector3.new(1.2, 0.12, 0.1),
			Position = at(i * 1.7, 0.9, -12.42),
			Color = Color3.fromRGB(12, 12, 14),
			Parent = folder,
		})
	end

	-- 左右の柱（少し手前へ かたむく）と、操作パネル
	local metal = { Color = SILVER, Material = Enum.Material.Metal, Parent = folder }
	local function metalRod(name: string, a: Vector3, b: Vector3, diameter: number)
		local props = table.clone(metal)
		props.Name = name
		return rod(a, b, diameter, props)
	end
	for _, x in { -4.8, 4.8 } do
		metalRod("Upright", at(x, 1.4, -10.9), at(x, 7.4, -9.7), 0.75)
		-- 手すり：柱から後ろへのびる。にぎる所は黒いゴム
		metalRod("Handrail", at(x, 5.4, -10.1), at(x, 4.9, -5.2), 0.55)
		rod(at(x, 4.9, -5.2), at(x, 4.75, -3.2), 0.72, {
			Name = "Grip",
			Color = RUBBER,
			Material = Enum.Material.Rubber,
			Parent = folder,
		})
		part({
			Name = "GripEnd",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.8, 0.8, 0.8),
			Position = at(x, 4.75, -3.2),
			Color = cfg.color,
			Material = Enum.Material.SmoothPlastic,
			Parent = folder,
		})
	end
	-- 前の横の手すり（心拍をはかる 金色の板つき）
	metalRod("FrontBar", at(-4.8, 5.4, -10.1), at(4.8, 5.4, -10.1), 0.55)
	for _, x in { -1.6, 1.6 } do
		rod(at(x - 0.7, 5.4, -10.1), at(x + 0.7, 5.4, -10.1), 0.66, {
			Name = "PulseSensor",
			Color = Color3.fromRGB(235, 200, 90),
			Material = Enum.Material.Metal,
			Parent = folder,
		})
	end

	-- 操作パネル：上が向こうへ たおれた板。こっち向き（+Z）の面が画面
	local tilt = CFrame.new(at(0, 7.3, -9.9)) * CFrame.Angles(math.rad(-18), 0, 0)
	part({
		Name = "ConsoleBack",
		Size = Vector3.new(11, 3.3, 0.5),
		CFrame = tilt * CFrame.new(0, 0, -0.3),
		Color = cfg.color,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	local console = part({
		Name = "Console",
		Size = Vector3.new(10.6, 2.9, 0.6),
		CFrame = tilt,
		Color = DARK,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	local screen = part({
		Name = "Screen",
		Size = Vector3.new(6.4, 2.1, 0.1),
		CFrame = tilt * CFrame.new(-1.6, 0.1, 0.32),
		Color = Color3.fromRGB(8, 14, 22),
		Material = Enum.Material.Glass,
		Parent = folder,
	})
	local reqText = if cfg.required > 0
		then string.format("必要スピード %d", cfg.required)
		else "だれでも使える"
	do
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Back
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 50
		sg.LightInfluence = 0
		sg.Parent = screen
		local function line(y: number, h: number, textValue: string, color: Color3)
			local t = Instance.new("TextLabel")
			t.Position = UDim2.new(0.04, 0, y, 0)
			t.Size = UDim2.new(0.92, 0, h, 0)
			t.BackgroundTransparency = 1
			t.Font = Enum.Font.GothamBold
			t.TextScaled = true
			t.TextColor3 = color
			t.Text = textValue
			t.Parent = sg
		end
		line(0.04, 0.26, cfg.name, cfg.color)
		line(0.3, 0.44, string.format("⚡ +%d /秒", cfg.gain), Color3.fromRGB(120, 255, 170))
		line(0.74, 0.22, reqText, Color3.fromRGB(200, 210, 225))
	end
	-- ボタン：スタート（緑）、ストップ（赤）、速さの上下
	local buttonColors = {
		Color3.fromRGB(60, 200, 90),
		Color3.fromRGB(230, 60, 60),
		Color3.fromRGB(70, 130, 230),
		Color3.fromRGB(70, 130, 230),
	}
	for i, color in buttonColors do
		local column, line = (i - 1) % 2, (i - 1) // 2
		part({
			Name = "Button",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.16, 0.75, 0.75),
			CFrame = tilt * CFrame.new(2.7 + column * 1.3, 0.55 - line * 1.1, 0.34) * CFrame.Angles(0, math.pi / 2, 0),
			Color = color,
			Material = Enum.Material.Neon,
			Parent = folder,
		})
	end
	-- 安全キー（赤い ひも）
	part({
		Name = "SafetyKey",
		Size = Vector3.new(0.6, 0.3, 0.2),
		CFrame = tilt * CFrame.new(-1.6, -1.25, 0.36),
		Color = Color3.fromRGB(230, 40, 40),
		Parent = folder,
	})
	rod((tilt * CFrame.new(-1.6, -1.25, 0.4)).Position, at(-1.2, 5.0, -8.6), 0.08, {
		Name = "SafetyCord",
		Color = Color3.fromRGB(230, 40, 40),
		CanCollide = false,
		Parent = folder,
	})
	-- 遠くからでも読める 浮かぶ文字
	label(console, string.format("%s\n+%d スピード/秒\n%s", cfg.name, cfg.gain, reqText), 5.5, 14, 6, cfg.color)

	-- 後ろ：ベルトに流されても落ちないように、低い さくと 見えない壁
	for _, x in { -5.4, 5.4 } do
		metalRod("RearPost", at(x, 0, 10.4), at(x, 3.4, 10.4), 0.5)
	end
	rod(at(-5.4, 3.4, 10.4), at(5.4, 3.4, 10.4), 0.5, {
		Name = "RearBar",
		Color = cfg.color,
		Material = Enum.Material.Metal,
		Parent = folder,
	})
	metalRod("RearBarLow", at(-5.4, 2.2, 10.4), at(5.4, 2.2, 10.4), 0.35)
	part({
		Name = "BackWall",
		Size = Vector3.new(12, 8, 1),
		Position = at(0, 4, 10.5),
		Transparency = 1,
		Parent = folder,
	})

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

-- 塔のぼりの入口（ベースの左うしろ）。中に入ると、空の上の部屋へワープする
local function buildTower(): ProximityPrompt
	local origin = Vector3.new(-50, 0, 55)
	local stone = Color3.fromRGB(120, 112, 140)
	local model = Instance.new("Model")
	model.Name = "TowerGate"
	model.Parent = world
	-- だんだん細くなる塔
	local tiers = { { 18, 16 }, { 15, 14 }, { 12, 12 }, { 9, 10 } }
	local y = 0
	for i, t in tiers do
		local w, h = t[1], t[2]
		part({
			Name = "Tier",
			Size = Vector3.new(w, h, w),
			Position = origin + Vector3.new(0, y + h / 2, 0),
			Color = if i % 2 == 0 then stone else stone:Lerp(Color3.new(1, 1, 1), 0.15),
			Material = Enum.Material.Cobblestone,
			Parent = model,
		})
		-- 角の光る石
		for _, c in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
			part({
				Name = "Gem",
				Size = Vector3.new(1.2, 1.2, 1.2),
				Position = origin + Vector3.new(c[1] * w / 2, y + h, c[2] * w / 2),
				Color = Color3.fromRGB(170, 120, 255),
				Material = Enum.Material.Neon,
				CanCollide = false,
				Parent = model,
			})
		end
		y += h
	end
	local top = part({
		Name = "Top",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(6, 6, 6),
		Position = origin + Vector3.new(0, y + 3, 0),
		Color = Color3.fromRGB(190, 140, 255),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = model,
	})
	local light = Instance.new("PointLight")
	light.Color = top.Color
	light.Range = 40
	light.Brightness = 3
	light.Parent = top
	label(top, "🗼 塔のぼり", 6, 18, 4, Color3.fromRGB(220, 200, 255))
	-- 入口（ベースの中心がわ）
	local door = part({
		Name = "Door",
		Size = Vector3.new(1, 9, 7),
		Position = origin + Vector3.new(9.2, 4.5, 0),
		Color = Color3.fromRGB(60, 30, 90),
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		CanCollide = false,
		Parent = model,
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "塔に入る"
	prompt.ObjectText = "1階ずつ 敵をたおして 上へ（5階ごとにボス）"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = door
	return prompt
end

-- ひみつのゾーンの門（条件を満たした人の画面では、通りぬけられるようになる）
local function buildSecretGate(zStart: number): BasePart
	local gate = part({
		Name = "SecretGate",
		Size = Vector3.new(TRACK_WIDTH, 40, 2),
		Position = Vector3.new(0, 20, -zStart + 6),
		Color = Color3.fromRGB(70, 230, 150),
		Material = Enum.Material.ForceField,
		Transparency = 0.3,
	})
	local sign = part({
		Name = "SecretSign",
		Size = Vector3.new(1, 1, 1),
		Position = Vector3.new(0, 10, -zStart + 8),
		Transparency = 1,
		CanCollide = false,
	})
	label(
		sign,
		string.format(
			"🔒 ひみつの門\nやみの竜王を %d回 たおして\n図鑑を %d種類 集めると 開く",
			Config.SecretZone.bossKills,
			Config.SecretZone.book
		),
		0,
		30,
		9,
		Color3.fromRGB(170, 255, 210)
	)
	return gate
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

-- 道の材質（ゾーンごと）
local ROAD_MATERIAL = {
	tree = Enum.Material.Ground,
	cactus = Enum.Material.Sandstone,
	pine = Enum.Material.Cobblestone,
	rock = Enum.Material.Asphalt,
	cloud = Enum.Material.Marble,
	star = Enum.Material.Glass,
	ruins = Enum.Material.Cobblestone,
}

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
			elseif zone.decor == "star" then Enum.Material.Slate
			else Enum.Material.Grass,
		-- 雲の上と星空のほかは、見た目を地形にまかせて、この部品は歩く床としてだけ使う
		Transparency = if zone.decor == "cloud" or zone.decor == "star" then 0 else 1,
	})
	part({
		Name = "Road" .. index,
		Size = Vector3.new(ROAD_WIDTH, 1, length),
		Position = Vector3.new(0, -0.4, centerZ),
		Color = zone.road,
		Material = ROAD_MATERIAL[zone.decor] or Enum.Material.Concrete,
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
			"%sゾーン %d：%s\n敵の速さ %d ／ たまご %d コイン",
			if zone.secret then "🔒 ひみつの" else "",
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
			Scenery.prop(zone.decor, Vector3.new(x, 0, z), rng)
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
	local towerPrompt = buildTower()

	local rng = Random.new(20261108)
	local eggs = {}
	local enemyHomes = {}
	local zStart = HUB_HALF
	local sceneZones = {}
	local secretZ = nil
	local zoneStarts = {}
	for i, zone in Config.Zones do
		local zEnd = zone.distance + 60
		zoneStarts[i] = zStart
		if zone.secret then
			secretZ = zStart - 6
			buildSecretGate(zStart)
		end
		table.insert(sceneZones, { decor = zone.decor, zStart = zStart, zEnd = zEnd })
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
	-- 道の外の景色（地形の丘・山・川と、森）
	Scenery.build(world, HUB_HALF, sceneZones)

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
		towerPrompt = towerPrompt,
		secretZ = secretZ, -- ひみつの門の位置（ベースからの距離）
		zoneStarts = zoneStarts,
		roadEnd = zStart,
	}
end

return WorldBuilder
