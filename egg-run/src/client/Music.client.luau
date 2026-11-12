-- BGM（自分の画面だけ）。Sounds.Music の曲を 順番に ずっと流す
-- 曲が読みこめないときは 次の曲へ進む

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Sounds"))

local music = Instance.new("Sound")
music.Name = "Music"
music.Volume = Sounds.MusicVolume
music.Parent = SoundService

local index = math.random(1, #Sounds.Music)
while true do
	local track = Sounds.Music[index]
	index = index % #Sounds.Music + 1
	music.SoundId = "rbxassetid://" .. track.id
	-- 読みこみを 10秒まで待つ
	local waited = 0
	while not music.IsLoaded and waited < 10 do
		waited += task.wait(0.25)
	end
	if music.IsLoaded and music.TimeLength > 0 then
		music:Play()
		-- 曲が終わるまで待つ（止まってしまったときのために、長さ + 5秒で 次へ）
		local limit = music.TimeLength + 5
		local played = 0
		while music.IsPlaying and played < limit do
			played += task.wait(0.5)
		end
		music:Stop()
		task.wait(1.5)
	else
		task.wait(2)
	end
end
