-- ゲーム全体の設定（数字を変えるとバランスを調整できます）
local Config = {}

Config.GameTitle = "たまごダッシュ"

-- 進行状況を保存する DataStore の名前（変えると全員の記録がリセットされます）
Config.DataStoreName = "EggDash_v1"

-- 走る速さ = 16 + スピード ÷ 20（上限 200）
Config.BaseWalkSpeed = 16
Config.SpeedPerWalk = 20
Config.MaxWalkSpeed = 200

function Config.walkSpeedFor(speed: number): number
	return math.min(Config.BaseWalkSpeed + math.floor(speed / Config.SpeedPerWalk), Config.MaxWalkSpeed)
end

-- ルームランナー：gain = 1秒あたりに増えるスピード、required = 使うのに必要なスピード
Config.Treadmills = {
	{ name = "ふつうのマシン", gain = 1, required = 0, color = Color3.fromRGB(90, 170, 255) },
	{ name = "シルバーマシン", gain = 3, required = 100, color = Color3.fromRGB(200, 205, 215) },
	{ name = "ゴールドマシン", gain = 8, required = 400, color = Color3.fromRGB(255, 200, 40) },
	{ name = "ダイヤマシン", gain = 20, required = 1200, color = Color3.fromRGB(120, 255, 240) },
}

-- たまごのゾーン：distance = ベースの中心からたまごまでの距離
-- 遠いほど敵が多く・速く・強くなり、ごほうびも増える
Config.Zones = {
	{
		name = "草原",
		enemyHealth = 30,
		distance = 300,
		enemies = 1,
		enemySpeed = 12,
		damage = 15,
		reward = 15,
		ground = Color3.fromRGB(110, 190, 90),
		road = Color3.fromRGB(205, 175, 120),
		enemyColor = Color3.fromRGB(120, 220, 90),
		eggColor = Color3.fromRGB(255, 250, 235),
		decor = "tree",
	},
	{
		name = "砂漠",
		enemyHealth = 90,
		distance = 800,
		enemies = 2,
		enemySpeed = 22,
		damage = 25,
		reward = 40,
		ground = Color3.fromRGB(235, 205, 130),
		road = Color3.fromRGB(190, 150, 90),
		enemyColor = Color3.fromRGB(230, 140, 50),
		eggColor = Color3.fromRGB(255, 190, 120),
		decor = "cactus",
	},
	{
		name = "雪原",
		enemyHealth = 220,
		distance = 1500,
		enemies = 3,
		enemySpeed = 32,
		damage = 35,
		reward = 100,
		ground = Color3.fromRGB(235, 245, 255),
		road = Color3.fromRGB(170, 200, 230),
		enemyColor = Color3.fromRGB(90, 170, 255),
		eggColor = Color3.fromRGB(170, 230, 255),
		decor = "pine",
	},
	{
		name = "火山",
		enemyHealth = 500,
		distance = 2400,
		enemies = 4,
		enemySpeed = 46,
		damage = 45,
		reward = 250,
		ground = Color3.fromRGB(70, 55, 55),
		road = Color3.fromRGB(120, 90, 80),
		enemyColor = Color3.fromRGB(255, 70, 40),
		eggColor = Color3.fromRGB(255, 110, 60),
		decor = "rock",
	},
	{
		name = "雲の上",
		enemyHealth = 1000,
		distance = 3500,
		enemies = 5,
		enemySpeed = 64,
		damage = 60,
		reward = 600,
		ground = Color3.fromRGB(250, 250, 255),
		road = Color3.fromRGB(255, 225, 140),
		enemyColor = Color3.fromRGB(170, 90, 255),
		eggColor = Color3.fromRGB(255, 215, 60),
		decor = "cloud",
		boss = true, -- 1体だけ大きいボスになる
	},
}

