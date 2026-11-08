-- ドラゴンの仲間：選んだドラゴンの模型を作り、プレイヤーの後ろをふわふわついて来させる
-- 模型は Rig（骨と部品）で組み立て、つばさ・しっぽ・首・あごを動かす

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Enemies = require(script.Parent:WaitForChild("Enemies"))
local Rig = require(script.Parent:WaitForChild("Rig"))

local Dragons = {}

type Look = {
	mouths: { Vector3 }, -- こうげきが出る口の位置（模型の中から見た位置）
	top: number, -- 名前を出す高さ
	flapSpeed: number, -- 羽ばたきの速さ
	flapAmp: number, -- 羽ばたきの大きさ（度）
	body: { size: Vector3, pos: Vector3 }?, -- 胴体のだ円体（レア度の飾りをつける場所）
	chest: Vector3?, -- 胸の宝石の位置
	gem: number?, -- 胸の宝石の大きさ
}

local folder: Folder
type Follower = {
	model: Model,
	root: BasePart,
	joints: { [string]: Rig.Joint },
	look: Look,
	cf: CFrame,
	scale: number,
	dragon: any,
	lastAttack: number,
	jawUntil: number,
	phase: number,
	target: any?,
}
local followers: { [Player]: Follower } = {}

-- はじめの仲間と、たまごから生まれるドラゴンの両方からさがす
function Dragons.find(id: string?)
	return Config.findDragon(id)
end

local A = require(script.Parent:WaitForChild("Anatomy"))
local WHITE, BLACK, CREAM, IVORY, MOUTH, AMBER = A.WHITE, A.BLACK, A.CREAM, A.IVORY, A.MOUTH, A.AMBER
local SCALES, ROCK, METAL, GLOW = A.SCALES, A.ROCK, A.METAL, A.GLOW
local shade, tint, v = A.shade, A.tint, A.v
local eye, chain, tail, spines, leg, wing = A.eye, A.chain, A.tail, A.spines, A.leg, A.wing

--------------------------------------------------------------------------------
-- レア度が高いほど強そうにする飾り
--   ★2 銀の角が1組ふえる、背中のとげがふえる
--   ★3 角が2組、目が光る、背中のとげが金属に、胸に宝石
--   ★4 金の角が3組（かんむり）、体の横に光るもよう、光をまとう
--   ★5 頭の上に光の輪、光の粒が舞う
-- rarity が 0 のとき（はじめの仲間）は飾りをつけない
--------------------------------------------------------------------------------
local GOLD = Color3.fromRGB(255, 200, 60)
local SILVER = Color3.fromRGB(215, 222, 235)

local function accentOf(rarity: number): Color3
	local info = Config.Rarities[rarity]
	return if info then info.color else IVORY
end

-- 角の色と材質
local function hornOf(rarity: number, base: Color3): (Color3, Enum.Material?)
	if rarity >= 5 then
		return GOLD, GLOW
	elseif rarity >= 4 then
		return GOLD, METAL
	elseif rarity >= 2 then
		return SILVER, METAL
	end
	return base, nil
end

-- 背中のとげ：レアなほど数が多く、高く、光る
local function crest(r, from: Vector3, to: Vector3, n: number, h0: number, h1: number, base: Color3, rarity: number)
	local extra = math.max(0, rarity - 1)
	local k = 1 + 0.18 * extra
	local color, mat = base, nil
	if rarity >= 4 then
		color, mat = accentOf(rarity), GLOW
	elseif rarity >= 3 then
		color, mat = accentOf(rarity), METAL
	end
	spines(r, from, to, n + extra, h0 * k, h1 * k, color, mat)
end

-- ドラゴンの頭
type HeadOpts = {
	bone: string, -- 頭の骨
	jaw: string, -- あごの骨
	pos: Vector3, -- 頭の中心
	size: number,
	color: Color3,
	belly: Color3,
	horn: Color3,
	iris: Color3,
	glowEyes: boolean?,
	mat: Enum.Material?,
	rarity: number?, -- レア度（角のかんむり、光の輪）
	halo: boolean?, -- ★5 の光の輪をこの頭につけるか
}

