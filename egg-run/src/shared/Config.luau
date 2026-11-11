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
	{ name = "神話", color = Color3.fromRGB(255, 70, 220) }, -- 課金の武器だけ
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
	for _, g in { { 5, 1000 }, { 20, 10000 }, { 50, 200000 } } do
		add(
			"weapon" .. g[1],
			"武器コレクター",
			"weapons",
			g[1],
			g[2],
			string.format("武器を %d 種類 集める", g[1])
		)
	end
	for _, g in { { 10, 300 }, { 200, 5000 } } do
		add(
			"wkill" .. g[1],
			"武器の達人",
			"weaponKills",
			g[1],
			g[2],
			string.format("武器で 敵を %d 体 たおす", g[1])
		)
	end
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

------------------------------------------------------------------------
-- 武器（自分でも戦える）：10の形 × 5つのレア度 = 50種類
------------------------------------------------------------------------

-- 形ごとの特ちょう
-- power = こうげき力の倍率、cooldown = 何秒ごとにふれるか、range = とどく距離、arc = 当たる角度（度）
-- crit = 会心（2倍）の出やすさ、stun = 敵を止める秒数、ranged = 遠くへ飛ばす、splash = 当たったまわりにも当たる半径
Config.WeaponShapes = {
	{ shape = "sword", noun = "剣", power = 1, cooldown = 0.5, range = 9, arc = 110, desc = "バランスがいい" },
	{
		shape = "katana",
		noun = "刀",
		power = 0.9,
		cooldown = 0.35,
		range = 9,
		arc = 90,
		crit = 0.25,
		desc = "すばやい。ときどき会心の一撃（2倍）",
	},
	{
		shape = "dagger",
		noun = "短剣",
		power = 0.5,
		cooldown = 0.22,
		range = 6,
		arc = 80,
		desc = "とても はやく ふれる",
	},
	{
		shape = "greatsword",
		noun = "大剣",
		power = 2.2,
		cooldown = 1,
		range = 11,
		arc = 170,
		desc = "おそいが 広く 強い",
	},
	{
		shape = "spear",
		noun = "槍",
		power = 1.1,
		cooldown = 0.6,
		range = 16,
		arc = 40,
		desc = "まっすぐ 遠くまで とどく",
		lunge = true,
	},
	{
		shape = "scythe",
		noun = "鎌",
		power = 1.3,
		cooldown = 0.9,
		range = 12,
		arc = 360,
		desc = "ぐるっと回って まわり全部に当たる",
	},
	{ shape = "axe", noun = "斧", power = 1.9, cooldown = 0.8, range = 8, arc = 110, desc = "一撃が 重い" },
	{
		shape = "hammer",
		noun = "ハンマー",
		power = 2.3,
		cooldown = 1.2,
		range = 10,
		arc = 360,
		stun = 1,
		desc = "地面をたたいて まわりの敵を 1秒 止める",
	},
	{
		shape = "bow",
		noun = "弓",
		power = 0.9,
		cooldown = 0.65,
		range = 70,
		arc = 120,
		ranged = true,
		desc = "遠くの敵を 矢で ねらう",
	},
	{
		shape = "staff",
		noun = "杖",
		power = 1.1,
		cooldown = 1,
		range = 55,
		arc = 120,
		ranged = true,
		splash = 12,
		desc = "魔法の玉が はじけて まわりにも当たる",
	},
}

-- レア度ごとの材料（名前の前につく）、基本のこうげき力、ねだん
Config.WeaponTiers = {
	{ prefix = "ひのきの", damage = 8, price = 150 },
	{ prefix = "てつの", damage = 24, price = 1500 },
	{ prefix = "ミスリルの", damage = 70, price = 12000 },
	{ prefix = "黄金竜の", damage = 200, price = 80000 },
	{ prefix = "星くずの", damage = 550, price = 400000 },
}

-- 形ごとの ねだんの倍率
local WEAPON_PRICE = {
	sword = 1,
	katana = 1.2,
	dagger = 0.8,
	greatsword = 1.3,
	spear = 1.1,
	scythe = 1.4,
	axe = 1.1,
	hammer = 1.3,
	bow = 1.2,
	staff = 1.3,
}

-- ためし用：true のあいだは、武器が全部 無料（ためし終わったら false にもどす）
Config.FreeWeaponsForTest = true

