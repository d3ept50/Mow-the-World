-- Player input that the server acts on: sprint (hold Shift or Ctrl) and click / tap to
-- mow faster. The client only reports "sprinting" or "clicked"; the server decides the
-- walk speed and does all the cutting.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")

local Input = RS:WaitForChild("Remotes"):WaitForChild("Input")

local Controls = {}

local SPRINT_KEYS = {
	[Enum.KeyCode.LeftShift] = true,
	[Enum.KeyCode.RightShift] = true,
	[Enum.KeyCode.LeftControl] = true,
	[Enum.KeyCode.RightControl] = true,
	[Enum.KeyCode.ButtonL3] = true, -- gamepad: click the left stick
}
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

function Controls.init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if SPRINT_KEYS[input.KeyCode] then
			if not UserInputService:GetFocusedTextBox() then
				held[input.KeyCode] = true
				setSprint(true)
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
