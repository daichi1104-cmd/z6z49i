-- ゲームの進行管理：保存、トレーニング、たまごの回収、ショップ、ドラゴンの仲間
-- 毎日のごほうび（Progress）、塔のぼり（Tower）、黄金のたまごイベント、わざ、進化・交配・卒業

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Sounds"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))
local Enemies = require(script.Parent:WaitForChild("Enemies"))
local Dragons = require(script.Parent:WaitForChild("Dragons"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local Tower = require(script.Parent:WaitForChild("Tower"))
local WorldBoss = require(script.Parent:WaitForChild("WorldBoss"))
local Ranking = require(script.Parent:WaitForChild("Ranking"))
local Weapons = require(script.Parent:WaitForChild("Weapons"))
local Armor = require(script.Parent:WaitForChild("Armor"))

local world = WorldBuilder.build()

-- クライアントとのやりとり
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage
local function remote(className: string, name: string): any
	local r = Instance.new(className)
	r.Name = name
	r.Parent = remotes
	return r
end
local notify = remote("RemoteEvent", "Notify") :: RemoteEvent
local trainGain = remote("RemoteEvent", "TrainGain") :: RemoteEvent
local openShop = remote("RemoteEvent", "OpenShop") :: RemoteEvent
local goHome = remote("RemoteEvent", "GoHome") :: RemoteEvent
local buyItem = remote("RemoteFunction", "BuyItem") :: RemoteFunction
local knockback = remote("RemoteEvent", "Knockback") :: RemoteEvent
local hatchEgg = remote("RemoteFunction", "HatchEgg") :: RemoteFunction
local dragonAction = remote("RemoteFunction", "DragonAction") :: RemoteFunction
local dailyAction = remote("RemoteFunction", "DailyAction") :: RemoteFunction
local useSkill = remote("RemoteFunction", "UseSkill") :: RemoteFunction
local weaponAction = remote("RemoteFunction", "WeaponAction") :: RemoteFunction
local armorAction = remote("RemoteFunction", "ArmorAction") :: RemoteFunction
local screenFx = remote("RemoteEvent", "ScreenFx") :: RemoteEvent
local rebirthAction = remote("RemoteFunction", "Rebirth") :: RemoteFunction
Weapons.setScreenFx(screenFx)

-- DataStore は Studio で API アクセスが無効だと失敗するので pcall で守る
local store
pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName)
end)

type Egg = { zone: any, readyAt: number, child: string? }
type Data = {
	speed: number,
	coins: number,
	eggs: number,
	items: { [string]: boolean },
	collection: { [string]: number }, -- たまごから生まれたドラゴン（id → 何体持っているか）
	seen: { [string]: boolean }, -- 一度でも仲間にしたドラゴン（図鑑に出る）
	incubator: { Egg }, -- 檻の中のたまご（readyAt = かえる時刻、child = 交配で決まった中身）
	team: { string }, -- ついて来るドラゴン（最大 3匹）
	xp: { [string]: number }, -- ドラゴンごとの経験値
	secretOpen: boolean, -- ひみつのゾーンの門が開いたか
	weapons: { [string]: boolean }, -- 持っている武器
	weapon: string, -- 手に持つ武器
	armors: { [string]: boolean }, -- 持っている防具
	armor: { [string]: string }, -- 身につけている防具（場所 → 防具の id）
	stats: any,
	achievements: any,
	login: any,
	daily: any,
	freeEggAt: number,
	rebirths: number, -- 転生した回数
	best: { [string]: number }, -- タイムアタックの記録（ゾーン → 秒）
}

local data: { [Player]: Data } = {}
local carrying: { [Player]: any } = {} -- 運んでいるたまご（ゾーン番号、または "gold"）
local pendingGain: { [Player]: number } = {}
local lastWarn: { [Player]: number } = {}
-- わざの効果（いつまで続くか）
type Buffs = { trainUntil: number, train: number, speedUntil: number, speed: number, shieldUntil: number }
local buffs: { [Player]: Buffs } = {}
local skillReadyAt: { [Player]: number } = {}
local streak: { [Player]: number } = {} -- やられずに続けて届けた回数
local carryStart: { [Player]: number } = {} -- たまごを拾った時刻（タイムアタック）

-- いまの天気（全部のサーバーで同じ）
local function weather()
	return (Config.weatherAt(os.time()))
end

local function defaultData(): Data
	local d = {
		speed = 0,
		coins = 0,
		eggs = 0,
		items = {},
		collection = {},
		seen = {},
		incubator = {},
		team = { "Chibi" },
		xp = {},
		secretOpen = false,
		weapons = { [Config.StarterWeapon] = true },
		weapon = Config.StarterWeapon,
		armors = {},
		armor = {},
		rebirths = 0,
		best = {},
	}
	Progress.ensure(d)
	return d :: any
end

local function isStarter(id: string): boolean
	for _, starter in Config.Dragons do
		if starter.id == id then
			return true
		end
	end
	return false
end

-- はじめの仲間はだれでも、生まれたドラゴンは持っていれば連れて行ける
local function canUseDragon(d: Data, id: string): boolean
	return isStarter(id) or (d.collection[id] or 0) > 0
end

local function loadData(player: Player): Data
	local d = defaultData()
	if not store then
		return d
	end
	local ok, value = pcall(function()
		return store:GetAsync("player_" .. player.UserId)
	end)
	if not ok or typeof(value) ~= "table" then
		return d
	end
	d.speed = tonumber(value.speed) or 0
	d.coins = tonumber(value.coins) or 0
	d.eggs = tonumber(value.eggs) or 0
	if typeof(value.items) == "table" then
		for id, owned in value.items do
			d.items[tostring(id)] = owned == true
		end
	end
	if typeof(value.collection) == "table" then
		for id, count in value.collection do
			if Config.findDragon(tostring(id)) and tonumber(count) then
				d.collection[tostring(id)] = math.max(0, math.floor(tonumber(count) :: number))
			end
		end
	end
	if typeof(value.seen) == "table" then
		for id, yes in value.seen do
			if yes == true and Config.findDragon(tostring(id)) then
				d.seen[tostring(id)] = true
			end
		end
	end
	-- 前の版のデータ：持っているドラゴンは、図鑑に出す
	for id, count in d.collection do
		if count > 0 then
			d.seen[id] = true
		end
	end
	if typeof(value.incubator) == "table" then
		for _, egg in value.incubator do
			if typeof(egg) ~= "table" then
				continue
			end
			local zone = tonumber(egg.zone) or egg.zone
			local readyAt = tonumber(egg.readyAt)
			local child = if typeof(egg.child) == "string" and Config.findDragon(egg.child) then egg.child else nil
			if Config.eggInfo(zone) and readyAt and #d.incubator < 5 then
				table.insert(d.incubator, { zone = zone, readyAt = readyAt, child = child })
			end
		end
	end
	if typeof(value.xp) == "table" then
		for id, xp in value.xp do
			if Config.findDragon(tostring(id)) and tonumber(xp) then
				d.xp[tostring(id)] = tonumber(xp) :: number
			end
		end
	end
	-- 連れているドラゴン（前の版は 1匹だけ：dragon）
	if typeof(value.team) == "table" then
		d.team = {}
		for _, id in value.team do
			if typeof(id) == "string" and canUseDragon(d, id) and not table.find(d.team, id) and #d.team < 3 then
				table.insert(d.team, id)
			end
		end
	elseif typeof(value.dragon) == "string" and canUseDragon(d, value.dragon) then
		d.team = { value.dragon }
	elseif value.dragon == false then
		d.team = {}
	end
	d.secretOpen = value.secretOpen == true
	if typeof(value.weapons) == "table" then
		for id, has in value.weapons do
			if has == true and Config.findWeapon(tostring(id)) then
				d.weapons[tostring(id)] = true
			end
		end
	end
	if Config.findWeapon(value.weapon) and d.weapons[value.weapon] then
		d.weapon = value.weapon
	end
	if typeof(value.armors) == "table" then
		for id, has in value.armors do
			if has == true and Config.findArmor(tostring(id)) then
				d.armors[tostring(id)] = true
			end
		end
	end
	if typeof(value.armor) == "table" then
		for slot, id in value.armor do
			local armor = Config.findArmor(id)
			if armor and armor.slot == slot and d.armors[armor.id] then
				d.armor[armor.slot] = armor.id
			end
		end
	end
	d.rebirths = math.max(0, math.floor(tonumber(value.rebirths) or 0))
	if typeof(value.best) == "table" then
		for zone, seconds in value.best do
			if tonumber(seconds) then
				d.best[tostring(zone)] = tonumber(seconds) :: number
			end
		end
	end
	d.stats = value.stats
	d.achievements = value.achievements
	d.login = value.login
	d.daily = value.daily
	d.freeEggAt = value.freeEggAt
	Progress.ensure(d)
	return d
