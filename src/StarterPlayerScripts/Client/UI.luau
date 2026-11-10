-- Small UI toolkit: instance helper, themed widgets, sounds and 3D item previews.
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")

local Game = require(RS.Shared.Config.Game)
local Models = require(RS.Shared.Models)

local UI = {}

UI.Theme = {
	bg = Color3.fromRGB(20, 23, 36),
	card = Color3.fromRGB(36, 42, 64),
	card2 = Color3.fromRGB(54, 62, 92),
	text = Color3.fromRGB(255, 255, 255),
	dim = Color3.fromRGB(182, 190, 215),
	green = Color3.fromRGB(64, 205, 100),
	red = Color3.fromRGB(238, 76, 84),
	gold = Color3.fromRGB(255, 200, 60),
	blue = Color3.fromRGB(64, 150, 255),
	purple = Color3.fromRGB(172, 96, 250),
	grey = Color3.fromRGB(98, 104, 128),
	cyan = Color3.fromRGB(70, 215, 245),
	orange = Color3.fromRGB(255, 150, 50),
	pink = Color3.fromRGB(255, 105, 170),
	teal = Color3.fromRGB(45, 195, 175),
	ink = Color3.fromRGB(12, 13, 22),
}
local T = UI.Theme
UI.settings = { music = true, sfx = true, otherWorkers = true, effects = true }

function UI.new(class: string, props, children)
	local inst = Instance.new(class)
	local parent
	if props then
		for k, v in pairs(props) do
			if k == "Parent" then
				parent = v
			else
				inst[k] = v
			end
		end
	end
	if children then
		for _, c in ipairs(children) do
			c.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
local new = UI.new

function UI.corner(r: number)
	return new("UICorner", { CornerRadius = UDim.new(0, r) })
end

function UI.stroke(color: Color3, thickness: number?)
	return new("UIStroke", { Color = color, Thickness = thickness or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

-- vertical shading: lighter at the top, darker at the bottom (multiplies the background colour)
function UI.gradient(strength: number?)
	local s = strength or 0.28
	return new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1 - s, 1 - s, 1 - s)) })
end

-- soft drop shadow behind a frame (sibling placed just under it)
function UI.shadow(target: GuiObject, spread: number?)
	local sp = spread or 6
	local sh = new("Frame", {
		Name = "Shadow",
		AnchorPoint = target.AnchorPoint,
		Position = target.Position + UDim2.fromOffset(0, sp),
		Size = target.Size,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		ZIndex = math.max(target.ZIndex - 1, 0),
		Visible = target.Visible,
		Parent = target.Parent,
	})
	local c = target:FindFirstChildOfClass("UICorner")
	if c then
		c:Clone().Parent = sh
	end
	return sh
end

