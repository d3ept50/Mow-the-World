-- Contents of every menu panel + the crate opening sequence.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local RS = game:GetService("ReplicatedStorage")

local Config = RS.Shared.Config
local Items = require(Config.Items)
local W = require(Config.Workers)
local Game = require(Config.Game)
local Areas = require(Config.Areas)
local Util = require(RS.Shared.Util)
local Models = require(RS.Shared.Models)
local State = require(script.Parent.State)
local UI = require(script.Parent.UI)
local Menus = require(script.Parent.Menus)

local player = Players.LocalPlayer
local new, T, fmt = UI.new, UI.Theme, Util.fmt
local CENTER = Enum.TextXAlignment.Center
local R = Menus.renderers
local CF, ANG = CFrame.new, CFrame.Angles

local Panels = { auto = nil }
local busy = false

Menus.titles = {
	Workers = "👷 Workers", Crates = "📦 Worker Crates", Mowers = "✂️ Mowers", Bags = "🎒 Grass Bags", Vehicles = "🚜 Vehicles",
	Rebirth = "🔁 Rebirth Shrine", Daily = "🎁 Daily Rewards", Achievements = "🏆 Achievements", Inventory = "🧳 Inventory",
	Robux = "🛒 Robux Shop", Diamonds = "💎 Diamond Shop", Settings = "⚙️ Settings",
}

local function rarityColor(rarityId: string): Color3
	if rarityId == "Secret" then
		return Color3.fromRGB(255, 60, 85)
	end
	return W.RarityById[rarityId].color
end

local function act(name, ...)
	local args = table.pack(...)
	return function()
		State.action(name, table.unpack(args, 1, args.n))
	end
end

local function areaLocked(areaId: number): boolean
	local d = State.data
	return d.areasUnlocked < areaId
end

---------------------------------------------------------------- mowers / bags / vehicles
R.Mowers = function(body)
	local d = State.data
	local list = Menus.scroller(body)
	local mult = Game.Rebirth.powerMult(d.rebirths)
	for i, def in ipairs(Items.Mowers) do
		local sub = string.format("⚔️ %s damage   ⚡ %.1f cuts/s   ⭕ %s radius   🌿 x%s grass", fmt(def.damage * mult), def.speed, tostring(def.radius), tostring(def.eff))
		if def.rebirth then
			sub ..= "\nRebirth exclusive — unlocked forever at Rebirth " .. def.rebirth
		else
			sub ..= "\nRequires: " .. Areas.List[def.area].name
		end
		local r, icon = Menus.row(list, 86, def.name, sub, def.rebirth and T.gold or nil)
		r.LayoutOrder = i
		UI.viewport("mower", def.id).Parent = icon
		local owned = State.ownsMower(def.id)
		if owned and d.equippedMower == def.id then
			Menus.rowButton(r, "✔ Equipped", T.grey, false)
		elseif owned then
			Menus.rowButton(r, "Equip", T.blue, true, act("EquipMower", def.id))
		elseif def.rebirth then
			Menus.rowButton(r, "🔁 Rebirth " .. def.rebirth, T.grey, false)
		elseif areaLocked(def.area) then
			Menus.rowButton(r, "🔒 Locked", T.grey, false)
		else
			Menus.rowButton(r, "$" .. fmt(def.price), d.cash >= def.price and T.green or T.red, true, act("BuyMower", def.id))
		end
	end
end

R.Bags = function(body)
	local d = State.data
	local list = Menus.scroller(body)
	local current = State.bagDef()
	for i, def in ipairs(Items.Bags) do
		local r, icon = Menus.row(list, 86, def.name, "Holds <b>" .. fmt(def.capacity) .. "</b> grass" .. (def.capacity == math.huge and " — never fills up!" or ""))
		r.LayoutOrder = i
		Menus.iconText(icon, "🎒", def.color)
		if def.id == current.id then
			Menus.rowButton(r, "✔ Equipped", T.grey, false)
		elseif def.order < current.order then
			Menus.rowButton(r, "Owned", T.grey, false)
		else
			Menus.rowButton(r, "$" .. fmt(def.price), d.cash >= def.price and T.green or T.red, true, act("BuyBag", def.id))
		end
	end
end