-- ショップの商品（一度買うとずっと使える）
-- trainMult: トレーニング倍率（持っている中で一番高いものが効く）
-- maxHealth: 最大体力 / damageMult: 受けるダメージの倍率 / jumpPower: ジャンプ力
Config.Items = {
	{
		id = "Shoes2",
		name = "ランニングシューズ",
		price = 50,
		desc = "トレーニング効果 2倍",
		trainMult = 2,
	},
	{ id = "Shoes3", name = "プロシューズ", price = 300, desc = "トレーニング効果 3倍", trainMult = 3 },
	{
		id = "Shoes5",
		name = "ロケットシューズ",
		price = 1500,
		desc = "トレーニング効果 5倍",
		trainMult = 5,
	},
	{
		id = "Shoes10",
		name = "でんせつのシューズ",
		price = 6000,
		desc = "トレーニング効果 10倍",
		trainMult = 10,
	},
	{ id = "Health1", name = "体力アップ", price = 120, desc = "最大体力 100 → 175", maxHealth = 175 },
	{ id = "Health2", name = "体力アップ II", price = 900, desc = "最大体力 → 300", maxHealth = 300 },
	{
		id = "Armor1",
		name = "木のたて",
		price = 200,
		desc = "受けるダメージ 25% ダウン",
		damageMult = 0.75,
	},
	{ id = "Armor2", name = "鉄のよろい", price = 1200, desc = "受けるダメージ 半分", damageMult = 0.5 },
	{ id = "Jump1", name = "ジャンプばね", price = 80, desc = "ジャンプ力アップ", jumpPower = 70 },
	{
		id = "Cage4",
		name = "檻をふやす",
		price = 400,
		desc = "檻に入るたまご 3 → 4こ",
		incubatorSlots = 4,
	},
	{
		id = "Cage5",
		name = "檻をふやす II",
		price = 2500,
		desc = "檻に入るたまご → 5こ",
		incubatorSlots = 5,
	},
}

-- はじめの仲間（全員無料。1体えらんで連れて行ける。後ろをついてきて、力をくれる）
-- たまごから生まれるドラゴン（Config.HatchDragons）も、同じしくみで連れて行ける
-- shape: 見た目の種類 / trainMult: トレーニング倍率に掛ける / coinMult: たまごのコイン倍率
-- damageMult: 受けるダメージの倍率 / walkBonus: 走る速さに足す / regen: 1秒に回復する体力
-- attack: 近くの敵を自動でこうげき（damage = 1発の威力、shots = 1回に撃つ数、range = 届く距離、cooldown = 何秒ごとか）
Config.Dragons = {
	{
		id = "Chibi",
		name = "ちびドラゴン",
		desc = "トレーニング 1.5倍",
		shape = "small",
		color = Color3.fromRGB(110, 200, 255),
		trainMult = 1.5,
		attack = { damage = 8, shots = 1, range = 35, cooldown = 1, color = Color3.fromRGB(150, 220, 255) },
	},
	{
		id = "Thunder",
		name = "いかずちドラゴン",
		desc = "走る速さ +10・速射",
		shape = "winged",
		color = Color3.fromRGB(255, 220, 60),
		walkBonus = 10,
		attack = { damage = 12, shots = 1, range = 45, cooldown = 0.5, color = Color3.fromRGB(255, 240, 90) },
	},
	{
		id = "Gaia",
		name = "ガイアマグマ",
		desc = "大地とマグマの竜。ダメージ 40% ダウン",
		shape = "magma",
		color = Color3.fromRGB(200, 50, 30),
		damageMult = 0.6,
		attack = { damage = 35, shots = 1, range = 40, cooldown = 1.3, color = Color3.fromRGB(255, 120, 30) },
	},
	{
		id = "Triple",
		name = "トリプルヘッド",
		desc = "三つ首の金の竜。コイン 1.5倍",
		shape = "triple",
		color = Color3.fromRGB(240, 190, 50),
		coinMult = 1.5,
		attack = { damage = 15, shots = 3, range = 45, cooldown = 1.2, color = Color3.fromRGB(255, 210, 80) },
	},
	{
		id = "Giga",
		name = "ギガザウルス",
		desc = "巨大な怪獣。こうげき力 最強",
		shape = "giant",
		color = Color3.fromRGB(70, 110, 80),
		attack = { damage = 70, shots = 1, range = 55, cooldown = 1.4, color = Color3.fromRGB(255, 80, 40) },
	},
	{
		id = "Phoenix",
		name = "フェニックス",
		desc = "炎の不死鳥。体力が 1秒に 5 回復",
		shape = "phoenix",
		color = Color3.fromRGB(230, 60, 40),
		regen = 5,
		attack = { damage = 20, shots = 1, range = 50, cooldown = 0.9, color = Color3.fromRGB(255, 150, 40) },
	},
}