-- ドラゴンの頭（頭・鼻先・まゆ・目・鼻のあな・角・きば・下あご）。口の位置を返す
local function dragonHead(r, o: HeadOpts): Vector3
	local L, p, c = o.size, o.pos, o.color
	local rarity = o.rarity or 0
	local hornColor, hornMat = hornOf(rarity, o.horn)
	r:use(o.bone)
	r:ell(v(0.62, 0.52, 0.66) * L, p, c, nil, o.mat)
	r:ell(v(0.44, 0.3, 0.74) * L, p + v(0, -0.05, -0.46) * L, c, v(-6, 0, 0), o.mat)
	-- 口の中（あごが開くと見える）
	r:ell(v(0.36, 0.12, 0.6) * L, p + v(0, -0.21, -0.42) * L, MOUTH)
	for _, s in { -1, 1 } do
		-- まゆの出っぱり
		r:ell(v(0.22, 0.12, 0.32) * L, p + v(s * 0.2, 0.18, -0.2) * L, shade(c, 0.25), v(0, s * -15, s * -12), o.mat)
		eye(r, p + v(s * 0.23, 0.07, -0.25) * L, 0.17 * L, o.iris, o.glowEyes)
		r:ball(0.07 * L, p + v(s * 0.09, 0.06, -0.82) * L, BLACK)
		-- 後ろへそり返る角（2本つなぎ）
		local h0 = p + v(s * 0.17, 0.22, 0.1) * L
		local h1 = p + v(s * 0.27, 0.42, 0.42) * L
		local h2 = p + v(s * 0.31, 0.47, 0.82) * L
		r:limb(h0, h1, 0.14 * L, hornColor, hornMat)
		r:ball(0.12 * L, h1, hornColor, hornMat)
		r:limb(h1, h2, 0.09 * L, hornColor, hornMat)
		r:ball(0.08 * L, h2, hornColor, hornMat)
		-- レアなほど、頭の上に角がならぶ（★4 からは かんむりのよう）
		local crown = if rarity >= 4 then 3 elseif rarity >= 3 then 2 elseif rarity >= 2 then 1 else 0
		for k = 1, crown do
			local base = p + v(s * (0.08 + k * 0.03), 0.24, -0.22 + (k - 1) * 0.2) * L
			local tip = base + v(s * 0.1, 0.32 + 0.07 * rarity - k * 0.04, 0.16) * L
			r:spike(base, tip, 0.13 * L, hornColor, hornMat)
		end
		-- ほおのとげ
		r:spike(p + v(s * 0.28, -0.06, 0.12) * L, p + v(s * 0.46, -0.04, 0.42) * L, 0.12 * L, o.horn)
		-- 上のきば
		for i = 0, 2 do
			local z = -0.52 - i * 0.12
			r:spike(p + v(s * 0.15, -0.18, z) * L, p + v(s * 0.14, -0.3, z) * L, 0.06 * L, IVORY)
		end
	end
	-- 下あご（骨ごと動いて口が開く）
	r:bone(o.jaw, o.bone, p + v(0, -0.18, -0.02) * L)
	r:ell(v(0.4, 0.16, 0.72) * L, p + v(0, -0.3, -0.4) * L, o.belly, nil, o.mat)
	for _, s in { -1, 1 } do
		for i = 0, 1 do
			local z = -0.58 - i * 0.14
			r:spike(p + v(s * 0.13, -0.26, z) * L, p + v(s * 0.13, -0.16, z) * L, 0.05 * L, IVORY)
		end
	end
	r:use(o.bone)
	-- ★5：頭の上に浮かぶ光の輪
	if rarity >= 5 and o.halo ~= false then
		local center = p + v(0, 0.95, 0.3) * L
		for i = 0, 9 do
			local a = i / 10 * math.pi * 2
			r:ball(0.13 * L, center + v(math.cos(a) * 0.45, 0, math.sin(a) * 0.45) * L, accentOf(rarity), GLOW)
		end
	end
	return p + v(0, -0.22, -0.88) * L
end

--------------------------------------------------------------------------------
-- 体の形ごとの作り方
--------------------------------------------------------------------------------

local BUILDERS: { [string]: (any, Color3, number) -> Look } = {}

-- 子どものドラゴン：頭が大きく、ずんぐりした体
BUILDERS.small = function(r, c, rarity)
	local belly = tint(c, 0.6)
	r:ell(v(2.1, 1.9, 2.6), v(0, 0, 0), c, nil, SCALES)
	r:ell(v(1.5, 1.5, 1.9), v(0, -0.2, -0.45), belly)
	chain(r, { v(0, 0.4, -0.9), v(0, 0.9, -1.25) }, 1.1, 1, c, SCALES)
	r:bone("Head", "Root", v(0, 0.95, -1.2))
	local mouth = dragonHead(r, {
		bone = "Head",
		jaw = "Jaw",
		pos = v(0, 1.35, -1.55),
		size = 1.9,
		color = c,
		belly = belly,
		horn = IVORY,
		iris = AMBER,
		glowEyes = rarity >= 3,
		mat = SCALES,
		rarity = rarity,
	})
	r:use("Root")
	for _, s in { -1, 1 } do
		leg(r, v(s * 0.6, -0.4, -0.6), v(s * 0.7, -0.85, -0.85), v(s * 0.7, -1.15, -0.7), 0.55, c, IVORY, SCALES)
		leg(r, v(s * 0.65, -0.35, 0.6), v(s * 0.75, -0.8, 0.3), v(s * 0.75, -1.15, 0.55), 0.65, c, IVORY, SCALES)
		wing(r, s, if s < 0 then "WingL" else "WingR", {
			shoulder = v(s * 0.55, 0.7, -0.3),
			span = 2.3,
			chord = 1.4,
			bone = c,
			skin = tint(c, 0.35),
			mat = SCALES,
		})
	end
	crest(r, v(0, 0.95, -0.4), v(0, 0.85, 0.8), 3, 0.35, 0.25, IVORY, rarity)
	tail(r, "Tail", v(0, -0.15, 1.1), v(0, -0.25, 1), 4, 2.6, 0.85, c, SCALES, IVORY)
	return {
		mouths = { mouth },
		top = 3,
		flapSpeed = 9,
		flapAmp = 32,
		body = { size = v(2.1, 1.9, 2.6), pos = v(0, 0, 0) },
		chest = v(0, -0.35, -1.38),
		gem = 0.42,
	}
end