R.Vehicles = function(body)
	local d = State.data
	local list = Menus.scroller(body)
	for i, def in ipairs(Items.Vehicles) do
		local sub = string.format("💨 %d speed   ⚔️ x%s damage   ⭕ %d radius   🎒 x%s storage", def.speed, tostring(def.dmg), def.radius, tostring(def.storage))
		if def.pass then
			sub ..= "\nIncluded in the Premium Vehicle Pack"
		elseif def.rebirth then
			sub ..= "\nRebirth exclusive — unlocked forever at Rebirth " .. def.rebirth
		else
			sub ..= "\nRequires: " .. Areas.List[def.area].name
		end
		local r, icon = Menus.row(list, 86, def.name, sub, (def.rebirth or def.pass) and T.gold or nil)
		r.LayoutOrder = i
		UI.viewport("vehicle", def.id).Parent = icon
		local owned = State.ownsVehicle(def.id)
		if owned and d.equippedVehicle == def.id then
			Menus.rowButton(r, player:GetAttribute("Riding") and "🚶 Exit" or "🚜 Ride", T.blue, true, act("ToggleRide"))
		elseif owned then
			Menus.rowButton(r, "Select", T.blue, true, act("EquipVehicle", def.id))
		elseif def.pass then
			Menus.rowButton(r, "🛒 Robux Shop", T.gold, true, function()
				Menus.open("Robux")
			end)
		elseif def.rebirth then
			Menus.rowButton(r, "🔁 Rebirth " .. def.rebirth, T.grey, false)
		elseif areaLocked(def.area) then
			Menus.rowButton(r, "🔒 Locked", T.grey, false)
		else
			Menus.rowButton(r, "$" .. fmt(def.price), d.cash >= def.price and T.green or T.red, true, act("BuyVehicle", def.id))
		end
	end
end

