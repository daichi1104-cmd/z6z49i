-- ゲーム全体の設定（数字を変えるとバランスを調整できます）
local Config = {}

Config.GameTitle = "爆速ドラゴニック卵ゲーム🐉"

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
		enemyName = "大トカゲ",
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
		enemyName = "大サソリ",
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
		enemyName = "氷のオオカミ",
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
		enemyName = "溶岩サンショウウオ",
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
		enemyName = "あらしの竜",
		boss = true, -- 1体だけ大きいボスになる
		bossName = "やみの竜王",
	},
	{
		name = "星空",
		enemyHealth = 2000,
		distance = 4800,
		enemies = 5,
		enemySpeed = 78,
		damage = 75,
		reward = 1500,
		ground = Color3.fromRGB(28, 26, 64),
		road = Color3.fromRGB(150, 135, 255),
		enemyColor = Color3.fromRGB(90, 220, 255),
		eggColor = Color3.fromRGB(160, 130, 255),
		decor = "star",
		enemyName = "ほしくずの竜",
	},
	{
		-- ひみつのゾーン：条件（Config.SecretZone）を満たした人だけ、門を通れる
		name = "古代の遺跡",
		enemyHealth = 4000,
		distance = 6300,
		enemies = 6,
		enemySpeed = 92,
		damage = 95,
		reward = 4000,
		ground = Color3.fromRGB(110, 140, 80),
		road = Color3.fromRGB(190, 175, 140),
		enemyColor = Color3.fromRGB(70, 230, 150),
		eggColor = Color3.fromRGB(90, 255, 175),
		decor = "ruins",
		enemyName = "いせきのゴーレム",
		boss = true,
		bossName = "こだいの守護竜",
		secret = true,
	},
}

-- ひみつのゾーン（古代の遺跡）の門が開く条件
Config.SecretZone = { bossKills = 3, book = 30 }

-- たまごの大きさの倍率（ゾーンの順。遠いゾーンのたまごほどレアで、大きい）
Config.EggScale = { 1, 1.2, 1.45, 1.75, 2.1, 2.4, 2.7 }

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
	{
		id = "Team2",
		name = "仲間の席",
		price = 1000,
		desc = "いっしょに連れていけるドラゴン 1 → 2匹",
		teamSlots = 2,
	},
	{
		id = "Team3",
		name = "仲間の席 II",
		price = 8000,
		desc = "いっしょに連れていけるドラゴン → 3匹",
		teamSlots = 3,
	},
}