end

local function saveData(player: Player)
	local d = data[player]
	if not store or not d then
		return
	end
	pcall(function()
		store:SetAsync("player_" .. player.UserId, {
			speed = d.speed,
			coins = d.coins,
			eggs = d.eggs,
			items = d.items,
			collection = d.collection,
			seen = d.seen,
			incubator = d.incubator,
			team = d.team,
			xp = d.xp,
			secretOpen = d.secretOpen,
			weapons = d.weapons,
			weapon = d.weapon,
			armors = d.armors,
			armor = d.armor,
			stats = d.stats,
			achievements = d.achievements,
			login = d.login,
			daily = d.daily,
			freeEggAt = d.freeEggAt,
			rebirths = d.rebirths,
			best = d.best,
		})
	end)
end

--------------------------------------------------------------------------------
-- 強さの計算（持ち物・連れているドラゴン・わざの効果）
--------------------------------------------------------------------------------

local function teamDragons(d: Data): { any }
	local list = {}
	for _, id in d.team do
		local dragon = Dragons.find(id)
		if dragon then
			table.insert(list, dragon)
		end
	end
	return list
end

local function levelOf(d: Data, id: string): number
	return Config.levelFor(d.xp[id] or 0)
end

local function itemBest(d: Data, key: string, start: number, pick: (number, number) -> number): number
	local value = start
	for _, item in Config.Items do
		if d.items[item.id] and item[key] then
			value = pick(value, item[key])
		end
	end
	return value
end

local function buffOf(player: Player): Buffs
	local b = buffs[player]
	if not b then
		b = { trainUntil = 0, train = 1, speedUntil = 0, speed = 0, shieldUntil = 0 }
		buffs[player] = b
	end
	return b
end

