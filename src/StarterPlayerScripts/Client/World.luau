-- Client-side world visuals: gates, area atmosphere, animated props/NPCs, effects for
-- mowing / chests / bosses, and the worker followers of every player.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RS = game:GetService("ReplicatedStorage")

local Config = RS.Shared.Config
local W = require(Config.Workers)
local Game = require(Config.Game)
local Areas = require(Config.Areas)
local Util = require(RS.Shared.Util)
local Models = require(RS.Shared.Models)
local State = require(script.Parent.State)
local UI = require(script.Parent.UI)
local Menus = require(script.Parent.Menus)
local Remotes = RS.Remotes

local player = Players.LocalPlayer
local V, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local fmt = Util.fmt
local World = {}
local rng = Random.new()

---------------------------------------------------------------- effect helpers
local fxPart
local pool, poolIndex = {}, 0

local function setupFx()
	fxPart = Instance.new("Part")
	fxPart.Name = "LocalFx"
	fxPart.Anchored = true
	fxPart.CanCollide = false
	fxPart.CanQuery = false
	fxPart.Transparency = 1
	fxPart.Size = V(1, 1, 1)
	fxPart.CFrame = CF(0, 0, 0)
	fxPart.Parent = workspace
	for i = 1, 24 do
		local att = Instance.new("Attachment")
		att.Parent = fxPart
		local e = Instance.new("ParticleEmitter")
		e.Enabled = false
		e.Lifetime = NumberRange.new(0.45, 0.9)
		e.Speed = NumberRange.new(8, 16)
		e.SpreadAngle = Vector2.new(70, 70)
		e.Acceleration = V(0, -38, 0)
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-200, 200)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
		e.LightEmission = 0.4
		e.Parent = att
		pool[i] = { att = att, emitter = e }
	end
end

local function burst(pos: Vector3, color: Color3, count: number)
	poolIndex = poolIndex % #pool + 1
	local p = pool[poolIndex]
	p.att.WorldPosition = pos
	p.emitter.Color = ColorSequence.new(color)
	p.emitter:Emit(count)
end

