-- 防具の見た目：キャラの体に、部品を溶接してつける（頭・体・うで・足・せなか）
-- 向き：キャラの前は -Z、上は +Y。部品はぜんぶ「当たらない・重さなし」

local Armor = {}

local FOLDER = "ArmorParts"

type Look = {
	main: Color3,
	mat: Enum.Material,
	trim: Color3,
	trimMat: Enum.Material,
	gem: Color3,
}

-- レア度ごとの材料の色
local LOOKS: { Look } = {
	{ -- ★1 かわ
		main = Color3.fromRGB(150, 100, 60),
		mat = Enum.Material.Leather,
		trim = Color3.fromRGB(90, 60, 38),
		trimMat = Enum.Material.Leather,
		gem = Color3.fromRGB(215, 190, 140),
	},
	{ -- ★2 てつ
		main = Color3.fromRGB(165, 170, 182),
		mat = Enum.Material.Metal,
		trim = Color3.fromRGB(80, 85, 98),
		trimMat = Enum.Material.Metal,
		gem = Color3.fromRGB(220, 225, 235),
	},
	{ -- ★3 ミスリル
		main = Color3.fromRGB(105, 195, 245),
		mat = Enum.Material.Metal,
		trim = Color3.fromRGB(235, 242, 252),
		trimMat = Enum.Material.Metal,
		gem = Color3.fromRGB(120, 255, 235),
	},
	{ -- ★4 黄金竜
		main = Color3.fromRGB(250, 195, 45),
		mat = Enum.Material.Metal,
		trim = Color3.fromRGB(185, 40, 40),
		trimMat = Enum.Material.Metal,
		gem = Color3.fromRGB(255, 90, 60),
	},
	{ -- ★5 星くず
		main = Color3.fromRGB(88, 60, 165),
		mat = Enum.Material.Glass,
		trim = Color3.fromRGB(240, 225, 255),
		trimMat = Enum.Material.Neon,
		gem = Color3.fromRGB(255, 120, 255),
	},
}

-- 体の「場所」：どの部品の、どこに、どの大きさの箱があるか（R15 でも R6 でも同じように使う）
type Region = { part: BasePart, cf: CFrame, size: Vector3 }
type Rig = { [string]: Region }

local function region(part: Instance?, cf: CFrame?, size: Vector3?): Region?
	if part and part:IsA("BasePart") then
		return { part = part, cf = cf or CFrame.new(), size = size or part.Size }
	end
	return nil
end

local function rigOf(character: Model): Rig
	local rig: Rig = {}
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		-- R6 の頭は 部品が横長（2×1×1）で、見た目は 1.25 の立方体
		local s = if character:FindFirstChild("UpperTorso") then head.Size.Y else 1.25
		rig.head = { part = head, cf = CFrame.new(), size = Vector3.new(s, s, s) }
	end
	if character:FindFirstChild("UpperTorso") then
		rig.chest = region(character:FindFirstChild("UpperTorso")) :: Region
		rig.waist = region(character:FindFirstChild("LowerTorso")) :: Region
		for _, side in { "Left", "Right" } do
			rig["shoulder" .. side] = region(character:FindFirstChild(side .. "UpperArm")) :: Region
			rig["forearm" .. side] = region(character:FindFirstChild(side .. "LowerArm")) :: Region
			rig["hand" .. side] = region(character:FindFirstChild(side .. "Hand")) :: Region
			rig["shin" .. side] = region(character:FindFirstChild(side .. "LowerLeg")) :: Region
			rig["foot" .. side] = region(character:FindFirstChild(side .. "Foot")) :: Region
		end
	else
		local torso = character:FindFirstChild("Torso")
		rig.chest = region(torso, CFrame.new(0, 0.3, 0), Vector3.new(2, 1.4, 1)) :: Region
		rig.waist = region(torso, CFrame.new(0, -0.75, 0), Vector3.new(2, 0.5, 1)) :: Region
		for _, side in { "Left", "Right" } do
			local arm = character:FindFirstChild(side .. " Arm")
			local leg = character:FindFirstChild(side .. " Leg")
			rig["shoulder" .. side] = region(arm, CFrame.new(0, 0.6, 0), Vector3.new(1, 0.8, 1)) :: Region
			rig["forearm" .. side] = region(arm, CFrame.new(0, -0.35, 0), Vector3.new(1, 0.9, 1)) :: Region
			rig["hand" .. side] = region(arm, CFrame.new(0, -0.85, 0), Vector3.new(1, 0.3, 1)) :: Region
			rig["shin" .. side] = region(leg, CFrame.new(0, -0.3, 0), Vector3.new(1, 0.9, 1)) :: Region
			rig["foot" .. side] = region(leg, CFrame.new(0, -0.85, 0), Vector3.new(1, 0.3, 1)) :: Region
		end
	end
	return rig
