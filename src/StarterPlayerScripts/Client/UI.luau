-- Small UI toolkit: instance helper, themed widgets, sounds and 3D item previews.
-- Every menu, the HUD and the pop-ups are built from these pieces, so the whole look of the
-- interface (colours, corners, outlines, shading) is set here.
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")

local Game = require(RS.Shared.Config.Game)
local Models = require(RS.Shared.Models)

local UI = {}

UI.Theme = {
	bg = Color3.fromRGB(23, 27, 48), -- panels and HUD backgrounds
	card = Color3.fromRGB(39, 46, 80), -- rows and tiles inside a panel
	card2 = Color3.fromRGB(62, 72, 118), -- raised parts of a card, neutral buttons
	text = Color3.fromRGB(255, 255, 255),
	dim = Color3.fromRGB(184, 194, 228),
	green = Color3.fromRGB(72, 212, 104),
	red = Color3.fromRGB(240, 80, 90),
	gold = Color3.fromRGB(255, 202, 64),
	blue = Color3.fromRGB(70, 150, 255),
	purple = Color3.fromRGB(168, 100, 255),
	grey = Color3.fromRGB(102, 110, 140),
	cyan = Color3.fromRGB(66, 212, 246),
	orange = Color3.fromRGB(255, 150, 52),
	pink = Color3.fromRGB(255, 106, 174),
	teal = Color3.fromRGB(44, 200, 178),
	ink = Color3.fromRGB(11, 13, 26), -- outlines and text strokes
}
local T = UI.Theme
UI.Font = Enum.Font.FredokaOne -- headings, numbers and buttons
UI.BodyFont = Enum.Font.GothamMedium -- longer descriptions
UI.settings = { music = true, sfx = true, otherWorkers = true, effects = true, arrow = true }

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

-- fully rounded ends (a pill or a circle)
function UI.round()
	return new("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function UI.stroke(color: Color3, thickness: number?, transparency: number?)
	return new("UIStroke", { Color = color, Thickness = thickness or 2, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

function UI.padding(x: number, y: number?)
	local py = y or x
	return new("UIPadding", { PaddingLeft = UDim.new(0, x), PaddingRight = UDim.new(0, x), PaddingTop = UDim.new(0, py), PaddingBottom = UDim.new(0, py) })
end

-- vertical shading: lighter at the top, darker at the bottom (multiplies the background colour)
function UI.gradient(strength: number?)
	local s = strength or 0.28
	return new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1 - s, 1 - s, 1 - s)) })
end

-- The shading on buttons and bar fills: a bright top half and a deeper bottom edge, so they
-- look raised and glossy. The colour it is used on is lightened first (see UI.button).
local function gloss()
	return new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.48, Color3.fromRGB(236, 236, 236)),
			ColorSequenceKeypoint.new(0.52, Color3.fromRGB(214, 214, 214)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(172, 172, 172)),
		}),
	})
end
UI.gloss = gloss

-- A dark rounded panel with a soft top-to-bottom shade and an outline: the base of every
-- HUD widget and pop-up card. accent colours the outline.
function UI.panel(props, accent: Color3?, radius: number?)
	local base = { BackgroundColor3 = T.bg, BackgroundTransparency = 0.04, BorderSizePixel = 0 }
	for k, v in pairs(props) do
		base[k] = v
	end
	return new("Frame", base, { UI.corner(radius or 16), UI.gradient(0.32), UI.stroke(accent or T.ink, 2.5) })
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
		Font = UI.Font,
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
function UI.tween(inst, t, goal, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

-- A chunky, glossy button with a dark outline. props are TextButton properties, plus
-- Enabled = false (greyed out, does nothing) and Corner = radius. The first UIStroke inside
-- is the outline, so callers can recolour it (the worker cards do).
function UI.button(props, onClick)
	local color = props.BackgroundColor3 or T.green
	local enabled = props.Enabled ~= false
	local corner = props.Corner or 12
	props.Enabled = nil
	local base = {
		Font = UI.Font,
		TextColor3 = T.text,
		TextSize = 18,
		Text = "",
	}
	for k, v in pairs(props) do
		if k ~= "BackgroundColor3" and k ~= "Corner" then
			base[k] = v
		end
	end
	base.AutoButtonColor = false
	base.Active = enabled
	base.BorderSizePixel = 0
	base.BackgroundColor3 = enabled and color:Lerp(Color3.new(1, 1, 1), 0.14) or T.grey
	if not enabled then
		base.TextTransparency = 0.3
	end
	local b = new("TextButton", base, { UI.corner(corner), gloss() })
	new("UIStroke", { Color = T.ink, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
	new("UIStroke", { Color = T.ink, Thickness = 1.8, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Transparency = 0.15, Parent = b })
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
			to(0.93)
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

-- A progress bar: a dark rounded track, a glossy fill and a centred label.
-- Returns the track, the fill (resize it with Size = fromScale(ratio, 1)) and the label.
function UI.bar(props, fillColor)
	local frame = new("Frame", props, { UI.round(), UI.stroke(T.ink, 2.5) })
	frame.BackgroundColor3 = Color3.fromRGB(14, 16, 30)
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = fillColor, BorderSizePixel = 0, Parent = frame }, { UI.round(), gloss() })
	local label = UI.text({ Name = "Label", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 15, ZIndex = 2, Outline = true, Parent = frame })
	return frame, fill, label
end

-- A round coloured badge with an emoji in it (currency icons, the bag icon...).
function UI.badge(props, emoji: string, color: Color3, textSize: number?)
	local base = { BackgroundColor3 = color, BorderSizePixel = 0 }
	for k, v in pairs(props) do
		base[k] = v
	end
	local f = new("Frame", base, { UI.round(), gloss(), UI.stroke(T.ink, 2.5) })
	UI.text({ Name = "Icon", Text = emoji, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = textSize or 22, ZIndex = (base.ZIndex or 1) + 1, Parent = f })
	return f
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
		vp = new("ViewportFrame", { BackgroundTransparency = 1, Ambient = Color3.fromRGB(200, 200, 200), LightColor = Color3.fromRGB(255, 255, 255), LightDirection = Vector3.new(0.5, -1, 0.6) })
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
