-- Visible equipment on characters: mower in hand / pushed, rideable vehicles, title tag.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Models = require(RS.Shared.Models)
local Game = require(RS.Shared.Config.Game)
local Data = require(script.Parent.Data)

local Character = {}
local CF = CFrame.new

-- Welds a model to a body part. cf is where the model's pivot goes, in world space.
local function attach(model, bodyPart, cf, char)
	model:PivotTo(cf)
	Models.weld(model)
	local root = model.PrimaryPart
	root.Anchored = false
	local w = Instance.new("WeldConstraint")
	w.Part0 = bodyPart
	w.Part1 = root
	w.Parent = root
	model.Parent = char
end

-- Roblox's own poses, played over the walking animation:
--   hold = "holding a tool", the right arm held out in front (scissors)
--   sit  = sitting, for mowers the player rides
local POSES = {
	hold = { [Enum.HumanoidRigType.R15] = "rbxassetid://507768375", [Enum.HumanoidRigType.R6] = "rbxassetid://182393478" },
	sit = { [Enum.HumanoidRigType.R15] = "rbxassetid://2506281703", [Enum.HumanoidRigType.R6] = "rbxassetid://178130996" },
}
local poseTracks = setmetatable({}, { __mode = "k" }) -- [character] = { [pose] = AnimationTrack }

-- Plays one pose (or none, when pose is nil) and stops the others.
local function setPose(char, hum, pose)
	local tracks = poseTracks[char]
	if not tracks then
		tracks = {}
		poseTracks[char] = tracks
	end
	if pose and not tracks[pose] then
		local animator = hum:FindFirstChildOfClass("Animator")
		local id = POSES[pose][hum.RigType]
		if animator and id then
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			local ok, loaded = pcall(function()
				return animator:LoadAnimation(anim)
			end)
			if ok and loaded then
				loaded.Priority = Enum.AnimationPriority.Action
				loaded.Looped = true
				tracks[pose] = loaded
			end
		end
	end
	for name, track in pairs(tracks) do
		if name == pose then
			if not track.IsPlaying then
				track:Play(0.15)
			end
		elseif track.IsPlaying then
			track:Stop(0.15)
		end
	end
end

-- Sitting on a mower: the seat is usually higher or lower than the player's hips, so the
-- character's hip height is changed to match it and put back when they get off.
-- height = how far the bottom of the root part should be above the ground, or nil to restore.
local function setHip(hum, height)
	local last = hum:GetAttribute("RideHip")
	if not last or math.abs(hum.HipHeight - last) > 0.01 then
		-- the current value was not set here (first time, or Roblox rescaled the avatar)
		hum:SetAttribute("BaseHip", hum.HipHeight)
	end
	local target = hum:GetAttribute("BaseHip")
	if height then
		-- R15 hip height is measured from the ground; R6 is an offset on top of 2-stud legs
		target = hum.RigType == Enum.HumanoidRigType.R15 and height or height - 2
	end
	hum.HipHeight = target
	hum:SetAttribute("RideHip", target)
end

-- Where the ground is, measured down from the middle of the root part.
local function groundOffset(hum, hrp)
	if hum.RigType == Enum.HumanoidRigType.R15 then
		return -(hum.HipHeight + hrp.Size.Y / 2)
	end
	return -(3 + hum.HipHeight)
end

-- Where the scissors are gripped, in the model's own space before scaling: between the
-- two handle blocks (see Models.mower).
local SCISSOR_GRIP = Vector3.new(0, 1.04, 0.1)

-- Puts hand-held scissors in the right hand, lined up like a Roblox tool. Returns false
-- if this character has no right hand to hold them.
local function holdScissors(model, char, hum)
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	local grip = hand and hand:FindFirstChild("RightGripAttachment")
	if not grip then
		return false
	end
	attach(model, hand, grip.WorldCFrame * CF(-SCISSOR_GRIP * model:GetScale()), char)
	return true
end

local function updateTag(player, char, pr)
	local head = char:FindFirstChild("Head")
	if not head then
		return
	end
	local tag = head:FindFirstChild("MowTag")
	if not tag then
		tag = Instance.new("BillboardGui")
		tag.Name = "MowTag"
		tag.Size = UDim2.fromScale(9, 1.3)
		tag.StudsOffset = Vector3.new(0, 2.7, 0)
		tag.MaxDistance = 90
		tag.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.Name = "Text"
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.TextScaled = true
		t.Font = Enum.Font.FredokaOne
		t.TextColor3 = Color3.fromRGB(255, 220, 90)
		t.TextStrokeTransparency = 0.3
		t.Parent = tag
		tag.Parent = head
	end
	local text = pr.title ~= "" and ("[" .. pr.title .. "] ") or ""
	if pr.rebirths > 0 then
		text ..= "🔁 " .. pr.rebirths
	end
	tag.Text.Text = text