-- 敵が反応する距離と、たまごから離れて追いかけてくる限界
Config.EnemyAggroRange = 55
Config.EnemyLeashRange = 120

-- 敵をたおしたとき：ボスは体力 4倍、たまごのごほうびの 30% のコイン、何秒後に復活するか
Config.BossHealthMult = 4
Config.EnemyBountyRate = 0.3
Config.EnemyRespawnTime = 12
Config.BossRespawnTime = 30

------------------------------------------------------------------------
-- 檻でたまごをかえす
------------------------------------------------------------------------

-- 檻に入るたまごの数（ショップの「檻をふやす」で増える）
Config.IncubatorSlots = 3

-- ゾーンごとの、かえるまでの時間（秒）
Config.HatchTime = { 30, 60, 120, 240, 480 }

-- レア度
Config.Rarities = {
	{ name = "ノーマル", color = Color3.fromRGB(210, 210, 210) },
	{ name = "レア", color = Color3.fromRGB(90, 175, 255) },
	{ name = "スーパーレア", color = Color3.fromRGB(195, 100, 255) },
	{ name = "ウルトラレア", color = Color3.fromRGB(255, 175, 40) },
	{ name = "レジェンド", color = Color3.fromRGB(255, 80, 90) },
}

-- ゾーンごとの、レア度の出やすさ（ノーマル, レア, スーパーレア, ウルトラレア, レジェンド の重み）
-- 遠いたまごほどレアなドラゴンが出る
Config.HatchOdds = {
	{ 70, 25, 5, 0, 0 },
	{ 50, 35, 13, 2, 0 },
	{ 30, 38, 24, 7, 1 },
	{ 15, 30, 33, 18, 4 },
	{ 5, 20, 35, 28, 12 },
}

-- 100種類のドラゴンは「属性 × 体の形」で作る
-- tier が高い属性・形ほどレアになる（合計でレア度が決まる）
local ELEMENTS = {
	{ name = "ほのお", tier = 0, color = Color3.fromRGB(255, 90, 40) },
	{ name = "みず", tier = 0, color = Color3.fromRGB(60, 140, 255) },
	{ name = "くさ", tier = 0, color = Color3.fromRGB(80, 200, 80) },
	{ name = "いわ", tier = 0, color = Color3.fromRGB(150, 130, 100) },
	{ name = "かぜ", tier = 0, color = Color3.fromRGB(160, 235, 215) },
	{ name = "つち", tier = 0, color = Color3.fromRGB(170, 110, 60) },
	{ name = "こおり", tier = 1, color = Color3.fromRGB(175, 230, 255) },
	{ name = "かみなり", tier = 1, color = Color3.fromRGB(255, 225, 50) },
	{ name = "どく", tier = 1, color = Color3.fromRGB(165, 75, 200) },
	{ name = "はがね", tier = 1, color = Color3.fromRGB(170, 175, 190) },
	{ name = "すな", tier = 1, color = Color3.fromRGB(230, 200, 130) },
	{ name = "やみ", tier = 2, color = Color3.fromRGB(70, 45, 100) },
	{ name = "ひかり", tier = 2, color = Color3.fromRGB(255, 250, 205) },
	{ name = "ほし", tier = 2, color = Color3.fromRGB(110, 120, 255) },
	{ name = "さくら", tier = 2, color = Color3.fromRGB(255, 170, 205) },
	{ name = "にじ", tier = 3, color = Color3.fromRGB(255, 110, 240) },
	{ name = "きん", tier = 3, color = Color3.fromRGB(255, 200, 40) },
}

