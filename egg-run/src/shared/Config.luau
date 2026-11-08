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
}

-- ドラゴンの仲間（全員無料。1体えらんで連れて行ける。後ろをついてきて、力をくれる）
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

return Config