---------------------------------------------------------------- workers
R.Workers = function(body, ctx)
	local d = State.data
	ctx.sort = ctx.sort or "power"
	local top = new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, Parent = body })
	UI.text({ Text = string.format("Equipped %d/%d    Owned %d/%d", #d.equipped, State.slots(), #d.workers, W.MAX_INVENTORY), Size = UDim2.new(1, -330, 1, 0), TextSize = 18, Parent = top })
	UI.button({ Text = "Sort: " .. (ctx.sort == "power" and "Power" or "Rarity"), BackgroundColor3 = T.card2, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -160, 0, 2), Size = UDim2.fromOffset(150, 36), Parent = top }, function()
		ctx.sort = ctx.sort == "power" and "rarity" or "power"
		Menus.refresh()
	end)
	UI.button({ Text = "⚡ Equip Best", BackgroundColor3 = T.green, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = UDim2.fromOffset(150, 36), Parent = top }, act("EquipBest"))

	local list = table.clone(d.workers)
	table.sort(list, function(a, b)
		if ctx.sort == "rarity" then
			local ra, rb = W.RarityById[W.ById[a.id].rarity].order, W.RarityById[W.ById[b.id].rarity].order
			if ra ~= rb then
				return ra > rb
			end
		end
		local pa, pb = W.power(a), W.power(b)
		if pa ~= pb then
			return pa > pb
		end
		return a.uid < b.uid
	end)
	if #list == 0 then
		UI.text({ Text = "No workers yet!\nOpen a crate at the 📦 Worker Crate Shop in the marketplace.", Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, 0, 0, 80), TextXAlignment = CENTER, TextSize = 20, TextColor3 = T.dim, TextTruncate = Enum.TextTruncate.None, Parent = body })
		return
	end

	local grid = new("ScrollingFrame", { Name = "Scroll", Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, -258, 1, -46), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 8, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = body }, { new("UIGridLayout", { CellSize = UDim2.fromOffset(98, 112), CellPadding = UDim2.fromOffset(7, 7), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local sel = ctx.selected and State.worker(ctx.selected) or list[1]
	for i, inst in ipairs(list) do
		local def = W.ById[inst.id]
		local rc = rarityColor(def.rarity)
		local card = UI.button({ BackgroundColor3 = rc:Lerp(Color3.new(0, 0, 0), 0.6), LayoutOrder = i, Parent = grid }, function()
			ctx.selected = inst.uid
			ctx.confirm = nil
			Menus.refresh()
		end)
		local stroke = card:FindFirstChildOfClass("UIStroke")
		stroke.Color = inst == sel and T.gold or rc
		stroke.Thickness = inst == sel and 3 or 2
		stroke.Transparency = 0
		UI.text({ Text = "👷", Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 4), TextXAlignment = CENTER, TextSize = 28, Parent = card })
		UI.text({ Text = def.name, Position = UDim2.fromOffset(4, 40), Size = UDim2.new(1, -8, 0, 30), TextXAlignment = CENTER, TextSize = 12, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextColor3 = rc:Lerp(Color3.new(1, 1, 1), 0.4), Parent = card })
		UI.text({ Text = "⚔️ " .. fmt(State.workerPower(inst)), Position = UDim2.fromOffset(0, 72), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = CENTER, TextSize = 14, Parent = card })
		UI.text({ Text = "Lv " .. inst.lvl .. string.rep("⭐", inst.tier), Position = UDim2.fromOffset(0, 90), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = CENTER, TextSize = 12, TextColor3 = T.dim, Parent = card })
		local badge = (State.isEquipped(inst.uid) and "✅" or "") .. (inst.locked and "🔒" or "")
		if badge ~= "" then
			UI.text({ Text = badge, Position = UDim2.fromOffset(4, 2), Size = UDim2.fromOffset(60, 18), TextSize = 13, Parent = card })
		end
	end

	local pane = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 46), Size = UDim2.new(0, 250, 1, -46), BackgroundColor3 = T.card, Parent = body }, { UI.corner(12) })
	if not sel then
		return
	end
	local def = W.ById[sel.id]
	local rc = rarityColor(def.rarity)
	local holder = new("Frame", { Position = UDim2.fromOffset(70, 4), Size = UDim2.fromOffset(110, 100), BackgroundTransparency = 1, Parent = pane })
	UI.viewport("worker", def.id).Parent = holder
	UI.text({ Text = def.name, Position = UDim2.fromOffset(6, 104), Size = UDim2.new(1, -12, 0, 22), TextXAlignment = CENTER, TextSize = 19, TextColor3 = rc:Lerp(Color3.new(1, 1, 1), 0.3), Parent = pane })
	UI.text({ Text = def.rarity .. "   ⚔️ " .. fmt(State.workerPower(sel)), Position = UDim2.fromOffset(6, 126), Size = UDim2.new(1, -12, 0, 18), TextXAlignment = CENTER, TextSize = 15, TextColor3 = rc, Parent = pane })
	UI.text({ Text = "Level " .. sel.lvl .. "/" .. W.MAX_LEVEL .. "    Stars " .. sel.tier .. "/" .. W.MAX_TIER, Position = UDim2.fromOffset(6, 145), Size = UDim2.new(1, -12, 0, 18), TextXAlignment = CENTER, TextSize = 14, TextColor3 = T.dim, Parent = pane })
	local y = 168
	local function btn(text, color, enabled, fn)
		UI.button({ Text = text, BackgroundColor3 = color, Enabled = enabled, Position = UDim2.fromOffset(10, y), Size = UDim2.new(1, -20, 0, 34), TextSize = 15, Parent = pane }, fn)
		y += 38
	end
	if State.isEquipped(sel.uid) then
		btn("Unequip", T.card2, true, act("UnequipWorker", sel.uid))
	else
		btn("Equip", T.green, true, act("EquipWorker", sel.uid))
	end
	if sel.lvl < W.MAX_LEVEL then
		local cost = W.levelCost(sel)
		btn("Level Up   $" .. fmt(cost), d.cash >= cost and T.blue or T.red, true, act("LevelWorker", sel.uid))
	else
		btn("Max Level", T.grey, false)
	end
	if sel.tier < W.MAX_TIER then
		local cost = W.tierCost(sel)
		btn("Upgrade ⭐   💎 " .. cost, d.diamonds >= cost and T.purple or T.red, true, act("TierWorker", sel.uid))
	else
		btn("Fully Upgraded ⭐⭐⭐", T.grey, false)
	end
	btn(sel.locked and "🔓 Unlock" or "🔒 Lock (favourite)", T.card2, true, act("LockWorker", sel.uid))
	btn(ctx.confirm == sel.uid and "Tap again to delete!" or "🗑 Delete", T.red, not sel.locked, function()
		if ctx.confirm == sel.uid then
			ctx.confirm = nil
			ctx.selected = nil
			State.action("DeleteWorker", sel.uid)
		else
			ctx.confirm = sel.uid
			Menus.refresh()
		end
	end)
end

