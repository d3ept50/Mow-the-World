-- HUD, notifications and the panel framework. Panel contents live in the Panels module.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local Config = RS.Shared.Config
local Items = require(Config.Items)
local W = require(Config.Workers)
local Game = require(Config.Game)
local Areas = require(Config.Areas)
local Util = require(RS.Shared.Util)
local State = require(script.Parent.State)
local UI = require(script.Parent.UI)

local player = Players.LocalPlayer
local new, T, fmt = UI.new, UI.Theme, Util.fmt
local CENTER = Enum.TextXAlignment.Center

local Menus = { renderers = {}, titles = {} }
local root, toastRoot, modal, body, titleLabel
local refs = {}
local current
local renderQueued = false

-- Buttons that are always on screen: { icon, label, panel }.
Menus.MENU = {
	{ "👷", "Workers", "Workers" }, { "🧭", "Teleport", "Teleport" }, { "🎁", "Daily", "Daily" },
	{ "🛒", "Shop", "Robux" }, { "📋", "Menu", "More" },
}
-- Everything else lives behind the Menu button (and at the shops in the marketplace).
Menus.MORE = {
	{ "📦", "Crates", "Crates" }, { "✂️", "Mowers", "Mowers" }, { "🎒", "Bags", "Bags" },
	{ "🔁", "Rebirth", "Rebirth" }, { "💎", "Diamonds", "Diamonds" },
	{ "🏆", "Awards", "Achievements" }, { "🧳", "Items", "Inventory" }, { "⚙️", "Settings", "Settings" },
}

local MENU_COLORS = {
	Workers = T.blue, Crates = T.orange, Mowers = T.red, Bags = T.teal, Vehicles = Color3.fromRGB(110, 124, 165), Rebirth = T.purple,
	Daily = T.pink, Achievements = T.gold, Inventory = Color3.fromRGB(96, 170, 110), Robux = T.green, Diamonds = T.cyan, Settings = T.grey,
	Teleport = T.teal, More = T.card2,
}
Menus.COLORS = MENU_COLORS

---------------------------------------------------------------- notifications & banners
local NOTE_COLORS = { info = T.text, good = T.green, bad = T.red, big = T.gold, rebirth = T.purple }