-- つばさの大きい、すらりとしたドラゴン。背中にいなずまの光
BUILDERS.winged = function(r, c, rarity)
	local belly = tint(c, 0.55)
	local bolt = Color3.fromRGB(110, 220, 255)
	r:ell(v(1.7, 1.6, 3.6), v(0, 0, 0), c, nil, SCALES)
	r:ell(v(1.2, 1.1, 2.8), v(0, -0.32, -0.2), belly)
	chain(r, { v(0, 0.3, -1.4), v(0, 0.9, -2.1), v(0, 1.55, -2.55), v(0, 2, -2.8) }, 1, 0.7, c, SCALES)
	r:bone("Head", "Root", v(0, 2, -2.8))
	local mouth = dragonHead(r, {
		bone = "Head",
		jaw = "Jaw",
		pos = v(0, 2.25, -3.3),
		size = 1.7,
		color = c,
		belly = belly,
		horn = shade(c, 0.5),
		iris = bolt,
		glowEyes = true,
		mat = SCALES,
		rarity = rarity,
	})
	r:use("Root")
	for _, s in { -1, 1 } do
		leg(r, v(s * 0.55, -0.3, 0.8), v(s * 0.65, -0.85, 0.4), v(s * 0.65, -1.25, 0.75), 0.6, c, IVORY, SCALES)
		wing(r, s, if s < 0 then "WingL" else "WingR", {
			shoulder = v(s * 0.5, 0.55, -0.7),
			span = 5,
			chord = 2.8,
			bone = shade(c, 0.2),
			skin = c:Lerp(Color3.fromRGB(255, 250, 170), 0.45),
			mat = SCALES,
		})
	end
	-- 背中のいなずま模様（光る）
	for i = 0, 3 do
		local s = if i % 2 == 0 then 1 else -1
		r:ell(v(0.18, 0.14, 0.95), v(s * 0.18, 0.78, -1.1 + i * 0.75), bolt, v(-4, s * 35, 0), GLOW)
	end
	if rarity >= 2 then
		crest(r, v(0, 0.8, -1.3), v(0, 0.76, 1.4), 3, 0.35, 0.25, shade(c, 0.4), rarity)
	end
	local tip = tail(r, "Tail", v(0, 0, 1.7), v(0, -0.15, 1), 5, 4.8, 0.75, c, SCALES, shade(c, 0.4))
	-- しっぽの先のスペード
	r:tri(tip + v(0, 0, -0.2), tip + v(-0.55, 0, 0.35), tip + v(0, 0, 1.1), bolt, GLOW, 0.12)
	r:tri(tip + v(0, 0, -0.2), tip + v(0.55, 0, 0.35), tip + v(0, 0, 1.1), bolt, GLOW, 0.12)
	r:use("Root")
	return {
		mouths = { mouth },
		top = 3.8,
		flapSpeed = 6,
		flapAmp = 30,
		body = { size = v(1.7, 1.6, 3.6), pos = v(0, 0, 0) },
		chest = v(0, -0.3, -1.72),
		gem = 0.36,
	}
end

-- 岩のドラゴン：重い体に、マグマの光るすじ。つばさはない
BUILDERS.magma = function(r, c, rarity)
	local rock = Color3.fromRGB(60, 40, 36)
	local lava = Color3.fromRGB(255, 130, 30)
	r:ell(v(3.4, 2.7, 5), v(0, 0, 0), c, nil, ROCK)
	r:ell(v(2.6, 1.8, 3.8), v(0, -0.55, -0.3), shade(c, 0.3), nil, ROCK)
	-- マグマのすじ
	for i = -1, 1 do
		r:ell(v(3.2, 0.14, 0.3), v(0, 0.55, i * 1.3), lava, v(0, i * 8, 0), GLOW)
	end
	-- 背中の岩のかたまり
	for i = -2, 2 do
		local s = if i % 2 == 0 then 1 else -1
		local size = 1.15 - math.abs(i) * 0.12
		r:block(v(1, 1, 1) * size, v(s * 0.45, 1.25, i * 1), rock, v(45, i * 20, 45), ROCK)
		-- ★3 から、岩のかたまりの上に光る結晶がはえる
		if rarity >= 3 then
			local base = v(s * 0.45, 1.25 + size * 0.5, i * 1)
			r:spike(base, base + v(s * 0.15, 0.5 + rarity * 0.15, 0.2), 0.45, accentOf(rarity), GLOW)
		end
	end
	chain(r, { v(0, 0.5, -1.9), v(0, 0.9, -2.6) }, 1.8, 1.6, c, ROCK)
	r:bone("Head", "Root", v(0, 0.95, -2.7))
	local mouth = dragonHead(r, {
		bone = "Head",
		jaw = "Jaw",
		pos = v(0, 1.1, -3.4),
		size = 2.3,
		color = c,
		belly = shade(c, 0.3),
		horn = rock,
		iris = lava,
		glowEyes = true,
		mat = ROCK,
		rarity = rarity,
	})
	r:use("Root")
	for _, s in { -1, 1 } do
		for _, z in { -1.5, 1.5 } do
			leg(r, v(s * 1.3, -0.6, z), v(s * 1.6, -1.6, z - 0.4), v(s * 1.6, -2.35, z + 0.05), 1.15, c, rock, ROCK)
		end
	end
	tail(r, "Tail", v(0, -0.2, 2.3), v(0, -0.2, 1), 4, 3.8, 1.4, c, ROCK, rock)
	local light = Instance.new("PointLight")
	light.Color = lava
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = r.root
	return {
		mouths = { mouth },
		top = 3.6,
		flapSpeed = 0,
		flapAmp = 0,
		body = { size = v(3.4, 2.7, 5), pos = v(0, 0, 0) },
		chest = v(0, -0.45, -2.42),
		gem = 0.6,
	}