local function floatText(pos: Vector3, text: string, color: Color3, scale: number?)
	if not UI.settings.effects then
		return
	end
	local att = Instance.new("Attachment")
	att.Parent = fxPart
	att.WorldPosition = pos
	local s = scale or 5
	local bb = Instance.new("BillboardGui")
	bb.Adornee = att
	bb.Size = UDim2.fromScale(s, s * 0.32)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 200
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Parent = bb
	bb.Parent = att
	TweenService:Create(bb, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = V(rng:NextNumber(-1, 1), 4.5, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(att, 1)
end

local function myPos(): Vector3?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	return hrp and hrp.Position or nil
end

local function near(pos: Vector3, range: number): boolean
	local p = myPos()
	return p ~= nil and (p - pos).Magnitude <= range
end

---------------------------------------------------------------- gates
local function updateGates()
	local unlocked = State.data.areasUnlocked
	for _, g in ipairs(CollectionService:GetTagged("Gate")) do
		local open = (g:GetAttribute("Area") or 99) <= unlocked
		g.CanCollide = not open
		g.Transparency = open and 1 or 0.55
		local lock = g:FindFirstChild("LockGui")
		if lock then
			lock.Enabled = not open
		end
	end
end

---------------------------------------------------------------- atmosphere per area
local MARKET_SKY = { clock = 14, ambient = Color3.fromRGB(150, 150, 150), fog = Color3.fromRGB(200, 225, 255), density = 0.25, tint = Color3.fromRGB(255, 255, 255) }
local tint, atmosphere

local function applySky(areaId)
	local a = Areas.List[areaId]
	local sky = a and a.sky or MARKET_SKY
	local info = TweenInfo.new(1.6, Enum.EasingStyle.Sine)
	TweenService:Create(Lighting, info, { ClockTime = sky.clock, Ambient = sky.ambient, OutdoorAmbient = sky.ambient }):Play()
	TweenService:Create(atmosphere, info, { Color = sky.fog, Decay = sky.fog, Density = sky.density }):Play()
	TweenService:Create(tint, info, { TintColor = sky.tint }):Play()
end

---------------------------------------------------------------- animated world objects
local spin, spinModels, bob, sway, wander = {}, {}, {}, {}, {}

local function register(tag, store, make)
	local function add(inst)
		store[inst] = make(inst)
	end
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		add(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
		store[inst] = nil
	end)
end

local function animateWorld(t, dt, camPos)
	for part, base in pairs(spin) do
		if (base.Position - camPos).Magnitude < 260 then
			part.CFrame = base * ANG(0, t * 1.4, 0)
		end
	end
	for model, base in pairs(spinModels) do
		if (base.Position - camPos).Magnitude < 200 then
			model:PivotTo(base * ANG(0, t * 0.6, 0))
		end
	end
	for model, base in pairs(bob) do
		if (base.Position - camPos).Magnitude < 160 then
			model:PivotTo(base * CF(0, math.abs(math.sin(t * 2.2 + base.Position.X)) * 0.25, 0) * ANG(0, math.sin(t * 0.8 + base.Position.Z) * 0.25, 0))
		end
	end
	for part, base in pairs(sway) do
		if (base.Position - camPos).Magnitude < 260 then
			part.CFrame = base * ANG(0, 0, math.sin(t * 1.3 + base.Position.X) * 0.035)
		end
	end
	for model, w in pairs(wander) do
		if not w.target or (w.target - w.pos).Magnitude < 1 then
			if not w.waitUntil then
				w.waitUntil = t + rng:NextNumber(0.5, 4)
			end
			if t >= w.waitUntil then
				local a, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(22, 92)
				w.target = V(math.sin(a) * r, 0.4, math.cos(a) * r)
				w.waitUntil = nil
			end
		else
			local delta = w.target - w.pos
			w.pos += delta.Unit * math.min(delta.Magnitude, 7 * dt)
			if (w.pos - camPos).Magnitude < 220 then
				model:PivotTo(CFrame.lookAt(w.pos, V(w.target.X, w.pos.Y, w.target.Z)) * CF(0, math.abs(math.sin(t * 9 + w.phase)) * 0.3, 0))
			end
		end
	end
end

---------------------------------------------------------------- worker followers
local rendered = {}
local workerFolder
local tileCache = {}

local function tilesOf(areaId)
	local cache = tileCache[areaId]
	if not cache then
		local folder = workspace:FindFirstChild("Grass") and workspace.Grass:FindFirstChild(tostring(areaId))
		if not folder or #folder:GetChildren() < Areas.TILES then
			return nil
		end
		cache = {}
		for _, p in ipairs(folder:GetChildren()) do
			cache[tonumber(p.Name)] = p
		end
		tileCache[areaId] = cache
	end
	return cache
end

local function pickTile(areaId, pos, taken)
	local cache = tilesOf(areaId)
	if not cache then
		return nil
	end
	local col, row = Areas.tileCoord(areaId, pos)
	local best, bestD
	for dr = -7, 7 do
		local rr = row + dr
		if rr >= 0 and rr < Areas.GRID then
			for dc = -7, 7 do
				local cc = col + dc
				if cc >= 0 and cc < Areas.GRID then
					local tile = cache[rr * Areas.GRID + cc + 1]
					local d = dr * dr + dc * dc
					if tile and tile.Transparency < 1 and not taken[tile] and d > 2 and (not bestD or d < bestD) then
						best, bestD = tile, d
					end
				end
			end
		end
	end
	return best
end

local function syncWorkers(plr)
	local json = plr:GetAttribute("Workers") or "[]"
	if plr ~= player and not UI.settings.otherWorkers then
		json = "[]"
	end
	local r = rendered[plr]
	if r and r.json == json then
		return
	end
	if r then
		for _, it in ipairs(r.items) do
			it.model:Destroy()
		end
	end
	local ok, list = pcall(HttpService.JSONDecode, HttpService, json)
	local items = {}
	if ok and type(list) == "table" then
		for _, w in ipairs(list) do
			if W.ById[w.id] then
				local m = Models.worker(w.id)
				m.Parent = workerFolder
				table.insert(items, { model = m, phase = rng:NextNumber(0, 10), retarget = 0 })
			end
		end
	end
	rendered[plr] = { json = json, items = items }
end

local function animateWorkers(t, dt)
	for plr, r in pairs(rendered) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local n = #r.items
		if hrp and n > 0 then
			local ground = hrp.Position.Y - 3
			local bossArea = plr:GetAttribute("BossArea") or 0
			local area = plr:GetAttribute("Area") or 0
			local canMow = area >= 1 and (plr ~= player or area <= State.data.areasUnlocked)
			local taken = {}
			for _, it in ipairs(r.items) do
				if it.tile then
					taken[it.tile] = true
				end
			end
			for i, it in ipairs(r.items) do
				local goal, look, working
				if bossArea > 0 then
					local a = Areas.List[bossArea]
					local ang = (i / n) * math.pi * 2 + t * 0.35
					local rad = a.boss.size * 0.6 + 4
					goal = a.bossPos + V(math.sin(ang) * rad, 0.7, math.cos(ang) * rad)
					look = a.bossPos
					working = true
					it.tile = nil
				else
					if canMow then
						if not it.tile or it.tile.Transparency >= 1 or t > it.retarget then
							if it.tile then
								taken[it.tile] = nil
							end
							if t > (it.nextScan or 0) then
								it.nextScan = t + 0.35
								it.tile = pickTile(area, hrp.Position, taken)
								it.retarget = t + 2.5
								if it.tile then
									taken[it.tile] = true
								end
							elseif it.tile and it.tile.Transparency >= 1 then
								it.tile = nil
							end
						end
					else
						it.tile = nil
					end
					if it.tile then
						goal = V(it.tile.Position.X, 0.2, it.tile.Position.Z)
						look = goal + (goal - hrp.Position) * V(1, 0, 1)
						working = true
					else
						local offset = hrp.CFrame * CF((i - (n + 1) / 2) * 3.4, 0, 4.5 + ((i - 1) % 2) * 2.6)
						goal = V(offset.X, ground, offset.Z)
						look = goal + hrp.CFrame.LookVector * 10
					end
				end
				it.pos = it.pos or goal
				local delta = goal - it.pos
				local dist = delta.Magnitude
				if dist > 70 then
					it.pos = goal
				elseif dist > 0.05 then
					it.pos += delta.Unit * math.min(dist, math.max(24, dist * 4) * dt)
				end
				local moving = dist > 0.6
				local face = moving and goal or look
				local flat = V(face.X, it.pos.Y, face.Z)
				local cf = (flat - it.pos).Magnitude > 0.2 and CFrame.lookAt(it.pos, flat) or CF(it.pos)
				local hop = 0
				if moving then
					hop = math.abs(math.sin((t + it.phase) * 10)) * 0.7
				elseif working then
					hop = math.abs(math.sin((t + it.phase) * 9)) * 0.3
					cf *= ANG(math.sin((t + it.phase) * 9) * 0.3, 0, 0)
				end
				it.model:PivotTo(cf * CF(0, hop, 0))
			end
		elseif n > 0 then
			for _, it in ipairs(r.items) do
				it.model:PivotTo(CF(0, -500, 0))
				it.pos = nil
			end
		end
	end
end

---------------------------------------------------------------- remote effects
local function chestColor(id)
	for _, c in ipairs(Game.Chests) do
		if c.id == id then
			return c.color
		end
	end
	return Color3.fromRGB(255, 220, 90)
end

local function connectRemotes()
	Remotes.GrassFx.OnClientEvent:Connect(function(areaId, list)
		local a = Areas.List[areaId]
		if not a or not UI.settings.effects then
			return
		end
		local cam = workspace.CurrentCamera.CFrame.Position
		if (a.center - cam).Magnitude > 280 then
			return
		end
		local first
		for i = 1, math.min(#list, 12) do
			local pos = Areas.tilePos(areaId, list[i]) + V(0, 1.6, 0)
			first = first or pos
			burst(pos, a.grass, 8)
		end
	end)

	local lastGrass = 0
	local pending = 0
	Remotes.Gain.OnClientEvent:Connect(function(kind, amount, pos)
		if kind == "grass" then
			pending += amount
			if os.clock() - lastGrass > 0.18 then
				lastGrass = os.clock()
				floatText(pos + V(0, 3.5, 0), "+" .. fmt(pending) .. " 🌿", Color3.fromRGB(190, 255, 170), 4.5)
				pending = 0
			end
		elseif kind == "cash" then
			floatText(pos + V(0, 5, 0), "+$" .. fmt(amount), Color3.fromRGB(255, 225, 90), 9)
			burst(pos + V(0, 2, 0), Color3.fromRGB(255, 225, 90), 30)
			UI.sfx("sell", 1, 0.1)
		end
	end)

	Remotes.Milestone.OnClientEvent:Connect(function(areaId, pct, text)
		local a = Areas.List[areaId]
		Menus.banner(a.name .. " " .. pct .. "% cleared!", a.grass:Lerp(Color3.new(1, 1, 1), 0.3))
		Menus.notify("🌿 " .. pct .. "% milestone reward: " .. text, "big")
		Menus.confetti()
	end)

	Remotes.ChestFx.OnClientEvent:Connect(function(kind, pos, id)
		if not near(pos, 200) then
			return
		end
		local color = chestColor(id)
		if kind == "reveal" then
			burst(pos + V(0, 2, 0), color, 40)
			UI.sfx("chest", 1.1)
			floatText(pos + V(0, 6, 0), "🧰 " .. id .. " Chest!", color:Lerp(Color3.new(1, 1, 1), 0.3), 10)
		else
			burst(pos + V(0, 2, 0), color, 70)
			burst(pos + V(0, 3, 0), Color3.fromRGB(255, 225, 90), 50)
			UI.sfx("reveal", 1.2)
		end
	end)

	local lastDmg, pendingDmg = 0, 0
	Remotes.BossFx.OnClientEvent:Connect(function(kind, areaId, a1, a2, a3, a4)
		local a = Areas.List[areaId]
		if not a then
			return
		end
		if kind == "start" then
			Menus.banner("⚔️ " .. a.boss.name .. "!", Color3.fromRGB(255, 90, 90))
			Menus.notify("Stay close to the boss so your mower hits it — and dodge the red circles!", "info")
			UI.sfx("boss")
		elseif kind == "dmg" then
			pendingDmg += a1
			if os.clock() - lastDmg > 0.3 then
				lastDmg = os.clock()
				local s = a.boss.size
				floatText(a.bossPos + V(rng:NextNumber(-s, s) * 0.5, s * 1.2, rng:NextNumber(-s, s) * 0.5), "-" .. fmt(pendingDmg), Color3.fromRGB(255, 110, 110), 8)
				burst(a.bossPos + V(0, s * 0.7, 0), a.boss.color2, 10)
				UI.sfx("hit", rng:NextNumber(0.9, 1.2), 0.25)
				pendingDmg = 0
			end
		elseif kind == "attack" then
			local pos, radius, delay = a2, a3, a4
			if not near(pos, 220) then
				return
			end
			local ring = Instance.new("Part")
			ring.Shape = Enum.PartType.Cylinder
			ring.Anchored = true
			ring.CanCollide = false
			ring.CanQuery = false
			ring.Material = Enum.Material.Neon
			ring.Color = Color3.fromRGB(255, 50, 50)
			ring.Transparency = 0.75
			ring.Size = V(0.3, radius * 2, radius * 2)
			ring.CFrame = CF(pos + V(0, 0.2, 0)) * ANG(0, 0, math.rad(90))
			ring.Parent = workspace
			TweenService:Create(ring, TweenInfo.new(delay, Enum.EasingStyle.Linear), { Transparency = 0.25 }):Play()
			task.delay(delay, function()
				burst(pos + V(0, 1, 0), Color3.fromRGB(255, 120, 60), 60)
				UI.sfx("boss", 1.3)
				ring:Destroy()
			end)
		elseif kind == "defeat" then
			local pos = a1
			if near(pos, 250) then
				for i = 1, 6 do
					task.delay(i * 0.2, burst, pos + V(rng:NextNumber(-6, 6), rng:NextNumber(-3, 6), rng:NextNumber(-6, 6)), Color3.fromHSV(rng:NextNumber(), 0.7, 1), 60)
				end
			end
		elseif kind == "win" then
			Menus.banner("🏆 VICTORY!", Color3.fromRGB(255, 215, 80))
			Menus.confetti()
		elseif kind == "fail" then
			Menus.banner("The boss wins this time...", Color3.fromRGB(255, 90, 90))
			Menus.notify("Upgrade your mower and workers, then try again!", "info")
		end
	end)
end

---------------------------------------------------------------- init
local SHOP_PANEL = { Mowers = "Mowers", Bags = "Bags", Crates = "Crates", Vehicles = "Vehicles", Rebirth = "Rebirth", Diamonds = "Diamonds", Robux = "Robux" }

---------------------------------------------------------------- guide arrow
-- An arrow over the player's head. Red: the bag is full, so it points to where to sell.
-- Green: it leads a brand-new player to the first area (bridge first, then across).
-- The compass button in the HUD turns it off (UI.settings.arrow).
local GUIDE_GREEN, GUIDE_RED = Color3.fromRGB(120, 255, 90), Color3.fromRGB(255, 70, 60)
local guide = { model = nil, parts = nil, color = nil, newPlayer = false, bridgeStart = nil, lastLook = 0, sellTarget = nil }

local function findBridgeStart()
	for _, g in ipairs(CollectionService:GetTagged("Gate")) do
		if g:GetAttribute("Area") == 1 then
			-- the gate is thin along the bridge; the bridge runs from it back towards the market
			local gp = g.Position
			if g.Size.X < g.Size.Z then
				return V(gp.X - math.sign(gp.X) * Areas.GAP, 0, gp.Z)
			end
			return V(gp.X, 0, gp.Z - math.sign(gp.Z) * Areas.GAP)
		end
	end
	return nil
end

local function startGuide()
	local d = State.data
	local cutSoFar = d.stats and d.stats.grassCut or 0
	guide.newPlayer = d.areasUnlocked <= 1 and d.rebirths == 0 and cutSoFar == 0
	guide.bridgeStart = findBridgeStart()

	local model = Instance.new("Model")
	model.Name = "GuideArrow"
	local function piece(size, offset)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Size = size
		p.Parent = model
		return { p, offset }
	end
	-- the arrow points along -Z: a shaft plus two arms that meet at the tip
	local tip = V(0, 0, -2.2)
	local parts = { piece(V(0.7, 0.45, 2.6), CF(0, 0, -0.6)) }
	for _, side in ipairs({ -1, 1 }) do
		local dir = V(side * math.sin(math.rad(42)), 0, math.cos(math.rad(42)))
		local c = tip + dir
		table.insert(parts, piece(V(0.7, 0.45, 2.2), CFrame.lookAt(c, c + dir)))
	end
	guide.model, guide.parts = model, parts -- stays out of the workspace until it has a target
end

-- Where to sell from here: this area's pad, the market's sell shop, or (on a bridge)
-- wherever the arrow was already heading.
local function sellTarget(area)
	local a = area and area >= 1 and Areas.List[area]
	if a then
		return a.sellPos
	elseif area == 0 then
		return Areas.Shops.Sell
	end
	return guide.sellTarget or Areas.Shops.Sell
end

local function updateGuide(t)
	if not guide.model then
		return
	end
	local area = player:GetAttribute("Area")
	if guide.newPlayer and area == 1 then
		guide.newPlayer = false
		Menus.notify("🌿 You made it! Walk over the grass to mow it, then sell it at the 💰 pad.", "good")
	end
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	local d = State.data
	local target, color
	if head and UI.settings.arrow then
		local pos = head.Position
		if d.bagCount > 0 and d.bagCount >= State.bagCapacity() - 0.001 then
			guide.sellTarget = sellTarget(area)
			target, color = guide.sellTarget, GUIDE_RED
		elseif guide.newPlayer then
			if not guide.bridgeStart and t - guide.lastLook > 1 then
				guide.lastLook = t
				guide.bridgeStart = findBridgeStart()
			end
			local bs = guide.bridgeStart
			target, color = Areas.List[1].center, GUIDE_GREEN
			if bs and area == 0 and (V(pos.X, 0, pos.Z) - bs).Magnitude > 18 then
				target = bs
			end
		end
		if target then
			local flat = V(target.X - pos.X, 0, target.Z - pos.Z)
			if flat.Magnitude < 1 then
				target = nil
			else
				local origin = pos + V(0, 4.2 + math.sin(t * 4) * 0.35, 0)
				local base = CFrame.lookAt(origin, origin + flat.Unit)
				for _, it in ipairs(guide.parts) do
					it[1].CFrame = base * it[2]
				end
			end
		end
	end
	if color ~= GUIDE_RED then
		guide.sellTarget = nil
	end
	if target and color ~= guide.color then
		guide.color = color
		for _, it in ipairs(guide.parts) do
			it[1].Color = color
		end
	end
	local parent = target and workspace or nil
	if guide.model.Parent ~= parent then
		guide.model.Parent = parent
	end
end

function World.init()
	setupFx()
	tint = Lighting:FindFirstChild("AreaTint") or Instance.new("ColorCorrectionEffect")
	tint.Name = "AreaTint"
	tint.Parent = Lighting
	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Parent = Lighting

	updateGates()
	CollectionService:GetInstanceAddedSignal("Gate"):Connect(updateGates)
	State.onChange(function(patch)
		if patch.areasUnlocked then
			updateGates()
		end
	end)

	applySky(player:GetAttribute("Area") or 0)
	player:GetAttributeChangedSignal("Area"):Connect(function()
		applySky(player:GetAttribute("Area") or 0)
	end)

	register("Spin", spin, function(p)
		return p.CFrame
	end)
	register("Sway", sway, function(p)
		return p.CFrame
	end)
	register("SpinModel", spinModels, function(m)
		return m:GetPivot()
	end)
	register("Bob", bob, function(m)
		return m:GetPivot()
	end)
	register("Wander", wander, function(m)
		return { pos = m:GetPivot().Position, phase = rng:NextNumber(0, 6) }
	end)

	workerFolder = Instance.new("Folder")
	workerFolder.Name = "LocalWorkers"
	workerFolder.Parent = workspace
	local function watch(plr)
		syncWorkers(plr)
		plr:GetAttributeChangedSignal("Workers"):Connect(function()
			syncWorkers(plr)
		end)
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		watch(plr)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(plr)
		local r = rendered[plr]
		if r then
			for _, it in ipairs(r.items) do
				it.model:Destroy()
			end
			rendered[plr] = nil
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1.5)
			for _, plr in ipairs(Players:GetPlayers()) do
				syncWorkers(plr)
			end
		end
	end)

	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		t += dt
		local camPos = workspace.CurrentCamera.CFrame.Position
		animateWorld(t, dt, camPos)
		animateWorkers(t, dt)
		updateGuide(t)
	end)

	connectRemotes()
	startGuide()

	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who ~= player then
			return
		end
		local shop = prompt.Parent and prompt.Parent:GetAttribute("Shop")
		if shop and SHOP_PANEL[shop] then
			Menus.open(SHOP_PANEL[shop], {})
		end
	end)

	UI.music(UI.settings.music)
end

return World