Config.Weapons = {}
do
	local n = 0
	for rarity, tier in Config.WeaponTiers do
		for _, s in Config.WeaponShapes do
			n += 1
			table.insert(Config.Weapons, {
				id = string.format("W%02d", n),
				name = tier.prefix .. s.noun,
				shape = s.shape,
				rarity = rarity,
				damage = math.floor(tier.damage * s.power + 0.5),
				cooldown = s.cooldown,
				range = s.range,
				arc = s.arc,
				crit = s.crit,
				stun = s.stun,
				ranged = s.ranged,
				splash = s.splash,
				lunge = s.lunge,
				desc = s.desc,
				price = if Config.FreeWeaponsForTest
					then 0
					else math.floor(tier.price * WEAPON_PRICE[s.shape] / 10 + 0.5) * 10,
			})
		end
	end
end

-- ★6 神話の武器（課金＝Robux のゲームパスでだけ手に入る。形ごとに 1本ずつ）
-- passId：Roblox で作ったゲームパスの番号（0 のあいだは「準備中」。ためし用の無料中は、無料でもらえる）
-- robux：画面に出す ねだんの目安（本当のねだんは Roblox のゲームパスの設定で決まる）
-- color：光の色、color2：2つめの色（光の粒や軌跡に使う）
Config.MythicWeapons = {
	{
		shape = "sword",
		finisher = "オーロラ・ブレイク", -- 必殺わざの名前
		name = "極光剣オーロラ",
		passId = 2076244905,
		robux = 399,
		color = Color3.fromRGB(80, 255, 200),
		color2 = Color3.fromRGB(150, 120, 255),
	},
	{
		shape = "katana",
		finisher = "紅蓮百花", -- 必殺わざの名前
		name = "紅蓮刀ホムラ",
		passId = 2075068963,
		robux = 399,
		color = Color3.fromRGB(255, 70, 40),
		color2 = Color3.fromRGB(255, 200, 60),
	},
	{
		shape = "dagger",
		finisher = "雷影千手", -- 必殺わざの名前
		name = "雷影短剣イナズマ",
		passId = 2074403036,
		robux = 299,
		color = Color3.fromRGB(255, 240, 80),
		color2 = Color3.fromRGB(120, 200, 255),
	},
	{
		shape = "greatsword",
		finisher = "メテオフォール", -- 必殺わざの名前
		name = "星砕きの大剣",
		passId = 2075626840,
		robux = 499,
		color = Color3.fromRGB(120, 140, 255),
		color2 = Color3.fromRGB(255, 255, 255),
	},
	{
		shape = "spear",
		finisher = "流星一閃", -- 必殺わざの名前
		name = "流星槍ミーティア",
		passId = 2074823017,
		robux = 399,
		color = Color3.fromRGB(255, 160, 60),
		color2 = Color3.fromRGB(255, 255, 200),
	},
	{
		shape = "scythe",
		finisher = "冥府の大旋風", -- 必殺わざの名前
		name = "冥府の大鎌",
		passId = 2075152982,
		robux = 499,
		color = Color3.fromRGB(170, 60, 255),
		color2 = Color3.fromRGB(60, 255, 120),
	},
	{
		shape = "axe",
		finisher = "天地割り", -- 必殺わざの名前
		name = "轟雷斧ライジン",
		passId = 2076178958,
		robux = 399,
		color = Color3.fromRGB(90, 200, 255),
		color2 = Color3.fromRGB(255, 255, 140),
	},
	{
		shape = "hammer",
		finisher = "グランドクエイク", -- 必殺わざの名前
		name = "大地鳴動ハンマー",
		passId = 2074504800,
		robux = 499,
		color = Color3.fromRGB(255, 130, 40),
		color2 = Color3.fromRGB(120, 255, 80),
	},
	{
		shape = "bow",
		finisher = "虹の流星雨", -- 必殺わざの名前
		name = "虹光の神弓",
		passId = 2074966988,
		robux = 399,
		color = Color3.fromRGB(255, 90, 200),
		color2 = Color3.fromRGB(90, 230, 255),
	},
	{
		shape = "staff",
		finisher = "ギャラクシー・ノヴァ", -- 必殺わざの名前
		name = "銀河の杖",
		passId = 2075650997,
		robux = 499,
		color = Color3.fromRGB(110, 90, 255),
		color2 = Color3.fromRGB(255, 120, 230),
	},
}
-- 神話の武器の強さ：基本のこうげき力（形の倍率をかける）、とどく距離の倍率、
-- 何回ふるごとに「必殺」（まわり全部に大ダメージ）が出るか、必殺の半径と倍率
Config.Mythic = { damage = 1600, rangeMult = 1.3, burstEvery = 3, burstRadius = 26, burstMult = 3 }