end

-- 三つの首のドラゴン：金属のうろこ、しっぽも2本
BUILDERS.triple = function(r, c, rarity)
	local belly = tint(c, 0.45)
	r:ell(v(2.8, 2.4, 3.8), v(0, 0, 0), c, nil, METAL)
	r:ell(v(2, 1.7, 2.8), v(0, -0.4, -0.3), belly, nil, METAL)
	local mouths = {}
	for i, x in { -1, 0, 1 } do
		local top = v(x * 1.8, 3 - math.abs(x) * 0.2, -2.3)
		chain(r, { v(x * 0.6, 0.6, -1.4), v(x * 1.3, 1.9, -1.95), top }, 0.85, 0.7, c, METAL)
		local headName = "Head" .. i
		r:bone(headName, "Root", top)
		table.insert(
			mouths,
			dragonHead(r, {
				bone = headName,
				jaw = "Jaw" .. i,
				pos = top + v(0, 0.25, -0.5),
				size = 1.45,
				color = c,
				belly = belly,
				horn = IVORY,
				iris = Color3.fromRGB(255, 80, 50),
				glowEyes = true,
				mat = METAL,
				rarity = rarity,
				halo = i == 2, -- 光の輪はまん中の頭だけ
			})
		)
		r:use("Root")
	end
	for _, s in { -1, 1 } do
		leg(r, v(s * 0.8, -0.5, 0.9), v(s * 0.95, -1.15, 0.4), v(s * 0.95, -1.7, 0.85), 0.8, c, IVORY, METAL)
		wing(r, s, if s < 0 then "WingL" else "WingR", {
			shoulder = v(s * 0.8, 0.8, -0.4),
			span = 4.6,
			chord = 2.7,
			bone = shade(c, 0.25),
			skin = c:Lerp(Color3.fromRGB(255, 130, 50), 0.35),
			mat = METAL,
		})
	end
	if rarity >= 2 then
		crest(r, v(0, 1.18, -0.4), v(0, 1.08, 1.4), 3, 0.45, 0.3, IVORY, rarity)
	end
	tail(r, "TailA", v(-0.5, -0.2, 1.7), v(-0.25, -0.15, 1), 4, 3.4, 0.7, c, METAL, IVORY)
	tail(r, "TailB", v(0.5, -0.2, 1.7), v(0.25, -0.15, 1), 4, 3.4, 0.7, c, METAL, IVORY)
	return {
		mouths = mouths,
		top = 4.8,
		flapSpeed = 5,
		flapAmp = 28,
		body = { size = v(2.8, 2.4, 3.8), pos = v(0, 0, 0) },
		chest = v(0, -0.45, -1.82),
		gem = 0.5,
	}
end

-- 立って歩く大きなドラゴン：太い足と短い腕、背中に一列のとげ
BUILDERS.giant = function(r, c, rarity)
	local belly = tint(c, 0.5)
	local plate = tint(c, 0.7)
	r:ell(v(3.3, 5.2, 3.2), v(0, 0.6, 0), c, v(-15, 0, 0), SCALES)
	r:ell(v(2.3, 4.2, 1.3), v(0, 0.35, -1.25), belly, v(-15, 0, 0))
	chain(r, { v(0, 2.7, -0.6), v(0, 3.6, -1.15), v(0, 4.15, -1.6) }, 2.1, 1.8, c, SCALES)
	r:bone("Head", "Root", v(0, 4.15, -1.6))
	local mouth = dragonHead(r, {
		bone = "Head",
		jaw = "Jaw",
		pos = v(0, 4.5, -2.25),
		size = 2.5,
		color = c,
		belly = belly,
		horn = plate,
		iris = AMBER,
		glowEyes = rarity >= 3,
		mat = SCALES,
		rarity = rarity,
	})
	r:use("Root")
	for _, s in { -1, 1 } do
		-- 短い腕
		r:seg(v(s * 1.4, 2, -1.1), v(s * 1.75, 1.05, -1.75), 0.75, 0.7, c, SCALES)
		r:seg(v(s * 1.75, 1.05, -1.75), v(s * 1.5, 0.6, -2.45), 0.55, 0.5, c, SCALES)
		for _, x in { -1, 0, 1 } do
			local hand = v(s * 1.5 + x * 0.15, 0.55, -2.5)
			r:spike(hand, hand + v(0, -0.15, -0.4), 0.14, IVORY)
		end
		-- 太い足
		leg(r, v(s * 1.3, -1.3, 0.2), v(s * 1.55, -2.7, -0.75), v(s * 1.5, -4, 0.15), 1.8, c, IVORY, SCALES)
	end
	crest(r, v(0, 3.3, 0.35), v(0, -0.6, 2), 6, 1.3, 0.7, plate, rarity)
	tail(r, "Tail", v(0, -1.4, 1.5), v(0, -0.35, 1), 5, 6, 1.8, c, SCALES, plate)
	return {
		mouths = { mouth },
		top = 6.2,
		flapSpeed = 0,
		flapAmp = 0,
		body = { size = v(3.3, 5.2, 3.2), pos = v(0, 0.6, 0) },
		chest = v(0, 1.3, -1.85),
		gem = 0.6,
	}
