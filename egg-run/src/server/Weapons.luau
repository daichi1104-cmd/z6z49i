-- 武器：手に持つ模型（Tool）を作り、クリック（スマホはタップ）で敵をこうげきする
--
-- 模型は「にぎる所」を原点にして、刃や頭は +Z の方向にのばす
-- （Roblox の昔からの剣と同じ持ち方。Tool.Grip で手に合わせる）

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Enemies = require(script.Parent:WaitForChild("Enemies"))

local Weapons = {}

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

--------------------------------------------------------------------------------
-- 見た目（レア度ごとの材料）
--------------------------------------------------------------------------------

type Look = {
	blade: Color3,
	bladeMat: Enum.Material,
	grip: Color3,
	trim: Color3,
	trimMat: Enum.Material,
	glow: Color3?, -- 刃のふちの光（★3 から）
}

local LOOKS: { Look } = {
	{ -- ★1 ひのき
		blade = Color3.fromRGB(214, 178, 126),
		bladeMat = Enum.Material.Wood,
		grip = Color3.fromRGB(110, 72, 42),
		trim = Color3.fromRGB(150, 110, 70),
		trimMat = Enum.Material.Wood,
	},
	{ -- ★2 てつ
		blade = Color3.fromRGB(175, 180, 190),
		bladeMat = Enum.Material.Metal,
		grip = Color3.fromRGB(90, 55, 35),
		trim = Color3.fromRGB(120, 120, 130),
		trimMat = Enum.Material.Metal,
	},
	{ -- ★3 ミスリル
		blade = Color3.fromRGB(190, 225, 255),
		bladeMat = Enum.Material.Metal,
		grip = Color3.fromRGB(40, 60, 120),
		trim = Color3.fromRGB(210, 220, 235),
		trimMat = Enum.Material.Metal,
		glow = Color3.fromRGB(90, 220, 255),
	},
	{ -- ★4 黄金竜
		blade = Color3.fromRGB(255, 205, 70),
		bladeMat = Enum.Material.Metal,
		grip = Color3.fromRGB(150, 30, 30),
		trim = Color3.fromRGB(255, 225, 120),
		trimMat = Enum.Material.Metal,
		glow = Color3.fromRGB(255, 150, 40),
	},
	{ -- ★5 星くず
		blade = Color3.fromRGB(70, 45, 130),
		bladeMat = Enum.Material.Glass,
		grip = Color3.fromRGB(25, 20, 40),
		trim = Color3.fromRGB(230, 220, 255),
		trimMat = Enum.Material.Metal,
		glow = Color3.fromRGB(255, 120, 255),
	},
}

--------------------------------------------------------------------------------
-- 模型づくり
--------------------------------------------------------------------------------

type Builder = {
	tool: Tool,
	handle: Part,
	look: Look,
	rarity: number,
	tips: { Vector3 }, -- 刃の先など（光の粒を出す場所）
}

