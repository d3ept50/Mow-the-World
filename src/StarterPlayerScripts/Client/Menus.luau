-- HUD, notifications and the panel framework. Panel contents live in the Panels module.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
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

-- Buttons that are always on screen, two to a row: { icon, label, panel }.
-- They are the menus that work anywhere; buying things happens at the shops in town.
Menus.MENU = {
	{ "👷", "Workers", "Workers" }, { "🧳", "Items", "Inventory" },
	{ "🧭", "Teleport", "Teleport" }, { "🎁", "Daily", "Daily" },
	{ "🛒", "Shop", "Robux" }, { "📋", "Menu", "More" },
}
-- Everything else lives behind the Menu button (and at the shops in the marketplace).
Menus.MORE = {
	{ "📦", "Crates", "Crates" }, { "✂️", "Mowers", "Mowers" }, { "🎒", "Bags", "Bags" },
	{ "🔁", "Rebirth", "Rebirth" }, { "💎", "Diamonds", "Diamonds" },
	{ "🏆", "Awards", "Achievements" }, { "⚙️", "Settings", "Settings" },
}

local MENU_COLORS = {
	Workers = T.blue, Crates = T.orange, Mowers = T.red, Bags = T.teal, Vehicles = Color3.fromRGB(110, 124, 165), Rebirth = T.purple,
	Daily = T.pink, Achievements = T.gold, Inventory = Color3.fromRGB(96, 170, 110), Robux = T.green, Diamonds = T.cyan, Settings = T.grey,
	Teleport = T.teal, More = T.card2,
}
Menus.COLORS = MENU_COLORS

---------------------------------------------------------------- notifications & banners
-- While something fills the middle of the screen (the chest reel), messages move to the
-- bottom edge so they can still be read and do not cover it.
local NOTES_Y = 172 -- below the area name, the objective and the boss bar
function Menus.toastsLow(on: boolean)
	if refs.notes then
		refs.notes.Position = on and UDim2.new(0.5, 0, 1, -118) or UDim2.new(0.5, 0, 0, NOTES_Y)
	end
end

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
	local f = UI.panel({ Size = UDim2.new(1, 0, 0, big and 46 or 38), LayoutOrder = refs.noteOrder, Parent = holder }, color:Lerp(T.ink, 0.15), big and 23 or 19)
	-- a coloured dot on the left says at a glance what kind of message it is
	new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = color, BorderSizePixel = 0, Parent = f }, { UI.round() })
	local pop = new("UIScale", { Scale = 0.6, Parent = f })
	UI.tween(pop, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	new("TextLabel", { Text = text, Size = UDim2.new(1, -44, 1, -10), Position = UDim2.fromOffset(30, 5), BackgroundTransparency = 1, Font = UI.Font, TextColor3 = color:Lerp(T.text, 0.25), TextScaled = true, Parent = f }, { new("UITextSizeConstraint", { MaxTextSize = big and 21 or 17 }), new("UIStroke", { Color = T.ink, Thickness = 1.4, Transparency = 0.2 }) })
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
	local label = UI.text({ Text = text, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(900, 80), TextSize = 56, TextXAlignment = CENTER, TextColor3 = color or T.gold, Outline = true, ZIndex = 40, Parent = root })
	local outline = label:FindFirstChildOfClass("UIStroke")
	outline.Thickness = 3.5
	local sc = new("UIScale", { Scale = 0.2, Parent = label })
	UI.tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(2.2, function()
		UI.tween(label, 0.5, { TextTransparency = 1 })
		UI.tween(outline, 0.5, { Transparency = 1 })
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

-- The world behind an open menu is softly blurred.
local function menuBlur(on: boolean)
	local blur = Lighting:FindFirstChild("MenuBlur")
	if not blur then
		blur = Instance.new("BlurEffect")
		blur.Name = "MenuBlur"
		blur.Size = 0
		blur.Parent = Lighting
	end
	UI.tween(blur, 0.2, { Size = on and 10 or 0 })
end

function Menus.open(name: string, ctx)
	if current and current.name == name and not ctx then
		Menus.close()
		return
	end
	if not current then
		UI.sfx("open")
		menuBlur(true)
	end
	current = { name = name, ctx = ctx or {} }
	modal.Visible = true
	refs.backdrop.Visible = true
	refs.modalShadow.Visible = true
	local color = MENU_COLORS[name] or T.card2
	refs.header.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.08)
	refs.headerFill.BackgroundColor3 = refs.header.BackgroundColor3
	refs.modalStroke.Color = color:Lerp(T.ink, 0.55)
	refs.modalScale.Scale = 0.85
	UI.tween(refs.modalScale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	render()
end

function Menus.close()
	if current then
		UI.sfx("close")
		menuBlur(false)
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
	local base = { Name = "Scroll", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, ScrollBarImageColor3 = T.card2:Lerp(T.text, 0.3), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = parent }
	for k, v in pairs(props or {}) do
		base[k] = v
	end
	local s = new("ScrollingFrame", base)
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = s })
	-- room for the outlines of the rows, which the scrolling frame would otherwise clip
	new("UIPadding", { PaddingTop = UDim.new(0, 3), PaddingLeft = UDim.new(0, 3), PaddingBottom = UDim.new(0, 8), Parent = s })
	return s
