-- ルームランナーのベルトの白い線を、後ろへ流す（自分の画面の中だけで動かすので、通信はふえない）

local RunService = game:GetService("RunService")

local SPEED = 10 -- ベルトの速さ（サーバーの Main と同じ）

local world = workspace:WaitForChild("World", 60)
if not world then
	return
end

type Machine = { belt: BasePart, stripes: { BasePart }, offsets: { number }, y: number }
local machines: { Machine } = {}

local function watch(model: Instance)
	if not model:IsA("Model") or not model.Name:match("^Treadmill") then
		return
	end
	local belt = model:WaitForChild("Belt", 30) :: BasePart?
	if not belt then
		return
	end
	task.wait(1) -- 線の部品が とどくのを待つ
	local machine: Machine = { belt = belt, stripes = {}, offsets = {}, y = 0 }
	for _, child in model:GetChildren() do
		if child.Name == "Stripe" and child:IsA("BasePart") then
			local rel = belt.CFrame:PointToObjectSpace(child.Position)
			table.insert(machine.stripes, child)
			table.insert(machine.offsets, rel.Z)
			machine.y = rel.Y
		end
	end
	table.insert(machines, machine)
end

for _, child in world:GetChildren() do
	task.spawn(watch, child)
end
world.ChildAdded:Connect(watch)

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for _, m in machines do
		local length = m.belt.Size.Z - 0.6
		for i, stripe in m.stripes do
			-- ベルトの長さの中を、ぐるぐる回る
			local z = (m.offsets[i] + length / 2 + t * SPEED) % length - length / 2
			stripe.CFrame = m.belt.CFrame * CFrame.new(0, m.y, z)
		end
	end
end)