-- Text label with sensible defaults. Extra key: Outline = true adds a dark text outline.
function UI.text(props)
	local outline = props.Outline
	props.Outline = nil
	local base = {
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextColor3 = T.text,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for k, v in pairs(props) do
		base[k] = v
	end
	local label = new("TextLabel", base)
	if outline then
		new("UIStroke", { Color = T.ink, Thickness = 2.2, Parent = label })
	end
	return label
end

---------------------------------------------------------------- sounds
local sounds = {}
for name, id in pairs(Game.Sounds) do
	local s = Instance.new("Sound")
	s.Name = "MTW_" .. name
	s.SoundId = id
	s.Volume = name == "music" and 0.22 or 0.5
	s.Looped = name == "music"
	s.Parent = SoundService
	sounds[name] = s
end
local lastPlayed = {}

function UI.sfx(name: string, pitch: number?, minGap: number?)
	local s = sounds[name]
	if not s or not UI.settings.sfx then
		return
	end
	local now = os.clock()
	if minGap and now - (lastPlayed[name] or 0) < minGap then
		return
	end
	lastPlayed[name] = now
	s.PlaybackSpeed = pitch or 1
	SoundService:PlayLocalSound(s)
end

function UI.music(on: boolean)
	local s = sounds.music
	if on and not s.IsPlaying then
		s:Play()
	elseif not on and s.IsPlaying then
		s:Stop()
	end
end

---------------------------------------------------------------- buttons
function UI.button(props, onClick)
	local color = props.BackgroundColor3 or T.green
	local enabled = props.Enabled ~= false
	props.Enabled = nil
	local base = {
		BackgroundColor3 = enabled and color or T.grey,
		Font = Enum.Font.FredokaOne,
		TextColor3 = T.text,
		TextSize = 18,
		AutoButtonColor = enabled,
		Active = enabled,
		Text = "",
	}
	for k, v in pairs(props) do
		if k ~= "BackgroundColor3" and k ~= "Corner" then
			base[k] = v
		end
	end
	base.AutoButtonColor = false
	local b = new("TextButton", base, { UI.corner(props.Corner or 12), UI.gradient(enabled and 0.3 or 0.15) })
	new("UIStroke", { Color = T.ink, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Transparency = 0.15, Parent = b })
	new("UIStroke", { Color = T.ink, Thickness = 1.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Transparency = 0.25, Parent = b })
	-- glossy highlight along the top edge
	new("Frame", { Name = "Shine", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 3), Size = UDim2.new(1, -12, 0.32, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = enabled and 0.82 or 0.93, BorderSizePixel = 0, ZIndex = b.ZIndex, Active = false, Parent = b }, { UI.corner(math.max((props.Corner or 12) - 4, 4)) })
	if enabled then
		local scale = new("UIScale", { Parent = b })
		local function to(s)
			TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = s }):Play()
		end
		b.MouseEnter:Connect(function()
			to(1.05)
		end)
		b.MouseLeave:Connect(function()
			to(1)
		end)
		b.MouseButton1Down:Connect(function()
			to(0.94)
		end)
		b.MouseButton1Up:Connect(function()
			to(1.05)
		end)
		b.SelectionGained:Connect(function()
			to(1.05)
		end)
		b.SelectionLost:Connect(function()
			to(1)
		end)
	end
	if enabled and onClick then
		b.Activated:Connect(function()
			UI.sfx("click")
			onClick(b)
		end)
	end
	return b
end

function UI.tween(inst, t, goal, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

function UI.bar(props, fillColor)
	local frame = new("Frame", props, { UI.corner(10), UI.stroke(T.ink, 2.5) })
	frame.BackgroundColor3 = Color3.fromRGB(14, 16, 26)
	frame.BackgroundTransparency = 0.1
	local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = fillColor, BorderSizePixel = 0, Parent = frame }, { UI.corner(10), UI.gradient(0.35) })
	local label = UI.text({ Name = "Label", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 15, ZIndex = 2, Outline = true, Parent = frame })
	return frame, fill, label
end

---------------------------------------------------------------- 3D previews
local vpCache = {}

local function frameModel(vp, model)
	local cf, size = model:GetBoundingBox()
	local cam = Instance.new("Camera")
	cam.FieldOfView = 35
	local dist = size.Magnitude * 1.15
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(-0.75, 0.45, -1).Unit * dist, cf.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam
	return cam
end
UI.frameModel = frameModel

-- kind = "mower" | "vehicle" | "crate" | "worker". Cached: one preview per item.
function UI.viewport(kind: string, id: string)
	local key = kind .. ":" .. id
	local vp = vpCache[key]
	if not vp then
		vp = new("ViewportFrame", { BackgroundTransparency = 1, Ambient = Color3.fromRGB(190, 190, 190), LightColor = Color3.fromRGB(255, 255, 255), LightDirection = Vector3.new(0.5, -1, 0.6) })
		local model = Models[kind](id)
		model.Parent = vp
		frameModel(vp, model)
		vpCache[key] = vp
	end
	vp.Size = UDim2.fromScale(1, 1)
	vp.Position = UDim2.fromScale(0, 0)
	return vp
end

-- Detach cached previews before a panel is cleared so they are not destroyed.
function UI.releaseViewports()
	for _, vp in pairs(vpCache) do
		vp.Parent = nil
	end
end

return UI
