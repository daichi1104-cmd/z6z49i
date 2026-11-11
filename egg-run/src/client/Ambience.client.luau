-- 空と空気（自分の画面だけ）
-- ・時間：朝 → 昼 → 夕方 → 夜 が ゆっくり回る（Config.DayLength 秒で 1日。全員 同じ時刻）
-- ・天気：はれ・あめ・おいかぜ・きり・かみなり・にじ（Config.weatherAt。全員 同じ天気）
-- ・場所：砂漠は かげろうの黄色い空気、雪原は 青白く雪がちらつく、火山は 赤黒く火の粉が舞う など
-- ・星空のゾーンは いつも夜、古代の遺跡は いつも夕方、塔の中は むらさきの夜

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local player = Players.LocalPlayer

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
local colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

--------------------------------------------------------------------------------
-- 場所
--------------------------------------------------------------------------------

-- ゾーンの始まりの距離（WorldBuilder と同じ計算：前のゾーンのたまご + 60）
local starts = {}
for i in Config.Zones do
	starts[i] = if i == 1 then 80 else Config.Zones[i - 1].distance + 60
end

-- いる場所の種類："hub" / ゾーンの decor（tree, cactus, pine, rock, cloud, star, ruins）/ "tower"
local function placeAt(position: Vector3): string
	if position.Y > Config.Tower.arenaY - 100 then
		return "tower"
	end
	local found = "hub"
	for i, zone in Config.Zones do
		if -position.Z >= starts[i] then
			found = zone.decor
		end
	end
	return found
end

-- 場所ごとの空気
-- clock：時刻を固定する / tint：画面の色み / air・decay：遠くのかすみの色 / density・haze：かすみの こさ
-- particles：いつも舞っているもの / sky：空が見えない（雨や雪が ふらない）
type Place = {
	clock: number?,
	tint: Color3,
	air: Color3,
	decay: Color3,
	density: number,
	haze: number,
	saturation: number,
	particles: string?,
	noRain: boolean?,
	snow: boolean?,
}
local PLACES: { [string]: Place } = {
	hub = {
		tint = rgb(255, 255, 255),
		air = rgb(199, 212, 230),
		decay = rgb(107, 122, 153),
		density = 0.3,
		haze = 1.5,
		saturation = 0.06,
		particles = "pollen",
	},
	tree = {
		tint = rgb(250, 255, 246),
		air = rgb(196, 216, 226),
		decay = rgb(104, 130, 140),
		density = 0.31,
		haze = 1.6,
		saturation = 0.1,
		particles = "pollen",
	},
	cactus = {
		tint = rgb(255, 244, 222),
		air = rgb(232, 208, 168),
		decay = rgb(170, 130, 90),
		density = 0.38,
		haze = 2.4,
		saturation = 0.02,
		particles = "sand",
	},
	pine = {
		tint = rgb(226, 238, 255),
		air = rgb(214, 228, 245),
		decay = rgb(120, 150, 190),
		density = 0.42,
		haze = 2.2,
		saturation = -0.08,
		particles = "snow",
		snow = true,
	},
	rock = {
		tint = rgb(255, 226, 206),
		air = rgb(150, 96, 80),
		decay = rgb(90, 40, 30),
		density = 0.46,
		haze = 2.6,
		saturation = 0.05,
		particles = "embers",
	},
	cloud = {
		tint = rgb(255, 252, 244),
		air = rgb(226, 236, 250),
		decay = rgb(150, 175, 215),
		density = 0.24,
		haze = 1.2,
		saturation = 0.08,
		noRain = true,
	},
	star = {
		clock = 0.5,
		tint = rgb(214, 220, 255),
		air = rgb(60, 60, 120),
		decay = rgb(40, 30, 90),
		density = 0.25,
		haze = 1.4,
		saturation = 0.1,
		particles = "stardust",
		noRain = true,
	},
	ruins = {
		clock = 17.4,
		tint = rgb(255, 236, 214),
		air = rgb(230, 180, 140),
		decay = rgb(150, 90, 80),
		density = 0.35,
		haze = 2,
		saturation = 0.08,
		particles = "pollen",
	},
	tower = {
		clock = 21,
		tint = rgb(232, 220, 255),
		air = rgb(110, 80, 160),
		decay = rgb(60, 40, 110),
		density = 0.3,
		haze = 1.6,
		saturation = 0.05,
		noRain = true,
	},
}