end

-- Standard item row: icon box on the left, title + subtitle, action button on the right.
function Menus.row(parent, h: number, title: string, sub: string?, titleColor: Color3?)
	local r = new("Frame", { Name = title, Size = UDim2.new(1, -14, 0, h), BackgroundColor3 = T.card, BorderSizePixel = 0, Parent = parent }, { UI.corner(16), UI.gradient(0.2), UI.stroke(T.ink, 2, 0.35) })
	-- a thin bright line along the top edge catches the light
	new("Frame", { Name = "Edge", Position = UDim2.fromOffset(14, 1), Size = UDim2.new(1, -28, 0, 2), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.88, BorderSizePixel = 0, Parent = r })
	local icon = new("Frame", { Name = "Icon", Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(70, 70), BackgroundColor3 = T.card2, BorderSizePixel = 0, Parent = r }, { UI.corner(14), UI.gradient(0.3), UI.stroke(T.ink, 2, 0.25) })
	UI.text({ Name = "Title", Text = title, Position = UDim2.fromOffset(90, 8), Size = UDim2.new(1, -270, 0, 26), TextSize = 21, TextColor3 = titleColor or T.text, Outline = true, Parent = r })
	local subLabel = UI.text({ Name = "Sub", Text = sub or "", Position = UDim2.fromOffset(90, 36), Size = UDim2.new(1, -270, 0, h - 44), TextSize = 14, Font = UI.BodyFont, TextColor3 = T.dim, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, RichText = true, TextTruncate = Enum.TextTruncate.None, Parent = r })
	return r, icon, subLabel
end

function Menus.iconText(icon, emoji: string, color: Color3?)
	if color then
		icon.BackgroundColor3 = color
	end
	UI.text({ Text = emoji, Size = UDim2.fromScale(1, 1), TextXAlignment = CENTER, TextSize = 38, Parent = icon })
	if color then
		-- tinted icons get the same raised shading as buttons
		local g = icon:FindFirstChildOfClass("UIGradient")
		if g then
			g:Destroy()
		end
		UI.gloss().Parent = icon
	end
end

function Menus.rowButton(r, text: string, color: Color3, enabled: boolean, fn, y: number?, h: number?)
	return UI.button({ Name = text, Text = text, BackgroundColor3 = color, Enabled = enabled, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, y or 20), Size = UDim2.fromOffset(160, h or 46), TextSize = 17, Parent = r }, fn)
end