-- 部品を、にぎる所から見た位置 cf に置く（あとで Handle に溶接する）
local function piece(
	b: Builder,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	if shape then
		p.Shape = shape
	end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = b.tool
	return p
end

-- Z の方向にのびる円柱（Roblox の円柱は X 方向なので回す）
local function rodZ(
	b: Builder,
	d: number,
	z0: number,
	z1: number,
	color: Color3,
	material: Enum.Material,
	x: number?,
	y: number?
): Part
	return piece(
		b,
		v(math.abs(z1 - z0), d, d),
		CFrame.new(x or 0, y or 0, (z0 + z1) / 2) * CFrame.Angles(0, math.pi / 2, 0),
		color,
		material,
		Enum.PartType.Cylinder
	)
end

local function ball(b: Builder, d: number, pos: Vector3, color: Color3, material: Enum.Material): Part
	return piece(b, v(d, d, d), CFrame.new(pos), color, material, Enum.PartType.Ball)
end

-- 刃：幅 w（X）、厚さ t（Y）、長さ len（Z）。z0 から先へ。先はとがらせる。★3 からふちが光る
local function blade(b: Builder, w: number, t: number, z0: number, len: number, cf: CFrame?)
	local base = cf or CFrame.new()
	local look = b.look
	local body = len * 0.82
	piece(b, v(w, t, body), base * CFrame.new(0, 0, z0 + body / 2), look.blade, look.bladeMat)
	-- 先：45度回した四角を細くして、とがった形に
	local tipLen = len - body
	piece(
		b,
		v(w * 0.72, t * 0.95, w * 0.72),
		base * CFrame.new(0, 0, z0 + body) * CFrame.Angles(0, math.rad(45), 0),
		look.blade,
		look.bladeMat
	)
	if look.glow then
		for _, s in { -1, 1 } do
			piece(
				b,
				v(0.06, t * 1.1, body + tipLen * 0.3),
				base * CFrame.new(s * w / 2, 0, z0 + (body + tipLen * 0.3) / 2),
				look.glow,
				Enum.Material.Neon
			)
		end
	end
	table.insert(b.tips, (base * CFrame.new(0, 0, z0 + len)).Position)
end

-- にぎり（Handle）と、うしろの玉
local function grip(b: Builder, len: number, z0: number?)
	local z = z0 or -len * 0.4
	b.handle.Size = v(len, 0.32, 0.32)
	b.handle.Shape = Enum.PartType.Cylinder
	b.handle.CFrame = CFrame.new(0, 0, z + len / 2) * CFrame.Angles(0, math.pi / 2, 0)
	b.handle.Color = b.look.grip
	b.handle.Material = Enum.Material.Fabric
	ball(b, 0.42, v(0, 0, z - 0.1), b.look.trim, b.look.trimMat)
end

local SHAPES: { [string]: (Builder) -> () } = {}

SHAPES.sword = function(b)
	grip(b, 1.2)
	piece(b, v(1.5, 0.25, 0.28), CFrame.new(0, 0, 0.82), b.look.trim, b.look.trimMat)
	blade(b, 0.42, 0.12, 0.96, 3.4)
end

SHAPES.greatsword = function(b)
	grip(b, 1.8, -0.9)
	piece(b, v(2.2, 0.35, 0.4), CFrame.new(0, 0, 1.1), b.look.trim, b.look.trimMat)
	ball(b, 0.45, v(-1.15, 0, 1.1), b.look.trim, b.look.trimMat)
	ball(b, 0.45, v(1.15, 0, 1.1), b.look.trim, b.look.trimMat)
	blade(b, 0.85, 0.18, 1.3, 5)
end

SHAPES.katana = function(b)
	grip(b, 1.5, -0.6)
	-- 丸いつば
	piece(
		b,
		v(0.12, 0.85, 0.85),
		CFrame.new(0, 0, 0.95) * CFrame.Angles(0, math.pi / 2, 0),
		b.look.trim,
		b.look.trimMat,
		Enum.PartType.Cylinder
	)
	-- 少しそった刃（3つに分けて、だんだん上へ曲げる）
	local cf = CFrame.new(0, 0, 1.0)
	for i = 1, 3 do
		local len = if i == 3 then 1.5 else 1.25
		if i < 3 then
			piece(b, v(0.26, 0.09, len), cf * CFrame.new(0, 0, len / 2), b.look.blade, b.look.bladeMat)
			if b.look.glow then
				piece(
					b,
					v(0.05, 0.1, len),
					cf * CFrame.new(0, -0.02, len / 2) * CFrame.new(0.13, 0, 0),
					b.look.glow,
					Enum.Material.Neon
				)
			end
			cf = cf * CFrame.new(0, 0, len) * CFrame.Angles(math.rad(-6), 0, 0)
		else
			blade(b, 0.26, 0.09, 0, len, cf)
		end
	end
end

SHAPES.dagger = function(b)
	grip(b, 0.8, -0.35)
	piece(b, v(0.9, 0.2, 0.2), CFrame.new(0, 0, 0.5), b.look.trim, b.look.trimMat)
	blade(b, 0.36, 0.1, 0.6, 1.5)
end

SHAPES.spear = function(b)
	b.handle.Size = v(0.6, 0.3, 0.3)
	b.handle.Shape = Enum.PartType.Cylinder
	b.handle.CFrame = CFrame.Angles(0, math.pi / 2, 0)
	b.handle.Color = b.look.grip
	b.handle.Material = Enum.Material.Fabric
	rodZ(b, 0.24, -2.4, 5.2, b.look.trim:Lerp(b.look.grip, 0.6), Enum.Material.Wood)
	ball(b, 0.32, v(0, 0, -2.45), b.look.trim, b.look.trimMat)
	rodZ(b, 0.36, 5.1, 5.5, b.look.trim, b.look.trimMat)
	blade(b, 0.48, 0.12, 5.5, 1.7)
	-- 穂先の横の小さな刃
	for _, s in { -1, 1 } do
		piece(
			b,
			v(0.5, 0.1, 0.18),
			CFrame.new(s * 0.32, 0, 5.6) * CFrame.Angles(0, s * math.rad(-30), 0),
			b.look.blade,
			b.look.bladeMat
		)
	end
end

SHAPES.scythe = function(b)
	grip(b, 0.9, -0.45)
	rodZ(b, 0.24, -1.6, 4.4, b.look.trim:Lerp(b.look.grip, 0.6), Enum.Material.Wood)
	rodZ(b, 0.34, 4.2, 4.6, b.look.trim, b.look.trimMat)
	-- 上の刃：手に持ったとき縦（+X）へ出て、手もとの方へ曲がる
	local cf = CFrame.new(0.2, 0, 4.35) * CFrame.Angles(0, math.rad(90), 0)
	for i = 1, 4 do
		local len = 0.95
		local w = 0.55 - i * 0.08
		piece(b, v(w, 0.1, len), cf * CFrame.new(0, 0, len / 2), b.look.blade, b.look.bladeMat)
		if b.look.glow then
			-- 内がわ（曲がる方）の刃が光る
			piece(b, v(0.06, 0.11, len), cf * CFrame.new(w / 2, 0, len / 2), b.look.glow, Enum.Material.Neon)
		end
		cf = cf * CFrame.new(0, 0, len) * CFrame.Angles(0, math.rad(22), 0)
	end
	table.insert(b.tips, cf.Position)
end

SHAPES.axe = function(b)
	grip(b, 1, -0.5)
	rodZ(b, 0.26, -0.6, 3.1, b.look.trim:Lerp(b.look.grip, 0.6), Enum.Material.Wood)
	-- 頭：手に持ったとき縦（+X）に、大きな刃
	piece(b, v(0.5, 0.3, 0.7), CFrame.new(0, 0, 2.8), b.look.trim, b.look.trimMat)
	piece(b, v(1.5, 0.16, 1.1), CFrame.new(0.85, 0, 2.8), b.look.blade, b.look.bladeMat)
	piece(b, v(0.5, 0.16, 1.5), CFrame.new(1.55, 0, 2.8), b.look.blade, b.look.bladeMat)
	if b.look.glow then
		piece(b, v(0.1, 0.17, 1.55), CFrame.new(1.82, 0, 2.8), b.look.glow, Enum.Material.Neon)
	end
	table.insert(b.tips, v(1.8, 0, 2.8))
end

SHAPES.hammer = function(b)
	grip(b, 1, -0.5)
	rodZ(b, 0.28, -0.6, 3, b.look.trim:Lerp(b.look.grip, 0.6), Enum.Material.Wood)
	-- 頭：横向きの太い円柱と、両はしの金具
	piece(
		b,
		v(2.2, 1.2, 1.2),
		CFrame.new(0, 0, 3.2) * CFrame.Angles(0, 0, math.pi / 2),
		b.look.blade,
		b.look.bladeMat,
		Enum.PartType.Cylinder
	)
	for _, s in { -1, 1 } do
		piece(
			b,
			v(0.25, 1.35, 1.35),
			CFrame.new(0, s * 1.05, 3.2) * CFrame.Angles(0, 0, math.pi / 2),
			b.look.glow or b.look.trim,
			if b.look.glow then Enum.Material.Neon else b.look.trimMat,
			Enum.PartType.Cylinder
		)
	end
	table.insert(b.tips, v(0, 1.2, 3.2))
end

SHAPES.bow = function(b)
	-- にぎり（縦にまっすぐ）。弓の弧は Y 方向に広がり、前（+Z）へふくらむ
	b.handle.Size = v(0.8, 0.3, 0.3)
	b.handle.Shape = Enum.PartType.Cylinder
	b.handle.CFrame = CFrame.Angles(0, 0, math.pi / 2)
	b.handle.Color = b.look.grip
	b.handle.Material = Enum.Material.Fabric
	local tipsY = {}
	for _, s in { -1, 1 } do
		local cf = CFrame.new(0, s * 0.4, 0) * CFrame.Angles(s * math.rad(-90), 0, 0)
		for i = 1, 3 do
			local len = 0.9
			piece(b, v(0.22, 0.16 - i * 0.02, len), cf * CFrame.new(0, 0, len / 2), b.look.blade, b.look.bladeMat)
			cf = cf * CFrame.new(0, 0, len) * CFrame.Angles(s * math.rad(-20), 0, 0)
		end
		ball(
			b,
			0.22,
			cf.Position,
			b.look.glow or b.look.trim,
			if b.look.glow then Enum.Material.Neon else b.look.trimMat
		)
		tipsY[s] = cf.Position
	end
	-- 弦
	local top, bottom = tipsY[1], tipsY[-1]
	local mid = (top + bottom) / 2
	piece(
		b,
		v(0.04, (top - bottom).Magnitude, 0.04),
		CFrame.new(mid),
		Color3.fromRGB(240, 240, 240),
		Enum.Material.SmoothPlastic
	)
	table.insert(b.tips, top)
end

SHAPES.staff = function(b)
	grip(b, 0.9, -0.45)
	rodZ(b, 0.26, -1.8, 3.8, b.look.trim:Lerp(b.look.grip, 0.6), Enum.Material.Wood)
	-- 先：つめで玉をつかむ
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2
		piece(
			b,
			v(0.12, 0.12, 0.9),
			CFrame.new(math.cos(a) * 0.32, math.sin(a) * 0.32, 4.15)
				* CFrame.Angles(math.sin(a) * 0.4, -math.cos(a) * 0.4, 0),
			b.look.trim,
			b.look.trimMat
		)
	end
	local orbColor = b.look.glow or b.look.blade
	local orb = ball(b, 0.85, v(0, 0, 4.45), orbColor, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = orbColor
	light.Range = 8
	light.Brightness = 1.5
	light.Parent = orb
	table.insert(b.tips, v(0, 0, 4.45))
end

-- 武器の Tool を作る
function Weapons.build(weapon): Tool
	local tool = Instance.new("Tool")
	tool.Name = weapon.name
	tool.ToolTip = string.format("%s %s", string.rep("★", weapon.rarity), weapon.name)
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	-- 昔からの剣と同じ持ち方：にぎる所が手、+Z が前
	tool.Grip = CFrame.new(0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 0)
	tool:SetAttribute("WeaponId", weapon.id)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = v(0.3, 0.3, 1)
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.CastShadow = false
	handle.Parent = tool

	local b: Builder = { tool = tool, handle = handle, look = LOOKS[weapon.rarity], rarity = weapon.rarity, tips = {} }
	local build = SHAPES[weapon.shape] or SHAPES.sword
	build(b)

	-- Handle の位置は にぎる所（原点）にそろえ、ほかの部品を溶接する
	local offset = handle.CFrame
	for _, p in tool:GetChildren() do
		if p:IsA("BasePart") and p ~= handle then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = p
			weld.Parent = p
		end
	end
	-- Handle の形を変えたもの（円柱など）は、向きがずれるので Grip でもどす
	tool.Grip = offset:Inverse() * tool.Grip

	-- レアなほど光る
	local look = b.look
	if weapon.rarity >= 4 then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = look.glow or look.blade
		sparkles.Parent = handle
		local light = Instance.new("PointLight")
		light.Color = look.glow or look.blade
		light.Range = 6 + weapon.rarity
		light.Brightness = 1
		light.Parent = handle
	end
	if weapon.rarity >= 5 then
		for _, tip in b.tips do
			local spot = piece(b, v(0.2, 0.2, 0.2), CFrame.new(tip), look.glow or look.blade, Enum.Material.Neon)
			spot.Transparency = 1
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = spot
			weld.Parent = spot
			local motes = Instance.new("ParticleEmitter")
			motes.Color = ColorSequence.new(look.glow or look.blade, Color3.fromRGB(255, 255, 255))
			motes.LightEmission = 1
			motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
			motes.Transparency = NumberSequence.new(0.1, 1)
			motes.Lifetime = NumberRange.new(0.5, 0.9)
			motes.Rate = 18
			motes.Speed = NumberRange.new(0.5, 1.5)
			motes.SpreadAngle = Vector2.new(180, 180)
			motes.Parent = spot
		end
	end
	return tool
end

--------------------------------------------------------------------------------
-- こうげき
--------------------------------------------------------------------------------

local folder: Folder
local lastSwing: { [Player]: number } = {}

local function effectFolder(): Folder
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "WeaponEffects"
		folder.Parent = workspace
	end
	return folder
end

local function fx(size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.CFrame = cf
	if shape then
		p.Shape = shape
	end
	p.Parent = effectFolder()
	return p
end

-- ふった跡：前に弧をえがく光（arc が 360 のときは、ぐるっと一周）
local function slashEffect(origin: Vector3, facing: Vector3, range: number, arc: number, color: Color3)
	local n = math.clamp(math.floor(arc / 20), 4, 18)
	local right = facing:Cross(Vector3.yAxis)
	local radius = math.max(3, range * 0.65)
	for i = 0, n - 1 do
		local t = if n == 1 then 0 else i / (n - 1) - 0.5
		local a = math.rad(arc) * t
		local dir = facing * math.cos(a) + right * math.sin(a)
		local pos = origin + dir * radius + Vector3.new(0, 0.5 - t * 0.6, 0)
		local p = fx(
			v(0.35, 0.35, radius * math.rad(arc) / n + 0.4),
			CFrame.lookAt(pos, pos + right * math.cos(a) - facing * math.sin(a)),
			color
		)
		p.Transparency = 0.15
		task.delay(i * 0.012, function()
			TweenService:Create(p, TweenInfo.new(0.25), { Transparency = 1, Size = p.Size * v(0.3, 0.3, 1) }):Play()
		end)
		Debris:AddItem(p, 0.5)
	end
end

-- ハンマー：地面に広がる輪
local function shockwave(origin: Vector3, radius: number, color: Color3)
	local ring = fx(
		v(0.4, 2, 2),
		CFrame.new(origin - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		Enum.PartType.Cylinder
	)
	ring.Transparency = 0.2
	TweenService:Create(
		ring,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad),
		{ Size = v(0.4, radius * 2, radius * 2), Transparency = 1 }
	):Play()
	Debris:AddItem(ring, 0.5)
end

-- 当たった敵の上に、ダメージの数字を出す
local function damageNumber(at: Vector3, amount: number, crit: boolean)
	local anchor = fx(v(0.2, 0.2, 0.2), CFrame.new(at), Color3.new(1, 1, 1))
	anchor.Transparency = 1
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(if crit then 130 else 90, if crit then 44 else 34)
	bb.StudsOffset = Vector3.new(math.random(-10, 10) / 10, 2, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 120
	bb.Parent = anchor
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = if crit then Color3.fromRGB(255, 220, 60) else Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0
	t.Text = if crit then string.format("会心！%d", amount) else tostring(amount)
	t.Parent = bb
	TweenService:Create(bb, TweenInfo.new(0.7), { StudsOffset = bb.StudsOffset + Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(t, TweenInfo.new(0.7), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 0.75)
end

local function hit(player: Player, weapon, e, mult: number)
	local crit = weapon.crit ~= nil and math.random() < weapon.crit
	local amount = math.floor(weapon.damage * mult * (if crit then 2 else 1) + 0.5)
	local at = Enemies.centerOf(e) + Vector3.new(0, e.size * 0.4, 0)
	if weapon.stun then
		Enemies.stun(e, weapon.stun)
	end
	Enemies.damage(e, amount, player, "weapon")
	damageNumber(at, amount, crit)
end

-- 遠くへ飛ばす（弓の矢・杖の魔法の玉）
local function shoot(player: Player, weapon, from: Vector3, target, mult: number)
	local color = LOOKS[weapon.rarity].glow or LOOKS[weapon.rarity].blade
	local to = Enemies.centerOf(target)
	local isArrow = weapon.shape == "bow"
	local p = if isArrow
		then fx(v(0.2, 0.2, 2.4), CFrame.lookAt(from, to), color)
		else fx(v(1.2, 1.2, 1.2), CFrame.new(from), color, Enum.PartType.Ball)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 8
	light.Parent = p
	local travel = math.clamp((to - from).Magnitude / 160, 0.06, 0.45)
	TweenService
		:Create(
			p,
			TweenInfo.new(travel, Enum.EasingStyle.Linear),
			{ CFrame = CFrame.lookAt(to, to + (to - from).Unit) }
		)
		:Play()
	task.delay(travel, function()
		p:Destroy()
		if not Enemies.isAlive(target) then
			return
		end
		hit(player, weapon, target, mult)
		if weapon.splash then
			shockwave(to + Vector3.new(0, 2.5, 0), weapon.splash, color)
			for _, other in Enemies.findInRange(to, weapon.splash) do
				if other ~= target then
					hit(player, weapon, other, mult * 0.6)
				end
			end
		end
	end)
end

-- 近くの敵のうち、正面から arc の角度の中で、range にとどくもの
local function targetsInFront(origin: Vector3, facing: Vector3, range: number, arc: number)
	local found = {}
	local cosHalf = math.cos(math.rad(math.min(arc, 359) / 2))
	for _, e in Enemies.findInRange(origin, range + 10) do
		local center = Enemies.centerOf(e)
		local to = Vector3.new(center.X - origin.X, 0, center.Z - origin.Z)
		local dist = to.Magnitude - e.size * 0.45
		if dist <= range then
			local inArc = arc >= 360 or to.Magnitude < 0.1 or facing:Dot(to.Unit) >= cosHalf
			if inArc then
				table.insert(found, { enemy = e, dist = dist })
			end
		end
	end
	table.sort(found, function(a, b)
		return a.dist < b.dist
	end)
	return found
end

-- ふる。mult = こうげき力の倍率（ふだんは 1）
function Weapons.swing(player: Player, tool: Tool, weapon, mult: number?)
	local m = mult or 1
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	if now - (lastSwing[player] or 0) < weapon.cooldown * 0.9 then
		return
	end
	lastSwing[player] = now

	-- ふる動き（Roblox の Animate が toolanim を見て、うでをふる）
	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = if weapon.lunge then "Lunge" else "Slash"
	anim.Parent = tool
	Debris:AddItem(anim, 0.3)

	local look = root.CFrame.LookVector
	local facing = Vector3.new(look.X, 0, look.Z)
	facing = if facing.Magnitude > 0.01 then facing.Unit else Vector3.new(0, 0, -1)
	local color = LOOKS[weapon.rarity].glow or LOOKS[weapon.rarity].blade
	local origin = root.Position

	if weapon.ranged then
		-- 正面の近くにいる敵をねらう（いなければ、届く範囲で一番近い敵）
		local list = targetsInFront(origin, facing, weapon.range, weapon.arc)
		if #list == 0 then
			list = targetsInFront(origin, facing, weapon.range, 360)
		end
		-- 手の少し前・上から飛ばす
		local from = origin + facing * 2.5 + Vector3.new(0, 1.2, 0)
		if #list > 0 then
			shoot(player, weapon, from, list[1].enemy, m)
		else
			slashEffect(origin, facing, 4, 40, color)
		end
		return
	end

	if weapon.shape == "hammer" then
		shockwave(origin, weapon.range, color)
	else
		slashEffect(origin, facing, weapon.range, weapon.arc, color)
	end
	for _, info in targetsInFront(origin, facing, weapon.range, weapon.arc) do
		hit(player, weapon, info.enemy, m)
	end
end

function Weapons.forget(player: Player)
	lastSwing[player] = nil
end

return Weapons