---------------------------------------------------------------- crates
function Panels.reveal(crateId: string, results)
	local crate = W.CrateById[crateId]
	local best, bestOrder = nil, 0
	for _, r in ipairs(results) do
		local def = W.ById[r.id]
		local o = W.RarityById[def.rarity].order
		if o > bestOrder then
			best, bestOrder = def, o
		end
	end
	local color = rarityColor(best.rarity)
	local overlay = new("TextButton", { Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.3, ZIndex = 50, Parent = Menus.root })
	local skip = false
	overlay.Activated:Connect(function()
		skip = true
	end)
	local ok, err = pcall(function()
		local halo = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(300, 300), BackgroundColor3 = crate.look.trim, BackgroundTransparency = 0.75, ZIndex = 50, Parent = overlay }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		local vp = new("ViewportFrame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(360, 360), BackgroundTransparency = 1, ZIndex = 51, Ambient = Color3.fromRGB(190, 190, 190), LightDirection = Vector3.new(0.5, -1, 0.6), Parent = overlay })
		local title = UI.text({ Text = crate.name, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.45, -250), Size = UDim2.fromOffset(700, 50), TextXAlignment = CENTER, TextSize = 40, Outline = true, ZIndex = 52, Parent = overlay })
		local model = Models.crate(crateId)
		model.Parent = vp
		local cam = UI.frameModel(vp, model)
		local base = model:GetPivot()
		UI.sfx("chest")
		local dur = Panels.auto and 0.7 or 1.3
		local t0 = os.clock()
		local anim = crate.anim
		while os.clock() - t0 < dur and not skip do
			local t = (os.clock() - t0) / dur
			local cf
			if anim == "shake" then
				cf = ANG(0, math.sin(t * 30) * 0.16, math.sin(t * 46) * 0.16 * t)
			elseif anim == "bounce" then
				cf = CF(0, math.abs(math.sin(t * math.pi * 4)) * 1.3, 0) * ANG(0, t * 3, 0)
			elseif anim == "spin" then
				cf = ANG(0, t * t * 18, 0)
			elseif anim == "pulse" then
				cf = ANG(0, t * 5, math.sin(t * 40) * 0.05)
				halo.Size = UDim2.fromOffset(300 + math.sin(t * 28) * 50, 300 + math.sin(t * 28) * 50)
			elseif anim == "float" then
				cf = CF(0, math.sin(t * math.pi) * 1.3, 0) * ANG(math.sin(t * 22) * 0.1, t * 7, 0)
			else
				cf = CF(0, t * t * 1.6, 0) * ANG(0, t * 13, 0)
			end
			model:PivotTo(base * cf)
			RunService.RenderStepped:Wait()
		end
		local flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BackgroundTransparency = 0.05, ZIndex = 60, Parent = overlay })
		UI.tween(flash, 0.55, { BackgroundTransparency = 1 })
		UI.sfx("reveal", 0.75 + bestOrder * 0.09)
		model:Destroy()
		cam:Destroy()
		halo.BackgroundColor3 = color
		halo.BackgroundTransparency = 0.55
		UI.tween(halo, 0.4, { Size = UDim2.fromOffset(420, 420) }, Enum.EasingStyle.Back)
		if bestOrder >= 5 then
			Menus.confetti()
		end
		skip = false
		local spinner
		if #results == 1 then
			spinner = Models.worker(best.id)
			spinner.Parent = vp
			UI.frameModel(vp, spinner)
			title.Text = string.upper(best.rarity) .. "!"
			title.TextColor3 = color
			UI.text({ Text = best.name, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.45, 180), Size = UDim2.fromOffset(700, 40), TextXAlignment = CENTER, TextSize = 32, Outline = true, ZIndex = 52, Parent = overlay })
			UI.text({ Text = "⚔️ " .. fmt(best.damage * Game.Rebirth.workerMult(State.data.rebirths)) .. " damage", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.45, 220), Size = UDim2.fromOffset(700, 28), TextXAlignment = CENTER, TextSize = 22, TextColor3 = T.gold, Outline = true, ZIndex = 52, Parent = overlay })
		else
			vp.Visible = false
			halo.Visible = false
			title.Text = "You got " .. #results .. " workers!"
			local cols = math.min(#results, 5)
			local grid = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(cols * 150, math.ceil(#results / 5) * 140), BackgroundTransparency = 1, ZIndex = 52, Parent = overlay }, { new("UIGridLayout", { CellSize = UDim2.fromOffset(140, 130), CellPadding = UDim2.fromOffset(10, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center }) })
			for _, r in ipairs(results) do
				local def = W.ById[r.id]
				local rc = rarityColor(def.rarity)
				local card = new("Frame", { BackgroundColor3 = rc:Lerp(Color3.new(0, 0, 0), 0.55), ZIndex = 52, Parent = grid }, { UI.corner(12), UI.stroke(rc, 3) })
				UI.text({ Text = "👷", Size = UDim2.new(1, 0, 0, 50), TextXAlignment = CENTER, TextSize = 36, ZIndex = 53, Parent = card })
				UI.text({ Text = def.name, Position = UDim2.fromOffset(4, 52), Size = UDim2.new(1, -8, 0, 40), TextXAlignment = CENTER, TextSize = 15, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, ZIndex = 53, Parent = card })
				UI.text({ Text = def.rarity, Position = UDim2.fromOffset(0, 98), Size = UDim2.new(1, 0, 0, 22), TextXAlignment = CENTER, TextSize = 17, TextColor3 = rc, ZIndex = 53, Parent = card })
			end
		end
		if Panels.auto then
			UI.button({ Text = "⏹ Stop Auto Open", BackgroundColor3 = T.red, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.fromOffset(240, 50), ZIndex = 61, Parent = overlay }, function()
				Panels.auto = nil
				skip = true
			end)
		else
			UI.text({ Text = "Tap anywhere to continue", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.fromOffset(500, 30), TextXAlignment = CENTER, TextSize = 18, TextColor3 = T.dim, ZIndex = 52, Parent = overlay })
		end
		local hold = Panels.auto and 1.1 or 3
		local t1 = os.clock()
		while os.clock() - t1 < hold and not skip do
			if spinner then
				spinner:PivotTo(ANG(0, (os.clock() - t1) * 1.8, 0))
			end
			RunService.RenderStepped:Wait()
		end
	end)
	if not ok then
		warn("[Crate reveal]", err)
	end
	overlay:Destroy()
end

function Panels.openCrate(crateId: string, count: number, owned: boolean): boolean
	if busy then
		return false
	end
	busy = true
	local ok, results = State.action("OpenCrate", crateId, count, owned)
	local good = ok == true and type(results) == "table" and #results > 0
	if good then
		Panels.reveal(crateId, results)
	end
	busy = false
	return good
end

function Panels.toggleAuto(crateId: string)
	if Panels.auto then
		Panels.auto = nil
		return
	end
	Panels.auto = crateId
	task.spawn(function()
		while Panels.auto == crateId do
			if not Panels.openCrate(crateId, 1, false) then
				break
			end
			task.wait(0.1)
		end
		Panels.auto = nil
		Menus.refresh()
	end)
end

local function oddsText(crateId)
	local parts = {}
	for _, e in ipairs(W.crateOdds(crateId)) do
		local pct = e.chance >= 1 and string.format("%.1f%%", e.chance) or string.format("%.2f%%", e.chance)
		table.insert(parts, string.format('<font color="%s">%s</font> %s', Util.hex(rarityColor(e.worker.rarity)), e.worker.name, pct))
	end
	return table.concat(parts, "  ·  ")
end

R.Crates = function(body)
	local d = State.data
	local list = Menus.scroller(body)
	for i, crate in ipairs(W.Crates) do
		local price = crate.currency == "diamonds" and ("💎 " .. fmt(crate.price)) or ("$" .. fmt(crate.price))
		local owned = d.crates[crate.id] or 0
		local locked = areaLocked(crate.area) and (d.stats.maxArea or 1) < crate.area
		local rebirthLocked = crate.rebirth ~= nil and d.rebirths < crate.rebirth
		local sub = "<b>" .. price .. "</b> each    In your inventory: <b>" .. owned .. "</b>\n<b>Possible workers:</b> " .. oddsText(crate.id)
		local r, icon = Menus.row(list, 176, crate.name, sub, crate.look.neon and crate.look.trim or nil)
		r.LayoutOrder = i
		UI.viewport("crate", crate.id).Parent = icon
		if locked then
			Menus.rowButton(r, "🔒 " .. Areas.List[crate.area].name, T.grey, false, nil, 12, 36)
		elseif rebirthLocked then
			Menus.rowButton(r, "🔁 Rebirth " .. crate.rebirth, T.grey, false, nil, 12, 36)
		else
			Menus.rowButton(r, "Open 1", T.green, true, function()
				task.spawn(Panels.openCrate, crate.id, 1, false)
			end, 12, 36)
			Menus.rowButton(r, "Open 3", T.blue, true, function()
				task.spawn(Panels.openCrate, crate.id, 3, false)
			end, 52, 36)
			Menus.rowButton(r, Panels.auto == crate.id and "⏹ Stop Auto" or "🔄 Auto Open", T.purple, true, function()
				Panels.toggleAuto(crate.id)
				Menus.refresh()
			end, 92, 36)
		end
		if owned > 0 then
			Menus.rowButton(r, "Use owned (" .. owned .. ")", T.gold, true, function()
				task.spawn(Panels.openCrate, crate.id, owned >= 3 and 3 or 1, true)
			end, 132, 36)
		end
	end
end

---------------------------------------------------------------- rebirth
R.Rebirth = function(body)
	local d = State.data
	local n = d.rebirths
	local RB = Game.Rebirth
	local cost, req = RB.cost(n), RB.areaReq(n)
	local okArea, okDia = d.areasUnlocked >= req, d.diamonds >= cost
	local function check(ok)
		return ok and "✅" or "❌"
	end
	local nextMower
	for _, m in ipairs(Items.Mowers) do
		if m.rebirth and m.rebirth > n then
			nextMower = m
			break
		end
	end
	local lines = {
		string.format("<font size='26'><b>Rebirth %d  →  %d</b></font>", n, n + 1),
		"",
		"<b>Requirements</b>",
		check(okArea) .. "  Unlock " .. Areas.List[req].name,
		check(okDia) .. "  💎 " .. fmt(d.diamonds) .. " / " .. fmt(cost) .. " diamonds",
		"",
		"<b>Permanent bonuses</b>",
		string.format("💵 Cash  x%.1f → <font color='#5EDC82'>x%.1f</font>", RB.cashMult(n), RB.cashMult(n + 1)),
		string.format("⚔️ Mowing power  x%.1f → <font color='#5EDC82'>x%.1f</font>", RB.powerMult(n), RB.powerMult(n + 1)),
		string.format("👷 Worker damage  x%.2f → <font color='#5EDC82'>x%.2f</font>", RB.workerMult(n), RB.workerMult(n + 1)),
		string.format("👷 Bonus worker slots  +%d → <font color='#5EDC82'>+%d</font>", RB.slots(n), RB.slots(n + 1)),
		nextMower and ("🌟 Next exclusive mower: <font color='#FFCD46'>" .. nextMower.name .. "</font> at Rebirth " .. nextMower.rebirth) or "🌟 All exclusive mowers unlocked!",
		"",
		"<font color='#AFB6CD'>You KEEP: all 💎 diamonds left over, every worker (levels + stars), crates, titles, achievements and gamepasses.</font>",
		"<font color='#AFB6CD'>Resets: cash, unlocked areas, normal mowers, bags and vehicles.</font>",
	}
	new("TextLabel", { Text = table.concat(lines, "\n"), RichText = true, Size = UDim2.new(1, -10, 1, -70), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 17, TextColor3 = T.text, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = body })
	UI.button({ Text = "🔁  REBIRTH", BackgroundColor3 = T.purple, Enabled = okArea and okDia, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.fromOffset(320, 56), TextSize = 26, Parent = body }, function()
		if State.action("Rebirth") then
			Menus.close()
		end
	end)
end

---------------------------------------------------------------- daily rewards
local DAILY_ICON = { cash = "💵", diamonds = "💎", crate = "📦", boost = "⚡" }
R.Daily = function(body)
	local d = State.data
	local today = State.now() // 86400
	local claimedToday = d.daily.last == today
	local streak = (d.daily.last >= today - 1) and d.daily.streak or 0
	local doneCount = claimedToday and ((streak - 1) % 7 + 1) or (streak % 7)
	UI.text({ Text = "Come back every day to grow your streak!   Current streak: " .. streak .. " day(s)", Size = UDim2.new(1, 0, 0, 30), TextSize = 18, TextXAlignment = CENTER, TextColor3 = T.dim, Parent = body })
	local rowF = new("Frame", { Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 190), BackgroundTransparency = 1, Parent = body }, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center }) })
	for i, r in ipairs(Game.Daily) do
		local done = i <= doneCount
		local isNext = not claimedToday and i == doneCount + 1
		local box = new("Frame", { Size = UDim2.fromOffset(101, 180), BackgroundColor3 = done and T.green:Lerp(T.bg, 0.5) or T.card, Parent = rowF }, { UI.corner(12), UI.stroke(isNext and T.gold or T.card2, isNext and 3 or 2) })
		UI.text({ Text = "Day " .. i, Size = UDim2.new(1, 0, 0, 30), TextXAlignment = CENTER, TextSize = 18, Parent = box })
		UI.text({ Text = done and "✅" or DAILY_ICON[r.kind], Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 60), TextXAlignment = CENTER, TextSize = 44, Parent = box })
		UI.text({ Text = r.label, Position = UDim2.fromOffset(4, 110), Size = UDim2.new(1, -8, 0, 60), TextXAlignment = CENTER, TextSize = 14, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextColor3 = T.dim, Parent = box })
	end
	UI.button({ Text = claimedToday and "Come back tomorrow!" or "🎁  CLAIM TODAY'S REWARD", BackgroundColor3 = T.green, Enabled = not claimedToday, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -30), Size = UDim2.fromOffset(380, 60), TextSize = 22, Parent = body }, act("ClaimDaily"))