end

-- 火の鳥：羽根を重ねたつばさと、扇のように広がる長い尾羽
BUILDERS.phoenix = function(r, c, rarity)
	local orange = Color3.fromRGB(255, 140, 30)
	local yellow = Color3.fromRGB(255, 220, 70)
	r:ell(v(1.8, 1.8, 2.7), v(0, 0, 0), c)
	r:ell(v(1.4, 1.5, 1.6), v(0, 0.05, -0.65), yellow)
	chain(r, { v(0, 0.6, -0.9), v(0, 1.25, -1.3) }, 1.1, 0.95, c)
	r:bone("Head", "Root", v(0, 1.3, -1.3))
	local hp = v(0, 1.75, -1.55)
	r:ell(v(1.2, 1.15, 1.35), hp, c)
	for _, s in { -1, 1 } do
		eye(r, hp + v(s * 0.36, 0.1, -0.35), 0.26, AMBER, rarity >= 3)
	end
	-- くちばし（上は先が下に曲がる）
	r:seg(hp + v(0, 0.02, -0.5), hp + v(0, -0.08, -1.05), 0.36, 0.3, yellow)
	r:spike(hp + v(0, -0.06, -1), hp + v(0, -0.3, -1.12), 0.14, yellow)
	-- とさか（光る羽根）
	local crestTilts = if rarity >= 4 then { -34, -22, -8, 8, 22, 34 } else { -22, -8, 8, 22 }
	for i, tilt in crestTilts do
		local base = hp + v(tilt / 80, 0.45, 0.05)
		local tip = base + v(tilt / 30, 0.9 + (i % 2) * 0.35, 0.6)
		r:seg(base, tip, 0.22, 0.08, if i % 2 == 0 then yellow else orange, GLOW)
	end
	-- ★5：頭の上に浮かぶ光の輪
	if rarity >= 5 then
		local center = hp + v(0, 1.35, 0.35)
		for i = 0, 9 do
			local a = i / 10 * math.pi * 2
			r:ball(0.17, center + v(math.cos(a) * 0.6, 0, math.sin(a) * 0.6), accentOf(rarity), GLOW)
		end
	end
	r:bone("Jaw", "Head", hp + v(0, -0.2, -0.45))
	r:seg(hp + v(0, -0.18, -0.5), hp + v(0, -0.22, -0.9), 0.28, 0.16, orange)
	r:use("Root")
	local mouth = hp + v(0, -0.18, -1.1)
	-- つばさ：内側から 赤 → オレンジ → 黄色 の羽根を重ねる
	for _, s in { -1, 1 } do
		local name = if s < 0 then "WingL" else "WingR"
		local sh = v(s * 0.6, 0.55, -0.25)
		r:bone(name, "Root", sh)
		local wrist = sh + v(s * 2.4, 0.7, 0.2)
		r:seg(sh, wrist, 0.6, 0.35, c)
		for i = 0, 7 do
			local t = i / 7
			local base = sh + (wrist - sh) * (0.3 + 0.7 * t)
			local dir = v(s * (0.15 + 0.9 * t), -0.05 + 0.1 * t, 1 - 0.75 * t).Unit
			local len = 1.8 + 1.6 * t
			local color = if t < 0.5 then c:Lerp(orange, t * 2) else orange:Lerp(yellow, (t - 0.5) * 2)
			r:seg(base, base + dir * len, 0.55, 0.1, color, if t > 0.7 then GLOW else nil)
			-- 上に重なる短い羽根
			r:seg(base + v(0, 0.1, 0), base + v(0, 0.1, 0) + dir * len * 0.5, 0.6, 0.12, c)
		end
		r:use("Root")
	end
	-- 尾羽
	r:bone("Tail1", "Root", v(0, -0.2, 1.1))
	-- ★4 からは尾羽が7本になり、長くなる
	local yaws = if rarity >= 4 then { -36, -24, -12, 0, 12, 24, 36 } else { -26, -13, 0, 13, 26 }
	local middle = (#yaws + 1) // 2
	for i, yaw in yaws do
		local dir = v(math.sin(math.rad(yaw)), -0.18, math.cos(math.rad(yaw))).Unit
		local len = 4.8 - math.abs(yaw) / 20 + math.max(0, rarity - 2) * 0.4
		local base = v(0, -0.2, 1.1)
		r:seg(base, base + dir * len, 0.5, 0.1, if i == middle then c else orange)
		r:ball(0.6, base + dir * (len - 0.15), yellow, GLOW)
	end
	r:use("Root")
	return {
		mouths = { mouth },
		top = 3.4 + (if rarity >= 5 then 0.8 else 0),
		flapSpeed = 4,
		flapAmp = 26,
		body = { size = v(1.8, 1.8, 2.7), pos = v(0, 0, 0) },
		chest = v(0, -0.2, -1.42),
		gem = 0.38,
	}
end

-- 海と風の守り神：銀色の流れるような体、大きなつばさ、背中と尾の先にひれ
BUILDERS.guardian = function(r, c, rarity)
	local belly = c:Lerp(Color3.fromRGB(150, 190, 210), 0.45)
	local fin = Color3.fromRGB(60, 170, 170)
	local glow = Color3.fromRGB(120, 255, 230)
	r:ell(v(1.6, 1.5, 3.6), v(0, 0, 0), c)
	r:ell(v(1.15, 1, 2.9), v(0, -0.3, -0.2), belly)
	-- 体の横の光るすじ
	for _, s in { -1, 1 } do
		r:ell(v(0.1, 0.12, 2.6), v(s * 0.72, 0.05, 0.1), glow, v(0, s * 4, 0), GLOW)
	end
	chain(r, { v(0, 0.3, -1.4), v(0, 0.95, -2.05), v(0, 1.6, -2.45), v(0, 2.1, -2.7) }, 0.95, 0.7, c)
	r:bone("Head", "Root", v(0, 2.1, -2.7))
	local mouth = dragonHead(r, {
		bone = "Head",
		jaw = "Jaw",
		pos = v(0, 2.35, -3.15),
		size = 1.6,
		color = c,
		belly = belly,
		horn = fin,
		iris = glow,
		glowEyes = true,
	})
	r:use("Root")
	-- 背中のひれ
	spines(r, v(0, 0.75, -1.2), v(0, 0.65, 1.3), 5, 0.6, 0.35, fin)
	for _, s in { -1, 1 } do
		leg(r, v(s * 0.5, -0.35, 0.9), v(s * 0.6, -0.85, 0.5), v(s * 0.6, -1.2, 0.85), 0.55, c, fin)
		wing(r, s, if s < 0 then "WingL" else "WingR", {
			shoulder = v(s * 0.5, 0.55, -0.6),
			span = 5.6,
			chord = 3,
			bone = c,
			skin = c:Lerp(Color3.fromRGB(170, 215, 230), 0.5),
		})
	end
	local tip = tail(r, "Tail", v(0, 0, 1.7), v(0, -0.1, 1), 6, 5.6, 0.7, c, nil, fin)
	-- 尾の先の、扇のようなひれ
	r:tri(tip + v(0, 0, -0.3), tip + v(-0.9, 0, 0.9), tip + v(0, 0, 1.3), fin)
	r:tri(tip + v(0, 0, -0.3), tip + v(0.9, 0, 0.9), tip + v(0, 0, 1.3), fin)
	r:use("Root")
	return { mouths = { mouth }, top = 4, flapSpeed = 3.5, flapAmp = 24 }
end

-- 海の巨大ドラゴン：クジラのような体、大きな胸びれ、尾びれ、光るもよう
BUILDERS.leviathan = function(r, c, rarity)
	local belly = c:Lerp(Color3.fromRGB(230, 240, 255), 0.75)
	local glow = Color3.fromRGB(70, 255, 220)
	r:ell(v(3, 2.6, 6), v(0, 0.1, 0.4), c)
	r:ell(v(2.4, 1.5, 5.2), v(0, -0.55, 0.2), belly)
	-- 光るもよう（背中の線と、横の丸）
	for _, s in { -1, 1 } do
		r:ell(v(0.14, 0.14, 3.4), v(s * 0.55, 1.22, 0.4), glow, v(-6, s * 6, 0), GLOW)
		for i = 0, 2 do
			r:ell(v(0.1, 0.42, 0.42), v(s * 1.43, 0.25, -0.6 + i * 1.1), glow, nil, GLOW)
		end
	end
	-- 頭（大きく丸い。下あごが開く）
	r:bone("Head", "Root", v(0, 0.1, -2.2))
	r:ell(v(2.5, 2, 2.4), v(0, 0.2, -2.8), c)
	for _, s in { -1, 1 } do
		eye(r, v(s * 0.95, 0.45, -3.3), 0.42, glow, true)
		r:limb(v(s * 0.5, 1, -2.8), v(s * 0.75, 1.5, -1.9), 0.22, IVORY)
		r:limb(v(s * 0.75, 1.5, -1.9), v(s * 0.8, 1.6, -1.3), 0.14, IVORY)
		for i = 0, 3 do
			local x = s * (0.25 + i * 0.22)
			r:spike(v(x, -0.35, -3.75 + i * 0.12), v(x, -0.6, -3.75 + i * 0.12), 0.1, IVORY)
		end
	end
	r:ell(v(1.9, 0.3, 1.8), v(0, -0.45, -3.1), MOUTH)
	r:bone("Jaw", "Head", v(0, -0.3, -2.2))
	r:ell(v(2.1, 0.6, 2.1), v(0, -0.75, -2.95), belly)
	r:use("Root")
	-- 胸びれ（つばさのように動く）
	for _, s in { -1, 1 } do
		local name = if s < 0 then "WingL" else "WingR"
		local base = v(s * 1.2, -0.4, -1)
		r:bone(name, "Root", base)
		r:tri(base, base + v(s * 3.4, -0.6, 0.6), base + v(0, 0, 1.6), c)
		r:tri(base + v(s * 3.4, -0.6, 0.6), base + v(0, 0, 1.6), base + v(s * 2.2, -0.45, 1.5), c)
		r:seg(base, base + v(s * 3.2, -0.55, 0.55), 0.3, 0.2, glow, GLOW)
		r:use("Root")
	end
	-- 背びれ
	r:tri(v(0, 1.2, 0.6), v(0, 2.1, 1.5), v(0, 1.1, 1.9), c)
	local tip = tail(r, "Tail", v(0, 0, 3.2), v(0, 0.1, 1), 4, 3.6, 1.6, c)
	-- 尾びれ
	for _, s in { -1, 1 } do
		r:tri(tip + v(0, 0, -0.4), tip + v(s * 2.2, 0.1, 0.9), tip + v(s * 0.4, 0, 0.6), c)
		r:seg(tip, tip + v(s * 2, 0.1, 0.8), 0.25, 0.15, glow, GLOW)
	end
	r:use("Root")
	return { mouths = { v(0, -0.45, -3.9) }, top = 3, flapSpeed = 2, flapAmp = 18 }
end

local SCALE =
	{ small = 1, winged = 1, magma = 1, triple = 1, giant = 1.4, phoenix = 1.1, guardian = 1.2, leviathan = 1.2 }

-- レアなドラゴンほど大きい（レジェンドは ノーマルの 1.4倍）
local function scaleOf(dragon): number
	return (SCALE[dragon.shape] or 1) * (1 + 0.1 * ((dragon.rarity or 1) - 1))
end

-- どの形にもつける、レア度の飾り（胸の宝石、体の横の光るもよう）
local function adorn(r, look: Look, rarity: number)
	if rarity < 3 then
		return
	end
	r:use("Root")
	local accent = accentOf(rarity)
	if look.chest then
		local g = look.gem or 0.45
		r:ell(
			v(g * 1.6, g * 1.6, g * 0.45),
			look.chest + v(0, 0, 0.06),
			if rarity >= 4 then GOLD else SILVER,
			nil,
			METAL
		)
		r:ell(v(g, g, g * 0.6), look.chest + v(0, 0, -0.06), accent, nil, GLOW)
	end
	local body = look.body
	if rarity >= 4 and body then
		-- だ円体の表面に、ななめの光るすじを3本ずつ
		local a, h, d = body.size.X / 2, body.size.Y / 2, body.size.Z / 2
		for _, s in { -1, 1 } do
			for i = -1, 1 do
				local y, z = h * 0.12, i * d * 0.42
				local x = a * math.sqrt(math.max(0, 1 - (y / h) ^ 2 - (z / d) ^ 2))
				r:ell(v(0.12, h * 0.75, math.min(a, d) * 0.16), body.pos + v(s * x, y, z), accent, v(-25, 0, 0), GLOW)
			end
		end
	end
end

local function build(dragon)
	local scale = scaleOf(dragon)
	local r = Rig.new(dragon.name, scale)
	local builder = BUILDERS[dragon.shape] or BUILDERS.small
	-- はじめの仲間はレア度がないので 0（レア度の飾りはつけない）
	local rarity = dragon.rarity or 0
	local look = builder(r, dragon.color, rarity)
	adorn(r, look, rarity)
	local model = r:finish()
	local root = r.root

	local nameTag = Instance.new("BillboardGui")
	nameTag.Size = UDim2.new(8, 0, 1.5, 0)
	nameTag.StudsOffset = Vector3.new(0, look.top * scale + 1, 0)
	nameTag.MaxDistance = 80
	nameTag.LightInfluence = 0
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	local rarityInfo = dragon.rarity and Config.Rarities[dragon.rarity]
	text.TextColor3 = if rarityInfo then rarityInfo.color else Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.Text = dragon.name
	text.Parent = nameTag
	nameTag.Adornee = root
	nameTag.Parent = model

	-- ウルトラレア以上はキラキラ光り、レア度の色の光をまとう
	if rarity >= 4 then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = dragon.color
		sparkles.Parent = root
		local aura = Instance.new("PointLight")
		aura.Color = accentOf(rarity)
		aura.Range = 8 + rarity * 2
		aura.Brightness = 1.2
		aura.Parent = root
	end
	-- レジェンドは、光の粒がまわりに舞い上がる
	if rarity >= 5 then
		local motes = Instance.new("ParticleEmitter")
		motes.Color = ColorSequence.new(accentOf(rarity), GOLD)
		motes.LightEmission = 1
		motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		motes.Transparency = NumberSequence.new(0.2, 1)
		motes.Lifetime = NumberRange.new(1, 1.6)
		motes.Rate = 14
		motes.Speed = NumberRange.new(1, 3)
		motes.SpreadAngle = Vector2.new(180, 180)
		motes.Acceleration = Vector3.new(0, 3, 0)
		motes.Parent = root
	end
	if dragon.shape == "phoenix" then
		local fire = Instance.new("Fire")
		fire.Size = 3
		fire.Heat = 2
		fire.Color = if dragon.rarity then dragon.color else Color3.fromRGB(255, 140, 30)
		fire.SecondaryColor = Color3.fromRGB(255, 50, 20)
		fire.Parent = root
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 160, 60)
		glow.Range = 12
		glow.Parent = root
	end
	return model, root, r.joints, look
