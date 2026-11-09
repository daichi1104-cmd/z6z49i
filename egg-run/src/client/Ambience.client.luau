-- 場所によって空の明るさを変える（自分の画面だけ）
-- 星空のゾーンは夜、古代の遺跡は夕方、塔の中はむらさきの夜

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local player = Players.LocalPlayer

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")

-- ふだんの明るさ（default.project.json の値）をおぼえておく
local normal = {
	lighting = {
		ClockTime = Lighting.ClockTime,
		Brightness = Lighting.Brightness,
		OutdoorAmbient = Lighting.OutdoorAmbient,
	},
	atmosphere = if atmosphere
		then { Color = atmosphere.Color, Decay = atmosphere.Decay, Density = atmosphere.Density }
		else nil,
}

local MOODS = {
	normal = normal,
	night = {
		lighting = { ClockTime = 0.5, Brightness = 1.2, OutdoorAmbient = Color3.fromRGB(70, 70, 120) },
		atmosphere = { Color = Color3.fromRGB(60, 60, 120), Decay = Color3.fromRGB(40, 30, 90), Density = 0.25 },
	},
	sunset = {
		lighting = { ClockTime = 17.4, Brightness = 2, OutdoorAmbient = Color3.fromRGB(140, 110, 90) },
		atmosphere = { Color = Color3.fromRGB(230, 180, 140), Decay = Color3.fromRGB(150, 90, 80), Density = 0.35 },
	},
	tower = {
		lighting = { ClockTime = 21, Brightness = 1.4, OutdoorAmbient = Color3.fromRGB(110, 90, 150) },
		atmosphere = { Color = Color3.fromRGB(110, 80, 160), Decay = Color3.fromRGB(60, 40, 110), Density = 0.3 },
	},
}

-- ゾーンの始まりの距離（WorldBuilder と同じ計算：前のゾーンのたまご + 60）
local starts = {}
for i, zone in Config.Zones do
	starts[i] = if i == 1 then 80 else Config.Zones[i - 1].distance + 60
	if zone.decor == "star" then
		starts.star = i
	elseif zone.decor == "ruins" then
		starts.ruins = i
	end
end

local function zoneAt(distance: number): number
	local found = 0
	for i = 1, #Config.Zones do
		if distance >= starts[i] then
			found = i
		end
	end
	return found
end

local function moodAt(position: Vector3): string
	if position.Y > Config.Tower.arenaY - 100 then
		return "tower"
	end
	local zone = Config.Zones[zoneAt(-position.Z)]
	if zone and zone.decor == "star" then
		return "night"
	elseif zone and zone.decor == "ruins" then
		return "sunset"
	end
	return "normal"
end

local current = "normal"
local function apply(name: string)
	current = name
	local mood = MOODS[name]
	local info = TweenInfo.new(2.5, Enum.EasingStyle.Sine)
	TweenService:Create(Lighting, info, mood.lighting):Play()
	if atmosphere and mood.atmosphere then
		TweenService:Create(atmosphere, info, mood.atmosphere):Play()
	end
end

while true do
	task.wait(0.5)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local mood = moodAt(root.Position)
		if mood ~= current then
			apply(mood)
		end
	end
end