-- 体の形ごとに、得意なこと（skill）がちがう
local SHAPES = {
	{ shape = "small", noun = "ドラ", tier = 0, skill = "train", cooldown = 1, shots = 1, power = 1 },
	{ shape = "winged", noun = "ウイング", tier = 1, skill = "walk", cooldown = 0.6, shots = 1, power = 0.8 },
	{ shape = "magma", noun = "ガイア", tier = 1, skill = "guard", cooldown = 1.3, shots = 1, power = 1.4 },
	{ shape = "phoenix", noun = "フェニックス", tier = 2, skill = "regen", cooldown = 0.9, shots = 1, power = 1 },
	{ shape = "triple", noun = "トリプル", tier = 2, skill = "coin", cooldown = 1.2, shots = 3, power = 0.6 },
	{ shape = "giant", noun = "ザウルス", tier = 2, skill = "power", cooldown = 1.4, shots = 1, power = 2 },
}

-- 100種類ちょうどにするため、はずす組み合わせ
local SKIP = { ["すなドラ"] = true, ["つちウイング"] = true }

-- レア度ごとの基本のこうげき力
local BASE_DAMAGE = { 6, 10, 18, 30, 50 }

-- 1.25 → "1.25"、1.5 → "1.5"、2 → "2"
local function num(x: number): string
	local text = string.format("%.2f", x):gsub("0+$", ""):gsub("%.$", "")
	return text
end

Config.HatchDragons = {}
Config.HatchByRarity = { {}, {}, {}, {}, {} }

do
	local n = 0
	for _, shape in SHAPES do
		for _, element in ELEMENTS do
			local name = element.name .. shape.noun
			if SKIP[name] then
				continue
			end
			n += 1
			local score = shape.tier + element.tier
			-- 0〜1 → ノーマル、2 → レア、3 → スーパーレア、4 → ウルトラレア、5 → レジェンド
			local rarity = if score <= 1 then 1 else math.min(score, 5)
			local d = {
				id = string.format("H%03d", n),
				name = name,
				shape = shape.shape,
				color = element.color,
				rarity = rarity,
				attack = {
					damage = math.floor(BASE_DAMAGE[rarity] * shape.power + 0.5),
					shots = shape.shots,
					range = 35 + rarity * 5,
					cooldown = shape.cooldown,
					color = element.color,
				},
			}
			if shape.skill == "train" then
				d.trainMult = 1 + rarity * 0.25
				d.desc = "トレーニング " .. num(d.trainMult) .. "倍"
			elseif shape.skill == "walk" then
				d.walkBonus = rarity * 4
				d.desc = string.format("走る速さ +%d", d.walkBonus)
			elseif shape.skill == "guard" then
				d.damageMult = 1 - rarity * 0.1
				d.desc = string.format("ダメージ %d%% ダウン", math.floor(rarity * 10 + 0.5))
			elseif shape.skill == "regen" then
				d.regen = rarity * 2
				d.desc = string.format("体力が 1秒に %d 回復", d.regen)
			elseif shape.skill == "coin" then
				d.coinMult = 1 + rarity * 0.15
				d.desc = "たまごのコイン " .. num(d.coinMult) .. "倍"
			else
				d.desc = "こうげき力 2倍"
			end
			table.insert(Config.HatchDragons, d)
			table.insert(Config.HatchByRarity[rarity], d)
		end
	end
end

-- id からドラゴンをさがす（はじめの仲間 → 生まれるドラゴンの順）
local byId = {}
for _, d in Config.Dragons do
	byId[d.id] = d
end
for _, d in Config.HatchDragons do
	byId[d.id] = d
end
function Config.findDragon(id: string?)
	return if id then byId[id] else nil
end

return Config