do
	for i, m in Config.MythicWeapons do
		local s
		for _, shape in Config.WeaponShapes do
			if shape.shape == m.shape then
				s = shape
			end
		end
		table.insert(Config.Weapons, {
			id = string.format("M%02d", i),
			name = m.name,
			shape = m.shape,
			rarity = 6,
			mythic = m,
			damage = math.floor(Config.Mythic.damage * s.power + 0.5),
			cooldown = s.cooldown,
			range = math.floor(s.range * Config.Mythic.rangeMult + 0.5),
			arc = s.arc,
			crit = s.crit,
			stun = s.stun,
			ranged = s.ranged,
			splash = if s.splash then s.splash * 1.5 else nil,
			lunge = s.lunge,
			desc = s.desc .. "。3回に1回 必殺の大爆発",
			price = 0,
			passId = m.passId,
			robux = m.robux,
		})
	end
end

-- はじめから持っている武器（ひのきの剣）
Config.StarterWeapon = "W01"

local weaponById = {}
for _, w in Config.Weapons do
	weaponById[w.id] = w
end
function Config.findWeapon(id: any)
	return if typeof(id) == "string" then weaponById[id] else nil
end

--------------------------------------------------------------------------------
-- 防具：5つの場所 × 2種類 × 5レア度 ＝ 50個
--------------------------------------------------------------------------------

-- 身につける場所（場所ごとに 1つずつ）
Config.ArmorSlots = {
	{ id = "head", name = "頭", icon = "⛑️" },
	{ id = "body", name = "体", icon = "🛡️" },
	{ id = "arms", name = "うで", icon = "🧤" },
	{ id = "legs", name = "足", icon = "🥾" },
	{ id = "back", name = "せなか", icon = "🦋" },
}

-- 能力の種類と、説明の書き方
-- hp：最大体力 / defense：受けるダメージを へらす（%）/ attack：武器のこうげき力（%）/ walk：走る速さ
-- jump：ジャンプ力 / coin：たまごのコイン（%）/ regen：毎秒の回復 / train：トレーニング（%）
Config.ArmorStats = {
	hp = { icon = "❤️", text = "体力 +%d" },
	defense = { icon = "🛡️", text = "ダメージ -%d%%" },
	attack = { icon = "⚔️", text = "こうげき +%d%%" },
	walk = { icon = "👟", text = "はやさ +%d" },
	jump = { icon = "🦘", text = "ジャンプ +%d" },
	coin = { icon = "🪙", text = "コイン +%d%%" },
	regen = { icon = "💚", text = "回復 毎秒+%d" },
	train = { icon = "⚡", text = "トレーニング +%d%%" },
}
Config.ArmorStatOrder = { "hp", "defense", "attack", "walk", "jump", "coin", "regen", "train" }

-- 防具の種類（場所ごとに 2つ）。values：レア度 1〜5 のときの能力の数字
Config.ArmorKinds = {
	{ kind = "helm", slot = "head", noun = "かぶと", stat = "defense", values = { 6, 10, 14, 18, 22 }, price = 1 },
	{
		kind = "hat",
		slot = "head",
		noun = "とんがりぼうし",
		stat = "train",
		values = { 20, 40, 60, 80, 100 },
		price = 1.1,
	},
	{
		kind = "plate",
		slot = "body",
		noun = "よろい",
		stat = "hp",
		values = { 50, 120, 260, 500, 900 },
		price = 1.4,
	},
	{ kind = "robe", slot = "body", noun = "ローブ", stat = "regen", values = { 2, 4, 7, 11, 16 }, price = 1.3 },
	{
		kind = "gauntlet",
		slot = "arms",
		noun = "こて",
		stat = "attack",
		values = { 10, 20, 35, 55, 80 },
		price = 1.2,
	},
	{
		kind = "bracelet",
		slot = "arms",
		noun = "うでわ",
		stat = "coin",
		values = { 10, 20, 30, 40, 50 },
		price = 1.1,
	},
	{ kind = "boots", slot = "legs", noun = "ブーツ", stat = "walk", values = { 2, 4, 6, 8, 10 }, price = 1 },
	{
		kind = "greaves",
		slot = "legs",
		noun = "すねあて",
		stat = "defense",
		values = { 6, 10, 14, 18, 22 },
		price = 1,
	},
	{ kind = "cape", slot = "back", noun = "マント", stat = "hp", values = { 30, 80, 170, 330, 600 }, price = 1.2 },
	{ kind = "wings", slot = "back", noun = "つばさ", stat = "jump", values = { 6, 12, 18, 24, 30 }, price = 1.5 },
}