end

type Builder = { folder: Instance, look: Look, rarity: number, rig: Rig }

-- 場所 r の まん中から見た位置 cf に、大きさ size の部品をつける
local function put(
	b: Builder,
	r: Region,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = "ArmorPiece"
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	local offset = r.cf * cf
	p.CFrame = r.part.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = r.part
	weld.Part1 = p
	weld.C0 = offset
	weld.Parent = p
	p.Parent = b.folder
	return p
end

local function main(b: Builder, r: Region, size: Vector3, cf: CFrame, shape: Enum.PartType?): Part
	return put(b, r, size, cf, b.look.main, b.look.mat, shape)
end
local function trim(b: Builder, r: Region, size: Vector3, cf: CFrame, shape: Enum.PartType?): Part
	return put(b, r, size, cf, b.look.trim, b.look.trimMat, shape)
end
-- 宝石（光る玉）
local function gem(b: Builder, r: Region, d: number, cf: CFrame): Part
	return put(b, r, Vector3.new(d, d, d), cf, b.look.gem, Enum.Material.Neon, Enum.PartType.Ball)
end
-- 立てた円柱（Roblox の円柱は X 軸にのびるので、Z 軸で 90 度回す）
local UP = CFrame.Angles(0, 0, math.pi / 2)
local function disc(b: Builder, r: Region, d: number, h: number, cf: CFrame, color: Color3, mat: Enum.Material): Part
	return put(b, r, Vector3.new(h, d, d), cf * UP, color, mat, Enum.PartType.Cylinder)
end
-- ★5 はキラキラする
local function sparkle(b: Builder, p: Part)
	if b.rarity >= 5 then
		local s = Instance.new("Sparkles")
		s.SparkleColor = b.look.gem
		s.Parent = p
	end
end

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end
local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end
local function sides(): { { name: string, sign: number } }
	return { { name = "Left", sign = -1 }, { name = "Right", sign = 1 } }
end

local builders: { [string]: (Builder) -> () } = {}

-- かぶと：顔は見えるように、上・後ろ・横をおおう
function builders.helm(b: Builder)
	local r = b.rig.head
	if not r then
		return
	end
	local s = r.size.Y
	local top = main(b, r, v(1.14 * s, 0.32 * s, 1.14 * s), at(0, 0.43 * s, 0))
	main(b, r, v(1.14 * s, 0.78 * s, 0.14 * s), at(0, -0.02 * s, 0.53 * s))
	for _, x in { -1, 1 } do
		main(b, r, v(0.14 * s, 0.62 * s, 0.72 * s), at(x * 0.53 * s, -0.06 * s, 0.2 * s))
	end
	trim(b, r, v(1.2 * s, 0.1 * s, 1.2 * s), at(0, 0.28 * s, 0))
	if b.rarity >= 2 then
		-- 鼻あて
		trim(b, r, v(0.1 * s, 0.42 * s, 0.08 * s), at(0, 0.08 * s, -0.57 * s))
	end
	if b.rarity >= 3 then
		-- てっぺんの かざり
		trim(b, r, v(0.1 * s, 0.26 * s, 0.95 * s), at(0, 0.7 * s, 0.05 * s))
		gem(b, r, 0.2 * s, at(0, 0.44 * s, -0.58 * s))
	end
	if b.rarity >= 4 then
		-- 角
		for _, x in { -1, 1 } do
			trim(
				b,
				r,
				v(0.15 * s, 0.6 * s, 0.15 * s),
				at(x * 0.66 * s, 0.66 * s, 0) * CFrame.Angles(0, 0, -x * math.rad(28))
			)
		end
	end
	sparkle(b, top)
end

-- とんがりぼうし：つばと、先へ細くなる とんがり
function builders.hat(b: Builder)
	local r = b.rig.head
	if not r then
		return
	end
	local s = r.size.Y
	local L = b.look
	disc(b, r, 2.0 * s, 0.08 * s, at(0, 0.5 * s, 0), L.main, L.mat)
	disc(b, r, 1.16 * s, 0.12 * s, at(0, 0.6 * s, 0), L.trim, L.trimMat)
	local widths = { 1.1, 0.86, 0.6, 0.34 }
	local last
	for i, w in widths do
		-- 上へ行くほど、少し後ろへ たおれる
		last = disc(b, r, w * s, 0.32 * s, at(0, (0.5 + i * 0.3) * s, (i - 1) * 0.07 * s), L.main, L.mat)
	end
	if b.rarity >= 2 then
		trim(b, r, v(0.24 * s, 0.2 * s, 0.06 * s), at(0, 0.6 * s, -0.59 * s))
	end
	if b.rarity >= 3 then
		gem(b, r, 0.16 * s, at(0, 0.6 * s, -0.62 * s))
	end
	if b.rarity >= 4 then
		-- 先の星
		gem(b, r, 0.28 * s, at(0, 1.92 * s, 0.26 * s))
	end
	if last then
		sparkle(b, last)
	end
end

-- よろい：胸当て・かた当て・ベルト
function builders.plate(b: Builder)
	local c, w = b.rig.chest, b.rig.waist
	if not c then
		return
	end
	local s = c.size
	local chest = main(b, c, v(s.X * 1.14, s.Y * 1.02, s.Z * 1.28), at(0, 0, 0))
	-- 胸のまん中の すじと、えり
	trim(b, c, v(s.X * 0.14, s.Y * 0.9, 0.06), at(0, 0, -s.Z * 0.66))
	trim(b, c, v(s.X * 0.8, s.Y * 0.12, s.Z * 1.34), at(0, s.Y * 0.48, 0))
	if w then
		trim(b, w, v(w.size.X * 1.14, w.size.Y * 0.6, w.size.Z * 1.24), at(0, w.size.Y * 0.1, 0))
		if b.rarity >= 3 then
			gem(b, w, 0.26, at(0, w.size.Y * 0.1, -w.size.Z * 0.66))
		end
	end
	for _, side in sides() do
		local sh = b.rig["shoulder" .. side.name]
		if sh then
			local z = sh.size
			main(b, sh, v(z.X * 1.4, z.Y * 0.42, z.Z * 1.4), at(side.sign * z.X * 0.08, z.Y * 0.36, 0))
			if b.rarity >= 2 then
				trim(b, sh, v(z.X * 1.5, z.Y * 0.12, z.Z * 1.5), at(side.sign * z.X * 0.08, z.Y * 0.14, 0))
			end
			if b.rarity >= 4 then
				-- かたの とげ
				trim(
					b,
					sh,
					v(0.16, 0.55, 0.16),
					at(side.sign * z.X * 0.55, z.Y * 0.72, 0) * CFrame.Angles(0, 0, -side.sign * math.rad(35))
				)
			end
		end
	end
	if b.rarity >= 4 then
		gem(b, c, 0.34, at(0, s.Y * 0.12, -s.Z * 0.68))
	end
	sparkle(b, chest)
end

-- ローブ：体をおおう服と、下へ広がる すそ
function builders.robe(b: Builder)
	local c, w = b.rig.chest, b.rig.waist
	if not c then
		return
	end
	local s = c.size
	local k = s.X / 2
	local chest = main(b, c, v(s.X * 1.1, s.Y * 1.02, s.Z * 1.22), at(0, 0, 0))
	trim(b, c, v(s.X * 0.9, s.Y * 0.14, s.Z * 1.3), at(0, s.Y * 0.47, 0))
	-- 前の たれ布
	trim(b, c, v(s.X * 0.22, s.Y * 0.95, 0.06), at(0, 0, -s.Z * 0.63))
	if w then
		local z = w.size
		for i = 1, 3 do
			local piece = if i == 3 then trim else main
			piece(
				b,
				w,
				v(z.X * (1.08 + 0.1 * i), 0.5 * k, z.Z * (1.25 + 0.22 * i)),
				at(0, z.Y * 0.5 - (i - 0.5) * 0.5 * k, 0)
			)
		end
		if b.rarity >= 2 then
			-- おび
			trim(b, w, v(z.X * 1.16, 0.16 * k, z.Z * 1.3), at(0, z.Y * 0.5, 0))
		end
		if b.rarity >= 3 then
			gem(b, w, 0.24 * k, at(0, z.Y * 0.5, -z.Z * 0.68))
		end
	end
	if b.rarity >= 4 then
		-- かたの かざり
		for _, x in { -1, 1 } do
			gem(b, c, 0.26 * k, at(x * s.X * 0.42, s.Y * 0.52, -s.Z * 0.5))
		end
	end
	sparkle(b, chest)
end

-- こて：うでの先と 手をおおう
function builders.gauntlet(b: Builder)
	for _, side in sides() do
		local f, h = b.rig["forearm" .. side.name], b.rig["hand" .. side.name]
		if f then
			local z = f.size
			local p = main(b, f, v(z.X * 1.28, z.Y * 0.9, z.Z * 1.28), at(0, 0, 0))
			trim(b, f, v(z.X * 1.44, z.Y * 0.2, z.Z * 1.44), at(0, z.Y * 0.4, 0))
			if b.rarity >= 3 then
				gem(b, f, 0.2, at(side.sign * z.X * 0.66, 0, 0))
			end
			if b.rarity >= 4 then
				for i = -1, 1, 2 do
					trim(
						b,
						f,
						v(0.4, 0.12, 0.12),
						at(side.sign * z.X * 0.8, i * z.Y * 0.22, 0) * CFrame.Angles(0, 0, side.sign * math.rad(20))
					)
				end
			end
			sparkle(b, p)
		end
		if h then
			local z = h.size
			trim(b, h, v(z.X * 1.22, z.Y * 1.02, z.Z * 1.22), at(0, 0, 0))
		end
	end
end

-- うでわ：うでの先の輪
function builders.bracelet(b: Builder)
	for _, side in sides() do
		local f = b.rig["forearm" .. side.name]
		if f then
			local z = f.size
			local ring = main(b, f, v(z.X * 1.32, z.Y * 0.24, z.Z * 1.32), at(0, -z.Y * 0.3, 0))
			if b.rarity >= 2 then
				trim(b, f, v(z.X * 1.4, z.Y * 0.08, z.Z * 1.4), at(0, -z.Y * 0.3, 0))
				main(b, f, v(z.X * 1.26, z.Y * 0.12, z.Z * 1.26), at(0, z.Y * 0.05, 0))
			end
			if b.rarity >= 3 then
				gem(b, f, 0.22, at(side.sign * z.X * 0.68, -z.Y * 0.3, 0))
			end
			if b.rarity >= 4 then
				gem(b, f, 0.18, at(0, -z.Y * 0.3, -z.Z * 0.68))
				gem(b, f, 0.18, at(0, -z.Y * 0.3, z.Z * 0.68))
			end
			sparkle(b, ring)
		end
	end
end

-- ブーツ：すねと足をおおう。つま先は前（-Z）へ少し出る
function builders.boots(b: Builder)
	for _, side in sides() do
		local sh, ft = b.rig["shin" .. side.name], b.rig["foot" .. side.name]
		if sh then
			local z = sh.size
			local p = main(b, sh, v(z.X * 1.26, z.Y * 0.8, z.Z * 1.26), at(0, -z.Y * 0.1, 0))
			trim(b, sh, v(z.X * 1.4, z.Y * 0.16, z.Z * 1.4), at(0, z.Y * 0.3, 0))
			if b.rarity >= 3 then
				gem(b, sh, 0.18, at(0, z.Y * 0.3, -z.Z * 0.7))
			end
			if b.rarity >= 4 then
				-- かかとの 小さな はね
				for i = 0, 1 do
					trim(
						b,
						sh,
						v(0.08, 0.2, 0.55 - i * 0.15),
						at(side.sign * z.X * 0.7, -z.Y * 0.1 + i * 0.2, z.Z * 0.35)
							* CFrame.Angles(math.rad(25 + i * 15), 0, 0)
					)
				end
			end
			sparkle(b, p)
		end
		if ft then
			local z = ft.size
			main(b, ft, v(z.X * 1.26, z.Y * 1.04, z.Z * 1.45), at(0, 0, -z.Z * 0.14))
			trim(b, ft, v(z.X * 1.3, z.Y * 0.3, z.Z * 1.5), at(0, -z.Y * 0.4, -z.Z * 0.14))
		end
	end
end

-- すねあて：すねの前の板と、ひざ当て
function builders.greaves(b: Builder)
	for _, side in sides() do
		local sh = b.rig["shin" .. side.name]
		if sh then
			local z = sh.size
			local p = main(b, sh, v(z.X * 1.12, z.Y * 0.9, z.Z * 0.4), at(0, -z.Y * 0.02, -z.Z * 0.5))
			trim(b, sh, v(z.X * 1.2, z.Y * 0.28, z.Z * 0.5), at(0, z.Y * 0.45, -z.Z * 0.52))
			if b.rarity >= 2 then
				-- 後ろへ回る 2本の おび
				for i = -1, 1, 2 do
					trim(b, sh, v(z.X * 1.16, z.Y * 0.1, z.Z * 1.16), at(0, i * z.Y * 0.22, 0))
				end
			end
			if b.rarity >= 3 then
				gem(b, sh, 0.2, at(0, z.Y * 0.45, -z.Z * 0.8))
			end
			if b.rarity >= 4 then
				trim(
					b,
					sh,
					v(0.12, z.Y * 0.5, 0.12),
					at(0, z.Y * 0.78, -z.Z * 0.6) * CFrame.Angles(math.rad(-15), 0, 0)
				)
			end
			sparkle(b, p)
		end
	end
end

-- マント：せなかに下がる布
function builders.cape(b: Builder)
	local c = b.rig.chest
	if not c then
		return
	end
	local s = c.size
	local k = s.X / 2
	local length = k * (2.7 + 0.25 * b.rarity)
	-- 上のふちを軸に、少し後ろへ ひらく
	local hinge = at(0, s.Y * 0.45, s.Z * 0.5 + 0.1) * CFrame.Angles(math.rad(-9), 0, 0)
	local cloth = main(b, c, v(s.X * 1.3, length, 0.1), hinge * at(0, -length / 2, 0))
	trim(b, c, v(s.X * 1.34, 0.16 * k, 0.24), hinge * at(0, -0.04, 0))
	if b.rarity >= 2 then
		-- すその ふち
		trim(b, c, v(s.X * 1.34, 0.14 * k, 0.12), hinge * at(0, -length + 0.07 * k, 0))
	end
	if b.rarity >= 3 then
		-- とめ金
		for _, x in { -1, 1 } do
			gem(b, c, 0.24 * k, at(x * s.X * 0.42, s.Y * 0.5, -s.Z * 0.45))
		end
	end
	if b.rarity >= 4 then
		-- まん中の もよう
		trim(b, c, v(s.X * 0.5, s.X * 0.5, 0.12), hinge * at(0, -length * 0.45, 0) * CFrame.Angles(0, 0, math.rad(45)))
	end
	sparkle(b, cloth)
end

-- つばさ：せなかから、左右に 3枚ずつ はねが広がる
function builders.wings(b: Builder)
	local c = b.rig.chest
	if not c then
		return
	end
	local s = c.size
	local k = s.X / 2
	local reach = k * (1.5 + 0.28 * b.rarity)
	for _, side in sides() do
		-- つけ根（せなかの上のほう）から、ななめ後ろへ
		local root = at(side.sign * s.X * 0.22, s.Y * 0.25, s.Z * 0.5 + 0.08)
			* CFrame.Angles(0, -side.sign * math.rad(28), 0)
		trim(b, c, v(0.3 * k, 0.3 * k, 0.3 * k), root, Enum.PartType.Ball)
		for i = 1, 3 do
			-- 上の はねほど長く、上を向く
			local len = reach * (1.15 - 0.2 * i)
			local angle = math.rad(62 - i * 34)
			local feather = root * CFrame.Angles(0, 0, side.sign * angle) * at(side.sign * len / 2, 0, 0)
			local piece = if i == 1 and b.rarity >= 2 then trim else main
			local p = piece(b, c, v(len, 0.5 * k, 0.09), feather)
			if i == 1 then
				sparkle(b, p)
			end
			if b.rarity >= 3 then
				gem(b, c, 0.16 * k, feather * at(side.sign * len / 2, 0, 0))
			end
		end
	end
end

-- 身につけている防具（場所 → 防具）を、キャラにつける。前のものは消して作り直す
function Armor.apply(character: Model?, pieces: { any })
	if not character then
		return
	end
	local old = character:FindFirstChild(FOLDER)
	if old then
		old:Destroy()
	end
	if #pieces == 0 then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER
	folder.Parent = character
	local rig = rigOf(character)
	for _, armor in pieces do
		local build = builders[armor.kind]
		local look = LOOKS[armor.rarity]
		if build and look then
			build({ folder = folder, look = look, rarity = armor.rarity, rig = rig })
		end
	end
end

return Armor