end
Dragons.build = build

function Dragons.equip(player: Player, id: string?)
	local old = followers[player]
	if old then
		old.model:Destroy()
		followers[player] = nil
	end
	local dragon = Dragons.find(id)
	if not dragon then
		return
	end
	local model, root, joints, look = build(dragon)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local start = if hrp then hrp.CFrame else CFrame.new(0, 5, 0)
	root.CFrame = start
	model.Parent = folder
	followers[player] = {
		model = model,
		root = root,
		joints = joints,
		look = look,
		cf = start,
		scale = scaleOf(dragon),
		dragon = dragon,
		lastAttack = 0,
		jawUntil = 0,
		phase = math.random() * 10,
		target = nil,
	}
end

-- 羽ばたき・しっぽ・首・あごを動かす
local function animate(f: Follower, t: number, now: number)
	local look = f.look
	local time = t + f.phase
	for name, joint in f.joints do
		if name == "WingL" or name == "WingR" then
			local side = if name == "WingL" then -1 else 1
			local flap = math.sin(time * look.flapSpeed) * look.flapAmp
			Rig.turn(joint, 0, side * -6, side * flap)
		elseif string.sub(name, 1, 4) == "Tail" then
			local i = tonumber(string.match(name, "(%d+)$")) or 1
			local sway = math.sin(time * 2.2 - i * 0.7) * (6 + i * 2)
			Rig.turn(joint, math.sin(time * 1.6 - i * 0.5) * 3, sway, 0)
		elseif string.sub(name, 1, 4) == "Head" then
			local i = tonumber(string.match(name, "(%d+)$")) or 0
			Rig.turn(joint, math.sin(time * 1.5 + i) * 5, math.sin(time * 0.9 + i * 2) * 6, 0)
		elseif string.sub(name, 1, 3) == "Jaw" then
			local open = if now < f.jawUntil then -28 else -2 - (math.sin(time * 1.2) + 1) * 2
			Rig.turn(joint, open, 0, 0)
		end
	end
