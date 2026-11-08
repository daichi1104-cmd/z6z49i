-- ゲームの進行管理：保存、トレーニング、たまごの回収、ショップ、ドラゴンの仲間

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))
local Enemies = require(script.Parent:WaitForChild("Enemies"))
local Dragons = require(script.Parent:WaitForChild("Dragons"))

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

-- DataStore は Studio で API アクセスが無効だと失敗するので pcall で守る
local store
pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName)
end)

type Data = {
	speed: number,
	coins: number,
	eggs: number,
	items: { [string]: boolean },
	collection: { [string]: number }, -- たまごから生まれたドラゴン（id → 何体持っているか）
	incubator: { { zone: number, readyAt: number } }, -- 檻の中のたまご（readyAt = かえる時刻）
	dragon: string?,
}

local data: { [Player]: Data } = {}
local carrying: { [Player]: number } = {} -- 運んでいるたまごのゾーン番号
local pendingGain: { [Player]: number } = {}
local lastWarn: { [Player]: number } = {}

local function defaultData(): Data
	return { speed = 0, coins = 0, eggs = 0, items = {}, collection = {}, incubator = {}, dragon = "Chibi" }
end

-- はじめの仲間はだれでも、生まれたドラゴンは持っていれば連れて行ける
local function canUseDragon(d: Data, id: string): boolean
	for _, starter in Config.Dragons do
		if starter.id == id then
			return true
		end
	end
	return (d.collection[id] or 0) > 0
end

local function loadData(player: Player): Data
	local d = defaultData()
	if not store then
		return d
	end
	local ok, value = pcall(function()
		return store:GetAsync("player_" .. player.UserId)
	end)
	if ok and typeof(value) == "table" then
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
		if typeof(value.incubator) == "table" then
			for _, egg in value.incubator do
				local zone = typeof(egg) == "table" and tonumber(egg.zone)
				local readyAt = typeof(egg) == "table" and tonumber(egg.readyAt)
				if zone and readyAt and Config.Zones[zone] and #d.incubator < 5 then
					table.insert(d.incubator, { zone = zone, readyAt = readyAt })
				end
			end
		end
		if typeof(value.dragon) == "string" and canUseDragon(d, value.dragon) then
			d.dragon = value.dragon
		elseif value.dragon == false then
			d.dragon = nil
		end
	end
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
			incubator = d.incubator,
			dragon = d.dragon or false,
		})
	end)
end

-- 持ち物とドラゴンから、強さを計算する
local function equippedDragon(d: Data)
	return Dragons.find(d.dragon)
end

local function trainMult(d: Data): number
	local m = 1
	for _, item in Config.Items do
		if d.items[item.id] and item.trainMult then
			m = math.max(m, item.trainMult)
		end
	end
	local dragon = equippedDragon(d)
	if dragon and dragon.trainMult then
		m *= dragon.trainMult
	end
	return m
end

local function damageMult(d: Data): number
	local m = 1
	for _, item in Config.Items do
		if d.items[item.id] and item.damageMult then
			m = math.min(m, item.damageMult)
		end
	end
	local dragon = equippedDragon(d)
	if dragon and dragon.damageMult then
		m *= dragon.damageMult
	end
	return m
end

local function coinMult(d: Data): number
	local dragon = equippedDragon(d)
	return if dragon and dragon.coinMult then dragon.coinMult else 1
end

local function maxHealth(d: Data): number
	local h = 100
	for _, item in Config.Items do
		if d.items[item.id] and item.maxHealth then
			h = math.max(h, item.maxHealth)
		end
	end
	return h
end

local function incubatorSlots(d: Data): number
	local n = Config.IncubatorSlots
	for _, item in Config.Items do
		if d.items[item.id] and item.incubatorSlots then
			n = math.max(n, item.incubatorSlots)
		end
	end
	return n
end

local function jumpPower(d: Data): number
	local j = 50
	for _, item in Config.Items do
		if d.items[item.id] and item.jumpPower then
			j = math.max(j, item.jumpPower)
		end
	end
	return j
end

local function walkSpeed(d: Data): number
	local dragon = equippedDragon(d)
	local bonus = if dragon and dragon.walkBonus then dragon.walkBonus else 0
	return Config.walkSpeedFor(d.speed) + bonus
end

