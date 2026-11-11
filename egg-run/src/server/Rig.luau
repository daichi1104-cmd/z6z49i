-- 生き物の模型を「骨」と「部品」で組み立てるしくみ
--
-- ・部品はすべて、どれかの骨にくっつける（Weld）
-- ・骨どうしは Motor6D でつなぎ、C0 を変えると羽ばたき・しっぽ・あごが動く
-- ・根元の骨（Root）だけを Anchored にして動かすので、毎フレーム送るのは
--   Root の位置と、動かした骨の角度だけですむ（スマホでも重くならない）
--
-- 座標はすべて「模型の中心から見た位置」で、-Z 方向が前。
-- scale を掛けた大きさで作られる。

local Rig = {}
Rig.__index = Rig

export type Joint = { motor: Motor6D, base: CFrame }

-- 皮ふでは ない材質（光るもの・目・金属の かざり）
local NOT_SKIN = {
	[Enum.Material.Neon] = true,
	[Enum.Material.Glass] = true,
	[Enum.Material.Metal] = true,
	[Enum.Material.ForceField] = true,
}
local BELLY_LIGHT = Color3.fromRGB(245, 232, 200)
local BACK_DARK = Color3.fromRGB(18, 16, 20)

local function newPart(className: string): BasePart
	local p = Instance.new(className) :: BasePart
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

function Rig.new(name: string, scale: number)
	local self = setmetatable({}, Rig)
	self.model = Instance.new("Model")
	self.model.Name = name
	self.scale = scale
	self.bones = {} :: { [string]: BasePart }
	self.boneParent = {} :: { [string]: string }
	self.parts = {} :: { { part: BasePart, bone: string, skin: boolean? } }
	self.current = "Root"
	self.joints = {} :: { [string]: Joint }
	local root = newPart("Part")
	root.Name = "Root"
	root.Size = Vector3.one * 0.4
	root.Transparency = 1
	root.CastShadow = false
	root.Anchored = true
	root.CFrame = CFrame.new()
	root.Parent = self.model
	self.bones.Root = root
	self.root = root
	self.model.PrimaryPart = root
	return self
end

-- 骨を作る（at = 関節の位置）。このあと作る部品は、この骨にくっつく
function Rig:bone(name: string, parent: string, at: Vector3)
	local b = newPart("Part")
	b.Name = name
	b.Size = Vector3.one * 0.2
	b.Transparency = 1
	b.CastShadow = false
	b.CFrame = CFrame.new(at * self.scale)
	b.Parent = self.model
	self.bones[name] = b
	self.boneParent[name] = parent
	self.current = name
	return name
end

-- 部品をくっつける骨を切りかえる
function Rig:use(name: string)
	self.current = name
end

local function rotation(rot: Vector3?): CFrame
	local r = rot or Vector3.zero
	return CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
end

function Rig:_add(p: BasePart, color: Color3, material: Enum.Material?)
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = self.model
	-- 皮ふ（うろこ・岩・毛）の部品は、あとで 自然な色むらと かげを つける
	local skin = material ~= nil and not NOT_SKIN[material]
	table.insert(self.parts, { part = p, bone = self.current, skin = skin })
	return p
end

-- たまご形（だ円体）。Ball とちがい、たて・よこ・奥行きを別々にできる
function Rig:ell(size: Vector3, pos: Vector3, color: Color3, rot: Vector3?, material: Enum.Material?)
	local p = newPart("Part")
	p.Size = size * self.scale
	p.CFrame = CFrame.new(pos * self.scale) * rotation(rot)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return self:_add(p, color, material)
end