end

-- 当たったところで、光がふくらんで消える
local function burst(position: Vector3, color: Color3, size: number)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.CFrame = CFrame.new(position)
	p.Parent = folder
	TweenService:Create(p, TweenInfo.new(0.3), { Size = Vector3.one * size, Transparency = 1 }):Play()
	task.delay(0.3, function()
		p:Destroy()
	end)
end

-- 口から敵へ、光の玉を飛ばす
local function shoot(player: Player, f: Follower, enemy, mouth: Vector3)
	local attack = f.dragon.attack
	if not Enemies.isAlive(enemy) or not f.model.Parent then
		return
	end
	local from = (f.cf * CFrame.new(mouth * f.scale)).Position
	local to = Enemies.centerOf(enemy)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * (0.8 + attack.damage / 40)
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Material = Enum.Material.Neon
	ball.Color = attack.color
	ball.CFrame = CFrame.new(from)
	local light = Instance.new("PointLight")
	light.Color = attack.color
	light.Range = 8
	light.Parent = ball
	ball.Parent = folder
	local travel = math.clamp((to - from).Magnitude / 120, 0.08, 0.45)
	TweenService:Create(ball, TweenInfo.new(travel, Enum.EasingStyle.Linear), { CFrame = CFrame.new(to) }):Play()
	task.delay(travel, function()
		ball:Destroy()
		if Enemies.isAlive(enemy) then
			burst(Enemies.centerOf(enemy), attack.color, 3 + attack.damage / 15)
			Enemies.damage(enemy, attack.damage, player)
		end
	end)