local function syncStats(player: Player)
	local d = data[player]
	local stats = player:FindFirstChild("leaderstats")
	if not d or not stats then
		return
	end
	(stats:FindFirstChild("スピード") :: IntValue).Value = math.floor(d.speed);
	(stats:FindFirstChild("コイン") :: IntValue).Value = math.floor(d.coins);
	(stats:FindFirstChild("たまご") :: IntValue).Value = d.eggs
	player:SetAttribute("WalkSpeed", walkSpeed(d))
	player:SetAttribute("TrainMult", trainMult(d))
	player:SetAttribute("Dragon", d.dragon or "")
	-- 檻と図鑑の中身は、文字にしてクライアントへ渡す
	player:SetAttribute("Incubator", HttpService:JSONEncode(d.incubator))
	player:SetAttribute("Collection", HttpService:JSONEncode(d.collection))
	player:SetAttribute("IncubatorSlots", incubatorSlots(d))
end

local function applyStats(player: Player, fullHeal: boolean?)
	local d = data[player]
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not d or not humanoid then
		return
	end
	humanoid.WalkSpeed = walkSpeed(d)
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

-- 持ち物の一覧（クライアントのショップ表示用）
local function markOwned(player: Player, folderName: string, id: string)
	local f = player:FindFirstChild(folderName)
	if f and not f:FindFirstChild(id) then
		local v = Instance.new("BoolValue")
		v.Name = id
		v.Value = true
		v.Parent = f
	end
end

-- たまごを運ぶ
local function dropEgg(player: Player)
	carrying[player] = nil
	player:SetAttribute("CarryingZone", nil)
	local head = player.Character and player.Character:FindFirstChild("Head")
	local egg = head and head:FindFirstChild("CarriedEgg")
	if egg then
		egg:Destroy()
	end
end

