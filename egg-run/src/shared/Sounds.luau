-- 音（ぜんぶ Roblox 公式が出している 無料の音。番号は Roblox の音の一覧で確かめたもの）
-- ・Sounds.ui(name)        ：自分にだけ聞こえる音（ボタン・お知らせ など。画面側で使う）
-- ・Sounds.on(part, name)  ：その部品から聞こえる音（近くの人みんなに聞こえる）
-- ・Sounds.at(position, name)：その場所から聞こえる音
-- ・Sounds.forToast(message, good)：お知らせの文の 先頭の絵文字から、合う音の名前を返す

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local Sounds = {}

type Def = { id: number, volume: number, speed: number?, vary: number? }

-- vary：鳴らすたびに 高さを 少しだけ変える（同じ音が続いても 機械っぽくならない）
local DEFS: { [string]: Def } = {
	-- 画面の音
	open = { id = 17208408337, volume = 0.5 }, -- 画面を開く
	back = { id = 17208186900, volume = 0.5 }, -- 画面を閉じる
	info = { id = 17208204604, volume = 0.35 }, -- ふつうのお知らせ
	good = { id = 17208361335, volume = 0.5 }, -- うれしいお知らせ
	bad = { id = 17208353912, volume = 0.55 }, -- できない・しっぱい
	buy = { id = 17208380755, volume = 0.6 }, -- 買った
	equip = { id = 17208323435, volume = 0.6 }, -- そうびした
	pickup = { id = 17208319162, volume = 0.6 }, -- たまごを拾った
	coin = { id = 127645268874265, volume = 0.6 }, -- コインをもらった
	fanfare = { id = 12222253, volume = 0.6 }, -- やったー！
	stinger = { id = 15675043410, volume = 0.6 }, -- 実績・新記録
	levelup = { id = 16480578169, volume = 0.45 }, -- レベルアップ
	rebirth = { id = 17208327798, volume = 0.8 }, -- 転生
	pop = { id = 15675055424, volume = 0.7 }, -- たまごが かえった
	lucky = { id = 16480570986, volume = 0.6 }, -- あたりゾーン・れんぞく配達
	train = { id = 16480580213, volume = 0.12, vary = 0.12 }, -- トレーニングで スピードが増えた
	warp = { id = 15675024286, volume = 0.6 }, -- ワープ
	hurt = { id = 12221984, volume = 0.7, vary = 0.1 }, -- 敵に はじき飛ばされた

	-- 世界の音
	slash = { id = 12222216, volume = 0.6, vary = 0.12 }, -- 剣をふる
	lunge = { id = 12222208, volume = 0.6, vary = 0.1 }, -- 突く
	swoosh = { id = 12222200, volume = 0.6, vary = 0.15 }, -- ハンマー・魔法の玉
	bow = { id = 12222103, volume = 0.6, vary = 0.1 }, -- 弓を放つ
	hit = { id = 12222046, volume = 0.55, vary = 0.15 }, -- 武器が当たった
	defeat = { id = 12222152, volume = 0.6, vary = 0.15 }, -- 敵をたおした
	boom = { id = 3149249837, volume = 0.9 }, -- ボスをたおした・必殺
	roar = { id = 9120031442, volume = 0.8 }, -- ドラゴンの わざ
	chest = { id = 16480575861, volume = 0.7 }, -- 宝箱

	-- 天気の音
	thunder = { id = 12222030, volume = 0.7, vary = 0.15 },
	lightning = { id = 12222019, volume = 0.6, vary = 0.1 },
	rain = { id = 1516791621, volume = 0.35 }, -- ずっと鳴らす 雨の音
}

local function url(def: Def): string
	return "rbxassetid://" .. def.id
end

local function tune(sound: Sound, def: Def)
	local speed = def.speed or 1
	if def.vary then
		speed *= 1 + (math.random() * 2 - 1) * def.vary
	end
	sound.PlaybackSpeed = speed
end

local function make(def: Def, parent: Instance, name: string): Sound
	local sound = Instance.new("Sound")
	sound.Name = "Sfx_" .. name
	sound.SoundId = url(def)
	sound.Volume = def.volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 12
	sound.RollOffMaxDistance = 110
	sound.Parent = parent
	return sound
end

-- 自分にだけ聞こえる音。同じ音は 0.07秒より 短い間では 重ねない（うるさくならないように）
local uiSounds: { [string]: Sound } = {}
local uiLast: { [string]: number } = {}
function Sounds.ui(name: string)
	local def = DEFS[name]
	if not def then
		return
	end
	local now = os.clock()
	if now - (uiLast[name] or 0) < 0.07 then
		return
	end
	uiLast[name] = now
	local sound = uiSounds[name]
	if not sound then
		sound = make(def, SoundService, name)
		uiSounds[name] = sound
	end
	tune(sound, def)
	sound:Play()
end

-- ずっと鳴らす音（雨など）を作って返す。音の大きさは 呼ぶ側で 少しずつ変える
function Sounds.loop(name: string): Sound
	local def = DEFS[name]
	local sound = make(def, SoundService, name)
	sound.Looped = true
	sound.Volume = 0
	return sound
end

function Sounds.volumeOf(name: string): number
	return DEFS[name].volume
end

-- 部品から鳴らす（その部品に 同じ音が もうあれば 使い回す）
function Sounds.on(part: Instance?, name: string)
	local def = DEFS[name]
	if not def or not part then
		return
	end
	local sound = part:FindFirstChild("Sfx_" .. name) :: Sound?
	if not sound then
		sound = make(def, part, name)
	end
	tune(sound :: Sound, def)(sound :: Sound):Play()
end

-- 場所から鳴らす（見えない点を置いて、鳴り終わったら消す）
function Sounds.at(position: Vector3, name: string)
	local def = DEFS[name]
	if not def then
		return
	end
	local point = Instance.new("Attachment")
	point.Name = "SfxPoint"
	point.Parent = workspace.Terrain
	point.WorldPosition = position
	local sound = make(def, point, name)
	tune(sound, def)
	sound:Play()
	Debris:AddItem(point, 8)
end

-- お知らせの 先頭の絵文字 → 音
local TOAST: { [string]: string } = {
	["🎉"] = "coin",
	["🪙"] = "coin",
	["🏆"] = "stinger",
	["🔓"] = "stinger",
	["⏱️"] = "stinger",
	["⬆️"] = "levelup",
	["🎯"] = "lucky",
	["🔥"] = "lucky",
	["🐣"] = "pop",
	["🛒"] = "buy",
	["🛡️"] = "equip",
	["💥"] = "bad",
	["💔"] = "bad",
	["⚠️"] = "bad",
	["🔒"] = "bad",
}

function Sounds.forToast(message: string, good: boolean?): string
	if good == false then
		return "bad"
	end
	for emoji, name in TOAST do
		if string.sub(message, 1, #emoji) == emoji then
			-- うれしい知らせでなければ（「まだ できない」など）ひかえめな音にする
			if good or name == "bad" then
				return name
			end
			return "info"
		end
	end
	if string.find(message, "ゲット", 1, true) then
		return "pickup"
	end
	if string.sub(message, 1, #"🥚") == "🥚" then
		return if string.find(message, "ません", 1, true) then "bad" else "pickup"
	end
	if string.sub(message, 1, #"🧰") == "🧰" then
		return if good then "fanfare" else "chest"
	end
	if string.sub(message, 1, #"⚔️") == "⚔️" then
		return if good then "coin" else "info"
	end
	return if good then "good" else "info"
end

return Sounds
