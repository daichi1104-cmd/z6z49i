-- 風景：Roblox の地形（Terrain）で作る丘・山・川・砂丘と、本物らしい木・サボテン・雲
--
-- ・道（ゾーンの中）の地面は平らなまま。見た目だけ地形にして、
--   歩く床は今までどおり見えない部品（y = 0）にする（敵の動きが変わらない）
-- ・道の外の丘や山は、地形の球を重ねて作る
-- ・遠くの木や岩は影を落とさない（軽くするため）

local Scenery = {}

local WIDE = 360 -- 道の中心から左右に、地形を作る広さ
local BACK = 240 -- ベースの後ろ（+Z）に、地形を作る長さ
local FAR = 110 -- これより道から遠い飾りは影を落とさない

local terrain: any
local folder: Instance
local groundAt: (number, number) -> (number?, Enum.Material?)

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

--------------------------------------------------------------------------------
-- 地形
--------------------------------------------------------------------------------

-- 箱の形に地形をうめる（一度に大きくしすぎないよう、256 スタッドごとに分ける）
local function box(material: Enum.Material, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number)
	local ax, bx = math.min(x0, x1), math.max(x0, x1)
	local az, bz = math.min(z0, z1), math.max(z0, z1)
	local x = ax
	while x < bx do
		local nx = math.min(x + 256, bx)
		local z = az
		while z < bz do
			local nz = math.min(z + 256, bz)
			terrain:FillBlock(
				CFrame.new((x + nx) / 2, (y0 + y1) / 2, (z + nz) / 2),
				v(nx - x, y1 - y0, nz - z),
				material
			)
			z = nz
		end
		x = nx
	end
end

local function ball(material: Enum.Material, pos: Vector3, r: number)
	terrain:FillBall(pos, r, material)
end

-- 山：下から上へ、だんだん小さくなる球を重ねる。上のほうは topMaterial（雪や岩）
local function mountain(
	pos: Vector3,
	radius: number,
	height: number,
	material: Enum.Material,
	topMaterial: Enum.Material,
	rng: Random
)
	local n = 9
	local drift = v(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * radius * 0.15
	for k = 0, n - 1 do
		local t = k / (n - 1)
		local r = radius * (1 - 0.78 * t)
		local y = (height - r) * t - r * 0.5 * (1 - t)
		ball(if t > 0.6 then topMaterial else material, pos + drift * t + v(0, y, 0), r)
	end
end

--------------------------------------------------------------------------------
-- 部品で作る飾り
--------------------------------------------------------------------------------

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
	p.Parent = props.Parent or folder
	return p
end

-- 立てた円柱
local function post(pos: Vector3, d: number, h: number, color: Color3, material: Enum.Material, shadow: boolean): Part
	return part({
		Shape = Enum.PartType.Cylinder,
		Size = v(h, d, d),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Material = material,
		CastShadow = shadow,
	})
end

-- a から b へのびる円柱（枝・サボテンのうで）
local function rod(a: Vector3, b: Vector3, d: number, color: Color3, material: Enum.Material, shadow: boolean): Part
	local dir = b - a
	return part({
		Shape = Enum.PartType.Cylinder,
		Size = v(dir.Magnitude, d, d),
		CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0),
		Color = color,
		Material = material,
		CastShadow = shadow,
	})
end