function Rig:ball(d: number, pos: Vector3, color: Color3, material: Enum.Material?)
	local p = newPart("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * d * self.scale
	p.CFrame = CFrame.new(pos * self.scale)
	return self:_add(p, color, material)
end

function Rig:block(size: Vector3, pos: Vector3, color: Color3, rot: Vector3?, material: Enum.Material?)
	local p = newPart("Part")
	p.Size = size * self.scale
	p.CFrame = CFrame.new(pos * self.scale) * rotation(rot)
	return self:_add(p, color, material)
end

-- a から b へのびる円柱（手足・骨・首など）
function Rig:limb(a: Vector3, b: Vector3, d: number, color: Color3, material: Enum.Material?)
	local p = newPart("Part")
	p.Shape = Enum.PartType.Cylinder
	local s = self.scale
	local len = (b - a).Magnitude
	p.Size = Vector3.new(len * s, d * s, d * s)
	-- 円柱は X 方向が長い
	local mid = (a + b) / 2 * s
	local dir = (b - a).Unit
	local up = if math.abs(dir.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
	local z = dir:Cross(up).Unit
	local y = z:Cross(dir).Unit
	p.CFrame = CFrame.fromMatrix(mid, dir, y, z)
	return self:_add(p, color, material)
end

-- base の中心から tip へとがる、角・つめ・きば・とげ
function Rig:spike(base: Vector3, tip: Vector3, width: number, color: Color3, material: Enum.Material?)
	local p = newPart("WedgePart")
	local s = self.scale
	local dir = tip - base
	local len = dir.Magnitude
	p.Size = Vector3.new(width * 0.6 * s, len * s, width * s)
	-- WedgePart は +Y の後ろ（+Z）側がとがる。上向き = dir、とがりを中心へ寄せるため少しずらす
	local y = dir.Unit
	local ref = if math.abs(y.Z) > 0.95 then Vector3.xAxis else Vector3.zAxis
	local x = y:Cross(ref).Unit
	local z = x:Cross(y).Unit
	p.CFrame = CFrame.fromMatrix((base + dir / 2) * s, x, y, z)
	return self:_add(p, color, material)
end

-- a から b へのびる、たまご形の部品（首・しっぽ・太もも・羽根など）
-- width = よこはば、thick = 厚み。つなぎ目がすき間にならないよう、少し長めに作る
function Rig:seg(a: Vector3, b: Vector3, width: number, thick: number, color: Color3, material: Enum.Material?)
	local p = newPart("Part")
	local s = self.scale
	local dir = b - a
	local len = dir.Magnitude + (width + thick) * 0.3
	p.Size = Vector3.new(width, thick, len) * s
	local up = if math.abs(dir.Unit.Y) > 0.97 then Vector3.zAxis else Vector3.yAxis
	p.CFrame = CFrame.lookAt((a + b) / 2 * s, b * s, up)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return self:_add(p, color, material)
end

-- 3つの点を結ぶうすい三角形（つばさの膜）。WedgePart 2枚で作る
function Rig:tri(a: Vector3, b: Vector3, c: Vector3, color: Color3, material: Enum.Material?, thickness: number?)
	local s = self.scale
	a, b, c = a * s, b * s, c * s
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local cross = ac:Cross(ab)
	if cross.Magnitude < 1e-4 then
		return
	end
	local right = cross.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local t = (thickness or 0.08) * s
	local w1 = newPart("WedgePart")
	w1.Size = Vector3.new(t, height, math.abs(ab:Dot(back)))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	self:_add(w1, color, material)
	local w2 = newPart("WedgePart")
	w2.Size = Vector3.new(t, height, math.abs(ac:Dot(back)))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
	self:_add(w2, color, material)
end

-- 組み立てを終える：部品を骨に、骨を親の骨につなぐ
function Rig:finish(): Model
	-- 本物の生き物のように：せなかは こく、おなかは 明るく（上からの光で 立体に見える）。
	-- 部品ごとに ほんの少し 色をばらつかせて、ぬりつぶした感じを なくす
	local low, high = math.huge, -math.huge
	for _, info in self.parts do
		if info.skin then
			local y = info.part.CFrame.Position.Y
			low, high = math.min(low, y), math.max(high, y)
		end
	end
	if high > low then
		for i, info in self.parts do
			if info.skin then
				local k = (info.part.CFrame.Position.Y - low) / (high - low)
				local c = info.part.Color:Lerp(BELLY_LIGHT, 0.16 * (1 - k) ^ 2):Lerp(BACK_DARK, 0.22 * k ^ 1.5)
				local wobble = ((i * 37) % 11 - 5) / 5 * 0.035
				info.part.Color = if wobble > 0 then c:Lerp(Color3.new(1, 1, 1), wobble) else c:Lerp(BACK_DARK, -wobble)
			end
		end
	end
	for _, info in self.parts do
		local bone = self.bones[info.bone]
		local w = Instance.new("Weld")
		w.Part0 = bone
		w.Part1 = info.part
		w.C0 = bone.CFrame:Inverse() * info.part.CFrame
		w.Parent = info.part
	end
	for name, parentName in self.boneParent do
		local bone = self.bones[name]
		local parent = self.bones[parentName]
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = parent
		m.Part1 = bone
		-- 関節の向きは模型と同じ。C0 にかける回転が、そのまま骨の回転になる
		local base = parent.CFrame:Inverse() * bone.CFrame
		m.C0 = base
		m.C1 = CFrame.new()
		m.Parent = bone
		self.joints[name] = { motor = m, base = base }
	end
	return self.model
end

-- 骨を回す（度）。同じ角度のときは送らない
function Rig.turn(joint: Joint?, x: number, y: number, z: number)
	if not joint then
		return
	end
	local cf = joint.base * CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
	if joint.motor.C0 ~= cf then
		joint.motor.C0 = cf
	end
end

return Rig
