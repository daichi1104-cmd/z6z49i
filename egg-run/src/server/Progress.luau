-- 毎日のごほうびと実績：ログインボーナス、今日のミッション、無料のたまご、実績（図鑑ボーナスをふくむ）
-- ここではデータ（Data）の計算だけをする。お知らせや保存は Main が行う

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Progress = {}

-- 数えるもの（d.stats）。zone は "z1" 〜 "z7"（そのゾーンのたまごを届けた数）
local STAT_KEYS = {
	"delivered",
	"hatched",
	"kills",
	"bossKills",
	"trained",
	"merges",
	"breeds",
	"graduated",
	"loginDays",
	"towerBest",
	"towerFloors",
	"weaponKills",
}

-- 読みこんだデータに、新しい項目がなければ足す
function Progress.ensure(d: any)
	d.stats = if typeof(d.stats) == "table" then d.stats else {}
	for _, key in STAT_KEYS do
		d.stats[key] = tonumber(d.stats[key]) or 0
	end
	d.stats.zone = if typeof(d.stats.zone) == "table" then d.stats.zone else {}
	for i = 1, #Config.Zones do
		local key = "z" .. i
		d.stats.zone[key] = tonumber(d.stats.zone[key]) or 0
	end
	d.achievements = if typeof(d.achievements) == "table" then d.achievements else {}
	d.login = if typeof(d.login) == "table" then d.login else {}
	d.login.day = tonumber(d.login.day) or 0
	d.login.streak = tonumber(d.login.streak) or 0
	d.daily = if typeof(d.daily) == "table" then d.daily else {}
	d.freeEggAt = tonumber(d.freeEggAt) or 0
end

function Progress.bump(d: any, key: string, amount: number?)
	d.stats[key] = (d.stats[key] or 0) + (amount or 1)
end

function Progress.bumpZone(d: any, zone: number)
	local key = "z" .. zone
	if d.stats.zone[key] then
		d.stats.zone[key] += 1
	end
end

-- 行ったことのある一番遠いゾーン（たまごを届けたことのあるゾーン。まだなら 1）
function Progress.bestZone(d: any): number
	local best = 1
	for i = 1, #Config.Zones do
		if (d.stats.zone["z" .. i] or 0) > 0 then
			best = i
		end
	end
	return best
end

-- ログインボーナスやミッションのコインの「基本」（遠くまで行けるようになるほど増える）
function Progress.rewardBase(d: any): number
	return math.max(50, Config.Zones[Progress.bestZone(d)].reward * 2)
end

local function seenCount(d: any, rarity: number?): number
	local n = 0
	for id in d.seen do
		local dragon = Config.findDragon(id)
		if dragon and dragon.rarity and (not rarity or dragon.rarity == rarity) then
			n += 1
		end
	end
	return n
end

local function maxLevel(d: any): number
	local best = 1
	for _, xp in d.xp do
		best = math.max(best, Config.levelFor(xp))
	end
	return best
end

function Progress.statValue(d: any, key: string): number
	if key == "book" then
		return seenCount(d)
	elseif key == "r4" then
		return seenCount(d, 4)
	elseif key == "r5" then
		return seenCount(d, 5)
	elseif key == "level" then
		return maxLevel(d)
	elseif key == "weapons" then
		local n = 0
		for _ in d.weapons or {} do
			n += 1
		end
		return n
	elseif key == "z6" or key == "z7" then
		return d.stats.zone[key] or 0
	end
	return d.stats[key] or 0
end

-- 達成した実績にしるしをつけて、コインをわたす。新しく達成したものの一覧を返す
function Progress.checkAchievements(d: any): { any }
	local done = {}
	for _, a in Config.Achievements do
		if not d.achievements[a.id] and Progress.statValue(d, a.stat) >= a.goal then
			d.achievements[a.id] = true
			d.coins += a.reward
			table.insert(done, a)
		end
	end
	return done
end

--------------------------------------------------------------------------------
-- ログインボーナス
--------------------------------------------------------------------------------

-- canClaim = 今日まだもらっていない、day = 何日目のごほうびか（1〜7）、streak = 連続ログイン日数
function Progress.loginState(d: any, now: number?)
	local today = Config.today(now)
	if d.login.day == today then
		return { canClaim = false, day = (d.login.streak - 1) % 7 + 1, streak = d.login.streak }
	end
	-- 昨日もらっていたら連続、そうでなければ 1日目から
	local streak = if d.login.day == today - 1 then d.login.streak + 1 else 1
	return { canClaim = true, day = (streak - 1) % 7 + 1, streak = streak }
end