--------------------------------------------------------------------------------
-- 舞うもの（雨・雪・砂・火の粉・花粉・ほたる）：カメラの上の 見えない板から出す
--------------------------------------------------------------------------------

local emitterPart = Instance.new("Part")
emitterPart.Name = "SkyEmitter"
emitterPart.Anchored = true
emitterPart.CanCollide = false
emitterPart.CanQuery = false
emitterPart.CanTouch = false
emitterPart.Transparency = 1
emitterPart.Size = Vector3.new(90, 1, 90)
emitterPart.Parent = workspace

-- 足もとの近くに ただようもの用（低い位置）
local lowPart = emitterPart:Clone()
lowPart.Name = "LowEmitter"
lowPart.Size = Vector3.new(70, 14, 70)
lowPart.Parent = workspace

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.LightInfluence = 1
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

local function fade(a: number, b: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, a),
		NumberSequenceKeypoint.new(0.8, b),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local EMITTERS: { [string]: ParticleEmitter } = {
	-- 雨：細長いしずくが まっすぐ落ちる
	rain = emitter(emitterPart, {
		Texture = SPARK,
		Color = ColorSequence.new(rgb(200, 215, 235)),
		Size = NumberSequence.new(0.22),
		Squash = NumberSequence.new(2.6),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Transparency = NumberSequence.new(0.45),
		Lifetime = NumberRange.new(0.55, 0.7),
		Speed = NumberRange.new(95, 115),
		EmissionDirection = Enum.NormalId.Bottom,
		SpreadAngle = Vector2.new(4, 4),
		Rate = 650,
		LightEmission = 0.2,
	}),
	-- 雪：ゆっくり、ふわふわ
	snow = emitter(emitterPart, {
		Texture = SPARK,
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Size = NumberSequence.new(0.28),
		Transparency = fade(0.15, 0.3),
		Lifetime = NumberRange.new(5, 7),
		Speed = NumberRange.new(7, 11),
		EmissionDirection = Enum.NormalId.Bottom,
		SpreadAngle = Vector2.new(25, 25),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
		Rate = 70,
		LightEmission = 0.4,
		Drag = 0.3,
	}),
	-- ふぶき（雪原で 雨の天気のとき）
	blizzard = emitter(emitterPart, {
		Texture = SPARK,
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Size = NumberSequence.new(0.3),
		Transparency = fade(0.1, 0.25),
		Lifetime = NumberRange.new(2.2, 3),
		Speed = NumberRange.new(22, 30),
		EmissionDirection = Enum.NormalId.Bottom,
		SpreadAngle = Vector2.new(20, 20),
		Acceleration = Vector3.new(14, 0, 4),
		Rate = 380,
		LightEmission = 0.4,
	}),
	-- 砂ぼこり（砂漠）
	sand = emitter(lowPart, {
		Texture = SMOKE,
		Color = ColorSequence.new(rgb(225, 195, 140)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 7) }),
		Transparency = fade(0.9, 0.94),
		Lifetime = NumberRange.new(4, 6),
		Speed = NumberRange.new(6, 12),
		EmissionDirection = Enum.NormalId.Right,
		SpreadAngle = Vector2.new(15, 6),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-20, 20),
		Rate = 9,
	}),
	-- 火の粉（火山）：下から上へ ゆらゆら
	embers = emitter(lowPart, {
		Texture = SPARK,
		Color = ColorSequence.new(rgb(255, 170, 60), rgb(255, 60, 20)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = fade(0, 0.2),
		Lifetime = NumberRange.new(3, 5),
		Speed = NumberRange.new(3, 8),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(40, 40),
		Acceleration = Vector3.new(2, 3, 0),
		Rate = 45,
		LightEmission = 1,
		LightInfluence = 0,
	}),
	-- 火山灰
	ash = emitter(emitterPart, {
		Texture = SMOKE,
		Color = ColorSequence.new(rgb(70, 62, 60)),
		Size = NumberSequence.new(0.5),
		Transparency = fade(0.5, 0.7),
		Lifetime = NumberRange.new(6, 8),
		Speed = NumberRange.new(5, 8),
		EmissionDirection = Enum.NormalId.Bottom,
		SpreadAngle = Vector2.new(30, 30),
		Rotation = NumberRange.new(0, 360),
		Rate = 30,
	}),
	-- 花粉・たねの綿毛（草原の昼）
	pollen = emitter(lowPart, {
		Texture = SPARK,
		Color = ColorSequence.new(rgb(255, 250, 215)),
		Size = NumberSequence.new(0.14),
		Transparency = fade(0.35, 0.5),
		Lifetime = NumberRange.new(5, 8),
		Speed = NumberRange.new(0.5, 2),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0.6, 0.2, 0.3),
		Rate = 14,
		LightEmission = 0.5,
	}),
	-- ほたる（草原の夜）
	fireflies = emitter(lowPart, {
		Texture = SPARK,
		Color = ColorSequence.new(rgb(200, 255, 120)),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.5, 0.3),
			NumberSequenceKeypoint.new(1, 0.1),
		}),
		Transparency = fade(0, 0.1),
		Lifetime = NumberRange.new(3, 6),
		Speed = NumberRange.new(0.5, 2.5),
		SpreadAngle = Vector2.new(180, 180),
		Rate = 10,
		LightEmission = 1,
		LightInfluence = 0,
	}),
	-- 星くず（星空）
	stardust = emitter(lowPart, {
		Texture = SPARK,
		Color = ColorSequence.new(rgb(190, 200, 255), rgb(255, 255, 255)),
		Size = NumberSequence.new(0.2),
		Transparency = fade(0.1, 0.3),
		Lifetime = NumberRange.new(4, 7),
		Speed = NumberRange.new(0.3, 1.5),
		SpreadAngle = Vector2.new(180, 180),
		Rate = 12,
		LightEmission = 1,
		LightInfluence = 0,
	}),
	-- 風に流れる葉っぱ（おいかぜ）
	leaves = emitter(lowPart, {
		Texture = SPARK,
		Color = ColorSequence.new(rgb(150, 205, 110), rgb(225, 200, 110)),
		Size = NumberSequence.new(0.24),
		Squash = NumberSequence.new(-0.6),
		Transparency = fade(0.1, 0.2),
		Lifetime = NumberRange.new(2.5, 4),
		Speed = NumberRange.new(26, 38),
		EmissionDirection = Enum.NormalId.Front,
		SpreadAngle = Vector2.new(12, 10),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-260, 260),
		Rate = 22,
	}),
}