-- レア度ごとの材料（名前の前につく）、ねだん、どの防具にも つく体力
Config.ArmorTiers = {
	{ prefix = "かわの", price = 200, hp = 10 },
	{ prefix = "てつの", price = 2000, hp = 25 },
	{ prefix = "ミスリルの", price = 15000, hp = 50 },
	{ prefix = "黄金竜の", price = 100000, hp = 100 },
	{ prefix = "星くずの", price = 500000, hp = 200 },
}

-- 受けるダメージを へらせる上限（%）
Config.ArmorDefenseCap = 60

-- 防具の一覧（A01〜A50）。ためし用の無料中（FreeWeaponsForTest）は、防具も無料
Config.Armors = {}
do
	local n = 0
	for rarity, tier in Config.ArmorTiers do
		for _, k in Config.ArmorKinds do
			n += 1
			local bonus = { hp = tier.hp }
			bonus[k.stat] = (bonus[k.stat] or 0) + k.values[rarity]
			table.insert(Config.Armors, {
				id = string.format("A%02d", n),
				name = tier.prefix .. k.noun,
				kind = k.kind,
				slot = k.slot,
				rarity = rarity,
				bonus = bonus,
				price = if Config.FreeWeaponsForTest then 0 else math.floor(tier.price * k.price / 10 + 0.5) * 10,
			})
		end
	end
end

local armorById = {}
for _, a in Config.Armors do
	armorById[a.id] = a
end
function Config.findArmor(id: any)
	return if typeof(id) == "string" then armorById[id] else nil
end

-- 能力を文字にする（例：「❤️体力 +60 ／ 🛡️ダメージ -6%」）
function Config.armorBonusText(bonus: { [string]: number }): string
	local parts = {}
	for _, key in Config.ArmorStatOrder do
		local value = bonus[key] or 0
		if value > 0 then
			local info = Config.ArmorStats[key]
			table.insert(parts, info.icon .. string.format(info.text, value))
		end
	end
	return table.concat(parts, " ／ ")
end

-- 身につけている防具（場所 → 防具の id）の能力を、全部たす
function Config.armorBonus(equipped: any): { [string]: number }
	local total = {}
	for _, key in Config.ArmorStatOrder do
		total[key] = 0
	end
	if typeof(equipped) == "table" then
		for _, slot in Config.ArmorSlots do
			local armor = Config.findArmor(equipped[slot.id])
			if armor and armor.slot == slot.id then
				for key, value in armor.bonus do
					total[key] += value
				end
			end
		end
	end
	total.defense = math.min(total.defense, Config.ArmorDefenseCap)
	return total
end

--------------------------------------------------------------------------------
-- 何度でも遊べるしくみ：転生・れんぞく配達・タイムアタック・あたりゾーン・天気・宝箱
--------------------------------------------------------------------------------

-- 数字 n から、0〜1 の ばらばらな数を作る（サーバーでも自分の画面でも 同じ答えになる）
local function mul32(a: number, b: number): number
	local hi, lo = bit32.rshift(a, 16), bit32.band(a, 0xFFFF)
	return bit32.band(bit32.lshift(bit32.band(hi * b, 0xFFFF), 16) + lo * b, 0xFFFFFFFF)
end
local function hash01(n: number): number
	local x = bit32.band(math.floor(n), 0xFFFFFFFF)
	x = mul32(bit32.bxor(x, bit32.rshift(x, 16)), 0x45D9)
	x = mul32(bit32.bxor(x, bit32.rshift(x, 13)), 0x9E37)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	return x / 4294967296
end

-- 転生：スピードが need にとどいたら、スピードとコインを 0 にもどして、ずっと続く力をもらう
-- （ドラゴン・武器・防具・ショップの商品・図鑑・実績は のこる）
-- speed = 1回目に必要なスピード、growth = 1回ごとに必要なスピードが何倍になるか
-- train / coin = 1回ごとに ふえる倍率（トレーニング +50%、たまごのコイン +25%）
Config.Rebirth = { speed = 3000, growth = 1.4, train = 0.5, coin = 0.25 }
function Config.rebirthNeed(count: number): number
	return math.floor(Config.Rebirth.speed * Config.Rebirth.growth ^ count / 100 + 0.5) * 100