end

local function tryAttack(player: Player, f: Follower)
	local attack = f.dragon.attack
	if not attack then
		return
	end
	local now = os.clock()
	if now - f.lastAttack < attack.cooldown then
		return
	end
	local enemy = Enemies.findNearest(f.cf.Position, attack.range)
	f.target = enemy
	if not enemy then
		return
	end
	f.lastAttack = now
	f.jawUntil = now + 0.35 + (attack.shots - 1) * 0.12
	local mouths = f.look.mouths
	for i = 1, attack.shots do
		local mouth = mouths[(i - 1) % #mouths + 1]
		task.delay((i - 1) * 0.12, shoot, player, f, enemy, mouth)
	end
end

function Dragons.start()
	folder = Instance.new("Folder")
	folder.Name = "Dragons"
	folder.Parent = workspace

	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		t += dt
		local now = os.clock()
		for player, f in followers do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if not root then
				continue
			end
			-- 近くの敵を自動でこうげき（持ち主が生きている間だけ）
			if humanoid and humanoid.Health > 0 then
				tryAttack(player, f)
			end
			-- 右うしろ上に浮かぶ
			local look = root.CFrame.LookVector
			local flatLook = Vector3.new(look.X, 0, look.Z)
			if flatLook.Magnitude < 0.01 then
				flatLook = Vector3.new(0, 0, -1)
			end
			flatLook = flatLook.Unit
			local right = flatLook:Cross(Vector3.yAxis)
			local bob = math.sin(t * 3) * 0.6
			local goalPos = root.Position
				+ right * (4 + f.scale * 2)
				- flatLook * (4 + f.scale * 2)
				+ Vector3.new(0, 2 + f.scale + bob, 0)
			-- 敵をねらっている間は、そちらを向く
			local faceDir = flatLook
			if f.target and Enemies.isAlive(f.target) then
				local toEnemy = Enemies.centerOf(f.target) - goalPos
				toEnemy = Vector3.new(toEnemy.X, 0, toEnemy.Z)
				if toEnemy.Magnitude > 0.1 then
					faceDir = toEnemy.Unit
				end
			end
			local goal = CFrame.lookAt(goalPos, goalPos + faceDir)
			-- 遠すぎたら瞬間移動、ふだんはなめらかに追う
			if (f.cf.Position - goalPos).Magnitude > 80 then
				f.cf = goal
			else
				f.cf = f.cf:Lerp(goal, math.min(1, dt * 8))
			end
			f.root.CFrame = f.cf
			animate(f, t, now)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		Dragons.equip(player, nil)
	end)
end

return Dragons
