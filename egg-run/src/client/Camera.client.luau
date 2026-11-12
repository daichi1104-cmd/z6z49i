-- カメラ：はじめから 引きで見えるようにする
-- ・ゲームに入ったとき、カメラを 後ろに引いた位置から始める（START）
-- ・そのあとは ホイール（スマホは 2本指でつまむ）で 近く 〜 とても遠く（300）まで 自由に変えられる
--   いちばん遠くの数字は default.project.json の StarterPlayer.CameraMaxZoomDistance

local Players = game:GetService("Players")

local START = 40 -- はじめの カメラのきょり（ふつうは 12.5）

local player = Players.LocalPlayer
local minZoom = player.CameraMinZoomDistance

if not player.Character then
	player.CharacterAdded:Wait()
end
-- 近づける下限を いったん START にすると、カメラが そこまで下がる。すぐ元にもどす
player.CameraMinZoomDistance = START
task.wait(0.5)
player.CameraMinZoomDistance = minZoom
