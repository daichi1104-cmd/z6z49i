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

-- ドラゴンの仲間（1体だけ連れて行ける。後ろをついてきて力をくれる）
-- shape: 見た目の種類 / trainMult: トレーニング倍率に掛ける / coinMult: たまごのコイン倍率
-- damageMult: 受けるダメージの倍率 / walkBonus: 走る速さに足す
Config.Dragons = {
	{
		id = "Chibi",
		name = "ちびドラゴン",
		price = 0,
		desc = "はじめの仲間。トレーニング 1.2倍",
		shape = "small",
		color = Color3.fromRGB(110, 200, 255),
		trainMult = 1.2,
	},
	{
		id = "Thunder",
		name = "いかずちドラゴン",
		price = 250,
		desc = "走る速さ +8",
		shape = "winged",
		color = Color3.fromRGB(255, 220, 60),
		walkBonus = 8,
	},
	{
		id = "Gaia",
		name = "ガイアマグマ",
		price = 800,
		desc = "大地とマグマのドラゴン。ダメージ 30% ダウン",
		shape = "magma",
		color = Color3.fromRGB(200, 50, 30),
		damageMult = 0.7,
	},
	{
		id = "Triple",
		name = "トリプルヘッド",
		price = 2000,
		desc = "三つ首の金のドラゴン。たまごのコイン 2倍",
		shape = "triple",
		color = Color3.fromRGB(240, 190, 50),
		coinMult = 2,
	},
	{
		id = "Giga",
		name = "ギガザウルス",
		price = 5000,
		desc = "巨大な怪獣ドラゴン。トレーニング 2倍＋走る速さ +15",
		shape = "giant",
		color = Color3.fromRGB(70, 110, 80),
		trainMult = 2,
		walkBonus = 15,
	},
}

-- 敵が反応する距離と、たまごから離れて追いかけてくる限界
Config.EnemyAggroRange = 55
Config.EnemyLeashRange = 120

return Config