function Menus.notify(text: string, kind: string?)
	kind = kind or "info"
	local color = NOTE_COLORS[kind] or T.text
	local big = kind == "big" or kind == "rebirth"
	local holder = refs.notes
	local kids = {}
	for _, c in ipairs(holder:GetChildren()) do
		if c:IsA("Frame") then
			table.insert(kids, c)
		end
	end
	if #kids >= 4 then
		kids[1]:Destroy()
	end
	refs.noteOrder = (refs.noteOrder or 0) + 1
	local f = new("Frame", { Size = UDim2.new(1, 0, 0, big and 44 or 36), BackgroundColor3 = T.bg, BackgroundTransparency = 0.05, LayoutOrder = refs.noteOrder, Parent = holder }, { UI.corner(18), UI.stroke(color, 2.5), UI.gradient(0.35) })
	local pop = new("UIScale", { Scale = 0.6, Parent = f })
	UI.tween(pop, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	new("TextLabel", { Text = text, Size = UDim2.new(1, -20, 1, -8), Position = UDim2.fromOffset(10, 4), BackgroundTransparency = 1, Font = Enum.Font.FredokaOne, TextColor3 = color, TextScaled = true, Parent = f }, { new("UITextSizeConstraint", { MaxTextSize = big and 21 or 17 }) })
	if kind == "bad" then
		UI.sfx("error", 0.6, 0.3)
	elseif kind == "good" then
		UI.sfx("buy", 1, 0.1)
	elseif big then
		UI.sfx("win", 1, 1)
	end
	task.delay((big or kind == "bad") and 5.5 or 3.6, function()
		if f.Parent then
			f:Destroy()
		end
	end)
	if kind == "rebirth" then
		Menus.banner("🔁 REBIRTH!", T.purple)
		Menus.confetti()
	end
end

function Menus.banner(text: string, color: Color3?)
	local label = UI.text({ Text = text, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(900, 80), TextSize = 54, TextXAlignment = CENTER, TextColor3 = color or T.gold, Outline = true, ZIndex = 40, Parent = root })
	local sc = new("UIScale", { Scale = 0.2, Parent = label })
	UI.tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(2.2, function()
		UI.tween(label, 0.5, { TextTransparency = 1 })
		task.wait(0.55)
		label:Destroy()
	end)
end

function Menus.confetti()
	if not UI.settings.effects then
		return
	end
	local rng = Random.new()
	for _ = 1, 45 do
		local c = new("Frame", { Size = UDim2.fromOffset(rng:NextInteger(8, 14), rng:NextInteger(10, 18)), Position = UDim2.new(rng:NextNumber(), 0, 0, -30), Rotation = rng:NextInteger(0, 360), BackgroundColor3 = Color3.fromHSV(rng:NextNumber(), 0.75, 1), BorderSizePixel = 0, ZIndex = 39, Parent = root })
		local t = rng:NextNumber(1.4, 2.6)
		UI.tween(c, t, { Position = UDim2.new(c.Position.X.Scale + rng:NextNumber(-0.08, 0.08), 0, 1, 40), Rotation = c.Rotation + rng:NextInteger(-360, 360) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(t, function()
			c:Destroy()
		end)
	end
end

---------------------------------------------------------------- panel framework
local IGNORE = { bagCount = true, bagValue = true, progress = true, stats = true }

local function render()
	renderQueued = false
	if not current then
		return
	end
	local scrollPos
	local old = body:FindFirstChild("Scroll", true)
	if old then
		scrollPos = old.CanvasPosition
	end
	UI.releaseViewports()
	body:ClearAllChildren()
	titleLabel.Text = Menus.titles[current.name] or current.name
	local fn = Menus.renderers[current.name]
	if fn then
		fn(body, current.ctx)
	end
	local scroll = body:FindFirstChild("Scroll", true)
	if scroll and scrollPos then
		scroll.CanvasPosition = scrollPos
	end
end

function Menus.refresh()
	if current and not renderQueued then
		renderQueued = true
		task.defer(render)
	end
end

function Menus.open(name: string, ctx)
	if current and current.name == name and not ctx then
		Menus.close()
		return
	end
	if not current then
		UI.sfx("open")
	end
	current = { name = name, ctx = ctx or {} }
	modal.Visible = true
	refs.backdrop.Visible = true
	refs.modalShadow.Visible = true
	refs.header.BackgroundColor3 = MENU_COLORS[name] or T.card2
	refs.modalScale.Scale = 0.85
	UI.tween(refs.modalScale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	render()
end

function Menus.close()
	if current then
		UI.sfx("close")
	end
	current = nil
	modal.Visible = false
	refs.backdrop.Visible = false
	refs.modalShadow.Visible = false
	UI.releaseViewports()
	body:ClearAllChildren()
end

-- The keyboard key that does the same as pressing the Ride button.
Menus.RIDE_KEY = Enum.KeyCode.J

-- Gets on or off the equipped vehicle, if the player has one (the Ride button is showing).
function Menus.toggleRide()
	if refs.ride and refs.ride.Visible then
		UI.sfx("click")
		State.action("ToggleRide")
	end
end

function Menus.isOpen(name: string?): boolean
	return current ~= nil and (name == nil or current.name == name)
end

-- shared widgets for panels
function Menus.scroller(parent, props)
	local base = { Name = "Scroll", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 8, ScrollBarImageColor3 = T.dim, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = parent }
	for k, v in pairs(props or {}) do
		base[k] = v
	end
	local s = new("ScrollingFrame", base)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = s })
	return s
end

-- Standard item row: icon box on the left, title + subtitle, action button on the right.
function Menus.row(parent, h: number, title: string, sub: string?, titleColor: Color3?)
	local r = new("Frame", { Name = title, Size = UDim2.new(1, -12, 0, h), BackgroundColor3 = T.card, Parent = parent }, { UI.corner(14), UI.gradient(0.22), new("UIStroke", { Color = T.card2, Thickness = 1.5, Transparency = 0.2 }) })
	local icon = new("Frame", { Name = "Icon", Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(70, 70), BackgroundColor3 = T.card2, Parent = r }, { UI.corner(12), new("UIStroke", { Color = T.ink, Thickness = 1.5, Transparency = 0.4 }) })
	UI.text({ Name = "Title", Text = title, Position = UDim2.fromOffset(90, 8), Size = UDim2.new(1, -270, 0, 26), TextSize = 21, TextColor3 = titleColor or T.text, Parent = r })
	local subLabel = UI.text({ Name = "Sub", Text = sub or "", Position = UDim2.fromOffset(90, 36), Size = UDim2.new(1, -270, 0, h - 44), TextSize = 14, Font = Enum.Font.GothamMedium, TextColor3 = T.dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, RichText = true, TextTruncate = Enum.TextTruncate.None, Parent = r })
	return r, icon, subLabel
end

function Menus.iconText(icon, emoji: string, color: Color3?)
	if color then
		icon.BackgroundColor3 = color
	end
	UI.text({ Text = emoji, Size = UDim2.fromScale(1, 1), TextXAlignment = CENTER, TextSize = 38, Parent = icon })
end

function Menus.rowButton(r, text: string, color: Color3, enabled: boolean, fn, y: number?, h: number?)
	return UI.button({ Name = text, Text = text, BackgroundColor3 = color, Enabled = enabled, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, y or 20), Size = UDim2.fromOffset(160, h or 46), TextSize = 17, Parent = r }, fn)
end

---------------------------------------------------------------- HUD widgets
local function pill(parent, icon, color)
	local f = new("Frame", { Size = UDim2.fromOffset(204, 42), BackgroundColor3 = T.bg, BackgroundTransparency = 0.05, Parent = parent }, { UI.corner(21), UI.stroke(color, 2.5), UI.gradient(0.4) })
	new("Frame", { Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = color, BackgroundTransparency = 0.72, Parent = f }, { UI.corner(17) })
	UI.text({ Text = icon, Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(34, 34), TextXAlignment = CENTER, TextSize = 21, Parent = f })
	return UI.text({ Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -54, 1, 0), TextSize = 22, TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.2), Text = "0", Outline = true, Parent = f })
