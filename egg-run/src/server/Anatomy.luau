-- 生き物の体の部品（ドラゴンと敵の両方で使う）
-- r は Rig（骨と部品で組み立てる模型）。-Z 方向が前

local Anatomy = {}

--------------------------------------------------------------------------------
-- 色と材質
--------------------------------------------------------------------------------

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.fromRGB(15, 12, 12)
local CREAM = Color3.fromRGB(245, 228, 185)
local IVORY = Color3.fromRGB(238, 230, 205)
local MOUTH = Color3.fromRGB(120, 30, 35)
local AMBER = Color3.fromRGB(255, 190, 40)

local SCALES = Enum.Material.Slate -- うろこのような細かい凹凸
local ROCK = Enum.Material.Basalt
local METAL = Enum.Material.Metal
local GLOW = Enum.Material.Neon

local function shade(c: Color3, k: number): Color3
	return c:Lerp(BLACK, k)
end

local function tint(c: Color3, k: number): Color3
	return c:Lerp(CREAM, k)
end

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

--------------------------------------------------------------------------------
-- 体の部品（どのドラゴンにも使う）
--------------------------------------------------------------------------------

-- 目：色のついた眼球に、たてに細いひとみと、光の反射
local function eye(r, pos: Vector3, d: number, iris: Color3, glow: boolean?)
	local ball = r:ball(d, pos, iris, if glow then GLOW else Enum.Material.Glass)
	if not glow then
		-- ぬれた目：まわりを うつす
		ball.Reflectance = 0.22
	end
	-- ひとみの まわりの こい輪（虹彩の もよう）
	r:ell(v(d * 0.42, d * 0.84, d * 0.2), pos + v(0, 0, -d * 0.4), iris:Lerp(BLACK, 0.5))
	r:ell(v(d * 0.16, d * 0.74, d * 0.2), pos + v(0, 0, -d * 0.44), BLACK)
	r:ball(d * 0.24, pos + v(d * 0.16, d * 0.22, -d * 0.38), WHITE, GLOW)
end

-- 体の「おなかがわ」の向き：のびる方向に直角で、下（まっすぐ上へのびる首なら 前）
local function ventral(dir: Vector3): Vector3
	local d = dir.Unit
	local down = v(0, -1, 0)
	local side = down - d * down:Dot(d)
	if side.Magnitude < 0.3 then
		local front = v(0, 0, -1)
		side = front - d * front:Dot(d)
	end
	return side.Unit
end

-- 点をつないだ首（太さはだんだん変わる）
local function chain(r, points: { Vector3 }, w0: number, w1: number, color: Color3, mat: Enum.Material?)
	local n = #points - 1
	for i = 1, n do
		local w = w0 + (w1 - w0) * (i - 1) / math.max(1, n - 1)
		r:seg(points[i], points[i + 1], w, w * 0.92, color, mat)
		-- のどの下の はら板（ヘビのおなかのような 明るい うろこ）
		local under = ventral(points[i + 1] - points[i]) * w * 0.2
		r:seg(points[i] + under, points[i + 1] + under, w * 0.68, w * 0.62, color:Lerp(CREAM, 0.3), mat)
	end
end

-- しっぽ：骨をつないで作るので、根元から先まで波のようにゆれる。先の位置を返す
local function tail(
	r,
	prefix: string,
	start: Vector3,
	dir: Vector3,
	n: number,
	len: number,
	d0: number,
	color: Color3,
	mat: Enum.Material?,
	spikeColor: Color3?
): Vector3
	local step = len / n
	local parent = "Root"
	local p = start
	local d = dir.Unit
	for i = 1, n do
		local name = prefix .. i
		r:bone(name, parent, p)
		-- 先にいくほど少し上へカーブ
		d = (d + v(0, 0.06, 0)).Unit
		local q = p + d * step
		local w = d0 * (1 - 0.78 * (i - 1) / n)
		r:seg(p, q, w, w * 0.9, color, mat)
		-- しっぽの下の はら板
		local under = ventral(q - p) * w * 0.2
		r:seg(p + under, q + under, w * 0.66, w * 0.6, color:Lerp(CREAM, 0.3), mat)
		if spikeColor then
			local mid = p + d * step * 0.5 + v(0, w * 0.38, 0)
			r:spike(mid, mid + v(0, w * 0.5, 0) + d * w * 0.25, w * 0.55, spikeColor)
		end
		parent = name
		p = q
	end
	return p
end

-- 背中のとげを一列にならべる
local function spines(
	r,
	from: Vector3,
	to: Vector3,
	n: number,
	h0: number,
	h1: number,
	color: Color3,
	mat: Enum.Material?
)
	for i = 0, n - 1 do
		local t = if n == 1 then 0 else i / (n - 1)
		local base = from:Lerp(to, t)
		local h = h0 + (h1 - h0) * t
		r:spike(base, base + v(0, h, h * 0.35), h * 0.7, color, mat)
	end
end