-- もらう：成功したら、もらったもの { coins, egg } を返す
function Progress.claimLogin(d: any, now: number?)
	local state = Progress.loginState(d, now)
	if not state.canClaim then
		return nil
	end
	local reward = Config.LoginRewards[state.day]
	local coins = reward.coins * Progress.rewardBase(d)
	d.login.day = Config.today(now)
	d.login.streak = state.streak
	d.coins += coins
	Progress.bump(d, "loginDays")
	return { coins = coins, egg = reward.egg == true, day = state.day, streak = state.streak }
end

--------------------------------------------------------------------------------
-- 今日のミッション
--------------------------------------------------------------------------------

local function counterFor(d: any, m: any): number
	if m.kind == "zone" then
		return d.stats.zone["z" .. m.zone] or 0
	end
	return d.stats[m.kind] or 0
end

local function newMission(d: any, info: any): any
	local m = { kind = info.kind, claimed = false }
	if info.kind == "zone" then
		m.zone = Progress.bestZone(d)
		m.target = 1
	elseif info.kind == "trained" then
		m.target = math.max(100, math.floor(d.speed * 0.25 / 50) * 50)
	else
		m.target = info.targets[math.random(1, #info.targets)]
	end
	m.base = counterFor(d, m)
	return m
end

-- 日付が変わっていたら、新しいミッションを 3つ えらぶ
function Progress.refreshDaily(d: any, now: number?)
	local today = Config.today(now)
	if d.daily.day == today and typeof(d.daily.missions) == "table" then
		return
	end
	local pool = table.clone(Config.MissionKinds)
	local missions = {}
	for _ = 1, math.min(Config.MissionCount, #pool) do
		local info = table.remove(pool, math.random(1, #pool))
		table.insert(missions, newMission(d, info))
	end
	d.daily = { day = today, missions = missions, bonus = false }
end

function Progress.missionProgress(d: any, m: any): number
	return math.min(m.target, math.max(0, counterFor(d, m) - m.base))
end

function Progress.missionText(m: any): string
	local info
	for _, k in Config.MissionKinds do
		if k.kind == m.kind then
			info = k
		end
	end
	if not info then
		return "？"
	end
	if m.kind == "zone" then
		return string.format(info.text, Config.Zones[m.zone].name)
	end
	return string.format(info.text, m.target)
end

function Progress.missionReward(d: any): number
	return Progress.rewardBase(d) * 2
end

-- i 番目のミッションのごほうびをもらう
function Progress.claimMission(d: any, i: number): (boolean, string)
	local m = d.daily.missions and d.daily.missions[i]
	if not m then
		return false, "そのミッションはありません"
	end
	if m.claimed then
		return false, "もう もらいました"
	end
	if Progress.missionProgress(d, m) < m.target then
		return false, "まだ クリアしていません"
	end
	m.claimed = true
	local coins = Progress.missionReward(d)
	d.coins += coins
	return true, string.format("📋 ミッションクリア！ +%d コイン", coins)
end

-- 3つ全部クリアしたら、ふしぎなたまごが 1こ もらえる
function Progress.canClaimBonus(d: any): boolean
	if d.daily.bonus or typeof(d.daily.missions) ~= "table" then
		return false
	end
	for _, m in d.daily.missions do
		if not m.claimed then
			return false
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- 無料のたまご・ふしぎなたまご
--------------------------------------------------------------------------------

function Progress.freeEggReady(d: any, now: number?): boolean
	return (now or os.time()) >= d.freeEggAt
end

-- ふしぎなたまご（無料・ログイン・ミッション）は、行ったことのある一番遠いゾーンのたまごと同じ出やすさ
-- （星空・遺跡のたまごは特別なので、雲の上までにする）
function Progress.mysteryZone(d: any): number
	return math.min(Progress.bestZone(d), 5)
end

--------------------------------------------------------------------------------
-- クライアントに見せる中身
--------------------------------------------------------------------------------

function Progress.clientView(d: any, now: number?)
	local missions = {}
	for _, m in d.daily.missions or {} do
		table.insert(missions, {
			text = Progress.missionText(m),
			progress = Progress.missionProgress(d, m),
			target = m.target,
			claimed = m.claimed,
		})
	end
	local achievementStats = {}
	for _, a in Config.Achievements do
		achievementStats[a.stat] = Progress.statValue(d, a.stat)
	end
	return {
		login = Progress.loginState(d, now),
		loginBase = Progress.rewardBase(d),
		missions = missions,
		missionReward = Progress.missionReward(d),
		bonus = d.daily.bonus == true,
		freeEggAt = d.freeEggAt,
		achievements = d.achievements,
		stats = achievementStats,
		towerBest = d.stats.towerBest,
		bossKills = d.stats.bossKills,
	}
end

return Progress
