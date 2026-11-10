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

-- Roblox's own "holding a tool" pose: the right arm held out in front.
local HOLD_ANIM = {
	[Enum.HumanoidRigType.R15] = "rbxassetid://507768375",
	[Enum.HumanoidRigType.R6] = "rbxassetid://182393478",
}
local holdTracks = setmetatable({}, { __mode = "k" }) -- [character] = AnimationTrack

local function setHolding(char, hum, on)
	local track = holdTracks[char]
	if on and not track then
		local animator = hum:FindFirstChildOfClass("Animator")
		local id = HOLD_ANIM[hum.RigType]
		if animator and id then
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			local ok, loaded = pcall(function()
				return animator:LoadAnimation(anim)
			end)
			if ok and loaded then
				loaded.Priority = Enum.AnimationPriority.Action
				loaded.Looped = true
				holdTracks[char] = loaded
				track = loaded
			end
		end
	end
	if track then
		if on and not track.IsPlaying then
			track:Play(0.15)
		elseif not on and track.IsPlaying then
			track:Stop(0.15)
		end
	end
end

-- Where the scissors are gripped, in the model's own space before scaling: between the
-- two handle blocks (see Models.mower).
local SCISSOR_GRIP = Vector3.new(0, 1.04, 0.1)

-- Puts hand-held scissors in the right hand, lined up like a Roblox tool, and raises the
-- arm. Returns false if this character has no right hand to hold them.
local function holdScissors(model, char, hum)
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	local grip = hand and hand:FindFirstChild("RightGripAttachment")
	if not grip then
		return false
	end
	attach(model, hand, grip.WorldCFrame * CF(-SCISSOR_GRIP * model:GetScale()), char)
	setHolding(char, hum, true)
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
	local ground = hum.RigType == Enum.HumanoidRigType.R15 and -(hum.HipHeight + hrp.Size.Y / 2) or -3
	local v = Data.ridingVehicle(player)
	local holding = false
	if v then
		attach(Models.vehicle(v.id), hrp, hrp.CFrame * CF(0, ground, 0), char)
	else
		local id = Data.ownsMower(player, pr.equippedMower) and pr.equippedMower or "Scissors"
		local model = Models.mower(id)
		if model:GetAttribute("Kind") == "scissors" then
			holding = holdScissors(model, char, hum)
			if not holding then
				attach(model, hrp, hrp.CFrame * CF(0.95, -1.5, -0.7), char)
			end
		else
			attach(model, hrp, hrp.CFrame * CF(0, ground, -1.3), char)
		end
	end
	if not holding then
		setHolding(char, hum, false)
	end
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
