-- The chest reel. When the player opens a treasure chest the server decides the prizes and
-- sends them here as a list of columns; this module only plays the show: the screen blurs,
-- an aura in the chest's colour turns behind the reels, each column spins through the
-- things the chest can hold and stops on its prize. A luck prize starts another column
-- with better odds. Rare prizes get their own colour, confetti and a banner.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local RS = game:GetService("ReplicatedStorage")

local Models = require(RS.Shared.Models)
local UI = require(script.Parent.UI)
local Menus = require(script.Parent.Menus)

local ChestSpin = {}
local player = Players.LocalPlayer
local T = UI.Theme
local new = UI.new
local rng = Random.new()
local rgb = Color3.fromRGB
local WHITE, GOLD, GREEN = rgb(255, 255, 255), rgb(255, 214, 90), rgb(120, 255, 110)
local Quad, Quart, Back, Linear, Sine = Enum.EasingStyle.Quad, Enum.EasingStyle.Quart, Enum.EasingStyle.Back, Enum.EasingStyle.Linear, Enum.EasingStyle.Sine
local Out, In, InOut = Enum.EasingDirection.Out, Enum.EasingDirection.In, Enum.EasingDirection.InOut
local CENTER = Enum.TextXAlignment.Center

local CARD_W, CARD_H, GAP = 160, 84, 8
local PITCH = CARD_H + GAP
local WIN_H = PITCH * 3 - GAP -- three cards show at a time
local COL_W, COL_H = CARD_W + 24, WIN_H + 58
local LAND = 30 -- the card the reel stops on
local STACK_H = 600

local queue = {}
local busy = false

local function tw(inst, t, goal, style, dir)
	local tween = TweenService:Create(inst, TweenInfo.new(t, style or Quad, dir or Out), goal)
	tween:Play()
	return tween
end

-- The colour a prize is shown in. (The Secret rarity is nearly black: show it as crimson.)
local function shown(color: Color3): Color3
	local _, _, v = color:ToHSV()
	return v < 0.3 and rgb(255, 50, 80) or color
end

-- How big a deal a prize is: 0 = ordinary, 1 = rare (Epic), 2 = huge (Legendary or better).
local function grade(item): number
	if item.kind == "worker" then
		return item.order >= 5 and 2 or item.order >= 4 and 1 or 0
	end
	return 0
end