local function trainMult(player: Player, d: Data): number
	local m = itemBest(d, "trainMult", 1, math.max)
	for _, dragon in teamDragons(d) do
		if dragon.trainMult then
			m *= dragon.trainMult
		end
	end
	local b = buffOf(player)
	if os.clock() < b.trainUntil then
		m *= b.train
	end
	return m
		* (1 + Config.armorBonus(d.armor).train / 100)
		* Config.rebirthTrainMult(d.rebirths)
		* (weather().train or 1)
		* Config.friendBoost(#Players:GetPlayers())
end

local function damageMult(player: Player, d: Data): number
	if os.clock() < buffOf(player).shieldUntil then
		return 0
	end
	local m = itemBest(d, "damageMult", 1, math.min)
	for _, dragon in teamDragons(d) do
		if dragon.damageMult then
			m *= dragon.damageMult
		end
	end
	return m * (1 - Config.armorBonus(d.armor).defense / 100)
end

local function coinMult(d: Data): number
	local m = 1
	for _, dragon in teamDragons(d) do
		if dragon.coinMult then
			m *= dragon.coinMult
		end
	end
	return m
		* (1 + Config.armorBonus(d.armor).coin / 100)
		* Config.rebirthCoinMult(d.rebirths)
		* Config.friendBoost(#Players:GetPlayers())
end

local function regenOf(d: Data): number
	local r = 0
	for _, dragon in teamDragons(d) do
		r += dragon.regen or 0
	end
	return r + Config.armorBonus(d.armor).regen
end

local function maxHealth(d: Data): number
	return itemBest(d, "maxHealth", 100, math.max) + Config.armorBonus(d.armor).hp
end

local function incubatorSlots(d: Data): number
	return itemBest(d, "incubatorSlots", Config.IncubatorSlots, math.max)
end

local function teamSlots(d: Data): number
	return itemBest(d, "teamSlots", Config.TeamSlots, math.max)
end

local function jumpPower(d: Data): number
	return itemBest(d, "jumpPower", 50, math.max) + Config.armorBonus(d.armor).jump
end

local function walkSpeed(player: Player, d: Data): number
	local bonus = 0
	for _, dragon in teamDragons(d) do
		bonus += dragon.walkBonus or 0
	end
	local b = buffOf(player)
	if os.clock() < b.speedUntil then
		bonus += b.speed
	end
	return Config.walkSpeedFor(d.speed) + bonus + Config.armorBonus(d.armor).walk + (weather().walk or 0)
end

local function syncStats(player: Player)
	local d = data[player]
	local stats = player:FindFirstChild("leaderstats")
	if not d or not stats then
		return
	end
	(stats:FindFirstChild("スピード") :: IntValue).Value = math.floor(d.speed);
	(stats:FindFirstChild("コイン") :: IntValue).Value = math.floor(d.coins);
	(stats:FindFirstChild("たまご") :: IntValue).Value = d.eggs;
	(stats:FindFirstChild("転生") :: IntValue).Value = d.rebirths
	player:SetAttribute("Rebirths", d.rebirths)
	player:SetAttribute("Streak", streak[player] or 0)
	player:SetAttribute("Best", HttpService:JSONEncode(d.best))
	player:SetAttribute("WalkSpeed", walkSpeed(player, d))
	player:SetAttribute("TrainMult", trainMult(player, d))
	player:SetAttribute("Dragon", d.team[1] or "")
	-- 檻・図鑑・仲間・毎日のごほうびの中身は、文字にしてクライアントへ渡す
	player:SetAttribute("Incubator", HttpService:JSONEncode(d.incubator))
	player:SetAttribute("Collection", HttpService:JSONEncode(d.collection))
	player:SetAttribute("Seen", HttpService:JSONEncode(d.seen))
	player:SetAttribute("Team", HttpService:JSONEncode(d.team))
	player:SetAttribute("Xp", HttpService:JSONEncode(d.xp))
	player:SetAttribute("Profile", HttpService:JSONEncode(Progress.clientView(d)))
	player:SetAttribute("IncubatorSlots", incubatorSlots(d))
	player:SetAttribute("TeamSlots", teamSlots(d))
	player:SetAttribute("SecretOpen", d.secretOpen)
	player:SetAttribute("SkillReadyAt", skillReadyAt[player] or 0)
	player:SetAttribute("Weapons", HttpService:JSONEncode(d.weapons))
	player:SetAttribute("Weapon", d.weapon)
	player:SetAttribute("Armors", HttpService:JSONEncode(d.armors))
	player:SetAttribute("Armor", HttpService:JSONEncode(d.armor))
end

local function applyStats(player: Player, fullHeal: boolean?)
	local d = data[player]
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not d or not humanoid then
		return
	end
	humanoid.WalkSpeed = walkSpeed(player, d)
	local mh = maxHealth(d)
	if humanoid.MaxHealth ~= mh then
		humanoid.MaxHealth = mh
	end
	if fullHeal then
		humanoid.Health = mh
	end
	humanoid.UseJumpPower = true
	humanoid.JumpPower = jumpPower(d)
end

local function save(player: Player)
	task.spawn(saveData, player)
end

--------------------------------------------------------------------------------
-- 実績・ひみつの門・経験値
--------------------------------------------------------------------------------

-- 数字が変わったあとに呼ぶ：実績の達成と、ひみつの門をしらべる
local function checkProgress(player: Player)
	local d = data[player]
	if not d then
		return
	end
	for _, a in Progress.checkAchievements(d) do
		notify:FireClient(player, string.format("🏆 実績「%s」達成！ +%d コイン", a.desc, a.reward), true)
	end
	if
		not d.secretOpen
		and d.stats.bossKills >= Config.SecretZone.bossKills
		and Progress.statValue(d, "book") >= Config.SecretZone.book
	then
		d.secretOpen = true
		notify:FireClient(player, "🔓 ひみつの門が開いた！ 星空の先へ行ってみよう", true)
	end
end

-- 連れているドラゴン全員に経験値
local function addXp(player: Player, amount: number)
	local d = data[player]
	if not d or amount <= 0 then
		return
	end
	amount *= weather().xp or 1
	local leveled = false
	for _, id in d.team do
		local before = levelOf(d, id)
		d.xp[id] = (d.xp[id] or 0) + amount
		local after = levelOf(d, id)
		if after > before then
			leveled = true
			local dragon = Dragons.find(id)
			local name = if dragon then dragon.name else id
			notify:FireClient(player, string.format("⬆️ %s が レベル %d になった！", name, after), true)
			if before < Config.SkillLevel and after >= Config.SkillLevel and dragon then
				local skill = Config.Skills[dragon.shape]
				if skill then
					notify:FireClient(
						player,
						string.format(
							"✨ わざ「%s」を覚えた！ 右の ✨わざ ボタンで使える",
							skill.name
						),
						true
					)
				end
			end
		end
	end
	if leveled then
		Dragons.refreshNames(player)
		checkProgress(player)
	end
end

Dragons.setLevelSource(function(player: Player, id: string)
	local d = data[player]
	return if d then levelOf(d, id) else 1
end)

local function equipTeam(player: Player)
	local d = data[player]
	if d then
		Dragons.equip(player, d.team)
	end
end

-- 神話の武器のゲームパスを持っているか しらべる（下の「武器」のところで中身を書く）
local checkPasses: (Player) -> ()

-- 手に持つ武器をわたす（前の武器は消す）。持たせたら、すぐ手に持つ
local function giveWeapon(player: Player)
	local d = data[player]
	local weapon = d and Config.findWeapon(d.weapon)
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not weapon or not character or not backpack then
		return
	end
	for _, place in { backpack, character } do
		for _, child in place:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("WeaponId") then
				child:Destroy()
			end
		end
	end
	local tool = Weapons.build(weapon)
	tool.Activated:Connect(function()
		-- こて などの防具で、こうげき力が上がる
		local now = data[player]
		Weapons.swing(player, tool, weapon, if now then 1 + Config.armorBonus(now.armor).attack / 100 else 1)
	end)
	tool.Parent = backpack
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:EquipTool(tool)
	end
end

-- 身につけている防具を、キャラの体につける
local function wearArmor(player: Player)
	local d = data[player]
	if not d then
		return
	end
	local pieces = {}
	for _, slot in Config.ArmorSlots do
		local armor = Config.findArmor(d.armor[slot.id])
		if armor then
			table.insert(pieces, armor)
		end
	end
	Armor.apply(player.Character, pieces)
end

--------------------------------------------------------------------------------
-- ドラゴンが生まれる
--------------------------------------------------------------------------------

-- odds（レア度の重み）から、レア度をえらぶ
local function rollRarity(odds: { number }): number
	local total = 0
	for r, w in odds do
		if #Config.HatchByRarity[r] > 0 then
			total += w
		end
	end
	local pick = math.random() * total
	for r, w in odds do
		if #Config.HatchByRarity[r] > 0 then
			pick -= w
			if pick <= 0 then
				return r
			end
		end
	end
	return 1
end

local function rollDragon(odds: { number })
	local list = Config.HatchByRarity[rollRarity(odds)]
	return list[math.random(1, #list)]
end

-- ドラゴンを仲間に加える（新しく図鑑にのったら true）
local function giveDragon(player: Player, id: string): boolean
	local d = data[player]
	local isNew = not d.seen[id]
	d.collection[id] = (d.collection[id] or 0) + 1
	d.seen[id] = true
	return isNew
end

-- ふしぎなたまご（無料・ログイン・ミッション）：その場でかえる
local function mysteryHatch(player: Player): (string, boolean)
	local d = data[player]
	local dragon = rollDragon(Config.HatchOdds[Progress.mysteryZone(d)])
	local isNew = giveDragon(player, dragon.id)
	Progress.bump(d, "hatched")
	return dragon.id, isNew
end

-- 持っている数が 0 になったドラゴンは、連れていけない
local function dropFromTeamIfGone(player: Player, d: Data, id: string)
	if (d.collection[id] or 0) <= 0 and not isStarter(id) then
		local i = table.find(d.team, id)
		if i then
			table.remove(d.team, i)
			equipTeam(player)
		end
	end
end

--------------------------------------------------------------------------------
-- たまごを運ぶ
--------------------------------------------------------------------------------

local function dropEgg(player: Player)
	carrying[player] = nil
	carryStart[player] = nil
	player:SetAttribute("CarryingZone", nil)
	player:SetAttribute("CarryStart", nil)
	local head = player.Character and player.Character:FindFirstChild("Head")
	local egg = head and head:FindFirstChild("CarriedEgg")
	if egg then
		egg:Destroy()
	end
end

local function pickUpEgg(player: Player, zone: any)
	local head = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
	local info = Config.eggInfo(zone)
	if not head or not info then
		return
	end
	carrying[player] = zone
	carryStart[player] = os.clock()
	player:SetAttribute("CarryingZone", zone)
	player:SetAttribute("CarryStart", workspace:GetServerTimeNow())

	local egg = Instance.new("Part")
	egg.Name = "CarriedEgg"
	egg.Shape = Enum.PartType.Ball
	local eggSize = 2.2 * info.scale
	egg.Size = Vector3.one * eggSize
	egg.Color = info.color
	egg.CanCollide = false
	egg.CanQuery = false
	egg.CanTouch = false
	egg.Massless = true
	if zone == "gold" then
		egg.Material = Enum.Material.Foil
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = info.color
		sparkles.Parent = egg
	end
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = egg
	-- 頭の上にのせる（大きいたまごほど高い位置）
	egg.CFrame = head.CFrame * CFrame.new(0, 0.8 + eggSize * 0.65, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = egg
	weld.Parent = egg
	egg.Parent = head

	notify:FireClient(
		player,
		if zone == "gold"
			then "🌟 黄金のたまごをゲット！ ベースの巣まで運ぼう"
			else string.format("🥚 %sのたまごをゲット！ ベースの巣まで運ぼう", info.name)
	)
end

local function deliverEgg(player: Player)
	local d = data[player]
	local zone = carrying[player]
	local info = zone and Config.eggInfo(zone)
	if not d or not info then
		return
	end
	-- れんぞく配達・あたりゾーン・天気（にじ）で コインがふえる
	streak[player] = (streak[player] or 0) + 1
	local combo = Config.comboMult(streak[player])
	local lucky = typeof(zone) == "number" and zone == Config.luckyZone(os.time())
	local mult = coinMult(d) * combo * (if lucky then Config.Lucky.mult else 1) * (weather().coin or 1)
	local reward = math.floor(info.reward * mult)
	-- タイムアタック：自分の記録をぬりかえたら おまけ
	local took = if carryStart[player] then os.clock() - carryStart[player] else nil
	local record: string? = nil
	if took and typeof(zone) == "number" then
		local key = tostring(zone)
		local before = d.best[key]
		if not before then
			d.best[key] = took
			record = string.format("⏱️ %sの はじめての記録：%.1f秒", info.name, took)
		elseif took < before then
			d.best[key] = took
			local bonus = math.floor(info.reward * Config.TimeAttack.bonus * Config.rebirthCoinMult(d.rebirths))
			reward += bonus
			record = string.format("⏱️ 新記録！ %.1f秒 → %.1f秒（+%d コイン）", before, took, bonus)
		end
	end
	d.coins += reward
	d.eggs += 1
	dropEgg(player)
	if lucky then
		notify:FireClient(player, string.format("🎯 あたりゾーン！ コイン %d倍", Config.Lucky.mult), true)
	end
	if streak[player] >= 2 then
		notify:FireClient(
			player,
			string.format(
				"🔥 れんぞく %d回！ コイン +%d%%",
				streak[player],
				math.floor((combo - 1) * 100 + 0.5)
			),
			true
		)
	end
	if record then
		notify:FireClient(player, record, true)
	end
	Progress.bump(d, "delivered")
	if typeof(zone) == "number" then
		Progress.bumpZone(d, zone)
	end
	-- 檻にあきがあれば入れる
	if #d.incubator < incubatorSlots(d) then
		table.insert(d.incubator, { zone = zone, readyAt = os.time() + info.hatchTime })
		notify:FireClient(player, string.format("🎉 たまごを届けた！ +%d コイン", reward), true)
		notify:FireClient(
			player,
			string.format("🥚 たまごを檻に入れた（%d秒でかえるよ）", info.hatchTime)
		)
	else
		notify:FireClient(player, string.format("🎉 たまごを届けた！ +%d コイン", reward), true)
		notify:FireClient(player, "⚠️ 檻がいっぱい！ たまごをかえしてから運ぼう")
	end
	addXp(player, 4 * (if typeof(zone) == "number" then zone else 5))
	checkProgress(player)
	syncStats(player)
	save(player)
end

--------------------------------------------------------------------------------
-- 参加・退出
--------------------------------------------------------------------------------

Players.PlayerAdded:Connect(function(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	for _, name in { "スピード", "コイン", "たまご", "転生" } do
		local v = Instance.new("IntValue")
		v.Name = name
		v.Parent = stats
	end
	stats.Parent = player
	local owned = Instance.new("Folder")
	owned.Name = "OwnedItems"
	owned.Parent = player

	local d = loadData(player)
	data[player] = d
	for id, has in d.items do
		if has then
			local v = Instance.new("BoolValue")
			v.Name = id
			v.Value = true
			v.Parent = owned
		end
	end
	Progress.refreshDaily(d)
	checkProgress(player)
	syncStats(player)
	task.spawn(checkPasses, player)

	local function onCharacter(character: Model)
		dropEgg(player)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		applyStats(player, true)
		equipTeam(player)
		-- Backpack は キャラが出たあとに作られるので、少し待ってから武器をわたす
		task.delay(0.5, function()
			if player.Character == character then
				giveWeapon(player)
				wearArmor(player)
			end
		end)
		humanoid.Died:Connect(function()
			if carrying[player] then
				notify:FireClient(player, "💥 やられて たまごを落としてしまった…")
			end
			dropEgg(player)
			if (streak[player] or 0) >= 2 then
				notify:FireClient(player, "💔 れんぞく配達が とぎれた…")
			end
			streak[player] = 0
			player:SetAttribute("Streak", 0)
			Tower.leave(player, false)
			WorldBoss.leave(player, false)
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	-- 服や体の大きさが決まったあとに、防具を体に合わせて つけ直す
	player.CharacterAppearanceLoaded:Connect(function()
		task.wait(0.2)
		wearArmor(player)
	end)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	saveData(player)
	data[player] = nil
	carrying[player] = nil
	pendingGain[player] = nil
	lastWarn[player] = nil
	buffs[player] = nil
	skillReadyAt[player] = nil
	streak[player] = nil
	carryStart[player] = nil
	Weapons.forget(player)
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		task.spawn(saveData, player)
	end
	task.wait(2)
end)

-- 定期的に保存。日付が変わったら、ミッションを入れかえる
task.spawn(function()
	while true do
		task.wait(60)
		for _, player in Players:GetPlayers() do
			local d = data[player]
			if d then
				local day = d.daily.day
				Progress.refreshDaily(d)
				if d.daily.day ~= day then
					notify:FireClient(
						player,
						"📅 新しい日！ 今日のミッションとログインボーナスを見てみよう",
						true
					)
					syncStats(player)
				end
			end
		end
	end
end)
task.spawn(function()
	while true do
		task.wait(90)
		for _, player in Players:GetPlayers() do
			save(player)
		end
	end
end)

--------------------------------------------------------------------------------
-- 黄金のたまごイベント（30分ごとに 3分間、道のどこかに黄金のたまごが出る）
--------------------------------------------------------------------------------

local goldenFolder = Instance.new("Folder")
goldenFolder.Name = "GoldenEggs"
goldenFolder.Parent = workspace
local goldenEggs: { { part: BasePart, position: Vector3 } } = {}
local goldenWindow = -1

local function spawnGoldenEgg()
	local z = math.random(200, Config.Zones[5].distance - 100)
	local position = Vector3.new(math.random(-8, 8), 3, -z)
	local info = Config.SpecialEggs.gold
	local egg = Instance.new("Part")
	egg.Name = "GoldenEgg"
	egg.Shape = Enum.PartType.Ball
	egg.Size = Vector3.one * 5
	egg.Color = info.color
	egg.Material = Enum.Material.Foil
	egg.Anchored = true
	egg.CanCollide = false
	egg.CFrame = CFrame.new(position + Vector3.new(0, 1.5, 0))
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = egg
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = info.color
	sparkles.Parent = egg
	local light = Instance.new("PointLight")
	light.Color = info.color
	light.Range = 24
	light.Brightness = 4
	light.Parent = egg
	-- 遠くからでも見える光の柱
	local beam = Instance.new("Part")
	beam.Name = "GoldenBeam"
	beam.Shape = Enum.PartType.Cylinder
	beam.Size = Vector3.new(120, 4, 4)
	beam.CFrame = CFrame.new(position + Vector3.new(0, 60, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = info.color
	beam.Transparency = 0.6
	beam.Parent = egg
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(14, 0, 3, 0)
	bb.StudsOffset = Vector3.new(0, 6, 0)
	bb.LightInfluence = 0
	bb.MaxDistance = 400
	bb.Parent = egg
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.TextColor3 = info.color
	text.TextStrokeTransparency = 0.1
	text.Text = "🌟 黄金のたまご"
	text.Parent = bb
	egg.Parent = goldenFolder
	table.insert(goldenEggs, { part = egg, position = position })
end

task.spawn(function()
	local ev = Config.GoldenEvent
	while true do
		local now = os.time()
		local windowStart = now - now % ev.every
		local active = now - windowStart < ev.duration
		workspace:SetAttribute("GoldenEnd", windowStart + ev.duration)
		workspace:SetAttribute("GoldenNext", windowStart + ev.every)
		if active and goldenWindow ~= windowStart then
			goldenWindow = windowStart
			for _ = 1, 1 + math.floor(#Players:GetPlayers() / 3) do
				spawnGoldenEgg()
			end
			for _, player in Players:GetPlayers() do
				notify:FireClient(
					player,
					"🌟 黄金のたまごイベント！ 道のどこかに 光の柱が出たよ。急いで運ぼう！",
					true
				)
			end
		elseif not active and #goldenEggs > 0 then
			for _, g in goldenEggs do
				g.part:Destroy()
			end
			table.clear(goldenEggs)
		end
		-- くるくる回す
		for _, g in goldenEggs do
			g.part.CFrame = CFrame.new(g.position + Vector3.new(0, 1.5 + math.sin(os.clock() * 2) * 0.5, 0))
				* CFrame.Angles(0, os.clock(), 0)
		end
		task.wait(0.1)
	end
end)

--------------------------------------------------------------------------------
-- 天気が変わったら知らせる（走る速さ・トレーニング倍率が変わるので、数字を直す）
--------------------------------------------------------------------------------

task.spawn(function()
	local last = weather().id
	while true do
		task.wait(2)
		local now = weather()
		if now.id ~= last then
			last = now.id
			for _, player in Players:GetPlayers() do
				if data[player] then
					notify:FireClient(
						player,
						string.format("%s 天気が「%s」になった（%s）", now.icon, now.name, now.desc),
						true
					)
					syncStats(player)
					applyStats(player)
				end
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- 宝箱（道のどこかに ときどき出る。さわった人が もらえる）
--------------------------------------------------------------------------------

local chestFolder = Instance.new("Folder")
chestFolder.Name = "Chests"
chestFolder.Parent = workspace
type Chest = { model: Model, position: Vector3, zoneIndex: number, bornAt: number }
local chests: { Chest } = {}

local function chestPart(model: Model, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- 木の箱に 鉄のおび、金のかぎ。ふたは 丸い
local function buildChest(position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Chest"
	local base = CFrame.new(position) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	local wood = Color3.fromRGB(122, 78, 44)
	local iron = Color3.fromRGB(70, 72, 80)
	local gold = Color3.fromRGB(240, 190, 60)
	local body =
		chestPart(model, Vector3.new(4, 2.2, 2.6), base * CFrame.new(0, 1.1, 0), wood, Enum.Material.WoodPlanks)
	local lid = chestPart(
		model,
		Vector3.new(4, 2.6, 2.6),
		base * CFrame.new(0, 2.2, 0),
		wood:Lerp(Color3.new(0, 0, 0), 0.12),
		Enum.Material.WoodPlanks
	)
	lid.Shape = Enum.PartType.Cylinder
	for _, x in { -1.5, 0, 1.5 } do
		chestPart(model, Vector3.new(0.35, 2.3, 2.7), base * CFrame.new(x, 1.1, 0), iron, Enum.Material.Metal)
		local band =
			chestPart(model, Vector3.new(0.35, 2.72, 2.72), base * CFrame.new(x, 2.2, 0), iron, Enum.Material.Metal)
		band.Shape = Enum.PartType.Cylinder
	end
	chestPart(model, Vector3.new(4.1, 0.25, 2.7), base * CFrame.new(0, 2.15, 0), iron, Enum.Material.Metal)
	local lock =
		chestPart(model, Vector3.new(0.7, 0.9, 0.3), base * CFrame.new(0, 1.9, -1.4), gold, Enum.Material.Metal)
	lock.Reflectance = 0.35
	local light = Instance.new("PointLight")
	light.Color = gold
	light.Range = 18
	light.Brightness = 2
	light.Parent = lock
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = gold
	sparkles.Parent = body
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(8, 0, 2, 0)
	bb.StudsOffset = Vector3.new(0, 5.5, 0)
	bb.LightInfluence = 0
	bb.MaxDistance = 250
	bb.Parent = body
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = gold
	label.TextStrokeTransparency = 0.1
	label.Text = "🧰 宝箱"
	label.Parent = bb
	model.Parent = chestFolder
	return model
end

-- ひみつのゾーン以外の道の どこかに出す
local function spawnChest()
	local options = {}
	for i, zone in Config.Zones do
		if not zone.secret then
			table.insert(options, i)
		end
	end
	local zoneIndex = options[math.random(1, #options)]
	local from = if zoneIndex == 1 then 110 else Config.Zones[zoneIndex - 1].distance + 80
	local to = Config.Zones[zoneIndex].distance - 30
	local position = Vector3.new(math.random(-9, 9), 0.6, -math.random(from, to))
	table.insert(
		chests,
		{ model = buildChest(position), position = position, zoneIndex = zoneIndex, bornAt = os.clock() }
	)
	for _, player in Players:GetPlayers() do
		notify:FireClient(player, string.format("🧰 %sの道に 宝箱が出た！", Config.Zones[zoneIndex].name))
	end
end

local function openChest(player: Player, chest: Chest)
	local d = data[player]
	chest.model:Destroy()
	if not d then
		return
	end
	local cfg = Config.Chest
	local zone = Config.Zones[chest.zoneIndex]
	local coins = zone.reward * (cfg.coinMin + math.random() * (cfg.coinMax - cfg.coinMin))
	local roll = math.random()
	if roll < cfg.jackpotChance then
		coins = zone.reward * cfg.jackpotMult
		notify:FireClient(
			player,
			string.format("💎 大当たりの宝箱！！ +%d コイン", math.floor(coins)),
			true
		)
		screenFx:FireClient(player, Color3.fromRGB(255, 220, 90), 0.5)
	else
		notify:FireClient(player, string.format("🧰 宝箱を開けた！ +%d コイン", math.floor(coins)), true)
	end
	d.coins += math.floor(coins)
	if math.random() < cfg.eggChance then
		local id = mysteryHatch(player)
		local dragon = Dragons.find(id)
		notify:FireClient(
			player,
			string.format("🥚 宝箱から %s が生まれた！", if dragon then dragon.name else "ドラゴン"),
			true
		)
	end
	addXp(player, 3 * chest.zoneIndex)
	checkProgress(player)
	syncStats(player)
	save(player)
end

task.spawn(function()
	while true do
		task.wait(Config.Chest.every)
		for i = #chests, 1, -1 do
			if os.clock() - chests[i].bornAt > Config.Chest.life then
				chests[i].model:Destroy()
				table.remove(chests, i)
			end
		end
		if #Players:GetPlayers() > 0 and #chests < Config.Chest.max then
			spawnChest()
		end
	end
end)

--------------------------------------------------------------------------------
-- 転生：スピードとコインを 0 にもどして、ずっと続く力をもらう
--------------------------------------------------------------------------------

rebirthAction.OnServerInvoke = function(player: Player)
	local d = data[player]
	if not d then
		return false, "エラー"
	end
	local need = Config.rebirthNeed(d.rebirths)
	if d.speed < need then
		return false, string.format("スピードが あと %d いるよ", math.ceil(need - d.speed))
	end
	if carrying[player] then
		return false, "たまごを届けてから 転生しよう"
	end
	d.rebirths += 1
	d.speed = 0
	d.coins = 0
	local id = mysteryHatch(player)
	local dragon = Dragons.find(id)
	checkProgress(player)
	syncStats(player)
	applyStats(player, true)
	save(player)
	return true,
		string.format(
			"🌟 転生 %d回目！ 「%s」になった。おいわいに %s が生まれた",
			d.rebirths,
			Config.rebirthTitle(d.rebirths),
			if dragon then dragon.name else "ドラゴン"
		)
end

--------------------------------------------------------------------------------
-- メインループ：トレーニング、たまごを拾う・届ける、回復、ひみつの門
--------------------------------------------------------------------------------

-- ルームランナーのベルト（乗ると後ろへ流される）
for _, tm in world.treadmills do
	tm.belt.AssemblyLinearVelocity = Vector3.new(0, 0, 10)
end

local function treadmillUnder(position: Vector3)
	for _, tm in world.treadmills do
		local rel = tm.belt.CFrame:PointToObjectSpace(position)
		local half = tm.belt.Size / 2
		if math.abs(rel.X) <= half.X + 0.5 and math.abs(rel.Z) <= half.Z + 0.5 and rel.Y > 0 and rel.Y < 7 then
			return tm
		end
	end
	return nil
end

local TICK = 0.25
local buffActive: { [Player]: boolean } = {}
task.spawn(function()
	local tickCount = 0
	while true do
		task.wait(TICK)
		tickCount += 1
		for _, player in Players:GetPlayers() do
			local d = data[player]
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not d or not root or not humanoid or humanoid.Health <= 0 then
				continue
			end
			local pos = root.Position

			-- ひみつの門：開いていない人が通りぬけたら、門の手前へもどす
			if world.secretZ and not d.secretOpen and -pos.Z > world.secretZ + 3 and pos.Y < 200 then
				character:PivotTo(CFrame.new(0, 4, -(world.secretZ - 20)))
				notify:FireClient(player, "🔒 ひみつの門は まだ開いていない…")
			end

			-- たまご
			if carrying[player] then
				if (pos - world.nest).Magnitude < 12 then
					deliverEgg(player)
				end
			else
				for _, egg in world.eggs do
					if (pos - egg.position).Magnitude < 7 then
						pickUpEgg(player, egg.zoneIndex)
						break
					end
				end
				for i, g in goldenEggs do
					if not carrying[player] and (pos - g.position).Magnitude < 7 then
						g.part:Destroy()
						table.remove(goldenEggs, i)
						pickUpEgg(player, "gold")
						break
					end
				end
			end

			-- 宝箱
			for i, chest in chests do
				if (pos - chest.position).Magnitude < 7 then
					table.remove(chests, i)
					openChest(player, chest)
					break
				end
			end

			-- フェニックスなどの回復
			local regen = regenOf(d)
			if regen > 0 and humanoid.Health < humanoid.MaxHealth then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + regen * TICK)
			end

			-- わざの効果が切れたら、走る速さをもどす
			local b = buffOf(player)
			local now = os.clock()
			local anyBuff = now < b.speedUntil or now < b.trainUntil
			if buffActive[player] and not anyBuff then
				syncStats(player)
				applyStats(player)
			end
			buffActive[player] = anyBuff

			-- トレーニング
			local tm = treadmillUnder(pos)
			if tm then
				if d.speed >= tm.required then
					local gain = tm.gain * trainMult(player, d) * TICK
					d.speed += gain
					Progress.bump(d, "trained", gain)
					pendingGain[player] = (pendingGain[player] or 0) + gain
				elseif os.clock() - (lastWarn[player] or 0) > 3 then
					lastWarn[player] = os.clock()
					notify:FireClient(
						player,
						string.format("🔒 %sは スピード %d から使えるよ", tm.name, tm.required)
					)
				end
			end
		end

		-- 1秒ごとに表示を更新
		if tickCount % 4 == 0 then
			for player, gain in pendingGain do
				if gain > 0 then
					trainGain:FireClient(player, gain)
					addXp(player, 0.5)
					checkProgress(player)
					syncStats(player)
					applyStats(player)
				end
				pendingGain[player] = nil
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- ショップ
--------------------------------------------------------------------------------

world.shopPrompt.Triggered:Connect(function(player)
	openShop:FireClient(player)
end)

buyItem.OnServerInvoke = function(player: Player, id: any)
	local d = data[player]
	if not d or typeof(id) ~= "string" then
		return false, "エラー"
	end
	local item
	for _, it in Config.Items do
		if it.id == id then
			item = it
		end
	end
	if not item then
		return false, "その商品はありません"
	end
	if d.items[id] then
		return false, "もう持っています"
	end
	if d.coins < item.price then
		return false, string.format("コインが %d 足りません", item.price - math.floor(d.coins))
	end
	d.coins -= item.price
	d.items[id] = true
	local owned = player:FindFirstChild("OwnedItems")
	if owned and not owned:FindFirstChild(id) then
		local v = Instance.new("BoolValue")
		v.Name = id
		v.Value = true
		v.Parent = owned
	end
	syncStats(player)
	applyStats(player)
	save(player)
	return true, item.name .. " を手に入れた！"
end

--------------------------------------------------------------------------------
-- ドラゴン：連れていく・お休み・進化・卒業・交配
--------------------------------------------------------------------------------

local function hatchedDragon(d: Data, id: any)
	local dragon = if typeof(id) == "string" then Dragons.find(id) else nil
	if dragon and dragon.rarity and (d.collection[id] or 0) > 0 then
		return dragon
	end
	return nil
end

-- 交配で生まれる子ども：片方の親の「体の形」と、もう片方の「属性」を合わせる
local function breedChild(a, b)
	local options = {}
	for _, pair in { { a, b }, { b, a } } do
		local child = Config.findDragonByName(pair[2].element .. pair[1].noun)
		if child then
			table.insert(options, child)
		end
	end
	if #options == 0 then
		return a
	end
	return options[math.random(1, #options)]
end

local actions = {}

actions.equip = function(player: Player, d: Data, id: any)
	local dragon = if typeof(id) == "string" then Dragons.find(id) else nil
	if not dragon then
		return false, "そのドラゴンはいません"
	end
	if not canUseDragon(d, dragon.id) then
		return false, "そのドラゴンは まだ持っていません"
	end
	if table.find(d.team, dragon.id) then
		return false, "もう ついて来ています"
	end
	local msg = dragon.name .. " がついて来るよ！"
	if #d.team >= teamSlots(d) then
		-- 席がいっぱいなら、一番うしろの1匹と交代
		local old = Dragons.find(d.team[#d.team])
		d.team[#d.team] = dragon.id
		msg = string.format(
			"%s と交代して、%s がついて来るよ！",
			if old then old.name else "仲間",
			dragon.name
		)
	else
		table.insert(d.team, dragon.id)
	end
	equipTeam(player)
	return true, msg
end

actions.unequip = function(player: Player, d: Data, id: any)
	local i = if typeof(id) == "string" then table.find(d.team, id) else nil
	if i then
		table.remove(d.team, i)
	else
		table.clear(d.team)
	end
	equipTeam(player)
	return true, "ドラゴンをお休みさせた"
end

-- 同じドラゴン 3体 → ひとつ上のレア度のドラゴン（できれば同じ体の形）
actions.merge = function(player: Player, d: Data, id: any)
	local dragon = hatchedDragon(d, id)
	if not dragon then
		return false, "そのドラゴンは いません"
	end
	if dragon.rarity >= 5 then
		return false, "レジェンドは これ以上 進化できません"
	end
	if d.collection[dragon.id] < Config.MergeCount then
		return false, string.format("同じドラゴンが %d体 いると 進化できます", Config.MergeCount)
	end
	d.collection[dragon.id] -= Config.MergeCount
	local candidates = {}
	for _, other in Config.HatchByRarity[dragon.rarity + 1] do
		if other.shape == dragon.shape then
			table.insert(candidates, other)
		end
	end
	if #candidates == 0 then
		candidates = Config.HatchByRarity[dragon.rarity + 1]
	end
	local result = candidates[math.random(1, #candidates)]
	-- 経験値は、進化したドラゴンに引きつぐ
	d.xp[result.id] = math.max(d.xp[result.id] or 0, d.xp[dragon.id] or 0)
	local isNew = giveDragon(player, result.id)
	Progress.bump(d, "merges")
	dropFromTeamIfGone(player, d, dragon.id)
	return true, string.format("✨ %s 3体が %s に進化した！", dragon.name, result.name), result.id, isNew
end

actions.graduate = function(player: Player, d: Data, id: any)
	local dragon = hatchedDragon(d, id)
	if not dragon then
		return false, "そのドラゴンは いません"
	end
	local coins = Config.GraduateCoins[dragon.rarity]
	d.collection[dragon.id] -= 1
	d.coins += coins
	Progress.bump(d, "graduated")
	dropFromTeamIfGone(player, d, dragon.id)
	return true, string.format("🎓 %s が卒業した。ありがとう！ +%d コイン", dragon.name, coins)
end

actions.breed = function(_player: Player, d: Data, idA: any, idB: any)
	local a, b = hatchedDragon(d, idA), hatchedDragon(d, idB)
	if not a or not b then
		return false, "交配する 2匹を えらんでね"
	end
	if a == b and d.collection[a.id] < 2 then
		return false, "同じドラゴンどうしは 2体 いないと 交配できません"
	end
	if #d.incubator >= incubatorSlots(d) then
		return false, "檻がいっぱいです。たまごをかえしてから 交配しよう"
	end
	local cost = Config.breedCost(a.rarity, b.rarity)
	if d.coins < cost then
		return false, string.format("コインが %d 足りません", cost - math.floor(d.coins))
	end
	d.coins -= cost
	local child = breedChild(a, b)
	local seconds = Config.HatchTime[math.min(5, math.max(a.rarity, b.rarity))]
	table.insert(d.incubator, { zone = "breed", readyAt = os.time() + seconds, child = child.id })
	Progress.bump(d, "breeds")
	return true, string.format("🧬 交配のたまごが 檻に入った！（%d秒でかえるよ）", seconds)
end

dragonAction.OnServerInvoke = function(player: Player, action: any, a: any, b: any)
	local d = data[player]
	local fn = typeof(action) == "string" and actions[action]
	if not d or not fn then
		return false, "エラー"
	end
	local ok, msg, id, isNew = fn(player, d, a, b)
	if ok then
		checkProgress(player)
		syncStats(player)
		applyStats(player)
		save(player)
	end
	return ok, msg, id, isNew
end

-- 檻のたまごをかえす：slot 番目のたまごの時間が来ていたら、ドラゴンが生まれる
hatchEgg.OnServerInvoke = function(player: Player, slot: any)
	local d = data[player]
	if not d or typeof(slot) ~= "number" then
		return false
	end
	local egg = d.incubator[slot]
	if not egg or egg.readyAt > os.time() then
		return false
	end
	local info = Config.eggInfo(egg.zone)
	table.remove(d.incubator, slot)
	local dragon = if egg.child then Dragons.find(egg.child) else nil
	if not dragon then
		dragon = rollDragon(if info and info.odds then info.odds else Config.HatchOdds[1])
	end
	local isNew = giveDragon(player, dragon.id)
	Progress.bump(d, "hatched")
	checkProgress(player)
	syncStats(player)
	save(player)
	return true, dragon.id, isNew
end

world.incubatorPrompt.Triggered:Connect(function(player)
	openShop:FireClient(player, "cage")
end)

--------------------------------------------------------------------------------
-- 毎日のごほうび：ログインボーナス、ミッション、ミッション全部クリアのたまご、無料のたまご
--------------------------------------------------------------------------------

dailyAction.OnServerInvoke = function(player: Player, action: any, arg: any)
	local d = data[player]
	if not d then
		return false, "エラー"
	end
	Progress.refreshDaily(d)
	local ok, msg, id, isNew = false, "エラー", nil, nil
	if action == "login" then
		local reward = Progress.claimLogin(d)
		if reward then
			ok = true
			msg = string.format("📅 ログインボーナス %d日目！ +%d コイン", reward.day, reward.coins)
			if reward.egg then
				id, isNew = mysteryHatch(player)
			end
		else
			msg = "今日のぶんは もうもらったよ。また明日！"
		end
	elseif action == "mission" and typeof(arg) == "number" then
		ok, msg = Progress.claimMission(d, arg)
	elseif action == "bonus" then
		if Progress.canClaimBonus(d) then
			d.daily.bonus = true
			ok, msg = true, "🎁 ミッションを全部クリア！ ふしぎなたまごがかえった"
			id, isNew = mysteryHatch(player)
		else
			msg = "ミッションを 3つ全部 クリアすると もらえるよ"
		end
	elseif action == "free" then
		if Progress.freeEggReady(d) then
			d.freeEggAt = os.time() + Config.FreeEggInterval
			ok, msg = true, "🎰 無料のたまごが かえった！"
			id, isNew = mysteryHatch(player)
		else
			msg = "まだ ひけません"
		end
	end
	if ok then
		checkProgress(player)
		syncStats(player)
		save(player)
	end
	return ok, msg, id, isNew
end

--------------------------------------------------------------------------------
-- 武器：買う・持ちかえる
--------------------------------------------------------------------------------

weaponAction.OnServerInvoke = function(player: Player, action: any, id: any)
	local d = data[player]
	local weapon = Config.findWeapon(id)
	if not d or not weapon then
		return false, "その武器はありません"
	end
	local msg
	-- 神話の武器：Robux のゲームパスを買う画面を出す（買えたら PromptGamePassPurchaseFinished でわたす）
	if action == "robux" then
		if not weapon.mythic or d.weapons[weapon.id] then
			return false, "エラー"
		end
		if weapon.passId <= 0 then
			return false, "この武器は まだ準備中です"
		end
		MarketplaceService:PromptGamePassPurchase(player, weapon.passId)
		return true, ""
	end
	if action == "buy" and weapon.mythic and not d.weapons[weapon.id] and not Config.FreeWeaponsForTest then
		return false, "この武器は Robux で 手に入るよ"
	end
	if action == "buy" then
		if d.weapons[weapon.id] then
			return false, "もう持っています"
		end
		if d.coins < weapon.price then
			return false, string.format("コインが %d 足りません", weapon.price - math.floor(d.coins))
		end
		d.coins -= weapon.price
		d.weapons[weapon.id] = true
		msg = string.format("⚔️ %s を手に入れた！", weapon.name)
	elseif action == "equip" then
		if not d.weapons[weapon.id] then
			return false, "まだ持っていません"
		end
		msg = string.format("⚔️ %s に持ちかえた", weapon.name)
	else
		return false, "エラー"
	end
	-- 買ったら、そのまま手に持つ
	d.weapon = weapon.id
	giveWeapon(player)
	checkProgress(player)
	syncStats(player)
	save(player)
	return true, msg
end

--------------------------------------------------------------------------------
-- 防具：買う・つける・はずす
--------------------------------------------------------------------------------

armorAction.OnServerInvoke = function(player: Player, action: any, id: any)
	local d = data[player]
	local armor = Config.findArmor(id)
	if not d or not armor then
		return false, "その防具はありません"
	end
	local msg
	if action == "buy" then
		if d.armors[armor.id] then
			return false, "もう持っています"
		end
		if d.coins < armor.price then
			return false, string.format("コインが %d 足りません", armor.price - math.floor(d.coins))
		end
		d.coins -= armor.price
		d.armors[armor.id] = true
		-- 買ったら、そのまま身につける
		d.armor[armor.slot] = armor.id
		msg = string.format("🛡️ %s を手に入れた！", armor.name)
	elseif action == "equip" then
		if not d.armors[armor.id] then
			return false, "まだ持っていません"
		end
		d.armor[armor.slot] = armor.id
		msg = string.format("🛡️ %s を身につけた", armor.name)
	elseif action == "remove" then
		if d.armor[armor.slot] ~= armor.id then
			return false, "身につけていません"
		end
		d.armor[armor.slot] = nil
		msg = string.format("%s を はずした", armor.name)
	else
		return false, "エラー"
	end
	wearArmor(player)
	applyStats(player)
	syncStats(player)
	save(player)
	return true, msg
end

-- 神話の武器：ゲームパスを持っていたら わたす（入ったとき・買ったとき）
local function passWeapon(passId: number)
	for _, w in Config.Weapons do
		if w.mythic and w.passId == passId and passId > 0 then
			return w
		end
	end
	return nil
end

checkPasses = function(player: Player)
	local d = data[player]
	if not d then
		return
	end
	local changed = false
	for _, w in Config.Weapons do
		if w.mythic and w.passId > 0 and not d.weapons[w.id] then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, w.passId)
			end)
			if ok and owns then
				d.weapons[w.id] = true
				changed = true
			end
		end
	end
	if changed then
		syncStats(player)
		save(player)
	end
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
	local d = data[player]
	local w = passWeapon(passId)
	if not purchased or not d or not w then
		return
	end
	d.weapons[w.id] = true
	d.weapon = w.id
	giveWeapon(player)
	notify:FireClient(
		player,
		string.format("🌈 神話の武器「%s」を手に入れた！ ありがとう！", w.name),
		true
	)
	checkProgress(player)
	syncStats(player)
	save(player)
end)

--------------------------------------------------------------------------------
-- わざ：連れているドラゴンのうち、レベル 5 以上の全員が使う
--------------------------------------------------------------------------------

useSkill.OnServerInvoke = function(player: Player)
	local d = data[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not d or not root or not humanoid or humanoid.Health <= 0 then
		return false, "いまは使えません"
	end
	if os.time() < (skillReadyAt[player] or 0) then
		return false, string.format("あと %d秒 で使えるよ", (skillReadyAt[player] or 0) - os.time())
	end
	local used = {}
	local b = buffOf(player)
	local now = os.clock()
	for _, dragon in teamDragons(d) do
		local level = levelOf(d, dragon.id)
		local skill = Config.Skills[dragon.shape]
		if not skill or level < Config.SkillLevel then
			continue
		end
		-- レベルが高いほど、長く・強くなる
		local longer = 1 + 0.03 * (level - Config.SkillLevel)
		local power = (if dragon.attack then dragon.attack.damage else 10) * Config.levelPower(level)
		if skill.kind == "train" then
			b.trainUntil = now + skill.duration * longer
			b.train = math.max(if now < b.trainUntil then b.train else 1, skill.value)
		elseif skill.kind == "speed" then
			b.speedUntil = now + skill.duration * longer
			b.speed = skill.value
		elseif skill.kind == "shield" then
			b.shieldUntil = now + skill.duration * longer
		elseif skill.kind == "heal" then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * skill.value)
		elseif skill.kind == "blast" or skill.kind == "quake" then
			for _, e in Enemies.findInRange(root.Position, skill.radius) do
				if skill.kind == "quake" then
					Enemies.stun(e, skill.duration * longer)
				end
				Enemies.damage(e, power * skill.value, player)
			end
		end
		Dragons.effect(root.Position - Vector3.new(0, 2.5, 0), skill.color, skill.radius or 16)
		table.insert(used, skill.name)
	end
	if #used == 0 then
		return false,
			string.format("ドラゴンが レベル %d になると わざを覚えるよ", Config.SkillLevel)
	end
	skillReadyAt[player] = os.time() + Config.SkillCooldown
	Sounds.on(root, "roar")
	syncStats(player)
	applyStats(player)
	return true, "✨ " .. table.concat(used, "・") .. "！"
end

--------------------------------------------------------------------------------
-- ベースへ戻る・塔のぼり
--------------------------------------------------------------------------------

local function sendHome(player: Player)
	local character = player.Character
	if character then
		character:PivotTo(world.spawn.CFrame + Vector3.new(0, 4, 0))
	end
end

-- ベースへ戻る（たまごを持っているときは使えない。塔の中なら、塔を出る）
goHome.OnServerEvent:Connect(function(player)
	if Tower.isInside(player) then
		Tower.leave(player, true)
		return
	end
	if WorldBoss.isInside(player) then
		WorldBoss.leave(player, true)
		return
	end
	if carrying[player] then
		notify:FireClient(player, "🥚 たまごを持っている間は ワープできません")
		return
	end
	sendHome(player)
end)

Tower.init({
	notify = function(player: Player, msg: string, good: boolean?)
		notify:FireClient(player, msg, good)
	end,
	home = sendHome,
	cleared = function(player: Player, floor: number, reward: number)
		local d = data[player]
		if not d then
			return
		end
		d.coins += reward
		Progress.bump(d, "towerFloors")
		d.stats.towerBest = math.max(d.stats.towerBest, floor)
		notify:FireClient(player, string.format("🎉 %d階 クリア！ +%d コイン", floor, reward), true)
		addXp(player, 3 + floor)
		checkProgress(player)
		syncStats(player)
	end,
	ended = function(player: Player, cleared: number)
		local d = data[player]
		if not d or not player.Parent then
			return
		end
		notify:FireClient(
			player,
			string.format(
				"🗼 塔から出た。今回 %d階 までクリア（さいこう %d階）",
				cleared,
				d.stats.towerBest
			)
		)
		syncStats(player)
		save(player)
	end,
})

world.towerPrompt.Triggered:Connect(function(player)
	if carrying[player] then
		notify:FireClient(player, "🥚 たまごを持っている間は 塔に入れません")
		return
	end
	local ok, msg = Tower.enter(player)
	notify:FireClient(player, msg, ok)
end)

--------------------------------------------------------------------------------
-- 敵とドラゴンを動かす
--------------------------------------------------------------------------------

Dragons.start()
local enemyFolder = Instance.new("Folder")
enemyFolder.Name = "Enemies"
enemyFolder.Parent = workspace
for _, home in world.enemyHomes do
	Enemies.spawn(home.position, home.zoneIndex, home.boss, enemyFolder)
end
-- 敵をたおしたら、たおしたプレイヤーにコインと経験値
Enemies.onDefeated(function(player, enemy, source)
	if enemy.tag == "world" then
		-- みんなのボス：ごほうびは ダメージを与えた全員に（WorldBoss が分ける）
		WorldBoss.onDefeated(enemy)
		return
	end
	if enemy.tag == "tower" then
		Tower.onEnemyDefeated(enemy)
	end
	local d = player and data[player]
	if not player or not d then
		return
	end
	Progress.bump(d, "kills")
	if source == "weapon" then
		Progress.bump(d, "weaponKills")
	end
	if enemy.boss then
		Progress.bump(d, "bossKills")
	end
	if enemy.tag == "tower" then
		addXp(player, 2 + (Tower.floorOf(player) or 1))
	else
		local zone = Config.Zones[enemy.zoneIndex]
		local bounty = math.max(
			1,
			math.floor(zone.reward * Config.EnemyBountyRate * (if enemy.boss then 5 else 1) * (weather().bounty or 1))
		)
		d.coins += bounty
		local what = if enemy.boss then zone.bossName or "ボス" else zone.enemyName or zone.name .. "の敵"
		notify:FireClient(player, string.format("⚔️ %sをたおした！ +%d コイン", what, bounty), true)
		addXp(player, 2 * enemy.zoneIndex * (if enemy.boss then 5 else 1))
	end
	checkProgress(player)
	syncStats(player)
end)

--------------------------------------------------------------------------------
-- みんなで遊ぶ：みんなのボス・なかまブースト・ランキング
--------------------------------------------------------------------------------

-- その人の「1秒あたりのこうげき力」（武器 + 連れているドラゴン）。みんなのボスの体力を決めるのに使う
local function powerOf(player: Player): number
	local d = data[player]
	if not d then
		return 0
	end
	local dps = 0
	local weapon = Config.findWeapon(d.weapon)
	if weapon then
		dps += weapon.damage / weapon.cooldown * (1 + Config.armorBonus(d.armor).attack / 100)
	end
	for _, dragon in teamDragons(d) do
		local attack = dragon.attack
		if attack then
			dps += attack.damage * (attack.shots or 1) / attack.cooldown * Config.levelPower(levelOf(d, dragon.id))
		end
	end
	return dps
end

local bossPrompt = WorldBoss.init({
	notify = function(player: Player, msg: string, good: boolean?)
		notify:FireClient(player, msg, good)
	end,
	home = sendHome,
	power = powerOf,
	reward = function(player: Player, share: number, mvp: boolean)
		local d = data[player]
		if not d then
			return
		end
		local wb = Config.WorldBoss
		local coins = math.floor(Progress.rewardBase(d) * wb.coins * (if mvp then wb.mvp else 1))
		d.coins += coins
		Progress.bump(d, "worldBoss")
		local dragon = Dragons.find((mysteryHatch(player)))
		notify:FireClient(
			player,
			string.format(
				"🎉 ボスの ごほうび！ +%d コイン と %s（あなたの活やく %d%%%s）",
				coins,
				if dragon then dragon.name else "ドラゴン",
				math.floor(share * 100 + 0.5),
				if mvp then "・いちばん！" else ""
			),
			true
		)
		addXp(player, wb.xp)
		checkProgress(player)
		syncStats(player)
		save(player)
	end,
}, workspace, enemyFolder)

bossPrompt.Triggered:Connect(function(player)
	if carrying[player] then
		notify:FireClient(player, "🥚 たまごを持っている間は 入れません")
		return
	end
	if Tower.isInside(player) then
		return
	end
	local ok, msg = WorldBoss.enter(player)
	notify:FireClient(player, msg, ok)
end)

-- なかまブースト：人数が変わったら、全員の数字を直して 知らせる
local function friendBoostChanged(joined: Player?)
	local count = #Players:GetPlayers()
	workspace:SetAttribute("FriendBoost", Config.friendBoost(count))
	for _, player in Players:GetPlayers() do
		if data[player] then
			syncStats(player)
			if joined and player ~= joined then
				notify:FireClient(
					player,
					string.format(
						"🤝 %s が来た！ なかまブースト +%d%%（トレーニングとたまごのコイン）",
						joined.DisplayName,
						math.floor((Config.friendBoost(count) - 1) * 100 + 0.5)
					),
					true
				)
			end
		end
	end
end
Players.PlayerAdded:Connect(function(player)
	friendBoostChanged(player)
end)
Players.PlayerRemoving:Connect(function()
	-- 出ていく人が 数えられなくなってから 計算する
	task.defer(friendBoostChanged)
end)
friendBoostChanged()

Ranking.init(function(player: Player, key: string): number?
	local d = data[player]
	if not d then
		return nil
	end
	if key == "rebirths" then
		return d.rebirths
	elseif key == "eggs" then
		return d.eggs
	end
	return d.stats[key]
end, world.folder)

Enemies.start(function(player)
	local d = data[player]
	return if d then damageMult(player, d) else 1
end, function(player, direction)
	knockback:FireClient(player, direction)
end)