end

local function chip(parent, text, color)
	local f = new("Frame", { Size = UDim2.fromOffset(210, 28), BackgroundColor3 = T.bg, BackgroundTransparency = 0.12, Parent = parent }, { UI.corner(14), UI.gradient(0.35), new("UIStroke", { Color = color or T.card2, Thickness = 1.5, Transparency = 0.45 }) })
	UI.text({ Text = text, Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -12, 1, 0), TextSize = 14, TextColor3 = color or T.text, Parent = f })
end

---------------------------------------------------------------- boss prompt, lobby and invites
-- The prompt shows when the player steps into a boss's circle (World tells us), and turns
-- into a waiting room after "Invite friends". Invited players get a separate invite card.
local prompt = { zone = nil, dismissed = false, lobby = nil, shown = nil }
local invite = nil -- { area, hostId, endsAt }

local function inFight(): boolean
	return (player:GetAttribute("BossFight") or 0) ~= 0
end

local function renderPrompt()
	local card = refs.prompt
	local lobby = prompt.lobby
	local area = lobby and lobby.area or (not prompt.dismissed and prompt.zone) or nil
	if inFight() or not area or not Areas.List[area] then
		card.Visible = false
		prompt.shown = nil
		return
	end
	local key = (lobby and "lobby" or "ask") .. area
	if prompt.shown == key then
		return
	end
	prompt.shown = key
	for _, c in ipairs(card:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local a = Areas.List[area]
	local B = a.boss
	UI.text({ Text = "💀 " .. B.name, Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -32, 0, 30), TextSize = 25, TextXAlignment = CENTER, Outline = true, Parent = card })
	local function button(i, n, text, color, fn)
		local w = (468 - 16 * 2 - 10 * (n - 1)) / n
		UI.button({ Name = text, Text = text, BackgroundColor3 = color, Position = UDim2.fromOffset(16 + (i - 1) * (w + 10), 96), Size = UDim2.fromOffset(w, 48), TextSize = 17, Parent = card }, fn)
	end
	if lobby then
		refs.promptInfo = UI.text({ Text = "", Position = UDim2.fromOffset(16, 42), Size = UDim2.new(1, -32, 0, 44), TextSize = 16, TextXAlignment = CENTER, TextColor3 = T.dim, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, Parent = card })
		button(1, 2, "▶ Start now", T.green, function()
			State.action("BossBegin")
		end)
		button(2, 2, "✖ Cancel", T.red, function()
			State.action("BossCancel")
		end)
	else
		refs.promptInfo = nil
		UI.text({ Text = "❤️ " .. fmt(B.hp) .. "   💵 $" .. fmt(B.cash) .. "   💎 " .. B.diamonds .. "\nYour workers fight for you. Weak workers get knocked out!", Position = UDim2.fromOffset(16, 42), Size = UDim2.new(1, -32, 0, 44), TextSize = 15, TextXAlignment = CENTER, TextColor3 = T.dim, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, Parent = card })
		button(1, 3, "⚔️ Solo", T.green, function()
			State.action("BossSolo", area)
		end)
		button(2, 3, "👥 Invite friends", T.blue, function()
			State.action("BossInvite", area)
		end)
		button(3, 3, "✖ Exit", T.red, function()
			prompt.dismissed = true
			renderPrompt()
		end)
	end
	card.Visible = true
	refs.promptScale.Scale = 0.8
	UI.tween(refs.promptScale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- Called by World: the boss circle the player is standing in (nil = none).
function Menus.setBossZone(areaId: number?)
	if areaId ~= prompt.zone then
		prompt.zone = areaId
		prompt.dismissed = false
		renderPrompt()
	end
end

-- The player's own invite lobby: nil when it is over.
function Menus.setLobby(areaId: number?, seconds: number?, joined: number?, total: number?)
	prompt.lobby = areaId and { area = areaId, endsAt = os.clock() + (seconds or 0), joined = joined or 0, total = total or 0 } or nil
	renderPrompt()
end

local function hideInvite()
	invite = nil
	refs.invite.Visible = false
end

function Menus.showInvite(areaId: number, hostId: number, hostName: string, seconds: number)
	local a = Areas.List[areaId]
	if not a or inFight() then
		return
	end
	invite = { area = areaId, hostId = hostId, endsAt = os.clock() + seconds }
	refs.inviteText.Text = "👥 " .. hostName .. " invites you to fight the " .. a.boss.name .. "!"
	refs.invite.Visible = true
	UI.sfx("boss", 1.4)
end

function Menus.endInvite(hostId: number?)
	if invite and (hostId == nil or invite.hostId == hostId) then
		hideInvite()
	end
end

local function answerInvite(accept: boolean)
	local it = invite
	if it then
		hideInvite()
		State.action("BossRespond", it.hostId, accept)
	end
end

---------------------------------------------------------------- HUD
local function buildHUD()
	local cur = new("Frame", { Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(204, 140), BackgroundTransparency = 1, Parent = root }, { new("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }) })
	refs.cash = pill(cur, "💵", T.green)
	refs.diamonds = pill(cur, "💎", T.cyan)
	refs.rebirths = pill(cur, "🔁", T.purple)
	refs.rebirthPill = refs.rebirths.Parent

	-- one short column of buttons; everything else is behind "Menu"
	local column = new("Frame", { Name = "Menu", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.56, 0), Size = UDim2.fromOffset(66, #Menus.MENU * 72), BackgroundTransparency = 1, Parent = root }, { new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
	for i, m in ipairs(Menus.MENU) do
		local b = UI.button({ Name = m[3], BackgroundColor3 = MENU_COLORS[m[3]] or T.card, LayoutOrder = i, Corner = 16, Size = UDim2.fromOffset(64, 64), Parent = column }, function()
			Menus.open(m[3])
		end)
		UI.text({ Text = m[1], Size = UDim2.new(1, 0, 0, 42), TextXAlignment = CENTER, TextSize = 28, ZIndex = 2, Parent = b })
		UI.text({ Text = m[2], Position = UDim2.new(0, 0, 1, -22), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = CENTER, TextSize = 12, Outline = true, ZIndex = 2, Parent = b })
		if m[3] == "Daily" then
			refs.dailyBadge = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 4, 0, -4), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = T.red, Visible = false, ZIndex = 3, Parent = b }, { UI.corner(8) })
		end
	end

	local bottom = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(400, 64), BackgroundTransparency = 1, Parent = root })
	refs.areaBar, refs.areaFill, refs.areaLabel = UI.bar({ Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 28), Parent = bottom }, T.green)
	refs.bagBar, refs.bagFill, refs.bagLabel = UI.bar({ Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 30), Parent = bottom }, T.blue)
	refs.ride = UI.button({ Text = "🚜\nRide", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0.5, 212, 1, -12), Size = UDim2.fromOffset(72, 64), TextSize = 16, BackgroundColor3 = T.blue, Visible = false, Parent = root }, function()
		State.action("ToggleRide")
	end)
	-- key hint badge on the corner of the Ride button
	local key = new("Frame", { Name = "Key", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 6, 0, -6), Size = UDim2.fromOffset(24, 24), BackgroundColor3 = T.ink, ZIndex = 3, Parent = refs.ride }, { UI.corner(7), UI.stroke(T.text, 1.5) })
	UI.text({ Text = Menus.RIDE_KEY.Name, Size = UDim2.fromScale(1, 1), TextXAlignment = CENTER, TextSize = 15, ZIndex = 4, Parent = key })

	local top = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(520, 56), BackgroundTransparency = 1, Parent = root })
	refs.area = UI.text({ Size = UDim2.new(1, 0, 0, 32), TextXAlignment = CENTER, TextSize = 30, Outline = true, Parent = top })
	refs.objective = UI.text({ Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = CENTER, TextSize = 16, TextColor3 = T.gold, Outline = true, Parent = top })

	refs.boss = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 66), Size = UDim2.fromOffset(480, 60), BackgroundColor3 = T.bg, BackgroundTransparency = 0.05, Visible = false, Parent = root }, { UI.corner(16), UI.stroke(T.red, 2.5), UI.gradient(0.35) })
	refs.bossName = UI.text({ Position = UDim2.fromOffset(12, 2), Size = UDim2.new(1, -24, 0, 24), TextSize = 19, Parent = refs.boss })
	refs.bossTime = UI.text({ Position = UDim2.fromOffset(12, 2), Size = UDim2.new(1, -24, 0, 24), TextSize = 17, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = T.gold, Parent = refs.boss })
	refs.bossBar, refs.bossFill, refs.bossLabel = UI.bar({ Position = UDim2.fromOffset(10, 28), Size = UDim2.new(1, -20, 0, 24), Parent = refs.boss }, T.red)
	UI.button({ Name = "Leave", Text = "🚪 Leave", BackgroundColor3 = T.grey, Position = UDim2.new(1, 10, 0, 8), Size = UDim2.fromOffset(92, 44), TextSize = 15, Parent = refs.boss }, function()
		State.action("BossLeave")
	end)

	-- active boosts only: worker details are in the Workers menu
	refs.side = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(210, 120), BackgroundTransparency = 1, Parent = root }, { new("UIListLayout", { Padding = UDim.new(0, 4) }) })

	refs.prompt = new("Frame", { Name = "BossPrompt", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -92), Size = UDim2.fromOffset(468, 156), BackgroundColor3 = T.bg, BackgroundTransparency = 0.03, Visible = false, ZIndex = 6, Parent = root }, { UI.corner(18), UI.stroke(T.red, 3), UI.gradient(0.3) })
	refs.promptScale = new("UIScale", { Parent = refs.prompt })

	-- invites sit on the toast layer so an open menu never hides them
	refs.invite = new("Frame", { Name = "BossInvite", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 300), Size = UDim2.fromOffset(440, 118), BackgroundColor3 = T.bg, BackgroundTransparency = 0.03, Visible = false, Parent = toastRoot }, { UI.corner(18), UI.stroke(T.blue, 3), UI.gradient(0.3) })
	refs.inviteText = UI.text({ Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 44), TextSize = 17, TextXAlignment = CENTER, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, Parent = refs.invite })
	refs.inviteJoin = UI.button({ Text = "✅ Join", BackgroundColor3 = T.green, Position = UDim2.fromOffset(14, 60), Size = UDim2.fromOffset(200, 46), TextSize = 17, Parent = refs.invite }, function()
		answerInvite(true)
	end)
	UI.button({ Text = "✖ Decline", BackgroundColor3 = T.red, Position = UDim2.fromOffset(226, 60), Size = UDim2.fromOffset(200, 46), TextSize = 17, Parent = refs.invite }, function()
		answerInvite(false)
	end)

	refs.notes = new("Frame", { Name = "Notes", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 132), Size = UDim2.fromOffset(560, 200), BackgroundTransparency = 1, Parent = toastRoot }, { new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }) })
