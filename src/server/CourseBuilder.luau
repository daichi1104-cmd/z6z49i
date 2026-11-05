-- アスレチックコースを Workspace に組み立てるモジュール
-- コースは +Z 方向へ進み、ステージごとに少しずつ高くなります。

local CollectionService = game:GetService("CollectionService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))

local CourseBuilder = {}

local PAD_SIZE = 12
local LAVA_COLOR = Color3.fromRGB(255, 85, 0)

local course: Folder
local checkpoints: { [number]: BasePart } = {}

local function stageColor(stage: number): Color3
	return Color3.fromHSV(((stage - 1) / Config.TotalStages) * 0.8, 0.65, 0.95)
end

local function makePart(props: { [string]: any }, parent: Instance?): BasePart
	local className = props.ClassName or "Part"
	local part = Instance.new(className) :: BasePart
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		if key ~= "ClassName" then
			(part :: any)[key] = value
		end
	end
	part.Parent = parent or course
	return part
end

-- 上面の中心が topCenter になるように置く
local function block(size: Vector3, topCenter: Vector3, props: { [string]: any }?): BasePart
	local p = table.clone(props or {})
	p.Size = size
	p.CFrame = CFrame.new(topCenter - Vector3.new(0, size.Y / 2, 0))
	return makePart(p)
end

local function makeKill(part: BasePart)
	part.Material = Enum.Material.Neon
	part.Color = LAVA_COLOR
	CollectionService:AddTag(part, "Kill")
end

------------------------------------------------------------------------
-- 障害物。どれも start（前の足場の奥のふち、上面の高さ）を受け取り、
-- 次のチェックポイントを置く位置（手前のふち）を返します。
------------------------------------------------------------------------

local Obstacles = {}

function Obstacles.jumps(start: Vector3, color: Color3, count: number, gap: number, rise: number, size: number): Vector3
	local pos = start
	for i = 1, count do
		local x = (i % 2 == 0) and 2 or -2
		pos = Vector3.new(start.X + x, pos.Y + rise, pos.Z + gap + size / 2)
		block(Vector3.new(size, 1, size), pos, { Color = color })
		pos += Vector3.new(0, 0, size / 2)
	end
	return Vector3.new(start.X, pos.Y, pos.Z + gap)
end

function Obstacles.beam(start: Vector3, color: Color3, length: number, width: number): Vector3
	block(Vector3.new(width, 1, length), start + Vector3.new(0, 0, length / 2), {
		Color = color,
		Material = Enum.Material.Wood,
	})
	return start + Vector3.new(0, 0, length)
end

function Obstacles.lava(start: Vector3, color: Color3, length: number): Vector3
	local floor = block(Vector3.new(14, 1, length), start + Vector3.new(0, -3, length / 2), {})
	makeKill(floor)
	local z = 4
	local i = 0
	while z < length - 2 do
		i += 1
		local x = math.sin(i * 1.7) * 4
		block(Vector3.new(3, 1, 3), start + Vector3.new(x, 0, z), { Color = color })
		z += 6
	end
	return start + Vector3.new(0, 0, length)
end

function Obstacles.mover(start: Vector3, color: Color3, distance: number): Vector3
	local platformSize = Vector3.new(7, 1, 7)
	local from = start + Vector3.new(0, 0, 1 + platformSize.Z / 2)

	-- 見えない土台（固定）
	local anchor = block(Vector3.new(1, 1, 1), from - Vector3.new(0, 2, 0), {
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
	})
	-- 動く足場（物理で動かすので乗っているプレイヤーも一緒に運ばれる）
	local platform = block(platformSize, from, {
		Anchored = false,
		Color = color,
		Material = Enum.Material.Metal,
		CustomPhysicalProperties = PhysicalProperties.new(0.7, 1, 0, 1, 1),
	})

	-- アタッチメントの X 軸を +Z 方向に向ける
	local axisCFrame = CFrame.Angles(0, -math.pi / 2, 0)
	local a0 = Instance.new("Attachment")
	a0.CFrame = CFrame.new(0, 2, 0) * axisCFrame
	a0.Parent = anchor
	local a1 = Instance.new("Attachment")
	a1.CFrame = axisCFrame
	a1.Parent = platform

	local slider = Instance.new("PrismaticConstraint")
	slider.Attachment0 = a0
	slider.Attachment1 = a1
	slider.ActuatorType = Enum.ActuatorType.Servo
	slider.ServoMaxForce = 1e7
	slider.Speed = 9
	slider.LimitsEnabled = true
	slider.LowerLimit = 0
	slider.UpperLimit = distance
	slider.TargetPosition = 0
	slider.Parent = platform

	platform:SetNetworkOwner(nil)

	task.spawn(function()
		while platform.Parent do
			task.wait(distance / slider.Speed + 1.5)
			slider.TargetPosition = (slider.TargetPosition == 0) and distance or 0
		end
	end)

	return start + Vector3.new(0, 0, 1 + platformSize.Z + distance + 1)
end

function Obstacles.truss(start: Vector3, _color: Color3, height: number): Vector3
	makePart({
		ClassName = "TrussPart",
		Size = Vector3.new(2, height, 2),
		CFrame = CFrame.new(start + Vector3.new(0, height / 2, 1)),
		Color = Color3.fromRGB(160, 160, 170),
		Material = Enum.Material.Metal,
	})
	return start + Vector3.new(0, height, 2)
end

function Obstacles.spinner(start: Vector3, color: Color3, speed: number): Vector3
	local size = 18
	local center = start + Vector3.new(0, 0, 3 + size / 2)
	block(Vector3.new(size, 1, size), center, { Color = color })

	local pivot = center + Vector3.new(0, 2, 0)
	local post = makePart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, 1.5, 1.5),
		CFrame = CFrame.new(pivot) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(60, 60, 60),
	})

	local bar = makePart({
		Size = Vector3.new(size - 2, 1, 1),
		CFrame = CFrame.new(pivot),
		Anchored = false,
		CanCollide = false,
		Massless = true,
	})
	makeKill(bar)

	-- アタッチメントの X 軸を上向きにして、縦軸で回転させる
	local axis = CFrame.new(pivot) * CFrame.Angles(0, 0, math.pi / 2)
	local a0 = Instance.new("Attachment")
	a0.Parent = post
	a0.WorldCFrame = axis
	local a1 = Instance.new("Attachment")
	a1.Parent = bar
	a1.WorldCFrame = axis

	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = a0
	hinge.Attachment1 = a1
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.AngularVelocity = speed
	hinge.MotorMaxTorque = 1e8
	hinge.MotorMaxAcceleration = math.huge
	hinge.Parent = bar

	bar:SetNetworkOwner(nil)

	return start + Vector3.new(0, 0, 3 + size + 3)