end

function Character.updateSpeed(player: Player)
	local pr = Data.get(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not pr or not hum then
		return
	end
	local v = Data.ridingVehicle(player)
	local speed = (v and v.speed or 20) * Game.Speed.mult * (Data.boost(pr, "speed") and 1.5 or 1)
	if player:GetAttribute("Sprinting") then
		speed *= Game.Sprint.mult
	end
	if math.abs(hum.WalkSpeed - speed) > 0.01 then
		hum.WalkSpeed = speed
	end
end

-- Puts both hands on a mower's grip points: the handle of a pushed mower, or the steering
-- wheel of a ridden one. An IKControl bends each arm so the hand stays on its grip point
-- whatever animation is playing. (R15 avatars only.)
local GRIPS = {
	{ grip = "GripL", hand = "LeftHand", arm = "LeftUpperArm" },
	{ grip = "GripR", hand = "RightHand", arm = "RightUpperArm" },
}

local function releaseHandle(hum)
	for _, c in ipairs(hum:GetChildren()) do
		if c:IsA("IKControl") and c.Name == "MowerGrip" then
			c:Destroy()
		end
	end
end

local function holdHandle(model, char, hum)
	local root = model.PrimaryPart
	for _, g in ipairs(GRIPS) do
		local target = root and root:FindFirstChild(g.grip)
		local hand, arm = char:FindFirstChild(g.hand), char:FindFirstChild(g.arm)
		if target and hand and arm then
			local ik = Instance.new("IKControl")
			ik.Name = "MowerGrip"
			ik.Type = Enum.IKControlType.Position
			ik.ChainRoot = arm
			ik.EndEffector = hand
			ik.Target = target
			ik.SmoothTime = 0
			ik.Parent = hum
		end
	end
end

function Character.refresh(player: Player)
	local pr = Data.get(player)
	local char = player.Character
	if not pr or not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then
		return
	end
	for _, n in ipairs({ "Mower", "Vehicle" }) do
		local old = char:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end
	releaseHandle(hum)
	local v = Data.ridingVehicle(player)
	local model, seat
	if not v then
		local id = Data.ownsMower(player, pr.equippedMower) and pr.equippedMower or "Scissors"
		model = Models.mower(id)
		seat = model:GetAttribute("RideSeat") -- set on mowers the player sits on
	end
	-- sitting puts the bottom of the root part about half a stud above the seat cushion
	setHip(hum, seat and seat.Y + 0.5 or nil)
	local ground = groundOffset(hum, hrp)
	local pose = nil
	if v then
		attach(Models.vehicle(v.id), hrp, hrp.CFrame * CF(0, ground, 0), char)
	elseif model:GetAttribute("Kind") == "scissors" then
		if holdScissors(model, char, hum) then
			pose = "hold"
		else
			attach(model, hrp, hrp.CFrame * CF(0.95, -1.5, -0.7), char)
		end
	elseif seat then
		-- ridden: the seat goes under the player, who sits with both hands on the wheel
		attach(model, hrp, hrp.CFrame * CF(-seat.X, ground, -seat.Z), char)
		holdHandle(model, char, hum)
		pose = "sit"
	else
		-- pushed: the mower goes in front, with both hands on its handle
		attach(model, hrp, hrp.CFrame * CF(0, ground, -1.3), char)
		holdHandle(model, char, hum)
	end
	setPose(char, hum, pose)
	Character.updateSpeed(player)
	updateTag(player, char, pr)
end

function Character.init()
	local function onPlayer(player)
		player:SetAttribute("Riding", false)
		player:SetAttribute("BossArea", 0)
		player:SetAttribute("Sprinting", false)
		local function onChar(char)
			player:SetAttribute("Riding", false)
			char:WaitForChild("HumanoidRootPart", 10)
			char:WaitForChild("Humanoid", 10)
			task.wait(0.3)
			if player.Character == char then
				Character.refresh(player)
			end
		end
		player.CharacterAdded:Connect(onChar)
		player.CharacterAppearanceLoaded:Connect(function(char)
			task.wait(0.2)
			if player.Character == char then
				Character.refresh(player)
			end
		end)
		if player.Character then
			task.spawn(onChar, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Data.onLoaded(function(player)
		Character.refresh(player)
	end)
	RS.Remotes.Input.OnServerEvent:Connect(function(player, kind, on)
		if kind == "sprint" then
			player:SetAttribute("Sprinting", on == true)
			Character.updateSpeed(player)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(2)
			for _, p in ipairs(Players:GetPlayers()) do
				Character.updateSpeed(p)
			end
		end
	end)
end

return Character