local function pickUpEgg(player: Player, zoneIndex: number)
	local head = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	carrying[player] = zoneIndex
	player:SetAttribute("CarryingZone", zoneIndex)

	local egg = Instance.new("Part")
	egg.Name = "CarriedEgg"
	egg.Shape = Enum.PartType.Ball
	egg.Size = Vector3.one * 2.4
	egg.Color = Config.Zones[zoneIndex].eggColor
	egg.CanCollide = false
	egg.CanQuery = false
	egg.CanTouch = false
	egg.Massless = true
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = egg
	egg.CFrame = head.CFrame * CFrame.new(0, 2.6, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = egg
	weld.Parent = egg
	egg.Parent = head

	notify:FireClient(
		player,
		string.format("🥚 %sのたまごをゲット！ ベースの巣まで運ぼう", Config.Zones[zoneIndex].name)
	)
end

local function deliverEgg(player: Player)
	local d = data[player]
	local zoneIndex = carrying[player]
	if not d or not zoneIndex then
		return
	end
	local reward = math.floor(Config.Zones[zoneIndex].reward * coinMult(d))
	d.coins += reward
	d.eggs += 1
	dropEgg(player)
	-- 檻にあきがあれば入れる
	if #d.incubator < incubatorSlots(d) then
		local seconds = Config.HatchTime[zoneIndex]
		table.insert(d.incubator, { zone = zoneIndex, readyAt = os.time() + seconds })
		notify:FireClient(player, string.format("🎉 たまごを届けた！ +%d コイン", reward), true)
		notify:FireClient(player, string.format("🥚 たまごを檻に入れた（%d秒でかえるよ）", seconds))
	else
		notify:FireClient(player, string.format("🎉 たまごを届けた！ +%d コイン", reward), true)
		notify:FireClient(player, "⚠️ 檻がいっぱい！ たまごをかえしてから運ぼう")
	end
	syncStats(player)
	task.spawn(saveData, player)
end

Players.PlayerAdded:Connect(function(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	for _, name in { "スピード", "コイン", "たまご" } do
		local v = Instance.new("IntValue")
		v.Name = name
		v.Parent = stats
	end
	stats.Parent = player
	for _, name in { "OwnedItems" } do
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = player
	end

	local d = loadData(player)
	data[player] = d
	for id, owned in d.items do
		if owned then
			markOwned(player, "OwnedItems", id)
		end
	end
	syncStats(player)

	local function onCharacter(character: Model)
		dropEgg(player)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		applyStats(player, true)
		Dragons.equip(player, d.dragon)
		humanoid.Died:Connect(function()
			if carrying[player] then
				notify:FireClient(player, "💥 やられて たまごを落としてしまった…")
			end
			dropEgg(player)
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
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
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		task.spawn(saveData, player)
	end
	task.wait(2)
end)

-- 定期的に保存
task.spawn(function()
	while true do
		task.wait(90)
		for _, player in Players:GetPlayers() do
			task.spawn(saveData, player)
		end
	end
end)

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

-- メインループ：トレーニング、たまごを拾う・届ける
local TICK = 0.25
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
			end

			-- フェニックスなどの回復
			local dragon = equippedDragon(d)
			if dragon and dragon.regen and humanoid.Health < humanoid.MaxHealth then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + dragon.regen * TICK)
			end

			-- トレーニング
			local tm = treadmillUnder(pos)
			if tm then
				if d.speed >= tm.required then
					local gain = tm.gain * trainMult(d) * TICK
					d.speed += gain
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
					syncStats(player)
					applyStats(player)
				end
				pendingGain[player] = nil
			end
		end
	end
end)

-- ショップ
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
	markOwned(player, "OwnedItems", id)
	syncStats(player)
	applyStats(player)
	task.spawn(saveData, player)
	return true, item.name .. " を手に入れた！"
end

-- ドラゴン：action = "equip"（id のドラゴンを連れていく）/ "unequip"（お休み）
dragonAction.OnServerInvoke = function(player: Player, action: any, id: any)
	local d = data[player]
	if not d or typeof(action) ~= "string" then
		return false, "エラー"
	end
	if action == "unequip" then
		d.dragon = nil
		Dragons.equip(player, nil)
		syncStats(player)
		applyStats(player)
		task.spawn(saveData, player)
		return true, "ドラゴンをお休みさせた"
	end
	local dragon = if typeof(id) == "string" then Dragons.find(id) else nil
	if not dragon then
		return false, "そのドラゴンはいません"
	end
	if not canUseDragon(d, dragon.id) then
		return false, "そのドラゴンは まだ持っていません"
	end
	d.dragon = dragon.id
	Dragons.equip(player, dragon.id)
	syncStats(player)
	applyStats(player)
	task.spawn(saveData, player)
	return true, dragon.name .. " が仲間になった！"
end

-- たまごをかえす：slot 番目のたまごの時間が来ていたら、ドラゴンが生まれる
local function rollRarity(zoneIndex: number): number
	local odds = Config.HatchOdds[zoneIndex]
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

hatchEgg.OnServerInvoke = function(player: Player, slot: any)
	local d = data[player]
	if not d or typeof(slot) ~= "number" then
		return false
	end
	local egg = d.incubator[slot]
	if not egg then
		return false
	end
	if egg.readyAt > os.time() then
		return false
	end
	table.remove(d.incubator, slot)
	local rarity = rollRarity(egg.zone)
	local list = Config.HatchByRarity[rarity]
	local dragon = list[math.random(1, #list)]
	local isNew = (d.collection[dragon.id] or 0) == 0
	d.collection[dragon.id] = (d.collection[dragon.id] or 0) + 1
	syncStats(player)
	task.spawn(saveData, player)
	return true, dragon.id, isNew
end

world.incubatorPrompt.Triggered:Connect(function(player)
	openShop:FireClient(player, "cage")
end)

-- ベースへ戻る（たまごを持っているときは使えない）
goHome.OnServerEvent:Connect(function(player)
	if carrying[player] then
		notify:FireClient(player, "🥚 たまごを持っている間は ワープできません")
		return
	end
	local character = player.Character
	if character then
		character:PivotTo(world.spawn.CFrame + Vector3.new(0, 4, 0))
	end
end)

-- 敵とドラゴンを動かす
Dragons.start()
local enemyFolder = Instance.new("Folder")
enemyFolder.Name = "Enemies"
enemyFolder.Parent = workspace
for _, home in world.enemyHomes do
	Enemies.spawn(home.position, home.zoneIndex, home.boss, enemyFolder)
end
-- 敵をたおしたら、たおしたプレイヤーにコイン
Enemies.onDefeated(function(player, enemy)
	local d = player and data[player]
	if not player or not d then
		return
	end
	local zone = Config.Zones[enemy.zoneIndex]
	local bounty = math.max(1, math.floor(zone.reward * Config.EnemyBountyRate * (if enemy.boss then 5 else 1)))
	d.coins += bounty
	syncStats(player)
	local what = if enemy.boss then "ボス" else zone.name .. "の敵"
	notify:FireClient(player, string.format("⚔️ %sをたおした！ +%d コイン", what, bounty), true)
end)
Enemies.start(function(player)
	local d = data[player]
	return if d then damageMult(d) else 1
end, function(player, direction)
	knockback:FireClient(player, direction)
end)