end

local function refreshHUD()
	local d = State.data
	refs.cash.Text = "$" .. fmt(d.cash)
	refs.diamonds.Text = fmt(d.diamonds)
	refs.rebirths.Text = "Rebirth " .. d.rebirths
	refs.rebirthPill.Visible = d.rebirths > 0

	local fightId = player:GetAttribute("BossFight") or 0
	local area = player:GetAttribute("Area") or 0
	local a = Areas.List[area]
	refs.area.Text = a and a.name or (area == 0 and "🏪 Marketplace" or "🌉 Crossing the bridge")
	refs.area.TextColor3 = a and a.grass:Lerp(Color3.new(1, 1, 1), 0.35) or T.text

	local target = Areas.List[d.areasUnlocked]
	local nextArea = Areas.List[d.areasUnlocked + 1]
	if fightId ~= 0 then
		refs.objective.Text = "🎯 Stay close to the boss so your mower hits it"
	elseif d.bossKills[tostring(d.areasUnlocked)] and not nextArea then
		refs.objective.Text = "🎯 Visit the Rebirth Shrine for permanent bonuses"
	elseif d.bagCount >= State.bagCapacity() - 0.001 then
		refs.objective.Text = "🎯 Bag full — walk onto a 💰 selling station"
	else
		refs.objective.Text = "🎯 Defeat the " .. target.boss.name .. " in " .. target.name .. (nextArea and (" to unlock " .. nextArea.name) or "")
	end

	if a then
		local cut, _, goal, prev = State.milestone(area)
		refs.areaFill.BackgroundColor3 = a.grass
		if area > d.areasUnlocked then
			refs.areaFill.Size = UDim2.fromScale(0, 1)
			refs.areaLabel.Text = "🔒 " .. a.name
		elseif goal then
			refs.areaFill.Size = UDim2.fromScale(math.clamp((cut - prev) / (goal - prev), 0, 1), 1)
			refs.areaLabel.Text = "🌿 " .. fmt(cut) .. " / " .. fmt(goal) .. " grass cleared for a reward"
		else
			refs.areaFill.Size = UDim2.fromScale(1, 1)
			refs.areaLabel.Text = "🌿 " .. fmt(cut) .. " grass cleared — all rewards earned!"
		end
	else
		refs.areaFill.Size = UDim2.fromScale(0, 1)
		refs.areaLabel.Text = "Walk through a gate to start mowing!"
	end

	local cap = State.bagCapacity()
	local ratio = cap == math.huge and 0 or math.clamp(d.bagCount / cap, 0, 1)
	refs.bagFill.Size = UDim2.fromScale(ratio, 1)
	refs.bagFill.BackgroundColor3 = ratio >= 0.999 and T.red or T.blue
	refs.bagLabel.Text = "🎒 " .. fmt(math.floor(d.bagCount)) .. " / " .. fmt(cap) .. (ratio >= 0.999 and "  FULL!" or "")

	local hasVehicle = d.equippedVehicle ~= "" and State.ownsVehicle(d.equippedVehicle)
	refs.ride.Visible = hasVehicle and fightId == 0
	refs.ride.Text = player:GetAttribute("Riding") and "🚶\nExit" or "🚜\nRide"
	refs.dailyBadge.Visible = d.daily.last ~= State.now() // 86400

	for _, c in ipairs(refs.side:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for name, def in pairs(Game.Boosts) do
		local left = State.boostLeft(name)
		if left > 0 then
			chip(refs.side, def.icon .. " " .. def.name .. "  " .. Util.clock(left), T.gold)
		end
	end

	local model = fightId ~= 0 and workspace:FindFirstChild("Bosses") and workspace.Bosses:FindFirstChild("F" .. fightId)
	if model then
		local hp, max = model:GetAttribute("Health") or 0, model:GetAttribute("MaxHealth") or 1
		refs.boss.Visible = true
		refs.bossName.Text = "💀 " .. (model:GetAttribute("BossName") or "Boss")
		refs.bossFill.Size = UDim2.fromScale(math.clamp(hp / max, 0, 1), 1)
		refs.bossLabel.Text = fmt(hp) .. " / " .. fmt(max)
		refs.bossTime.Text = "⏱ " .. Util.clock((model:GetAttribute("EndsAt") or 0) - workspace:GetServerTimeNow())
	else
		refs.boss.Visible = false
	end

	-- boss prompt / waiting room / invite timers
	if prompt.lobby then
		local l = prompt.lobby
		local left = math.max(0, math.ceil(l.endsAt - os.clock()))
		if refs.promptInfo then
			refs.promptInfo.Text = "Waiting for friends… " .. left .. "s\n" .. l.joined .. " of " .. l.total .. " invited players have joined"
		end
	end
	if invite then
		local left = math.ceil(invite.endsAt - os.clock())
		if left <= 0 or inFight() then
			hideInvite()
		else
			refs.inviteJoin.Text = "✅ Join (" .. left .. ")"
		end
	end
	if refs.prompt.Visible == inFight() then
		renderPrompt()
	end
end
Menus.refreshHUD = refreshHUD

function Menus.init()
	local gui = new("ScreenGui", { Name = "MowUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 5, Parent = player:WaitForChild("PlayerGui") })
	root = new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	Menus.root = root
	local scale = new("UIScale", { Parent = root })
	local function rescale()
		local vp = workspace.CurrentCamera.ViewportSize
		local s = math.clamp(vp.Y / 720, 0.6, 1.5)
		if vp.X / s < 920 then
			s = vp.X / 920
		end
		scale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	-- Notifications, errors and invites get their own layer above every other screen, so
	-- no menu, shop or popup can ever cover them.
	local toastGui = new("ScreenGui", { Name = "MowToasts", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 100, Parent = player.PlayerGui })
	toastRoot = new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = toastGui })
	local toastScale = new("UIScale", { Parent = toastRoot })
	local function matchScale()
		toastScale.Scale = scale.Scale
		toastRoot.Size = UDim2.fromScale(1 / scale.Scale, 1 / scale.Scale)
	end
	matchScale()
	scale:GetPropertyChangedSignal("Scale"):Connect(matchScale)

	buildHUD()

	refs.backdrop = new("TextButton", { Name = "Backdrop", Text = "", AutoButtonColor = false, Position = UDim2.fromOffset(0, -200), Size = UDim2.new(1, 0, 1, 400), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5, BorderSizePixel = 0, Visible = false, ZIndex = 8, Parent = root })
	refs.backdrop.Activated:Connect(function()
		Menus.close()
	end)
	modal = new("Frame", { Name = "Modal", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(800, 510), BackgroundColor3 = T.bg, Visible = false, ZIndex = 10, Parent = root }, { UI.corner(22), UI.stroke(T.ink, 4) })
	refs.modalShadow = UI.shadow(modal, 10)
	refs.modalScale = new("UIScale", { Parent = modal })
	-- coloured header bar (colour follows the open menu)
	refs.header = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 60), BackgroundColor3 = T.card2, BorderSizePixel = 0, Parent = modal }, { UI.corner(22), UI.gradient(0.38) })
	new("Frame", { Name = "Square", Position = UDim2.new(0, 0, 1, -22), Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = T.bg, BorderSizePixel = 0, Parent = refs.header })
	new("Frame", { Name = "Line", Position = UDim2.new(0, 0, 1, -24), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = T.ink, BackgroundTransparency = 0.5, BorderSizePixel = 0, Parent = refs.header })
	titleLabel = UI.text({ Position = UDim2.fromOffset(24, 2), Size = UDim2.new(1, -90, 0, 36), TextSize = 28, Outline = true, ZIndex = 2, Parent = modal })
	UI.button({ Name = "Close", Text = "X", BackgroundColor3 = T.red, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, -8), Size = UDim2.fromOffset(46, 46), TextSize = 24, Corner = 23, ZIndex = 3, Parent = modal }, Menus.close)
	body = new("Frame", { Name = "Body", Position = UDim2.fromOffset(14, 48), Size = UDim2.new(1, -28, 1, -60), BackgroundTransparency = 1, Parent = modal })

	State.notify = Menus.notify
	RS.Remotes.Notify.OnClientEvent:Connect(Menus.notify)
	State.onChange(function(patch)
		refreshHUD()
		if current then
			for k in pairs(patch) do
				if not IGNORE[k] or (k == "stats" and current.name == "Achievements") then
					Menus.refresh()
					break
				end
			end
		end
	end)
	for _, attr in ipairs({ "Area", "Riding", "BossArea", "BossFight" }) do
		player:GetAttributeChangedSignal(attr):Connect(refreshHUD)
	end
	refreshHUD()
	task.spawn(function()
		while true do
			task.wait((inFight() or prompt.lobby or invite) and 0.15 or 0.5)
			refreshHUD()
		end
	end)
end

return Menus