end

---------------------------------------------------------------- achievements
R.Achievements = function(body)
	local d = State.data
	local list = Menus.scroller(body)
	for i, a in ipairs(Game.Achievements) do
		local tier = d.achievements[a.id] or 0
		local value = d.stats[a.stat] or 0
		local goal = a.tiers[math.min(tier + 1, #a.tiers)]
		local done = tier >= #a.tiers
		local sub = done and "Completed!" or ("Next reward: <b>+" .. a.reward * (tier + 1) .. " 💎</b>" .. ((tier + 1 == #a.tiers and a.title) and (" + title \"" .. a.title .. "\"") or ""))
		local r, icon = Menus.row(list, 86, a.name .. "  " .. string.rep("⭐", tier) .. string.rep("☆", #a.tiers - tier), sub)
		r.LayoutOrder = i
		Menus.iconText(icon, a.icon, done and T.gold:Lerp(T.bg, 0.4) or nil)
		local _, fill, label = UI.bar({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 30), Size = UDim2.fromOffset(230, 26), Parent = r }, done and T.gold or T.green)
		fill.Size = UDim2.fromScale(math.clamp(value / goal, 0, 1), 1)
		label.Text = fmt(math.floor(value)) .. " / " .. fmt(goal)
		r.Title.Size = UDim2.new(1, -350, 0, 26)
		r.Sub.Size = UDim2.new(1, -350, 0, 42)
	end
end

---------------------------------------------------------------- inventory (crates, boosts, titles)
R.Inventory = function(body)
	local d = State.data
	local list = Menus.scroller(body)
	local order = 0
	local function header(text)
		order += 1
		UI.text({ Text = text, Size = UDim2.new(1, -12, 0, 28), TextSize = 20, TextColor3 = T.gold, LayoutOrder = order, Parent = list })
	end
	header("Equipment")
	order += 1
	local mower = Items.MowerById[d.equippedMower] or Items.Mowers[1]
	local eq, eqIcon = Menus.row(list, 86, mower.name, "Bag: <b>" .. State.bagDef().name .. "</b>\nVehicle: <b>" .. (Items.VehicleById[d.equippedVehicle] and Items.VehicleById[d.equippedVehicle].name or "None") .. "</b>")
	eq.LayoutOrder = order
	UI.viewport("mower", mower.id).Parent = eqIcon
	Menus.rowButton(eq, "Change mower", T.blue, true, function()
		Menus.open("Mowers")
	end)

	header("Unopened crates")
	local any = false
	for _, crate in ipairs(W.Crates) do
		local count = d.crates[crate.id] or 0
		if count > 0 then
			any = true
			order += 1
			local r, icon = Menus.row(list, 86, crate.name .. "  x" .. count, "Earned from chests, bosses, achievements and daily rewards.")
			r.LayoutOrder = order
			UI.viewport("crate", crate.id).Parent = icon
			Menus.rowButton(r, "Open 1", T.green, true, function()
				task.spawn(Panels.openCrate, crate.id, 1, true)
			end, 6, 34)
			Menus.rowButton(r, "Open 3", T.blue, count >= 3, function()
				task.spawn(Panels.openCrate, crate.id, 3, true)
			end, 46, 34)
		end
	end
	if not any then
		order += 1
		UI.text({ Text = "No crates right now — find treasure chests and beat bosses to earn them.", Size = UDim2.new(1, -12, 0, 26), TextSize = 15, TextColor3 = T.dim, LayoutOrder = order, Parent = list })
	end

	header("Titles (shown above your head)")
	order += 1
	local wrap = new("Frame", { Size = UDim2.new(1, -12, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order, Parent = list }, { new("UIGridLayout", { CellSize = UDim2.fromOffset(180, 38), CellPadding = UDim2.fromOffset(8, 8) }) })
	UI.button({ Text = "No title", BackgroundColor3 = d.title == "" and T.green or T.card2, Parent = wrap }, act("EquipTitle", ""))
	for title in pairs(d.titles) do
		UI.button({ Text = title, BackgroundColor3 = d.title == title and T.green or T.card2, Parent = wrap }, act("EquipTitle", title))
	end
end

---------------------------------------------------------------- shops
R.Diamonds = function(body)
	local d = State.data
	local list = Menus.scroller(body)
	for i, item in ipairs(Game.DiamondShop) do
		local price = item.price
		local owned = false
		if item.kind == "perk" then
			owned = d.perks.autoSell == true
		elseif item.kind == "slot" then
			owned = (d.perks.slots or 0) >= item.max
			price = item.price * ((d.perks.slots or 0) + 1)
		end
		local r, icon = Menus.row(list, 86, item.name, item.desc)
		r.LayoutOrder = i
		Menus.iconText(icon, item.icon)
		if owned then
			Menus.rowButton(r, "✔ Owned", T.grey, false)
		else
			Menus.rowButton(r, "💎 " .. fmt(price), d.diamonds >= price and T.cyan or T.red, true, act("BuyDiamond", item.id))
		end
	end
end

R.Robux = function(body)
	local list = Menus.scroller(body)
	local order = 0
	local function header(text)
		order += 1
		UI.text({ Text = text, Size = UDim2.new(1, -12, 0, 28), TextSize = 20, TextColor3 = T.gold, LayoutOrder = order, Parent = list })
	end
	header("Gamepasses — optional, everything can be earned by playing")
	for _, pass in ipairs(Game.Passes) do
		order += 1
		local r, icon = Menus.row(list, 86, pass.name, pass.desc)
		r.LayoutOrder = order
		Menus.iconText(icon, pass.icon)
		if State.hasPass(pass.key) then
			Menus.rowButton(r, "✔ Owned", T.grey, false)
		else
			Menus.rowButton(r, "Buy", T.green, true, function()
				if pass.id == 0 then
					Menus.notify("This gamepass is not on sale yet.", "bad")
				else
					MarketplaceService:PromptGamePassPurchase(player, pass.id)
				end
			end)
		end
	end
	header("Packs and boosts")
	for _, product in ipairs(Game.Products) do
		order += 1
		local desc = product.kind == "cash" and "Instant cash that scales with your best area." or product.kind == "diamonds" and "Instant diamonds." or "Starts right away and stacks with time left."
		local r, icon = Menus.row(list, 86, product.name, desc)
		r.LayoutOrder = order
		Menus.iconText(icon, product.icon)
		Menus.rowButton(r, "Buy", T.green, true, function()
			if product.id == 0 then
				Menus.notify("This item is not on sale yet.", "bad")
			else
				MarketplaceService:PromptProductPurchase(player, product.id)
			end
		end)
	end
end

---------------------------------------------------------------- settings
R.Settings = function(body)
	local d = State.data
	local list = Menus.scroller(body)
	local function toggle(i, title, desc, value, fn, enabled)
		local r, icon = Menus.row(list, 86, title, desc)
		r.LayoutOrder = i
		Menus.iconText(icon, value and "✅" or "⬜")
		Menus.rowButton(r, value and "ON" or "OFF", value and T.green or T.grey, enabled ~= false, fn)
		local b = r:FindFirstChildOfClass("TextButton")
		if enabled ~= false then
			b.BackgroundColor3 = value and T.green or T.red
		end
	end
	local function local_(key)
		return function()
			UI.settings[key] = not UI.settings[key]
			UI.music(UI.settings.music)
			Menus.refresh()
		end
	end
	toggle(1, "Music", "Background music.", UI.settings.music, local_("music"))
	toggle(2, "Sound effects", "Mowing, selling and reward sounds.", UI.settings.sfx, local_("sfx"))
	toggle(3, "Visual effects", "Grass particles, floating numbers and confetti.", UI.settings.effects, local_("effects"))
	toggle(4, "Show other players' workers", "Turn off for better performance on slow devices.", UI.settings.otherWorkers, local_("otherWorkers"))
	local hasAuto = d.perks.autoSell or State.hasPass("AutoSell")
	toggle(5, "Auto Sell", hasAuto and "Sell automatically when your bag is full." or "Unlock in the 💎 Diamond Shop or 🛒 Robux Shop.", hasAuto and d.settings.autoSell ~= false, function()
		State.action("Setting", "autoSell", d.settings.autoSell == false)
	end, hasAuto)

	-- codes: a text box and a Redeem button; the server checks the code and gives the reward
	local r, icon = Menus.row(list, 86, "Codes", "Enter a code for rewards.")
	r.LayoutOrder = 6
	Menus.iconText(icon, "🎁")
	local box = new("TextBox", { Name = "Code", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -180, 0, 20), Size = UDim2.fromOffset(210, 46), BackgroundColor3 = T.bg, Font = Enum.Font.FredokaOne, TextSize = 17, TextColor3 = T.text, PlaceholderText = "Type code here", PlaceholderColor3 = T.dim, Text = "", ClearTextOnFocus = false, Parent = r }, { UI.corner(12), UI.stroke(T.card2, 2) })
	local function redeem()
		local text = box.Text
		if text:gsub("%s", "") == "" then
			return
		end
		box.Text = ""
		State.action("Redeem", text)
	end
	Menus.rowButton(r, "Redeem", T.green, true, redeem)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			redeem()
		end
	end)
end

return Panels