--------------------------------------------------------------------------------
-- にじ（天気が「にじ」のとき、道の先の空に かかる）
--------------------------------------------------------------------------------

local rainbow = Instance.new("Model")
rainbow.Name = "Rainbow"
do
	local colors = {
		rgb(255, 70, 70),
		rgb(255, 150, 50),
		rgb(255, 230, 70),
		rgb(90, 220, 110),
		rgb(70, 170, 255),
		rgb(90, 100, 235),
		rgb(170, 90, 230),
	}
	local SEGMENTS = 28
	for band, color in colors do
		local radius = 430 - band * 7
		for i = 0, SEGMENTS - 1 do
			local a0 = math.pi * i / SEGMENTS
			local a1 = math.pi * (i + 1) / SEGMENTS
			local p0 = Vector3.new(math.cos(a0) * radius, math.sin(a0) * radius, 0)
			local p1 = Vector3.new(math.cos(a1) * radius, math.sin(a1) * radius, 0)
			local part = Instance.new("Part")
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Material = Enum.Material.Neon
			part.Color = color
			part.Transparency = 1
			part.Size = Vector3.new((p1 - p0).Magnitude + 0.5, 7, 1)
			part.CFrame = CFrame.new((p0 + p1) / 2) * CFrame.Angles(0, 0, math.atan2(p1.Y - p0.Y, p1.X - p0.X))
			part.Parent = rainbow
		end
	end
	rainbow.Parent = workspace