---------------------------------------------------------------- HUD widgets
-- A currency counter: a dark capsule with a round coloured badge sticking out on the left,
-- and optionally a small "+" button on the right that opens the shop.
local PILL_W, PILL_H = 222, 42
local function pill(parent, order, icon, color, onPlus)
	local holder = new("Frame", { Size = UDim2.fromOffset(PILL_W, PILL_H), BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	UI.panel({ Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -16, 1, 0), Parent = holder }, nil, PILL_H / 2)
	UI.badge({ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(PILL_H + 8, PILL_H + 8), ZIndex = 2, Parent = holder }, icon, color, 24)
	local label = UI.text({ Position = UDim2.fromOffset(PILL_H + 16, 0), Size = UDim2.new(1, -(PILL_H + 16) - (onPlus and 44 or 14), 1, 0), TextSize = 24, TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35), Text = "0", Outline = true, ZIndex = 2, Parent = holder })
	if onPlus then
		UI.button({ Name = "Plus", Text = "+", BackgroundColor3 = T.green, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -7, 0.5, 0), Size = UDim2.fromOffset(30, 30), TextSize = 26, Corner = 15, ZIndex = 2, Parent = holder }, onPlus)
	end
	return label, holder
end

-- An active boost: a small capsule with its icon, name and time left.
local function chip(parent, text, color)
	local f = UI.panel({ Size = UDim2.fromOffset(230, 32), BackgroundTransparency = 0.1, Parent = parent }, color:Lerp(T.ink, 0.3), 16)
	UI.text({ Text = text, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -20, 1, 0), TextSize = 16, TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.2), Outline = true, Parent = f })
end

---------------------------------------------------------------- boss prompt, lobby and invites
-- The prompt shows when the player steps into a boss's circle (World tells us), and turns
-- into a waiting room after "Invite friends". Invited players get a separate invite card.
-- On the portal in town the same card is the way into the world boss fight.
local prompt = { zone = nil, dismissed = false, lobby = nil, shown = nil, portal = false }
local invite = nil -- { area, hostId, endsAt }

local function inFight(): boolean
	return (player:GetAttribute("BossFight") or 0) ~= 0
end

-- What the world boss card says: it depends on whether the boss is waiting, fighting or resting.
local function worldInfo(): string
	local state = workspace:GetAttribute("WorldBoss") or "ready"
	local left = (workspace:GetAttribute("WorldBossUntil") or 0) - workspace:GetServerTimeNow()
	if state == "fighting" then
		local n = workspace:GetAttribute("WorldBossPlayers") or 0
		return "⚔️ " .. n .. (n == 1 and " player" or " players") .. " fighting · boss at " .. (workspace:GetAttribute("WorldBossHp") or 100) .. "% · ⏱ " .. Util.clock(left) .. "\nJoin in! Rewards are shared by damage dealt."
	elseif state == "cooldown" then
		return "😴 The boss is resting. It returns in " .. Util.clock(left) .. ".\nRewards are shared by how much damage you deal."
	end
	return "The whole server fights one boss. It grows with every player who joins.\nRewards are shared by how much damage you deal."
end

