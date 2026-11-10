-- Player input: sprint (hold Shift), click / tap to mow faster, and Ctrl to lock the
-- camera behind the character. The client only reports "sprinting" or "clicked"; the server decides the
-- walk speed and does all the cutting.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")

local Input = RS:WaitForChild("Remotes"):WaitForChild("Input")
local Menus = require(script.Parent.Menus)

local Controls = {}

local SPRINT_KEYS = {
	[Enum.KeyCode.LeftShift] = true,
	[Enum.KeyCode.RightShift] = true,
	[Enum.KeyCode.ButtonL3] = true, -- gamepad: click the left stick
}
-- Shift is used for sprinting, so the game has its own camera lock on Ctrl. It behaves
-- like Roblox's Shift Lock but works for every player, whatever their Roblox settings.
local LOCK_KEYS = {
	[Enum.KeyCode.LeftControl] = true,
	[Enum.KeyCode.RightControl] = true,
}
local LOCK_OFFSET = Vector3.new(1.75, 0, 0) -- camera sits over the right shoulder
local LOCK_STEP = "MTW_CameraLock"
local locked = false
local BASE_FOV, SPRINT_FOV = 70, 78
local CLICK_GAP = 0.15 -- seconds between "cut" messages while clicking or holding

local held = {}
local sprinting = false
local pressing = 0 -- how many mouse buttons / touches are down on the world (not on UI)
local lastCut = 0

local function setSprint(on: boolean)
	if on == sprinting then
		return
	end
	sprinting = on
	Input:FireServer("sprint", on)
	local cam = workspace.CurrentCamera
	if cam then
		TweenService:Create(cam, TweenInfo.new(0.25, Enum.EasingStyle.Sine), { FieldOfView = on and SPRINT_FOV or BASE_FOV }):Play()
	end
end

local function sendCut()
	local now = os.clock()
	if now - lastCut >= CLICK_GAP then
		lastCut = now
		Input:FireServer("cut")
	end
end

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

---------------------------------------------------------------- camera lock (Ctrl)
local function lockParts()
	local char = Players.LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return hum, root
end

-- Runs every frame, just after Roblox's camera update, while the lock is on.
local function lockStep()
	local hum, root = lockParts()
	if Menus.isOpen() then
		-- free the cursor so menus can be clicked
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		if hum then
			hum.AutoRotate = true
		end
		return
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	local cam = workspace.CurrentCamera
	if hum and root and cam and hum.Health > 0 then
		hum.AutoRotate = false
		hum.CameraOffset = LOCK_OFFSET
		local look = cam.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
		end
	end
end

local function setLock(on: boolean)
	if on == locked then
		return
	end
	locked = on
	if on then
		RunService:BindToRenderStep(LOCK_STEP, Enum.RenderPriority.Camera.Value + 1, lockStep)
	else
		RunService:UnbindFromRenderStep(LOCK_STEP)
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		local hum = lockParts()
		if hum then
			hum.AutoRotate = true
			hum.CameraOffset = Vector3.zero
		end
	end
end

-- Roblox's own Shift Lock uses Shift, which is now sprint, so switch it off for this game.
local function disableRobloxShiftLock()
	pcall(function()
		Players.LocalPlayer.DevEnableMouseLock = false
	end)
	local node: Instance? = Players.LocalPlayer:WaitForChild("PlayerScripts", 10)
	for _, name in ipairs({ "PlayerModule", "CameraModule", "MouseLockController", "BoundKeys" }) do
		node = node and node:WaitForChild(name, 10)
	end
	if node and node:IsA("StringValue") then
		node.Value = ""
	end
end

function Controls.init()
	task.spawn(disableRobloxShiftLock)
	UserInputService.InputBegan:Connect(function(input, processed)
		if SPRINT_KEYS[input.KeyCode] then
			if not UserInputService:GetFocusedTextBox() then
				held[input.KeyCode] = true
				setSprint(true)
			end
		elseif LOCK_KEYS[input.KeyCode] then
			if not UserInputService:GetFocusedTextBox() then
				setLock(not locked)
			end
		elseif isPress(input) and not processed then
			pressing += 1
			sendCut()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if SPRINT_KEYS[input.KeyCode] then
			held[input.KeyCode] = nil
			setSprint(next(held) ~= nil)
		elseif isPress(input) then
			pressing = math.max(pressing - 1, 0)
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		table.clear(held)
		pressing = 0
		setSprint(false)
	end)
	-- holding the button down keeps the boost going
	RunService.Heartbeat:Connect(function()
		if pressing > 0 then
			sendCut()
		end
	end)
	-- a new character starts at normal speed on the server, so report again if still held
	Players.LocalPlayer.CharacterAdded:Connect(function()
		if sprinting then
			Input:FireServer("sprint", true)
		end
	end)
end

return Controls