end
local rainbowShown = false
local function showRainbow(show: boolean)
	if show == rainbowShown then
		return
	end
	rainbowShown = show
	local info = TweenInfo.new(4, Enum.EasingStyle.Sine)
	for _, part in rainbow:GetChildren() do
		TweenService:Create(part, info, { Transparency = if show then 0.78 else 1 }):Play()
	end
end

--------------------------------------------------------------------------------
-- 時刻と天気から、明るさを決める
--------------------------------------------------------------------------------

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- 0 = 夜、1 = 昼（朝 5〜8時に明るくなり、夕方 16.5〜19.5時に暗くなる）
local function dayAmount(clock: number): number
	return smooth((clock - 5) / 3) * (1 - smooth((clock - 16.5) / 3))
end
-- 朝やけ・夕やけの強さ（0〜1）
local function glowAmount(clock: number): number
	local dawn = 1 - math.min(1, math.abs(clock - 6.3) / 1.6)
	local dusk = 1 - math.min(1, math.abs(clock - 17.8) / 1.8)
	return math.max(0, dawn, dusk)
end

type Sky = { dim: number, density: number, haze: number, cover: number, saturation: number, glare: number }
local SKIES: { [string]: Sky } = {
	sunny = { dim = 1, density = 0, haze = 0, cover = 0.48, saturation = 0.03, glare = 0.35 },
	rain = { dim = 0.62, density = 0.14, haze = 0.8, cover = 0.92, saturation = -0.12, glare = 0 },
	wind = { dim = 0.95, density = -0.03, haze = -0.2, cover = 0.62, saturation = 0.02, glare = 0.3 },
	fog = { dim = 0.78, density = 0.3, haze = 1.6, cover = 0.8, saturation = -0.15, glare = 0 },
	storm = { dim = 0.45, density = 0.18, haze = 1, cover = 1, saturation = -0.18, glare = 0 },
	rainbow = { dim = 1.05, density = -0.02, haze = 0, cover = 0.42, saturation = 0.14, glare = 0.45 },
}

local clouds: Clouds? = nil
local function findClouds(): Clouds?
	if not clouds or not clouds.Parent then
		clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	end
	return clouds
end

local shownClock = Lighting.ClockTime
local flashUntil = 0
local nextFlash = os.clock() + 8
local activeEmitters: { [string]: boolean } = {}

local function setEmitters(wanted: { [string]: boolean })
	for name, e in EMITTERS do
		local on = wanted[name] == true
		if activeEmitters[name] ~= on then
			activeEmitters[name] = on
			e.Enabled = on
		end
	end
end