local renderPrompt
function renderPrompt()
	local card = refs.prompt
	local lobby = prompt.lobby
	local world = not lobby and not prompt.dismissed and not prompt.zone and prompt.portal
	local worldState = workspace:GetAttribute("WorldBoss") or "ready"
	local area = lobby and lobby.area or (not prompt.dismissed and prompt.zone) or (world and Areas.WORLD_ID) or nil
	if inFight() or not area or not Areas.List[area] then
		card.Visible = false
		prompt.shown = nil
		return
	end
	local key = (lobby and "lobby" or world and ("world" .. worldState) or "ask") .. area
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
	UI.text({ Text = (world and "🌍 WORLD BOSS · " or "💀 ") .. B.name, Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -32, 0, 30), TextSize = 25, TextXAlignment = CENTER, Outline = true, Parent = card })
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
	elseif world then
		-- one fight for the whole server: the text below is kept up to date by Menus.refresh
		refs.promptInfo = UI.text({ Text = worldInfo(), Position = UDim2.fromOffset(16, 42), Size = UDim2.new(1, -32, 0, 44), TextSize = 15, TextXAlignment = CENTER, TextColor3 = T.dim, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, Parent = card })
		if worldState == "cooldown" then
			button(1, 2, "😴 Resting…", T.grey, function()
				Menus.notify("The world boss is resting. Come back when the timer runs out!", "info")
			end)
		else
			button(1, 2, worldState == "fighting" and "⚔️ Join the fight" or "⚔️ Start the fight", T.green, function()
				State.action("WorldBossJoin")
			end)
		end
		button(2, 2, "✖ Exit", T.red, function()
			prompt.dismissed = true
			renderPrompt()
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

-- Called by World: is the player standing on the boss portal in town?
function Menus.setPortal(on: boolean)
	if on ~= prompt.portal then
		prompt.portal = on
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
-- A capsule that grows to fit its text: the area name and the objective at the top.
local function capsule(props, textSize: number, color: Color3)
	local base = { AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.bg, BackgroundTransparency = 0.06, BorderSizePixel = 0 }
	for k, v in pairs(props) do
		base[k] = v
	end
	local f = new("Frame", base, {
		UI.round(),
		UI.gradient(0.3),
		UI.padding(22, 0),
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	local stroke = UI.stroke(color, 2.5)
	stroke.Parent = f
	new("UISizeConstraint", { MinSize = Vector2.new(160, 0), Parent = f })
	local label = UI.text({ Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, TextSize = textSize, TextXAlignment = CENTER, TextTruncate = Enum.TextTruncate.None, TextColor3 = color, Outline = true, Parent = f })
	return label, stroke, f
end

local function buildHUD()
	-- left column: currencies, then the menu buttons in two columns
	local left = new("Frame", { Name = "Left", Position = UDim2.fromOffset(14, 12), Size = UDim2.fromOffset(PILL_W, 520), BackgroundTransparency = 1, Parent = root }, { new("UIListLayout", { Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local function shop()
		Menus.open("Robux")
	end
	refs.cash = pill(left, 1, "💵", T.green, shop)
	refs.diamonds = pill(left, 2, "💎", T.cyan, shop)
	refs.rebirths, refs.rebirthPill = pill(left, 3, "🔁", T.purple)

	local TILE, GAP = 76, 10
	local rows = math.ceil(#Menus.MENU / 2)
	local grid = new("Frame", { Name = "Menu", LayoutOrder = 4, Size = UDim2.fromOffset(TILE * 2 + GAP, rows * (TILE + GAP) + 4), BackgroundTransparency = 1, Parent = left }, {
		new("UIPadding", { PaddingTop = UDim.new(0, 6) }),
		new("UIGridLayout", { CellSize = UDim2.fromOffset(TILE, TILE), CellPadding = UDim2.fromOffset(GAP, GAP), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, m in ipairs(Menus.MENU) do
		local b = UI.button({ Name = m[3], BackgroundColor3 = MENU_COLORS[m[3]] or T.card, LayoutOrder = i, Corner = 18, Parent = grid }, function()
			Menus.open(m[3])
		end)
		UI.text({ Text = m[1], Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 40), TextXAlignment = CENTER, TextSize = 32, ZIndex = 2, Parent = b })
		UI.text({ Text = m[2], Position = UDim2.new(0, 2, 1, -25), Size = UDim2.new(1, -4, 0, 18), TextXAlignment = CENTER, TextSize = 14, Outline = true, ZIndex = 2, Parent = b })
		if m[3] == "Daily" then
			refs.dailyBadge = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 6, 0, -6), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = T.red, Visible = false, ZIndex = 3, Parent = b }, { UI.round(), UI.stroke(T.ink, 2) })
			UI.text({ Text = "!", Size = UDim2.fromScale(1, 1), TextXAlignment = CENTER, TextSize = 16, ZIndex = 4, Parent = refs.dailyBadge })
		end
	end

	-- bottom: grass progress in this area, then the bag with its badge
	local BAR_W = 480
	local bottom = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(BAR_W, 68), BackgroundTransparency = 1, Parent = root })
	refs.areaBar, refs.areaFill, refs.areaLabel = UI.bar({ Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -34, 0, 24), Parent = bottom }, T.green)
	refs.areaLabel.TextSize = 14
	refs.bagBar, refs.bagFill, refs.bagLabel = UI.bar({ Position = UDim2.fromOffset(34, 32), Size = UDim2.new(1, -34, 0, 36), Parent = bottom }, T.blue)
	refs.bagLabel.TextSize = 18
	refs.bagBadge = UI.badge({ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0, 50), Size = UDim2.fromOffset(52, 52), ZIndex = 3, Parent = bottom }, "🎒", T.blue, 26)
	refs.ride = UI.button({ Text = "🚜\nRide", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0.5, BAR_W / 2 + 14, 1, -16), Size = UDim2.fromOffset(76, 68), TextSize = 17, Corner = 18, BackgroundColor3 = T.blue, Visible = false, Parent = root }, function()
		State.action("ToggleRide")
	end)
	-- key hint badge on the corner of the Ride button
	local key = new("Frame", { Name = "Key", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 6, 0, -6), Size = UDim2.fromOffset(24, 24), BackgroundColor3 = T.ink, ZIndex = 3, Parent = refs.ride }, { UI.corner(7), UI.stroke(T.text, 1.5) })
	UI.text({ Text = Menus.RIDE_KEY.Name, Size = UDim2.fromScale(1, 1), TextXAlignment = CENTER, TextSize = 15, ZIndex = 4, Parent = key })

	-- top: where you are, and what to do next
	refs.area, refs.areaStroke = capsule({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(0, 44), Parent = root }, 26, T.text)
	refs.objective, refs.objectiveStroke = capsule({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), Size = UDim2.fromOffset(0, 30), BackgroundTransparency = 0.18, Parent = root }, 16, T.gold)
	refs.objectiveStroke.Color = T.gold:Lerp(T.ink, 0.45)

	refs.boss = UI.panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 102), Size = UDim2.fromOffset(480, 62), Visible = false, Parent = root }, T.red, 18)
	refs.bossName = UI.text({ Position = UDim2.fromOffset(14, 3), Size = UDim2.new(1, -28, 0, 24), TextSize = 19, Outline = true, Parent = refs.boss })
	refs.bossTime = UI.text({ Position = UDim2.fromOffset(14, 3), Size = UDim2.new(1, -28, 0, 24), TextSize = 17, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = T.gold, Outline = true, Parent = refs.boss })
	refs.bossBar, refs.bossFill, refs.bossLabel = UI.bar({ Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -24, 0, 24), Parent = refs.boss }, T.red)
	UI.button({ Name = "Leave", Text = "🚪 Leave", BackgroundColor3 = T.grey, Position = UDim2.new(1, 10, 0, 9), Size = UDim2.fromOffset(96, 44), TextSize = 15, Parent = refs.boss }, function()
		State.action("BossLeave")
	end)

	-- active boosts only: worker details are in the Workers menu
	refs.side = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), Size = UDim2.fromOffset(230, 160), BackgroundTransparency = 1, Parent = root }, { new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Right }) })

	refs.prompt = UI.panel({ Name = "BossPrompt", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -100), Size = UDim2.fromOffset(468, 156), BackgroundTransparency = 0.02, Visible = false, ZIndex = 6, Parent = root }, T.red, 20)
	refs.promptScale = new("UIScale", { Parent = refs.prompt })

	-- invites sit on the toast layer so an open menu never hides them
	refs.invite = UI.panel({ Name = "BossInvite", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 300), Size = UDim2.fromOffset(440, 118), BackgroundTransparency = 0.02, Visible = false, Parent = toastRoot }, T.blue, 20)
	refs.inviteText = UI.text({ Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 44), TextSize = 17, TextXAlignment = CENTER, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, Outline = true, Parent = refs.invite })
	refs.inviteJoin = UI.button({ Text = "✅ Join", BackgroundColor3 = T.green, Position = UDim2.fromOffset(14, 60), Size = UDim2.fromOffset(200, 46), TextSize = 17, Parent = refs.invite }, function()
		answerInvite(true)
	end)
	UI.button({ Text = "✖ Decline", BackgroundColor3 = T.red, Position = UDim2.fromOffset(226, 60), Size = UDim2.fromOffset(200, 46), TextSize = 17, Parent = refs.invite }, function()
		answerInvite(false)
	end)

	refs.notes = new("Frame", { Name = "Notes", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, NOTES_Y), Size = UDim2.fromOffset(560, 210), BackgroundTransparency = 1, Parent = toastRoot }, { new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
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
	refs.areaStroke.Color = a and a.grass:Lerp(T.ink, 0.2) or T.card2

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
		if area == Areas.WORLD_ID then
			refs.areaFill.Size = UDim2.fromScale(1, 1)
			refs.areaLabel.Text = "🌍 World boss · rewards are shared by damage dealt"
		elseif area > d.areasUnlocked then
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
	refs.bagBadge.BackgroundColor3 = ratio >= 0.999 and T.red or T.blue
	refs.bagLabel.Text = fmt(math.floor(d.bagCount)) .. " / " .. fmt(cap) .. (ratio >= 0.999 and "   BAG FULL!" or "")

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
		local share = player:GetAttribute("BossShare")
		refs.bossName.Text = "💀 " .. (model:GetAttribute("BossName") or "Boss") .. (share and ("  ·  You: " .. share .. "%") or "")
		refs.bossFill.Size = UDim2.fromScale(math.clamp(hp / max, 0, 1), 1)
		refs.bossLabel.Text = fmt(hp) .. " / " .. fmt(max)
		refs.bossTime.Text = "⏱ " .. Util.clock((model:GetAttribute("EndsAt") or 0) - workspace:GetServerTimeNow())
	else
		refs.boss.Visible = false
	end

	-- boss prompt / waiting room / invite timers
	if prompt.portal and not prompt.lobby then
		renderPrompt() -- redraws only when the world boss changes state
		if refs.promptInfo and prompt.shown and string.sub(prompt.shown, 1, 5) == "world" then
			refs.promptInfo.Text = worldInfo()
		end
	end
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

	refs.backdrop = new("TextButton", { Name = "Backdrop", Text = "", AutoButtonColor = false, Position = UDim2.fromOffset(0, -200), Size = UDim2.new(1, 0, 1, 400), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, Visible = false, ZIndex = 8, Parent = root })
	refs.backdrop.Activated:Connect(function()
		Menus.close()
	end)
	local HEADER, RADIUS = 64, 24
	modal = new("Frame", { Name = "Modal", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(820, 530), BackgroundColor3 = T.bg, BorderSizePixel = 0, Visible = false, ZIndex = 10, Parent = root }, { UI.corner(RADIUS), UI.gradient(0.2) })
	refs.modalStroke = UI.stroke(T.ink, 4)
	refs.modalStroke.Parent = modal
	refs.modalShadow = UI.shadow(modal, 10)
	refs.modalScale = new("UIScale", { Parent = modal })
	-- coloured header bar (colour follows the open menu). Its bottom corners are squared off
	-- by a strip of the same colour whose shading carries on from the header's.
	refs.header = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, HEADER), BackgroundColor3 = T.card2, BorderSizePixel = 0, Parent = modal }, { UI.corner(RADIUS), UI.gradient(0.3) })
	local top = 1 - 0.3 * (HEADER - RADIUS) / HEADER
	refs.headerFill = new("Frame", { Name = "Square", Position = UDim2.new(0, 0, 1, -RADIUS), Size = UDim2.new(1, 0, 0, RADIUS), BackgroundColor3 = T.card2, BorderSizePixel = 0, Parent = refs.header }, {
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(top, top, top), Color3.new(0.7, 0.7, 0.7)) }),
	})
	new("Frame", { Name = "Line", Position = UDim2.fromOffset(0, HEADER), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = T.ink, BackgroundTransparency = 0.3, BorderSizePixel = 0, Parent = modal })
	titleLabel = UI.text({ Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -100, 0, HEADER), TextSize = 30, Outline = true, ZIndex = 2, Parent = modal })
	UI.button({ Name = "Close", Text = "✕", BackgroundColor3 = T.red, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0, HEADER / 2), Size = UDim2.fromOffset(44, 44), TextSize = 22, Corner = 22, ZIndex = 3, Parent = modal }, Menus.close)
	body = new("Frame", { Name = "Body", Position = UDim2.fromOffset(14, HEADER + 14), Size = UDim2.new(1, -28, 1, -(HEADER + 26)), BackgroundTransparency = 1, Parent = modal })

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