local function blob(pos: Vector3, size: Vector3, color: Color3, material: Enum.Material, shadow: boolean): Part
	local p = part({
		Size = size,
		CFrame = CFrame.new(pos),
		Color = color,
		Material = material,
		CanCollide = false,
		CastShadow = shadow,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local BARK = Color3.fromRGB(92, 66, 44)
local LEAVES = { Color3.fromRGB(58, 120, 46), Color3.fromRGB(74, 138, 52), Color3.fromRGB(46, 104, 42) }
local PINE = { Color3.fromRGB(34, 82, 52), Color3.fromRGB(42, 94, 60) }
local SNOW = Color3.fromRGB(245, 248, 255)
local CACTUS = { Color3.fromRGB(78, 128, 66), Color3.fromRGB(92, 140, 72) }

-- 広葉樹：少し曲がった幹と枝、葉のかたまりを重ねる
local function tree(pos: Vector3, rng: Random, shadow: boolean)
	local h = rng:NextNumber(9, 14)
	local d = rng:NextNumber(1.4, 2)
	post(pos + v(0, h / 2, 0), d, h, BARK, Enum.Material.Wood, shadow)
	for _ = 1, 2 do
		local a = rng:NextNumber(0, math.pi * 2)
		local from = pos + v(0, h * rng:NextNumber(0.55, 0.75), 0)
		rod(from, from + v(math.cos(a) * 3, 2.5, math.sin(a) * 3), d * 0.5, BARK, Enum.Material.Wood, shadow)
	end
	local n = rng:NextInteger(5, 7)
	for i = 1, n do
		local a = i / n * math.pi * 2 + rng:NextNumber(0, 0.6)
		local r = if i == 1 then 0 else rng:NextNumber(2.2, 4)
		local s = if i == 1 then rng:NextNumber(7, 8.5) else rng:NextNumber(5, 7)
		local p = pos + v(math.cos(a) * r, h + (if i == 1 then 1.5 else rng:NextNumber(-1.5, 1.5)), math.sin(a) * r)
		blob(p, v(s, s * 0.85, s), LEAVES[rng:NextInteger(1, #LEAVES)], Enum.Material.LeafyGrass, shadow)
	end
end

-- 針葉樹：だんだん細くなる葉の段。snowy なら段の上に雪がつもる
local function pine(pos: Vector3, rng: Random, snowy: boolean, shadow: boolean)
	local k = rng:NextNumber(0.85, 1.25)
	post(pos + v(0, 2.5 * k, 0), 1.2 * k, 5 * k, BARK, Enum.Material.Wood, shadow)
	local color = PINE[rng:NextInteger(1, #PINE)]
	for i = 1, 4 do
		local t = (i - 1) / 3
		local w = 9 * k * (1 - t * 0.72)
		local y = (3 + i * 2.7) * k
		blob(pos + v(0, y, 0), v(w, 3.4 * k, w), color, Enum.Material.LeafyGrass, shadow)
		if snowy and i >= 2 then
			blob(pos + v(0, y + 1.1 * k, 0), v(w * 0.78, 1.3 * k, w * 0.78), SNOW, Enum.Material.Snow, false)
		end
	end
	blob(pos + v(0, 15.2 * k, 0), v(1.6, 3, 1.6) * k, if snowy then SNOW else color, Enum.Material.LeafyGrass, shadow)
end

-- サボテン：丸い頭の幹に、上へ曲がるうで
local function cactus(pos: Vector3, rng: Random, shadow: boolean)
	local h = rng:NextNumber(8, 13)
	local color = CACTUS[rng:NextInteger(1, #CACTUS)]
	local mat = Enum.Material.Plastic
	post(pos + v(0, h / 2, 0), 2.2, h, color, mat, shadow)
	part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2.2,
		CFrame = CFrame.new(pos + v(0, h, 0)),
		Color = color,
		Material = mat,
	})
	local a0 = rng:NextNumber(0, math.pi * 2)
	for i = 1, rng:NextInteger(1, 2) do
		local a = a0 + (i - 1) * math.pi
		local out = v(math.cos(a), 0, math.sin(a))
		local y = h * rng:NextNumber(0.35, 0.6)
		local up = rng:NextNumber(2.5, 4)
		local elbow = pos + v(0, y, 0) + out * 2.6
		rod(pos + v(0, y, 0), elbow, 1.6, color, mat, shadow)
		part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.6,
			CFrame = CFrame.new(elbow),
			Color = color,
			Material = mat,
		})
		post(elbow + v(0, up / 2, 0), 1.6, up, color, mat, shadow)
		part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.6,
			CFrame = CFrame.new(elbow + v(0, up, 0)),
			Color = color,
			Material = mat,
		})
	end
end

-- しげみ：小さな葉のかたまり
local function bush(pos: Vector3, rng: Random, shadow: boolean)
	for _ = 1, 3 do
		local s = rng:NextNumber(2.5, 4)
		blob(
			pos + v(rng:NextNumber(-1.5, 1.5), s * 0.3, rng:NextNumber(-1.5, 1.5)),
			v(s, s * 0.75, s),
			LEAVES[rng:NextInteger(1, #LEAVES)],
			Enum.Material.LeafyGrass,
			shadow
		)
	end
end

-- 雲：白いかたまりを重ねる（影は落とさない）
local function cloud(pos: Vector3, rng: Random, big: number?)
	local k = big or 1
	for _ = 1, rng:NextInteger(4, 6) do
		local s = rng:NextNumber(6, 11) * k
		blob(
			pos + v(rng:NextNumber(-6, 6), rng:NextNumber(0, 3), rng:NextNumber(-6, 6)) * k,
			v(s * 1.3, s * 0.8, s),
			Color3.fromRGB(250, 251, 255),
			Enum.Material.SmoothPlastic,
			false
		)
	end
end

-- 岩：地形の球を2〜3こ重ねる
local function boulder(pos: Vector3, rng: Random, material: Enum.Material, size: number?)
	local s = size or rng:NextNumber(3, 6)
	for _ = 1, rng:NextInteger(2, 3) do
		ball(material, pos + v(rng:NextNumber(-1, 1), rng:NextNumber(-0.5, 0.3), rng:NextNumber(-1, 1)) * s, s)
	end
end

-- 道の中（道と見えない壁のあいだ）に置く飾り。WorldBuilder から呼ぶ
-- 地形を作ってから置くので、ここではためておくだけ（Scenery.build で置く）
local pending: { () -> () } = {}

local function placeProp(kind: string, pos: Vector3, rng: Random)
	if kind == "tree" then
		if rng:NextNumber() < 0.7 then
			tree(pos, rng, true)
		else
			bush(pos, rng, true)
		end
	elseif kind == "cactus" then
		cactus(pos, rng, true)
	elseif kind == "pine" then
		pine(pos, rng, true, true)
	elseif kind == "rock" then
		boulder(pos + v(0, 1, 0), rng, if rng:NextNumber() < 0.5 then Enum.Material.Basalt else Enum.Material.Rock)
		if rng:NextNumber() < 0.5 then
			terrain:FillCylinder(
				CFrame.new(pos + v(rng:NextNumber(-4, 4), -1, rng:NextNumber(5, 8))),
				2,
				rng:NextNumber(3, 5),
				Enum.Material.CrackedLava
			)
		end
	elseif kind == "cloud" then
		cloud(pos + v(0, rng:NextNumber(2, 8), 0), rng)
	end
end

function Scenery.prop(kind: string, pos: Vector3, rng: Random)
	-- 乱数の流れが変わらないよう、ここで自分用の乱数を作っておく
	local own = Random.new(rng:NextInteger(1, 2 ^ 30))
	table.insert(pending, function()
		placeProp(kind, pos, own)
	end)
end

--------------------------------------------------------------------------------
-- ゾーンごとの景色（道の外側）
--------------------------------------------------------------------------------

-- 道の外の、x の場所をえらぶ（s = -1 左 / 1 右）
local function sideX(rng: Random, s: number, from: number, to: number): number
	return s * rng:NextNumber(from, to)
end

-- 地面の高さに置く。地面の材質が allowed にないとき（水・岩など）は置かない
local function onGround(x: number, z: number, allowed: { [Enum.Material]: boolean }): Vector3?
	local y, material = groundAt(x, z)
	if not y or (material and not allowed[material]) then
		return nil
	end
	return v(x, y - 0.3, z)
end

local function each(zStart: number, zEnd: number, step: number, fn: (number) -> ())
	local d = zStart + step / 2
	while d < zEnd do
		fn(-d)
		d += step
	end
end

local SCENES = {}

-- 草原：なだらかな丘、細長い池、森、遠くの緑の山
SCENES.tree = function(z0: number, z1: number, rng: Random)
	local G = Enum.Material.Grass
	box(G, -WIDE, WIDE, -16, 0, -z0, -z1)
	-- 左の池（岸は砂、水は少し低く）
	local pondA, pondB = z0 + 40, z1 - 40
	box(Enum.Material.Sand, -184, -126, -8, 0, -pondA, -pondB)
	box(Enum.Material.Air, -176, -134, -8, 0, -pondA - 8, -pondB + 8)
	box(Enum.Material.Water, -176, -134, -8, -1.5, -pondA - 8, -pondB + 8)
	each(z0, z1, 45, function(z)
		for _, s in { -1, 1 } do
			local x = sideX(rng, s, 90, 300)
			if not (x > -215 and x < -95) then
				local r = rng:NextNumber(25, 55)
				ball(G, v(x, -r * 0.6, z + rng:NextNumber(-15, 15)), r)
			end
		end
	end)
	each(z0, z1, 120, function(z)
		for _, s in { -1, 1 } do
			mountain(
				v(sideX(rng, s, 290, 340), 0, z),
				rng:NextNumber(60, 90),
				rng:NextNumber(70, 120),
				G,
				Enum.Material.Rock,
				rng
			)
		end
	end)
	local ok = { [G] = true, [Enum.Material.LeafyGrass] = true }
	each(z0, z1, 16, function(z)
		for _, s in { -1, 1 } do
			local x = sideX(rng, s, 58, 280)
			local at = onGround(x, z + rng:NextNumber(-4, 4), ok)
			if at then
				local shadow = math.abs(x) < FAR
				if rng:NextNumber() < 0.75 then
					tree(at, rng, shadow)
				else
					bush(at, rng, shadow)
				end
			end
		end
	end)
	each(z0, z1, 40, function(z)
		local s = if rng:NextNumber() < 0.5 then -1 else 1
		local at = onGround(sideX(rng, s, 60, 260), z, ok)
		if at then
			boulder(at, rng, Enum.Material.Rock)
		end
	end)
end

-- 砂漠：砂丘、赤い岩の台地、サボテン
SCENES.cactus = function(z0: number, z1: number, rng: Random)
	local S = Enum.Material.Sand
	box(S, -WIDE, WIDE, -16, 0, -z0, -z1)
	each(z0, z1, 40, function(z)
		for _, s in { -1, 1 } do
			local r = rng:NextNumber(30, 70)
			ball(S, v(sideX(rng, s, 80, 320), -r * 0.75, z + rng:NextNumber(-15, 15)), r)
		end
	end)
	-- 台地（メサ）：上が平らな岩の山を、2段重ねる
	each(z0, z1, 150, function(z)
		for _, s in { -1, 1 } do
			local x = sideX(rng, s, 140, 310)
			local h = rng:NextNumber(30, 60)
			local w, d = rng:NextNumber(40, 70), rng:NextNumber(40, 70)
			local turn = CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
			terrain:FillBlock(CFrame.new(x, h / 2 - 8, z) * turn, v(w, h + 16, d), Enum.Material.Sandstone)
			terrain:FillBlock(CFrame.new(x, h + 6, z) * turn, v(w * 0.6, 14, d * 0.6), Enum.Material.Sandstone)
		end
	end)
	local ok = { [S] = true }
	each(z0, z1, 32, function(z)
		for _, s in { -1, 1 } do
			local x = sideX(rng, s, 58, 300)
			local at = onGround(x, z + rng:NextNumber(-8, 8), ok)
			if at then
				cactus(at, rng, math.abs(x) < FAR)
			end
		end
	end)
	each(z0, z1, 35, function(z)
		local s = if rng:NextNumber() < 0.5 then -1 else 1
		local at = onGround(sideX(rng, s, 60, 260), z, ok)
		if at then
			boulder(at, rng, Enum.Material.Sandstone)
		end
	end)
end

-- 雪原：雪の丘、こおった湖、雪をかぶった高い山、針葉樹の森
SCENES.pine = function(z0: number, z1: number, rng: Random)
	local W = Enum.Material.Snow
	box(W, -WIDE, WIDE, -16, 0, -z0, -z1)
	local mid = (z0 + z1) / 2
	box(Enum.Material.Ice, 80, 190, -4, 0, -(mid - 120), -(mid + 120))
	each(z0, z1, 50, function(z)
		for _, s in { -1, 1 } do
			local x = sideX(rng, s, 90, 300)
			if not (x > 60 and x < 210 and math.abs(-z - mid) < 140) then
				local r = rng:NextNumber(25, 50)
				ball(W, v(x, -r * 0.6, z + rng:NextNumber(-15, 15)), r)
			end
		end
	end)
	each(z0, z1, 100, function(z)
		for _, s in { -1, 1 } do
			mountain(
				v(sideX(rng, s, 230, 340), 0, z + rng:NextNumber(-20, 20)),
				rng:NextNumber(60, 100),
				rng:NextNumber(90, 160),
				Enum.Material.Rock,
				W,
				rng
			)
		end
	end)
	local ok = { [W] = true }
	each(z0, z1, 15, function(z)
		for _, s in { -1, 1 } do
			local x = sideX(rng, s, 58, 260)
			local at = onGround(x, z + rng:NextNumber(-3, 3), ok)
			if at then
				pine(at, rng, true, math.abs(x) < FAR)
			end
		end
	end)
	each(z0, z1, 45, function(z)
		local s = if rng:NextNumber() < 0.5 then -1 else 1
		local at = onGround(sideX(rng, s, 60, 260), z, ok)
		if at then
			boulder(at, rng, Enum.Material.Rock)
		end
	end)
end

-- 火山：黒い岩の大地、くねくね流れる溶岩の川、けむりを上げる火山
SCENES.rock = function(z0: number, z1: number, rng: Random)
	local B = Enum.Material.Basalt
	box(B, -WIDE, WIDE, -16, 0, -z0, -z1)
	-- 溶岩の川（左右に1本ずつ、波のようにくねる）
	local phase = rng:NextNumber(0, math.pi * 2)
	each(z0, z1, 12, function(z)
		for _, s in { -1, 1 } do
			local x = s * (95 + math.sin(z / 70 + phase + s) * 30)
			box(Enum.Material.CrackedLava, x - 7, x + 7, -4, 0, z - 7, z + 7)
		end
	end)
	each(z0, z1, 45, function(z)
		for _, s in { -1, 1 } do
			local r = rng:NextNumber(20, 45)
			ball(if rng:NextNumber() < 0.5 then B else Enum.Material.Rock, v(sideX(rng, s, 140, 300), -r * 0.6, z), r)
		end
	end)
	-- 火山（左右に1つずつ）。てっぺんをくぼませて溶岩を入れ、けむりを出す
	for i, s in { -1, 1 } do
		local z = -(z0 + (z1 - z0) * (if i == 1 then 0.35 else 0.7))
		local x = s * rng:NextNumber(250, 290)
		local height = rng:NextNumber(150, 180)
		mountain(v(x, 0, z), rng:NextNumber(100, 120), height, B, Enum.Material.Rock, rng)
		local top = v(x, height - 10, z)
		ball(Enum.Material.Air, top + v(0, 14, 0), 22)
		ball(Enum.Material.CrackedLava, top - v(0, 6, 0), 12)
		local vent = part({
			Name = "Vent",
			Size = v(4, 4, 4),
			Position = top + v(0, 4, 0),
			Transparency = 1,
			CanCollide = false,
			CastShadow = false,
		})
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(70, 65, 65)
		smoke.Size = 60
		smoke.Opacity = 0.35
		smoke.RiseVelocity = 12
		smoke.Parent = vent
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 110, 30)
		glow.Range = 60
		glow.Brightness = 3
		glow.Parent = vent
	end
	each(z0, z1, 30, function(z)
		for _, s in { -1, 1 } do
			local at = onGround(sideX(rng, s, 58, 240), z, { [B] = true, [Enum.Material.Rock] = true })
			if at then
				boulder(at, rng, if rng:NextNumber() < 0.5 then B else Enum.Material.Rock)
			end
		end
	end)
end

-- 雲の上：道の下に広がる雲の海と、まわりに浮かぶ雲
SCENES.cloud = function(z0: number, z1: number, rng: Random)
	each(z0, z1, 32, function(z)
		local x = -WIDE
		while x <= WIDE do
			local r = rng:NextNumber(22, 40)
			ball(Enum.Material.Snow, v(x + rng:NextNumber(-10, 10), -70 + rng:NextNumber(-8, 8), z), r)
			x += 48
		end
	end)
	each(z0, z1, 60, function(z)
		for _, s in { -1, 1 } do
			cloud(v(sideX(rng, s, 60, 300), rng:NextNumber(-25, 30), z), rng, rng:NextNumber(1.2, 2.2))
		end
	end)
end

-- ベースのまわり：草地と、森、遠くの雪山
local function hubScene(hubHalf: number, rng: Random)
	local G = Enum.Material.Grass
	box(G, -WIDE, WIDE, -16, 0, -hubHalf, BACK)
	for _ = 1, 26 do
		local x, z = rng:NextNumber(-WIDE + 40, WIDE - 40), rng:NextNumber(hubHalf + 50, BACK - 20)
		local r = rng:NextNumber(25, 50)
		ball(G, v(x, -r * 0.6, z), r)
	end
	for _, x in { -300, -150, 0, 150, 300 } do
		mountain(
			v(x + rng:NextNumber(-30, 30), 0, BACK + 20),
			rng:NextNumber(90, 120),
			rng:NextNumber(150, 200),
			Enum.Material.Rock,
			Enum.Material.Snow,
			rng
		)
	end
	-- ベースの広場（中心から hubHalf の四角）の外に、木をならべる
	local ok = { [G] = true }
	for _ = 1, 45 do
		local x, z = rng:NextNumber(-WIDE + 20, WIDE - 20), rng:NextNumber(-hubHalf, BACK - 30)
		local inside = math.abs(x) < hubHalf + 8 and z < hubHalf + 8
		local trackGap = math.abs(x) < 60 and z < -hubHalf + 20
		if not inside and not trackGap then
			local at = onGround(x, z, ok)
			if at then
				local d = math.max(math.abs(x) - hubHalf, z - hubHalf)
				if rng:NextNumber() < 0.75 then
					tree(at, rng, d < 40)
				else
					bush(at, rng, d < 40)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------

-- zones = { { decor, zStart, zEnd } }（zStart〜zEnd はベースからの距離。道は -Z へ伸びる）
-- opts.terrain と opts.groundAt はテスト用（ふつうは workspace の地形を使う）
function Scenery.build(
	parent: Instance,
	hubHalf: number,
	zones: { { decor: string, zStart: number, zEnd: number } },
	opts: any?
)
	opts = opts or {}
	folder = Instance.new("Folder")
	folder.Name = "Scenery"
	folder.Parent = parent
	terrain = opts.terrain or workspace.Terrain
	if opts.groundAt then
		groundAt = opts.groundAt
	else
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { terrain }
		groundAt = function(x: number, z: number)
			local hit = workspace:Raycast(v(x, 500, z), v(0, -600, 0), params)
			if hit then
				return hit.Position.Y, hit.Material
			end
			return nil, nil
		end
	end

	if not opts.terrain then
		-- 水の見た目と、空の雲
		terrain.WaterColor = Color3.fromRGB(38, 105, 130)
		terrain.WaterWaveSize = 0.12
		terrain.WaterWaveSpeed = 8
		terrain.WaterReflectance = 0.7
		terrain.WaterTransparency = 0.45
		pcall(function()
			terrain.Decoration = true -- 草の葉がゆれる
		end)
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.55
		clouds.Density = 0.6
		clouds.Parent = terrain
	end

	local rng = Random.new(20261109)
	hubScene(hubHalf, rng)
	local lastEnd = hubHalf
	for _, z in zones do
		local scene = SCENES[z.decor]
		if scene then
			scene(z.zStart, z.zEnd, rng)
		end
		-- 雲の上のゾーンは道の外に地面がないので、道の外からは入れないようにする
		if z.decor == "cloud" then
			for _, sgn in { -1, 1 } do
				part({
					Name = "Edge",
					Size = v(WIDE - 46, 300, 2),
					Position = v(sgn * (WIDE + 46) / 2, 100, -z.zStart),
					Transparency = 1,
					CastShadow = false,
				})
			end
		end
		lastEnd = z.zEnd
	end

	-- 道の中の飾り
	for _, place in pending do
		place()
	end
	table.clear(pending)

	-- 地形のはしから落ちないように、見えない壁でかこむ
	local length = lastEnd + BACK
	local centerZ = (BACK - lastEnd) / 2
	for _, x in { -WIDE, WIDE } do
		part({
			Name = "Edge",
			Size = v(2, 300, length),
			Position = v(x, 100, centerZ),
			Transparency = 1,
			CastShadow = false,
		})
	end
	part({ Name = "Edge", Size = v(WIDE * 2, 300, 2), Position = v(0, 100, BACK), Transparency = 1, CastShadow = false })
	part({
		Name = "Edge",
		Size = v(WIDE * 2, 300, 2),
		Position = v(0, 100, -lastEnd),
		Transparency = 1,
		CastShadow = false,
	})
	return folder
end

return Scenery