local function update(dt: number, retarget: boolean)
	local camera = workspace.CurrentCamera
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not camera or not root then
		return
	end
	local now = workspace:GetServerTimeNow()
	local placeName = placeAt(root.Position)
	local place = PLACES[placeName] or PLACES.hub
	local weather = Config.weatherAt(now)
	local sky = if place.noRain then SKIES.sunny else (SKIES[weather.id] or SKIES.sunny)

	-- 時刻：近いほうへ なめらかに進める（1秒に 3時間ぶんまで）
	local target = place.clock or Config.clockAt(now)
	local diff = (target - shownClock + 12) % 24 - 12
	shownClock = (shownClock + math.clamp(diff, -3 * dt, 3 * dt)) % 24
	Lighting.ClockTime = shownClock

	-- 舞うものの板を、カメラについて行かせる
	local focus = camera.CFrame.Position
	emitterPart.CFrame = CFrame.new(focus + Vector3.new(0, 38, 0))
	lowPart.CFrame = CFrame.new(root.Position + Vector3.new(0, 5, 0))
	rainbow:PivotTo(CFrame.new(root.Position.X * 0.2, -30, root.Position.Z - 620))

	if not retarget then
		return
	end

	local day = dayAmount(shownClock)
	local glow = glowAmount(shownClock)
	local wet = weather.id == "rain" or weather.id == "storm"
	local outside = not place.noRain

	-- 舞うもの
	local wanted: { [string]: boolean } = {}
	if outside and wet then
		wanted[if place.snow then "blizzard" else "rain"] = true
	end
	if outside and weather.id == "wind" then
		wanted.leaves = true
	end
	if place.particles == "embers" then
		wanted.embers = true
		wanted.ash = true
	elseif place.particles == "snow" then
		wanted.snow = not wanted.blizzard
	elseif place.particles == "sand" then
		wanted.sand = not wet
	elseif place.particles == "stardust" then
		wanted.stardust = true
	elseif place.particles == "pollen" and not wet then
		-- 昼は花粉、夜は ほたる
		if day > 0.5 then
			wanted.pollen = true
		elseif day < 0.2 then
			wanted.fireflies = true
		end
	end
	setEmitters(wanted)
	showRainbow(outside and weather.id == "rainbow" and day > 0.4)

	-- 明るさ
	local info = TweenInfo.new(1.2, Enum.EasingStyle.Linear)
	local nightAmbient = rgb(62, 68, 112)
	local dayAmbient = rgb(128, 128, 140)
	local warm = rgb(255, 170, 110)
	local ambient = nightAmbient:Lerp(dayAmbient, day):Lerp(warm, glow * 0.35)
	local brightness = (0.9 + 1.9 * day) * (if day > 0.3 then sky.dim else 1)
	local flashing = os.clock() < flashUntil
	TweenService:Create(Lighting, info, {
		Brightness = brightness,
		OutdoorAmbient = ambient,
		Ambient = rgb(20, 20, 30):Lerp(rgb(40, 40, 46), day),
		ColorShift_Top = rgb(255, 255, 255):Lerp(warm, glow * 0.6),
		ExposureCompensation = if flashing then 0.9 else 0.05 - 0.25 * (1 - sky.dim),
		EnvironmentDiffuseScale = 0.55 + 0.45 * day,
		EnvironmentSpecularScale = 0.6 + 0.4 * day,
	}):Play()
	if atmosphere then
		local air = place.air:Lerp(rgb(40, 46, 86), (1 - day) * 0.75):Lerp(rgb(255, 180, 130), glow * 0.45)
		local decay = place.decay:Lerp(rgb(24, 26, 60), (1 - day) * 0.75):Lerp(rgb(200, 90, 70), glow * 0.4)
		if sky.dim < 0.9 then
			air = air:Lerp(rgb(150, 156, 168), 0.5)
			decay = decay:Lerp(rgb(80, 86, 100), 0.5)
		end
		TweenService:Create(atmosphere, info, {
			Color = air,
			Decay = decay,
			Density = math.clamp(place.density + sky.density, 0.15, 0.78),
			Haze = math.max(0, place.haze + sky.haze),
			Glare = sky.glare * day + glow * 0.4,
		}):Play()
	end
	if colorCorrection then
		TweenService:Create(colorCorrection, info, {
			TintColor = place.tint:Lerp(rgb(190, 205, 255), (1 - day) * 0.5):Lerp(rgb(255, 222, 196), glow * 0.5),
			Saturation = place.saturation + sky.saturation,
			Contrast = 0.1 + 0.05 * (1 - sky.dim),
		}):Play()
	end
	if sunRays then
		TweenService:Create(sunRays, info, { Intensity = (0.05 + 0.14 * glow) * sky.dim * math.max(day, glow) }):Play()
	end
	local c = findClouds()
	if c then
		TweenService:Create(c, TweenInfo.new(6, Enum.EasingStyle.Sine), {
			Cover = sky.cover,
			Density = if sky.dim < 0.7 then 0.85 else 0.6,
			Color = rgb(255, 255, 255)
				:Lerp(rgb(110, 116, 130), math.clamp((1 - sky.dim) * 1.6, 0, 1))
				:Lerp(rgb(70, 76, 110), (1 - day) * 0.7)
				:Lerp(rgb(255, 190, 150), glow * 0.5),
		}):Play()
	end

	-- かみなり：ときどき 空が ピカッと光る
	if outside and weather.id == "storm" and os.clock() > nextFlash then
		nextFlash = os.clock() + 5 + math.random() * 9
		flashUntil = os.clock() + 0.18
		Lighting.ExposureCompensation = 1.2
	end
end

-- 0.1秒ごとに 時刻と位置、1秒ごとに 明るさ
task.spawn(function()
	local n = 0
	local last = os.clock()
	while true do
		task.wait(0.1)
		local t = os.clock()
		n += 1
		update(t - last, n % 10 == 1)
		last = t
	end
end)