end

function Obstacles.vanish(start: Vector3, _color: Color3, count: number): Vector3
	local pos = start
	for _ = 1, count do
		pos += Vector3.new(0, 0, 3 + 3)
		local tile = block(Vector3.new(6, 1, 6), pos, {
			Color = Color3.fromRGB(90, 200, 255),
			Material = Enum.Material.Glass,
			Transparency = 0.2,
		})
		CollectionService:AddTag(tile, "Vanish")
		pos += Vector3.new(0, 0, 3)
	end
	return pos + Vector3.new(0, 0, 3)
end

------------------------------------------------------------------------
-- ステージ構成
------------------------------------------------------------------------

local STAGES = {
	function(s, c)
		return Obstacles.jumps(s, c, 5, 4, 0.5, 5)
	end,
	function(s, c)
		return Obstacles.beam(s, c, 30, 1.5)
	end,
	function(s, c)
		return Obstacles.lava(s, c, 34)
	end,
	function(s, c)
		return Obstacles.mover(s, c, 22)
	end,
	function(s, c)
		return Obstacles.truss(s, c, 20)
	end,
	function(s, c)
		return Obstacles.jumps(s, c, 6, 6, 1.5, 4)
	end,
	function(s, c)
		return Obstacles.spinner(s, c, 1.6)
	end,
	function(s, c)
		return Obstacles.vanish(s, c, 6)
	end,
	function(s, c)
		local e = Obstacles.lava(s, c, 28)
		return Obstacles.beam(e, c, 20, 1)
	end,
	function(s, c)
		local e = Obstacles.mover(s, c, 18)
		block(Vector3.new(6, 1, 6), e + Vector3.new(0, 0, 3), { Color = c })
		return Obstacles.mover(e + Vector3.new(0, 0, 6), c, 18)
	end,
	function(s, c)
		local e = Obstacles.truss(s, c, 30)
		block(Vector3.new(6, 1, 6), e + Vector3.new(0, 0, 3), { Color = c })
		return Obstacles.jumps(e + Vector3.new(0, 0, 6), c, 5, 6, 0, 3)
	end,
	function(s, c)
		local e = Obstacles.spinner(s, c, 2.2)
		return Obstacles.spinner(e - Vector3.new(0, 0, 3), c, -2.8)
	end,
}

local function makeLabel(pad: BasePart, text: string)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = pad
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
end

local function makeCheckpoint(stage: number, nearEdge: Vector3): BasePart
	local isGoal = stage == Config.TotalStages
	local pad = block(Vector3.new(PAD_SIZE, 1, PAD_SIZE), nearEdge + Vector3.new(0, 0, PAD_SIZE / 2), {
		Name = "Checkpoint" .. stage,
		Color = isGoal and Color3.fromRGB(255, 205, 40) or stageColor(stage + 1),
		Material = isGoal and Enum.Material.Neon or Enum.Material.SmoothPlastic,
	})
	pad:SetAttribute("Stage", stage)
	CollectionService:AddTag(pad, "Checkpoint")
	makeLabel(pad, isGoal and "GOAL!" or tostring(stage))
	checkpoints[stage] = pad
	return pad
end

function CourseBuilder.build(): Folder
	course = Instance.new("Folder")
	course.Name = "Course"
	course.Parent = workspace

	-- スタート地点
	local spawn = makePart({
		ClassName = "SpawnLocation",
		Name = "Start",
		Size = Vector3.new(16, 1, 16),
		CFrame = CFrame.new(0, -0.5, 0),
		Color = stageColor(1),
		Duration = 0,
	}) :: SpawnLocation
	makeLabel(spawn, "START")
	checkpoints[0] = spawn

	local edge = Vector3.new(0, 0, 8)
	for stage, buildStage in STAGES do
		local nearEdge = buildStage(edge, stageColor(stage))
		makeCheckpoint(stage, nearEdge)
		edge = nearEdge + Vector3.new(0, 0, PAD_SIZE)
	end

	-- 下に広がる溶岩の海（落ちたらチェックポイントへ戻る）
	local lengthZ = edge.Z + 120
	local sea = block(Vector3.new(500, 1, lengthZ), Vector3.new(0, -25, edge.Z / 2), { Name = "LavaSea" })
	makeKill(sea)
	sea.Material = Enum.Material.CrackedLava

	return course
end

function CourseBuilder.getCheckpoint(stage: number): BasePart
	return checkpoints[math.clamp(stage, 0, Config.TotalStages)]
end

return CourseBuilder