-- 足：太もも → すね → 足先、つめ3本
local function leg(
	r,
	hip: Vector3,
	knee: Vector3,
	foot: Vector3,
	d: number,
	color: Color3,
	claw: Color3,
	mat: Enum.Material?
)
	r:seg(hip, knee, d, d, color, mat)
	-- 太ももの筋肉と、ひざの関節
	r:ell(v(d * 1.12, d * 1.25, d * 1.3), hip:Lerp(knee, 0.3), color, nil, mat)
	r:ball(d * 0.74, knee, color, mat)
	r:seg(knee, foot, d * 0.68, d * 0.68, color, mat)
	r:ell(v(d * 0.9, d * 0.42, d * 1.1), foot + v(0, 0, -d * 0.2), color, nil, mat)
	for _, x in { -1, 0, 1 } do
		-- 指（ふくらみ）と、根もとが太く 先が黒い つめ
		local toe = foot + v(x * d * 0.28, -d * 0.02, -d * 0.6)
		r:ell(v(d * 0.3, d * 0.3, d * 0.42), toe, color, nil, mat)
		local tip = foot + v(x * d * 0.34, -d * 0.2, -d * 1.02)
		r:spike(toe + v(0, 0, -d * 0.1), tip, d * 0.24, claw)
		r:spike(toe:Lerp(tip, 0.6), tip + v(0, -d * 0.03, -d * 0.06), d * 0.14, BLACK)
	end
	-- かかとの つめ
	r:spike(foot + v(0, 0, d * 0.3), foot + v(0, -d * 0.14, d * 0.62), d * 0.2, claw)
end

type WingOpts = {
	shoulder: Vector3,
	span: number, -- 片方のつばさの長さ
	chord: number, -- つばさの奥行き
	bone: Color3,
	skin: Color3,
	mat: Enum.Material?,
}

-- コウモリのようなつばさ：腕の骨と4本の指の骨のあいだに膜を張る
local function wing(r, side: number, name: string, o: WingOpts)
	local sh, S, C = o.shoulder, o.span, o.chord
	r:bone(name, "Root", sh)
	local function at(x: number, y: number, z: number): Vector3
		return sh + v(side * x * S, y * S, z * C)
	end
	local elbow = at(0.34, 0.22, -0.12)
	local wrist = at(0.56, 0.3, 0.02)
	local tips = { at(1, 0.16, 0.3), at(0.84, -0.02, 0.86), at(0.6, -0.06, 1.08), at(0.32, -0.03, 0.98) }
	local back = at(0.04, -0.04, 0.95)
	-- 膜（先に作って、骨が上に見えるようにする）
	local firstSkin = #r.parts + 1
	r:tri(wrist, tips[1], tips[2], o.skin, o.mat)
	r:tri(wrist, tips[2], tips[3], o.skin, o.mat)
	r:tri(wrist, tips[3], tips[4], o.skin, o.mat)
	r:tri(elbow, wrist, tips[4], o.skin, o.mat)
	r:tri(sh, elbow, tips[4], o.skin, o.mat)
	r:tri(sh, tips[4], back, o.skin, o.mat)
	-- 膜は うすい皮：光が少し すける
	for i = firstSkin, #r.parts do
		r.parts[i].part.Transparency = 0.16
	end
	-- 膜の中の すじ（指と指のあいだの 細い血管）
	for i = 1, #tips - 1 do
		local mid = tips[i]:Lerp(tips[i + 1], 0.5)
		r:limb(wrist, wrist:Lerp(mid, 0.82), S * 0.012, shade(o.skin, 0.3), o.mat)
	end
	-- 骨
	r:limb(sh, elbow, S * 0.08, o.bone, o.mat)
	r:ball(S * 0.08, elbow, o.bone, o.mat)
	r:limb(elbow, wrist, S * 0.065, o.bone, o.mat)
	r:ball(S * 0.07, wrist, o.bone, o.mat)
	for _, tip in tips do
		-- 指の骨：根もとが太く、先が細い。まん中に関節。先に小さな つめ
		local mid = wrist:Lerp(tip, 0.55)
		r:limb(wrist, mid, S * 0.04, o.bone, o.mat)
		r:ball(S * 0.042, mid, o.bone, o.mat)
		r:limb(mid, tip, S * 0.026, o.bone, o.mat)
		r:spike(tip, tip + (tip - mid).Unit * S * 0.05, S * 0.025, IVORY)
	end
	-- 手首のつめ
	r:spike(wrist, wrist + v(side * S * 0.05, S * 0.12, -S * 0.08), S * 0.05, IVORY)
	r:use("Root")
end

Anatomy.WHITE = WHITE
Anatomy.BLACK = BLACK
Anatomy.CREAM = CREAM
Anatomy.IVORY = IVORY
Anatomy.MOUTH = MOUTH
Anatomy.AMBER = AMBER
Anatomy.SCALES = SCALES
Anatomy.ROCK = ROCK
Anatomy.METAL = METAL
Anatomy.GLOW = GLOW
Anatomy.shade = shade
Anatomy.tint = tint
Anatomy.v = v
Anatomy.eye = eye
Anatomy.chain = chain
Anatomy.tail = tail
Anatomy.spines = spines
Anatomy.leg = leg
Anatomy.wing = wing

return Anatomy