-- いっしょに連れていけるドラゴンの数（ショップの「仲間の席」で増える）
Config.TeamSlots = 1

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
		id = "SeaGuard",
		name = "シルバーウイング",
		desc = "海と風の守り神。走る速さ +15・体力が 1秒に 2 回復",
		shape = "guardian",
		color = Color3.fromRGB(215, 220, 230),
		walkBonus = 15,
		regen = 2,
		attack = { damage = 25, shots = 1, range = 50, cooldown = 0.8, color = Color3.fromRGB(140, 255, 235) },
	},
	{
		id = "DeepBlue",
		name = "ディープブルー",
		desc = "海の巨大ドラゴン。ダメージ 30% ダウン・コイン 1.2倍",
		shape = "leviathan",
		color = Color3.fromRGB(40, 90, 200),
		damageMult = 0.7,
		coinMult = 1.2,
		attack = { damage = 40, shots = 1, range = 45, cooldown = 1.2, color = Color3.fromRGB(60, 170, 255) },
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
Config.HatchTime = { 30, 60, 120, 240, 480, 720, 960 }

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
	{ 2, 10, 30, 35, 23 },
	{ 0, 4, 22, 40, 34 },
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
				element = element.name,
				noun = shape.noun,
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

-- 名前（属性 + 体の形）からドラゴンをさがす（交配で使う）
local byName = {}
for _, d in Config.HatchDragons do
	byName[d.name] = d
end
function Config.findDragonByName(name: string)
	return byName[name]
end

------------------------------------------------------------------------
-- 特別なたまご（ゾーンのたまご以外）
------------------------------------------------------------------------

-- 黄金のたまご（イベントで出る）と、交配のたまご（中身は交配したときに決まる）
Config.SpecialEggs = {
	gold = {
		name = "黄金",
		reward = 800,
		color = Color3.fromRGB(255, 205, 40),
		scale = 2.2,
		hatchTime = 300,
		odds = { 0, 10, 35, 35, 20 },
	},
	breed = {
		name = "交配",
		reward = 0,
		color = Color3.fromRGB(255, 160, 210),
		scale = 1.4,
		hatchTime = 120,
	},
}

-- たまごの情報：zone が数字ならゾーンのたまご、文字なら特別なたまご
function Config.eggInfo(zone: any)
	if typeof(zone) == "number" then
		local z = Config.Zones[zone]
		if not z then
			return nil
		end
		return {
			name = z.name,
			reward = z.reward,
			color = z.eggColor,
			scale = Config.EggScale[zone],
			hatchTime = Config.HatchTime[zone],
			odds = Config.HatchOdds[zone],
		}
	end
	return Config.SpecialEggs[zone]
end

-- 黄金のたまごイベント：every 秒ごとに、duration 秒のあいだ（全部のサーバーで同じ時間）
-- 30分ごと（毎時 0分と30分）から 3分間
Config.GoldenEvent = { every = 1800, duration = 180 }

------------------------------------------------------------------------
-- ドラゴンのレベルと、わざ
------------------------------------------------------------------------

-- 経験値：敵をたおす・たまごを届ける・ルームランナーで走ると、連れているドラゴンに入る
Config.MaxLevel = 30
Config.SkillLevel = 5 -- このレベルで、わざを覚える
function Config.levelFor(xp: number): number
	return math.min(Config.MaxLevel, 1 + math.floor(math.sqrt(math.max(0, xp) / 10)))
end
function Config.xpForLevel(level: number): number
	return 10 * (level - 1) ^ 2
end
-- レベルが 1 上がるごとに、こうげき力が 5% アップ
function Config.levelPower(level: number): number
	return 1 + 0.05 * (level - 1)
end

-- わざ（体の形ごと）。左の「✨ わざ」ボタンで、連れているドラゴン全員が使う
-- kind: train（トレーニング倍率）/ speed（走る速さ）/ shield（ダメージなし）/ heal（回復）
--       blast（まわりの敵に大ダメージ）/ quake（まわりの敵を止めてダメージ）
Config.SkillCooldown = 25
Config.Skills = {
	small = {
		name = "がんばれコール",
		desc = "15秒 トレーニング 3倍",
		kind = "train",
		value = 3,
		duration = 15,
		color = Color3.fromRGB(120, 220, 255),
	},
	winged = {
		name = "おいかぜ",
		desc = "8秒 走る速さ +40",
		kind = "speed",
		value = 40,
		duration = 8,
		color = Color3.fromRGB(255, 240, 120),
	},
	guardian = {
		name = "海風のまもり",
		desc = "8秒 走る速さ +30",
		kind = "speed",
		value = 30,
		duration = 8,
		color = Color3.fromRGB(150, 255, 235),
	},
	magma = {
		name = "マグマバリア",
		desc = "6秒 ダメージを受けない",
		kind = "shield",
		duration = 6,
		color = Color3.fromRGB(255, 120, 40),
	},
	phoenix = {
		name = "いやしの炎",
		desc = "体力を 60% 回復",
		kind = "heal",
		value = 0.6,
		color = Color3.fromRGB(255, 160, 60),
	},
	triple = {
		name = "トリプルブレス",
		desc = "まわりの敵に こうげき力 ×6 のダメージ",
		kind = "blast",
		value = 6,
		radius = 60,
		color = Color3.fromRGB(255, 210, 80),
	},
	giant = {
		name = "だいじしん",
		desc = "まわりの敵を 4秒 止めて ×3 のダメージ",
		kind = "quake",
		value = 3,
		duration = 4,
		radius = 50,
		color = Color3.fromRGB(170, 120, 70),
	},
	leviathan = {
		name = "だいつなみ",
		desc = "まわりの敵を 3秒 止めて ×3 のダメージ",
		kind = "quake",
		value = 3,
		duration = 3,
		radius = 60,
		color = Color3.fromRGB(60, 170, 255),
	},
}

------------------------------------------------------------------------
-- 進化・交配・卒業
------------------------------------------------------------------------

-- 同じドラゴン 3体 → ひとつ上のレア度のドラゴン 1体
Config.MergeCount = 3
-- 交配にかかるコイン（2匹のレア度の合計で決まる）
function Config.breedCost(rarityA: number, rarityB: number): number
	return 50 * (rarityA + rarityB) ^ 2
end
-- 卒業させたときにもらえるコイン（レア度の順）
Config.GraduateCoins = { 30, 100, 400, 1500, 6000 }

------------------------------------------------------------------------
-- 毎日のごほうび
------------------------------------------------------------------------

-- 日付は日本時間で切りかわる
function Config.today(now: number?): number
	return math.floor(((now or os.time()) + 9 * 3600) / 86400)
end

-- ログインボーナス（7日でひとまわり）。coins は「ごほうびの基本」の何倍か、egg = ふしぎなたまご
Config.LoginRewards = {
	{ coins = 1 },
	{ coins = 2 },
	{ coins = 3 },
	{ coins = 4 },
	{ coins = 5 },
	{ coins = 6 },
	{ coins = 5, egg = true },
}

-- 無料のたまご（ガチャ）：何秒ごとに 1回ひけるか
Config.FreeEggInterval = 4 * 3600

-- 今日のミッション（毎日 3つ）。stat = 数えるもの、targets = 目標の候補
Config.MissionCount = 3
Config.MissionKinds = {
	{ kind = "delivered", text = "たまごを %d こ 届ける", targets = { 3, 5, 8 } },
	{ kind = "kills", text = "敵を %d 体 たおす", targets = { 10, 20, 30 } },
	{ kind = "hatched", text = "たまごを %d こ かえす", targets = { 2, 3, 5 } },
	{ kind = "trained", text = "スピードを %d きたえる" }, -- 目標は、その人のスピードで決まる
	{ kind = "zone", text = "%sのたまごを 1こ 届ける" }, -- 行ったことのある一番遠いゾーン
	{ kind = "towerFloors", text = "塔で %d 階 クリアする", targets = { 3, 5, 8 } },
}

------------------------------------------------------------------------
-- 実績（図鑑のコンプリートボーナスも、ここに入れる）
------------------------------------------------------------------------

-- stat：delivered / hatched / kills / bossKills / trained / merges / breeds / graduated / loginDays
--       towerBest / book（図鑑の数）/ level（一番高いレベル）/ z6・z7（そのゾーンのたまごを届けた数）
--       r4・r5（ウルトラレア・レジェンドに出会った数）
Config.Achievements = {}
do
	local function add(id: string, name: string, stat: string, goal: number, reward: number, desc: string)
		table.insert(
			Config.Achievements,
			{ id = id, name = name, stat = stat, goal = goal, reward = reward, desc = desc }
		)
	end
	for _, g in { { 1, 50 }, { 10, 200 }, { 100, 2000 }, { 500, 10000 }, { 1000, 30000 } } do
		add(
			"deliver" .. g[1],
			"たまご運び",
			"delivered",
			g[1],
			g[2],
			string.format("たまごを %d こ 届ける", g[1])
		)
	end
	for _, g in { { 1, 50 }, { 10, 300 }, { 50, 2000 }, { 200, 10000 } } do
		add(
			"hatch" .. g[1],
			"ふ化マスター",
			"hatched",
			g[1],
			g[2],
			string.format("たまごを %d こ かえす", g[1])
		)
	end
	for _, g in { { 10, 100 }, { 100, 1000 }, { 1000, 8000 }, { 5000, 40000 } } do
		add(
			"kill" .. g[1],
			"ドラゴンハンター",
			"kills",
			g[1],
			g[2],
			string.format("敵を %d 体 たおす", g[1])
		)
	end
	for _, g in { { 1, 1000 }, { 10, 8000 }, { 50, 40000 } } do
		add(
			"boss" .. g[1],
			"ボスたおし",
			"bossKills",
			g[1],
			g[2],
			string.format("ボスを %d 回 たおす", g[1])
		)
	end
	for _, g in { { 1000, 300 }, { 10000, 3000 }, { 100000, 30000 } } do
		add(
			"train" .. g[1],
			"きたえる足",
			"trained",
			g[1],
			g[2],
			string.format("スピードを %d きたえる", g[1])
		)
	end
	-- 図鑑のコンプリートボーナス
	for _, g in { { 10, 500 }, { 25, 2000 }, { 50, 8000 }, { 75, 20000 }, { 100, 100000 } } do
		add(
			"book" .. g[1],
			"図鑑ボーナス",
			"book",
			g[1],
			g[2],
			string.format("図鑑を %d 種類 うめる", g[1])
		)
	end
	add("r4", "はじめてのウルトラレア", "r4", 1, 2000, "ウルトラレアに 出会う")
	add("r5", "はじめてのレジェンド", "r5", 1, 10000, "レジェンドに 出会う")
	add("z6", "星空のたまご", "z6", 1, 3000, "星空のたまごを 届ける")
	add("z7", "古代のひみつ", "z7", 1, 10000, "古代の遺跡のたまごを 届ける")
	for _, g in { { 5, 500 }, { 10, 2000 }, { 20, 10000 }, { 30, 40000 } } do
		add(
			"tower" .. g[1],
			"塔のぼり",
			"towerBest",
			g[1],
			g[2],
			string.format("塔の %d 階を クリアする", g[1])
		)
	end
	for _, g in { { 7, 1000 }, { 30, 10000 } } do
		add(
			"login" .. g[1],
			"まいにちログイン",
			"loginDays",
			g[1],
			g[2],
			string.format("%d 日 ログインする", g[1])
		)
	end
	add("merge1", "はじめての進化", "merges", 1, 500, "ドラゴンを 進化させる")
	add("merge10", "進化マスター", "merges", 10, 5000, "ドラゴンを 10回 進化させる")
	add("breed1", "はじめての交配", "breeds", 1, 500, "ドラゴンを 交配する")
	add("breed10", "交配マスター", "breeds", 10, 5000, "ドラゴンを 10回 交配する")
	add("grad1", "はじめての卒業", "graduated", 1, 100, "ドラゴンを 卒業させる")
	add("level10", "なかよしレベル", "level", 10, 2000, "ドラゴンを レベル 10 にする")
	add("level30", "さいきょうの相棒", "level", 30, 30000, "ドラゴンを レベル 30 にする")
end

------------------------------------------------------------------------
-- 塔のぼりモード
------------------------------------------------------------------------

-- 塔の部屋は、空の高いところ（y = arenaY）に、プレイヤーごとに作る
Config.Tower = { arenaY = 900, spacing = 400, size = 120, rest = 3 }

-- f 階の敵：5階ごとにボス
function Config.towerFloor(f: number)
	local boss = f % 5 == 0
	local look = (math.floor((f - 1) / 2) % #Config.Zones) + 1
	return {
		count = if boss then 1 + math.floor(f / 10) else math.min(2 + math.floor(f / 3), 6),
		boss = boss,
		look = look,
		hp = math.floor(30 * 1.3 ^ (f - 1)),
		damage = 12 + 4 * f,
		speed = math.min(14 + 2.5 * f, 90),
		reward = math.floor(25 * 1.28 ^ (f - 1)),
	}
end

return Config