---------------------------------------------------------------- one prize card
local function card(parent, item, index: number, withModel: boolean)
	local c = shown(item.color)
	local f = new("Frame", { Name = "Card" .. index, Position = UDim2.fromOffset(0, (index - 1) * PITCH), Size = UDim2.fromOffset(CARD_W, CARD_H), BackgroundColor3 = c:Lerp(T.ink, 0.6), Parent = parent }, { UI.corner(14), UI.gradient(0.4) })
	local stroke = new("UIStroke", { Color = c, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = f })
	if withModel and item.worker then
		local vp = new("ViewportFrame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(2, 4), Size = UDim2.fromOffset(62, 76), Ambient = rgb(200, 200, 200), LightColor = WHITE, LightDirection = Vector3.new(0.5, -1, 0.6), Parent = f })
		local model = Models.worker(item.worker)
		model.Parent = vp
		UI.frameModel(vp, model)
	else
		UI.text({ Text = item.icon, Position = UDim2.fromOffset(2, 0), Size = UDim2.fromOffset(62, CARD_H), TextSize = 38, TextXAlignment = CENTER, Parent = f })
	end
	UI.text({ Text = item.label, Position = UDim2.fromOffset(66, 10), Size = UDim2.fromOffset(CARD_W - 72, 40), TextSize = 17, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Center, Outline = true, Parent = f })
	UI.text({ Text = item.sub, Position = UDim2.fromOffset(66, 52), Size = UDim2.fromOffset(CARD_W - 72, 20), TextSize = 12, TextColor3 = c:Lerp(WHITE, 0.45), Parent = f })
	return f, stroke
end

-- A filler card for the reel: picked from what the chest can hold. Rare things are shown
-- more often than they really come up, so the reel is worth watching.
local function filler(pool)
	local total = 0
	for _, p in ipairs(pool) do
		total += math.sqrt(p.w)
	end
	local r = rng:NextNumber() * total
	for _, p in ipairs(pool) do
		r -= math.sqrt(p.w)
		if r <= 0 then
			return p
		end
	end
	return pool[1]
end

-- The best thing in the chest, to sit right next to where the reel stops.
local function tease(pool)
	local best
	for _, p in ipairs(pool) do
		if p.kind == "worker" and (not best or p.order > best.order) then
			best = p
		end
	end
	return best or pool[1]
end

---------------------------------------------------------------- confetti
local CONFETTI = { rgb(255, 90, 110), rgb(255, 200, 60), rgb(90, 220, 120), rgb(80, 170, 255), rgb(190, 110, 255), WHITE }
local function confetti(layer, from: GuiObject, color: Color3, count: number, reach: number)
	local origin = from.AbsolutePosition + from.AbsoluteSize / 2 - layer.AbsolutePosition
	for i = 1, count do
		local size = rng:NextInteger(7, 15)
		local piece = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(origin.X, origin.Y), Size = UDim2.fromOffset(size, size * rng:NextNumber(0.5, 1.4)),
			BackgroundColor3 = i % 3 == 0 and color or CONFETTI[rng:NextInteger(1, #CONFETTI)], BorderSizePixel = 0, Rotation = rng:NextNumber(0, 360), ZIndex = 20, Parent = layer,
		}, { UI.corner(i % 4 == 0 and 8 or 2) })
		local ang = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(0.35, 1) * reach
		local t = rng:NextNumber(1, 1.9)
		tw(piece, t, { Position = UDim2.fromOffset(origin.X + math.cos(ang) * dist, origin.Y + math.sin(ang) * dist * 0.8 + reach * 0.45), Rotation = piece.Rotation + rng:NextNumber(-540, 540) }, Quad, Out)
		tw(piece, t, { BackgroundTransparency = 1 }, Quad, In)
		Debris:AddItem(piece, t + 0.1)
	end
end

---------------------------------------------------------------- the show
local function run(chestId: string, chestColor: Color3, data)
	local cols = data.columns
	local pool = data.pool
	local closed = false
	Menus.close()
	Menus.toastsLow(true)

	local blur = Instance.new("BlurEffect")
	blur.Name = "ChestSpinBlur"
	blur.Size = 0
	blur.Parent = Lighting
	tw(blur, 0.4, { Size = 24 })

	local gui = new("ScreenGui", { Name = "ChestSpin", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 60, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player.PlayerGui })
	local layer = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.ink, BackgroundTransparency = 1, BorderSizePixel = 0, Active = true, Parent = gui })
	tw(layer, 0.4, { BackgroundTransparency = 0.18 })

	-- the aura: beams turning slowly behind everything, and two soft discs that pulse
	local aura = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, Parent = layer })
	local auraScale = new("UIScale", { Scale = 0, Parent = aura })
	local tinted = {}
	for i = 0, 8 do
		local beam = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(i % 2 == 0 and 90 or 50, 1700), Rotation = i * 20, BackgroundColor3 = chestColor, BorderSizePixel = 0, Parent = aura })
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.88), NumberSequenceKeypoint.new(0.5, 0.62), NumberSequenceKeypoint.new(0.65, 0.88), NumberSequenceKeypoint.new(1, 1) }), Parent = beam })
		table.insert(tinted, beam)
	end
	local discs = {}
	for i, size in ipairs({ 760, 520 }) do
		local disc = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(size, size), BackgroundColor3 = chestColor, BackgroundTransparency = i == 1 and 0.88 or 0.8, BorderSizePixel = 0, Parent = aura }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		table.insert(tinted, disc)
		table.insert(discs, disc)
	end
	tw(auraScale, 0.6, { Scale = 1 }, Back)
	local function setAura(color: Color3, big: boolean?)
		for _, part in ipairs(tinted) do
			tw(part, 0.5, { BackgroundColor3 = color })
		end
		if big then
			tw(auraScale, 0.5, { Scale = 1.35 }, Back)
		end
	end

	-- everything else sits in one stack that is scaled to fit the screen
	local stack = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -30), Size = UDim2.new(1, 0, 0, STACK_H), BackgroundTransparency = 1, Parent = layer })
	local stackScale = new("UIScale", { Parent = stack })
	local title = UI.text({ Text = "🧰 " .. chestId .. " Chest", Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 50), TextSize = 42, TextXAlignment = CENTER, TextColor3 = shown(chestColor):Lerp(WHITE, 0.25), Outline = true, Parent = stack })
	local subtitle = UI.text({ Text = data.first and "🎁 First chest bonus: a guaranteed Epic or better worker!" or "Chest workers can't be found anywhere else", Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 26), TextSize = 19, TextXAlignment = CENTER, TextColor3 = data.first and GOLD or T.dim, Outline = true, Parent = stack })
	local row = new("Frame", { Position = UDim2.fromOffset(0, 90), Size = UDim2.new(1, 0, 0, COL_H), BackgroundTransparency = 1, Parent = stack }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 16), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local banner = UI.text({ Text = "", Position = UDim2.fromOffset(0, 96 + COL_H), Size = UDim2.new(1, 0, 0, 44), TextSize = 36, TextXAlignment = CENTER, Outline = true, Parent = stack })
	local bannerScale = new("UIScale", { Scale = 0, Parent = banner })
	local results = UI.text({ Text = "", Position = UDim2.fromOffset(0, 146 + COL_H), Size = UDim2.new(1, 0, 0, 26), TextSize = 19, TextXAlignment = CENTER, TextColor3 = T.text, Outline = true, TextTransparency = 1, Parent = stack })
	local flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 30, Parent = layer })

	local visible = 0
	local function fit()
		local view = workspace.CurrentCamera.ViewportSize
		stackScale.Scale = math.clamp(math.min(view.Y / (STACK_H + 40), view.X / (math.max(visible, 1) * (COL_W + 16) + 60)), 0.45, 1.15)
	end
	fit()

	local function say(text: string, color: Color3)
		banner.Text = text
		banner.TextColor3 = color
		bannerScale.Scale = 0
		tw(bannerScale, 0.35, { Scale = 1 }, Back)
	end

	local spin = RunService.RenderStepped:Connect(function(dt)
		aura.Rotation += dt * 14
		local pulse = 1 + math.sin(os.clock() * 2.4) * 0.04
		discs[1].Size = UDim2.fromOffset(760 * pulse, 760 * pulse)
		discs[2].Size = UDim2.fromOffset(520 / pulse, 520 / pulse)
	end)

	-- one column: build it, spin it, stop it on its prize
	local function runColumn(i: number, extra: number)
		local c = cols[i]
		local item = c.result
		visible += 1
		fit()
		local col = new("Frame", { Name = "Column" .. i, LayoutOrder = i, Size = UDim2.fromOffset(COL_W, COL_H), BackgroundColor3 = T.bg, Parent = row }, { UI.corner(20), UI.gradient(0.3) })
		local colStroke = new("UIStroke", { Color = c.luck > 1 and GREEN or shown(chestColor), Thickness = 3.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = col })
		local colScale = new("UIScale", { Scale = 0, Parent = col })
		UI.text({ Text = c.luck > 1 and ("🍀 " .. c.luck .. "x LUCK") or "🎰 SPIN", Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 28), TextSize = 20, TextXAlignment = CENTER, TextColor3 = c.luck > 1 and GREEN or WHITE, Outline = true, Parent = col })
		local window = new("Frame", { Position = UDim2.fromOffset(12, 42), Size = UDim2.fromOffset(CARD_W, WIN_H), BackgroundColor3 = T.ink, ClipsDescendants = true, Parent = col }, { UI.corner(14) })
		local strip = new("Frame", { Size = UDim2.fromOffset(CARD_W, (LAND + 2) * PITCH), BackgroundTransparency = 1, Parent = window })
		local winner, winnerStroke
		local best = tease(pool)
		for n = 1, LAND + 2 do
			if n == LAND then
				winner, winnerStroke = card(strip, item, n, true)
			else
				card(strip, (n == LAND + 1 and best ~= item) and best or filler(pool), n, false)
			end
		end
		-- the cards above and below the middle fade into the dark
		new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.ink, BorderSizePixel = 0, ZIndex = 3, Parent = window }, {
			UI.corner(14),
			new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.3, 1), NumberSequenceKeypoint.new(0.7, 1), NumberSequenceKeypoint.new(1, 0.1) }) }),
		})
		local marker = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 42 + WIN_H / 2), Size = UDim2.fromOffset(CARD_W + 10, CARD_H + 10), BackgroundTransparency = 1, ZIndex = 4, Parent = col }, { UI.corner(17) })
		local markerStroke = new("UIStroke", { Color = GOLD, Thickness = 3, Parent = marker })
		UI.text({ Text = "▶", Position = UDim2.new(0, -4, 0, 42 + WIN_H / 2 - 12), Size = UDim2.fromOffset(16, 24), TextSize = 18, TextColor3 = GOLD, ZIndex = 5, Outline = true, Parent = col })
		UI.text({ Text = "◀", Position = UDim2.new(1, -12, 0, 42 + WIN_H / 2 - 12), Size = UDim2.fromOffset(16, 24), TextSize = 18, TextColor3 = GOLD, ZIndex = 5, Outline = true, Parent = col })
		tw(colScale, 0.35, { Scale = 1 }, Back)

		local function yFor(n: number): number
			return WIN_H / 2 - ((n - 1) * PITCH + CARD_H / 2)
		end
		strip.Position = UDim2.fromOffset(0, yFor(2))
		task.wait(0.35)
		local last = 2
		local ticks = RunService.RenderStepped:Connect(function()
			local n = math.floor((WIN_H / 2 - strip.Position.Y.Offset) / PITCH) + 1
			if n ~= last then
				last = n
				UI.sfx("click", 0.85 + 0.6 * n / LAND, 0.035)
			end
		end)
		local over = rng:NextNumber(-0.36, 0.36) * CARD_H
		local roll = tw(strip, 3.8 + extra, { Position = UDim2.fromOffset(0, yFor(LAND) + over) }, Quart, Out)
		roll.Completed:Wait()
		ticks:Disconnect()
		if closed then
			return
		end
		tw(strip, 0.28, { Position = UDim2.fromOffset(0, yFor(LAND)) }, Back, Out)
		task.wait(0.3)

		-- the prize: its colour takes over the column, and the better it is the louder it gets
		local color = shown(item.color)
		local g = grade(item)
		winnerStroke.Thickness = 4
		tw(colStroke, 0.3, { Color = color })
		tw(markerStroke, 0.3, { Color = color, Thickness = 5 })
		local pop = new("UIScale", { Parent = marker })
		tw(pop, 0.18, { Scale = 1.12 }, Quad, Out)
		task.delay(0.18, tw, pop, 0.3, { Scale = 1 }, Back, Out)
		if item.kind == "luck" then
			UI.sfx("chest", 1.3)
			setAura(GREEN)
			confetti(layer, winner, GREEN, 26, 260)
		elseif g == 0 then
			UI.sfx("buy", 1.1)
			confetti(layer, winner, color, 14, 180)
		else
			UI.sfx("reveal", g == 2 and 1 or 1.15)
			setAura(color, true)
			say("✨ " .. string.upper(item.rarity) .. " WORKER! ✨", color:Lerp(WHITE, 0.2))
			confetti(layer, winner, color, g == 2 and 90 or 50, g == 2 and 620 or 420)
			if g == 2 then
				-- the biggest prizes: a flash, a second burst and a shake
				flash.BackgroundColor3 = color:Lerp(WHITE, 0.6)
				flash.BackgroundTransparency = 0.25
				tw(flash, 0.7, { BackgroundTransparency = 1 })
				task.delay(0.35, confetti, layer, title, color, 70, 700)
				task.spawn(function()
					for _ = 1, 12 do
						stack.Position = UDim2.new(0.5, rng:NextInteger(-9, 9), 0.5, -30 + rng:NextInteger(-9, 9))
						task.wait(0.03)
					end
					stack.Position = UDim2.new(0.5, 0, 0.5, -30)
				end)
			end
		end
		task.wait(g > 0 and 1.4 or 0.6)

		if item.kind == "luck" then
			for j = i + 1, #cols do
				if cols[j].from == i then
					say("🍀 " .. item.mult .. "x LUCK! Spinning again…", GREEN)
					task.wait(0.7)
					runColumn(j, 0)
					break
				end
			end
		end
	end

	UI.sfx("chest", 0.9)
	local bases = {}
	for i, c in ipairs(cols) do
		if c.from == 0 then
			table.insert(bases, i)
		end
	end
	if #bases > 1 then
		say("✨ DOUBLE SPIN! ✨", GOLD)
	end
	local pending = #bases
	for k, i in ipairs(bases) do
		task.spawn(function()
			local ok, err = pcall(runColumn, i, (k - 1) * 0.8)
			if not ok then
				warn("[ChestSpin]", err)
			end
			pending -= 1
		end)
	end
	while pending > 0 do
		task.wait(0.1)
	end

	-- what the chest gave, and a button to carry on
	local parts, best = {}, 0
	for _, c in ipairs(cols) do
		local item = c.result
		if item.kind ~= "luck" then
			table.insert(parts, item.kind == "worker" and ("👷 " .. item.label .. " (" .. item.rarity .. ")") or (item.icon .. " " .. item.label))
			best = math.max(best, grade(item))
		end
	end
	local summary = table.concat(parts, "   ·   ")
	results.Text = summary
	tw(results, 0.3, { TextTransparency = 0 })
	local collect = UI.button({ Name = "Collect", Text = "✅ Collect", BackgroundColor3 = T.green, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 182 + COL_H), Size = UDim2.fromOffset(220, 54), TextSize = 22, Parent = stack }, function()
		closed = true
	end)
	local shownAt = os.clock()
	while not closed and os.clock() - shownAt < 9 and gui.Parent do
		collect.Text = "✅ Collect (" .. math.ceil(9 - (os.clock() - shownAt)) .. ")"
		task.wait(0.2)
	end
	closed = true

	spin:Disconnect()
	tw(blur, 0.3, { Size = 0 })
	tw(layer, 0.3, { BackgroundTransparency = 1 })
	tw(stackScale, 0.25, { Scale = 0 }, Back, In)
	tw(auraScale, 0.25, { Scale = 0 }, Quad, In)
	task.wait(0.32)
	gui:Destroy()
	blur:Destroy()
	Menus.toastsLow(false)
	Menus.notify("🧰 " .. chestId .. " Chest: " .. summary, best > 0 and "big" or "good")
end

-- Play the reel for a chest the player has just opened. Chests opened while one is still
-- spinning wait their turn.
function ChestSpin.play(chestId: string, chestColor: Color3, data)
	if type(data) ~= "table" or type(data.columns) ~= "table" or #data.columns == 0 then
		return
	end
	table.insert(queue, { chestId, chestColor, data })
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		while #queue > 0 do
			local job = table.remove(queue, 1)
			local ok, err = pcall(run, job[1], job[2], job[3])
			if not ok then
				warn("[ChestSpin]", err)
				-- never leave the screen blurred or covered if something went wrong
				Menus.toastsLow(false)
				local stale = Lighting:FindFirstChild("ChestSpinBlur")
				if stale then
					stale:Destroy()
				end
				local gui = player.PlayerGui:FindFirstChild("ChestSpin")
				if gui then
					gui:Destroy()
				end
			end
		end
		busy = false
	end)
end

return ChestSpin