end
function Config.rebirthTrainMult(count: number): number
	return 1 + Config.Rebirth.train * count
end
function Config.rebirthCoinMult(count: number): number
	return 1 + Config.Rebirth.coin * count
end
-- 転生の回数でつく よび名
Config.RebirthTitles = {
	{ count = 0, name = "かけだし" },
	{ count = 1, name = "ルーキー" },
	{ count = 3, name = "ベテラン" },
	{ count = 5, name = "たつじん" },
	{ count = 10, name = "マスター" },
	{ count = 20, name = "でんせつ" },
	{ count = 50, name = "神話" },
}
function Config.rebirthTitle(count: number): string
	local name = Config.RebirthTitles[1].name
	for _, t in Config.RebirthTitles do
		if count >= t.count then
			name = t.name
		end
	end
	return name
end

-- れんぞく配達：やられずに続けて届けるほど、コインがふえる（1回ごとに +10%、+100% まで）
Config.Combo = { per = 0.1, max = 10 }
function Config.comboMult(streak: number): number
	return 1 + Config.Combo.per * math.clamp(streak - 1, 0, Config.Combo.max)
end

-- タイムアタック：たまごを拾ってから届けるまでの時間。自分の記録をぬりかえると、コインが bonus 倍 おまけ
Config.TimeAttack = { bonus = 1 }

-- あたりゾーン：every 秒ごとに入れかわる（全部のサーバーで同じ）。そのゾーンのたまごは コイン mult 倍
Config.Lucky = { every = 600, mult = 3 }
function Config.luckyZone(now: number): (number, number)
	local window = math.floor(now / Config.Lucky.every)
	local count = 0
	for _, zone in Config.Zones do
		if not zone.secret then
			count += 1
		end
	end
	return 1 + math.floor(hash01(window * 7 + 3) * count), (window + 1) * Config.Lucky.every
end

-- 天気：every 秒ごとに変わる（全部のサーバーで同じ）。weight = 出やすさ
-- train = トレーニング倍率、walk = 走る速さに足す、coin = たまごのコイン倍率、bounty = 敵のコイン倍率、xp = 経験値の倍率
Config.Weather = { every = 300 }
Config.Weathers = {
	{ id = "sunny", name = "はれ", icon = "☀️", weight = 30, desc = "いつもどおり" },
	{ id = "rain", name = "あめ", icon = "🌧️", weight = 20, train = 1.5, desc = "トレーニング 1.5倍" },
	{ id = "wind", name = "おいかぜ", icon = "🍃", weight = 16, walk = 8, desc = "走る速さ +8" },
	{ id = "fog", name = "きり", icon = "🌫️", weight = 14, bounty = 2, desc = "敵のコイン 2倍" },
	{
		id = "storm",
		name = "かみなり",
		icon = "⛈️",
		weight = 12,
		xp = 2,
		desc = "ドラゴンの経験値 2倍",
	},
	{ id = "rainbow", name = "にじ", icon = "🌈", weight = 8, coin = 1.5, desc = "たまごのコイン 1.5倍" },
}
function Config.weatherAt(now: number): (any, number)
	local window = math.floor(now / Config.Weather.every)
	local total = 0
	for _, w in Config.Weathers do
		total += w.weight
	end
	local pick = hash01(window * 13 + 5) * total
	local found = Config.Weathers[1]
	for _, w in Config.Weathers do
		pick -= w.weight
		if pick <= 0 then
			found = w
			break
		end
	end
	return found, (window + 1) * Config.Weather.every
end

-- 1日の長さ（秒）。全部のサーバーで同じ時刻になる。朝 → 昼 → 夕方 → 夜
Config.DayLength = 1200
function Config.clockAt(now: number): number
	-- 始まりを朝の 8時にする
	return (8 + (now % Config.DayLength) / Config.DayLength * 24) % 24
end

-- 宝箱：every 秒ごとに 道のどこかに出る（max こ まで、life 秒で消える）
-- コインは その場所のゾーンのごほうびの coinMin〜coinMax 倍。ときどき ふしぎなたまご、まれに 大当たり
Config.Chest = {
	every = 45,
	max = 4,
	life = 240,
	coinMin = 2,
	coinMax = 6,
	eggChance = 0.12,
	jackpotChance = 0.04,
	jackpotMult = 25,
}

return Config
