-- ランキングの看板：全部のサーバーを合わせた 上位の人を、ベースのうしろの看板に出す
-- ・数字は Roblox の「順番つきの保存（OrderedDataStore）」に入れる
-- ・保存が使えないとき（Studio など）は、いま同じサーバーにいる人だけで ならべる

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Ranking = {}

local R = Config.Ranking
local ROW_COLORS = {
	Color3.fromRGB(255, 215, 80), -- 1位：金
	Color3.fromRGB(215, 220, 230), -- 2位：銀
	Color3.fromRGB(225, 150, 90), -- 3位：銅
}

type Board = { def: any, store: any, rows: { TextLabel } }
local boards: { Board } = {}
local names: { [number]: string } = {}
local valueOf: (Player, string) -> number? = function()
	return nil
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	local name = if player then player.DisplayName else nil
	if not name then
		local ok, result = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		name = if ok then result else "？？？"
	end
	names[userId] = name
	return name
end

local function buildBoard(def: any, index: number, count: number, parent: Instance): { TextLabel }
	local width = 16
	local x = (index - (count + 1) / 2) * (width + 2)
	local origin = Vector3.new(x, 0, 76)
	local model = Instance.new("Model")
	model.Name = "Ranking_" .. def.key
	for _, dx in { -width / 2 + 0.5, width / 2 - 0.5 } do
		local post = Instance.new("Part")
		post.Name = "Post"
		post.Anchored = true
		post.Size = Vector3.new(1, 20, 1)
		post.CFrame = CFrame.new(origin + Vector3.new(dx, 10, 0.4))
		post.Color = Color3.fromRGB(90, 70, 50)
		post.Material = Enum.Material.Wood
		post.Parent = model
	end
	local panel = Instance.new("Part")
	panel.Name = "Panel"
	panel.Anchored = true
	panel.Size = Vector3.new(width, 17, 0.6)
	panel.CFrame = CFrame.new(origin + Vector3.new(0, 11, 0))
	panel.Color = Color3.fromRGB(30, 32, 44)
	panel.Material = Enum.Material.SmoothPlastic
	panel.Parent = model

	-- 看板の文字は、ベースのまん中がわ（-Z）の面に出す
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = panel
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.13, 0)
	title.BackgroundColor3 = def.color
	title.BorderSizePixel = 0
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(30, 30, 40)
	title.Text = def.title .. " ランキング"
	title.Parent = gui
	local rows = {}
	for i = 1, R.top do
		local row = Instance.new("TextLabel")
		row.Position = UDim2.new(0.03, 0, 0.14 + (i - 1) * 0.085, 0)
		row.Size = UDim2.new(0.94, 0, 0.075, 0)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.GothamBold
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = ROW_COLORS[i] or Color3.new(1, 1, 1)
		row.Text = string.format("%d位　ー", i)
		row.Parent = gui
		table.insert(rows, row)
	end
	model.Parent = parent
	return rows
end

local function show(board: Board, list: { { name: string, value: number } })
	for i, row in board.rows do
		local entry = list[i]
		row.Text = if entry
			then string.format("%d位　%s　%d%s", i, entry.name, entry.value, board.def.unit)
			else string.format("%d位　ー", i)
	end
end

-- いま同じサーバーにいる人だけの順位（保存が使えないとき用）
local function localList(key: string)
	local list = {}
	for _, player in Players:GetPlayers() do
		local value = valueOf(player, key)
		if value and value > 0 then
			table.insert(list, { name = player.DisplayName, value = math.floor(value) })
		end
	end
	table.sort(list, function(a, b)
		return a.value > b.value
	end)
	return list
end

local function refresh(board: Board)
	local key = board.def.key
	if not board.store then
		show(board, localList(key))
		return
	end
	-- このサーバーにいる人の数字を書きこむ
	for _, player in Players:GetPlayers() do
		local value = valueOf(player, key)
		if value and value > 0 then
			pcall(function()
				board.store:SetAsync(tostring(player.UserId), math.floor(value))
			end)
		end
	end
	local ok, page = pcall(function()
		return board.store:GetSortedAsync(false, R.top):GetCurrentPage()
	end)
	if not ok then
		show(board, localList(key))
		return
	end
	local list = {}
	for _, entry in page do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(list, { name = nameOf(userId), value = entry.value })
		end
	end
	show(board, list)
end

-- getValue(player, key)：その人の数字（まだ読みこめていなければ nil）
function Ranking.init(getValue: (Player, string) -> number?, parent: Instance)
	valueOf = getValue
	for i, def in R.boards do
		local store = nil
		pcall(function()
			store = DataStoreService:GetOrderedDataStore(Config.DataStoreName .. "_rank_" .. def.key)
		end)
		table.insert(boards, { def = def, store = store, rows = buildBoard(def, i, #R.boards, parent) })
	end
	task.spawn(function()
		task.wait(8) -- 最初の人のデータが 読みこまれるのを待つ
		while true do
			for _, board in boards do
				refresh(board)
				task.wait(1)
			end
			task.wait(R.every)
		end
	end)
end

return Ranking
