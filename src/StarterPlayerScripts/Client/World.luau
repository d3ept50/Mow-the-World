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
local Items = require(Config.Items)
local Util = require(RS.Shared.Util)
local Models = require(RS.Shared.Models)
local Style = require(RS.Shared.Style)
local State = require(script.Parent.State)
local UI = require(script.Parent.UI)
local Menus = require(script.Parent.Menus)
local ChestSpin = require(script.Parent.ChestSpin)
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
	TweenService:Create(Lighting, info, { ClockTime = sky.clock, Ambient = sky.ambient:Lerp(Color3.new(), 1 - Style.AMBIENT), OutdoorAmbient = sky.ambient:Lerp(Color3.new(), 1 - Style.OUTDOOR_AMBIENT) }):Play()
	TweenService:Create(atmosphere, info, { Color = sky.fog, Decay = sky.fog, Density = sky.density * Style.FOG }):Play()
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
		if not folder or #folder:GetChildren() < Areas.TILE_COUNT then
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

-- Grass under the player's own mower is hidden on this screen straight away, without waiting
-- for the server to answer. Only when one hit is enough to cut it, and only for a moment:
-- the server still decides, and a tile it did not cut comes back into view.
local predicted = {} -- [tile part] = time to stop hiding it locally
local function predictCuts()
	local now = os.clock()
	for part, untilT in pairs(predicted) do
		if now >= untilT then
			part.LocalTransparencyModifier = 0
			predicted[part] = nil
		end
	end
	local d = State.data
	local area = player:GetAttribute("Area") or 0
	local a = Areas.List[area]
	local pos = myPos()
	if not d or not a or not pos or area > d.areasUnlocked or (player:GetAttribute("BossFight") or 0) ~= 0 then
		return
	end
	local def = Items.MowerById[d.equippedMower]
	if not def or d.bagCount >= State.bagCapacity() or def.damage * Game.Rebirth.powerMult(d.rebirths or 0) < a.grassHP then
		return
	end
	local tiles = tilesOf(area)
	if not tiles then
		return
	end
	local TILE, GRID = Areas.TILE, Areas.GRID
	local col, row = Areas.tileCoord(area, pos)
	local reach = math.ceil(def.radius / TILE)
	local r2 = (def.radius + TILE * 0.35) ^ 2
	local ox, oz = a.center.X - GRID * TILE / 2, a.center.Z - GRID * TILE / 2
	for dr = -reach, reach do
		local rr = row + dr
		if rr >= 0 and rr < GRID then
			for dc = -reach, reach do
				local cc = col + dc
				if cc >= 0 and cc < GRID then
					local part = tiles[rr * GRID + cc + 1]
					if part and part.Transparency < 1 and not predicted[part] then
						local dx = ox + (cc + 0.5) * TILE - pos.X
						local dz = oz + (rr + 0.5) * TILE - pos.Z
						if dx * dx + dz * dz <= r2 then
							part.LocalTransparencyModifier = 1
							predicted[part] = now + 0.6
						end
					end
				end
			end
		end
	end
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

-- The boss model of the fight a player is in (nil when they are not fighting).
local function fightModel(plr)
	local id = plr:GetAttribute("BossFight") or 0
	local folder = id ~= 0 and workspace:FindFirstChild("Bosses")
	return folder and folder:FindFirstChild("F" .. id) or nil
end

-- Worker health in a boss fight arrives as "100,40,0": percent per equipped worker.
local function workerHealth(plr, r)
	local str = plr:GetAttribute("WorkerHP")
	if str ~= r.hpStr then
		r.hpStr = str
		r.hp = {}
		if type(str) == "string" then
			for n in string.gmatch(str, "%d+") do
				table.insert(r.hp, tonumber(n))
			end
		end
	end
	return r.hp
end

local function healthBar(it)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Health"
	bb.Size = UDim2.fromOffset(78, 16) -- a fixed size on screen, so it reads from across the arena
	bb.StudsOffsetWorldSpace = V(0, 5.6, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 140
	bb.Adornee = it.model.PrimaryPart
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	back.BorderSizePixel = 0
	back.Parent = bb
	Instance.new("UICorner", back).CornerRadius = UDim.new(0.5, 0)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 220, 110)
	fill.BorderSizePixel = 0
	fill.Parent = back
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0.5, 0)
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.Text = ""
	text.ZIndex = 2
	text.Parent = back
	bb.Parent = it.model
	it.bar, it.barFill, it.barText = bb, fill, text
end

local function setHealthBar(it, pct: number?)
	if pct == nil then
		if it.bar then
			it.bar:Destroy()
			it.bar, it.barFill, it.barText, it.pct = nil, nil, nil, nil
		end
		return
	end
	if not it.bar then
		healthBar(it)
	end
	if it.pct ~= pct then
		it.pct = pct
		it.barFill.Size = UDim2.fromScale(pct / 100, 1)
		it.barFill.BackgroundColor3 = pct > 50 and Color3.fromRGB(90, 220, 110) or pct > 20 and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(240, 80, 80)
		it.barText.Text = pct <= 0 and "💫 KO" or ""
	end
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
			local boss = fightModel(plr)
			local hp = boss and workerHealth(plr, r)
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
				local down = false
				setHealthBar(it, hp and (hp[i] or 100) or nil)
				if boss and boss.PrimaryPart then
					-- surround the boss wherever it walks; knocked out workers stay where they fell
					local a = Areas.List[boss:GetAttribute("Area") or 0] or Areas.List[1]
					local centre = boss:GetAttribute("Pos") or boss.PrimaryPart.Position
					local bp = boss.PrimaryPart.Position
					bp = V(bp.X, centre.Y + 0.2, bp.Z)
					down = hp[i] == 0
					if down and it.pos then
						goal = it.pos
					else
						local ang = (i / n) * math.pi * 2 + t * 0.35
						local rad = a.boss.size * 0.6 + 5
						goal = bp + V(math.sin(ang) * rad, 0, math.cos(ang) * rad)
					end
					look = bp
					working = not down
					it.tile = nil
				elseif plr:GetAttribute("BossFight") and plr:GetAttribute("BossFight") ~= 0 then
					-- the fight is ending: wait beside the player
					goal = V(hrp.Position.X + (i - (n + 1) / 2) * 3.4, ground, hrp.Position.Z + 5)
					look = hrp.Position
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
				if down then
					cf *= CF(0, 0.7, 0) * ANG(0, 0, math.rad(90)) -- lying on its side
				elseif moving then
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
		-- pct is now the number of grass tiles the reward was for
		Menus.banner(fmt(pct) .. " grass cleared!", a.grass:Lerp(Color3.new(1, 1, 1), 0.3))
		Menus.notify("🌿 " .. a.name .. " reward: " .. text, "big")
		Menus.confetti()
	end)

	Remotes.ChestFx.OnClientEvent:Connect(function(kind, pos, id, spin)
		if kind == "spin" then
			-- my own chest: the server has already decided the prizes, this plays the reel
			ChestSpin.play(id, chestColor(id), spin)
			return
		end
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
	local RED = Color3.fromRGB(255, 90, 90)
	-- where the boss of a fight is right now, and how big it is
	local function bossAt(areaId, fightId)
		local folder = workspace:FindFirstChild("Bosses")
		local model = folder and folder:FindFirstChild("F" .. tostring(fightId))
		local root = model and model.PrimaryPart
		return root and root.Position or nil, Areas.List[areaId].boss.size
	end
	Remotes.BossFx.OnClientEvent:Connect(function(kind, areaId, a1, a2, a3, a4)
		local a = Areas.List[areaId]
		if not a then
			return
		end
		if kind == "invite" then
			Menus.showInvite(areaId, a1, a2, a3)
		elseif kind == "lobby" then
			Menus.setLobby(areaId, a1, a2, a3)
		elseif kind == "lobbyEnd" then
			if a1 == player.UserId then
				Menus.setLobby(nil)
			else
				Menus.endInvite(a1)
			end
		elseif kind == "start" then
			Menus.close()
			Menus.setLobby(nil)
			Menus.endInvite(nil)
			Menus.banner("⚔️ " .. a.boss.name .. "!", RED)
			Menus.notify("Your workers fight for you. Stay close to the boss so your mower hits it too!", "info")
			UI.sfx("teleport")
			UI.sfx("boss")
		elseif kind == "dmg" then
			pendingDmg += a2
			if os.clock() - lastDmg > 0.3 then
				lastDmg = os.clock()
				local pos, s = bossAt(areaId, a1)
				if pos then
					floatText(pos + V(rng:NextNumber(-s, s) * 0.5, s * 0.9, rng:NextNumber(-s, s) * 0.5), "-" .. fmt(pendingDmg), Color3.fromRGB(255, 110, 110), 8)
					burst(pos + V(0, s * 0.3, 0), a.boss.color2, 10)
					UI.sfx("hit", rng:NextNumber(0.9, 1.2), 0.25)
				end
				pendingDmg = 0
			end
		elseif kind == "move" then
			-- the boss announces an attack: a1 = fight, a2 = attack name, a3 = where, a4 = warning time
			local move = Areas.Moves[a2]
			local pos, delay = a3, a4
			if not move or not near(pos, 260) then
				return
			end
			local s = a.boss.size
			floatText(pos + V(0, s * 1.9, 0), move.icon .. " " .. move.label, move.rage and Color3.fromRGB(255, 170, 60) or RED, 13)
			if move.rule == "none" then
				UI.sfx("boss", 0.7)
				burst(pos + V(0, s, 0), Color3.fromRGB(255, 140, 40), 60)
				return
			end
			local radius = s * 0.6 + ((move.rule == "all" or move.rule == "half") and 15 or 9)
			local ring = Instance.new("Part")
			ring.Shape = Enum.PartType.Cylinder
			ring.Anchored = true
			ring.CanCollide = false
			ring.CanQuery = false
			ring.Material = Enum.Material.Neon
			ring.Color = Color3.fromRGB(255, 50, 50)
			ring.Transparency = 0.8
			ring.Size = V(0.3, radius * 2, radius * 2)
			ring.CFrame = CF(pos + V(0, 0.25, 0)) * ANG(0, 0, math.rad(90))
			ring.Parent = workspace
			TweenService:Create(ring, TweenInfo.new(delay, Enum.EasingStyle.Linear), { Transparency = 0.3 }):Play()
			task.delay(delay + 0.2, function()
				burst(ring.Position + V(0, 1, 0), Color3.fromRGB(255, 120, 60), 50)
				UI.sfx("boss", 1.3, 0.15)
				ring:Destroy()
			end)
		elseif kind == "hurt" then
			-- a2 = list of { i = worker number, dmg, ko } for my own workers
			local mine = rendered[player]
			for _, h in ipairs(a2) do
				local it = mine and mine.items[h.i]
				local pos = it and it.pos
				if pos then
					floatText(pos + V(0, 4, 0), "-" .. fmt(h.dmg), Color3.fromRGB(255, 150, 150), 4.5)
					burst(pos + V(0, 2, 0), RED, 12)
					if h.ko then
						floatText(pos + V(0, 6, 0), "💫 Knocked out!", Color3.fromRGB(255, 220, 90), 8)
					end
				end
				if h.ko then
					UI.sfx("ko", 1, 0.2)
				end
			end
		elseif kind == "defeat" then
			local pos = a2
			if near(pos, 300) then
				for i = 1, 6 do
					task.delay(i * 0.2, burst, pos + V(rng:NextNumber(-6, 6), rng:NextNumber(-3, 6), rng:NextNumber(-6, 6)), Color3.fromHSV(rng:NextNumber(), 0.7, 1), 60)
				end
			end
		elseif kind == "win" then
			Menus.banner("🏆 VICTORY!", Color3.fromRGB(255, 215, 80))
			Menus.confetti()
		elseif kind == "fail" then
			Menus.banner("The boss wins this time...", RED)
			Menus.notify("Level up your workers and upgrade your mower, then try again!", "info")
		elseif kind == "left" then
			Menus.notify("You left the boss fight.", "info")
		end
	end)
end

---------------------------------------------------------------- init
local SHOP_PANEL = { Mowers = "Mowers", Bags = "Bags", Crates = "Crates", Vehicles = "Vehicles", Rebirth = "Rebirth", Diamonds = "Diamonds", Robux = "Robux" }

---------------------------------------------------------------- guide arrow
-- An arrow over the player's head.
-- Red: the bag is full, so it points to the nearest place to sell.
-- Green: it points the way to the highest area the player has unlocked, whenever they
-- are not in it: first to the start of the bridge into that area, then to its gate.
-- The compass button in the HUD turns it off (UI.settings.arrow).
local GUIDE_GREEN, GUIDE_RED = Color3.fromRGB(120, 255, 90), Color3.fromRGB(255, 70, 60)
local guide = { model = nil, parts = nil, color = nil, greeted = false, route = nil, lastLook = 0 }

-- The gate into an area and the far end of the bridge that leads to it.
local function findRoute(areaId)
	for _, g in ipairs(CollectionService:GetTagged("Gate")) do
		if g:GetAttribute("Area") == areaId then
			-- the gate is thin along the bridge, and the bridge runs away from the area's centre
			local gp, c = g.Position, Areas.List[areaId].center
			local bridgeStart
			local span = g:GetAttribute("Span") or Areas.GAP
			if g.Size.X < g.Size.Z then
				bridgeStart = V(gp.X + math.sign(gp.X - c.X) * span, 0, gp.Z)
			else
				bridgeStart = V(gp.X, 0, gp.Z + math.sign(gp.Z - c.Z) * span)
			end
			return { area = areaId, gate = V(gp.X, 0, gp.Z), bridgeStart = bridgeStart }
		end
	end
	return nil
end

local function startGuide()
	local d = State.data
	guide.greeted = (d.stats and d.stats.grassCut or 0) > 0 or d.areasUnlocked > 1 or d.rebirths > 0

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

-- The closest sell spot: the marketplace sell shop or the pad of any unlocked area.
local function nearestSell(pos, unlocked)
	local best, bestD = Areas.Shops.Sell, math.huge
	local function consider(p)
		local dx, dz = p.X - pos.X, p.Z - pos.Z
		local d2 = dx * dx + dz * dz
		if d2 < bestD then
			best, bestD = p, d2
		end
	end
	consider(Areas.Shops.Sell)
	for i = 1, math.min(unlocked, Areas.COUNT) do
		consider(Areas.List[i].sellPos)
	end
	return best
end

-- Where the green arrow should lead: nil when the player is already in their best area.
local function farmTarget(pos, area, unlocked, t)
	local best = math.clamp(unlocked, 1, Areas.COUNT)
	if area == best then
		return nil
	end
	if (not guide.route or guide.route.area ~= best) and t - guide.lastLook > 1 then
		guide.lastLook = t
		guide.route = findRoute(best)
	end
	local route = guide.route
	if not route or route.area ~= best then
		return Areas.List[best].center -- gate not loaded yet
	end
	-- on an island: head for the bridge first. On a bridge (no area): head for the gate.
	local onIsland = area ~= nil and area >= 0
	if onIsland and (V(pos.X, 0, pos.Z) - route.bridgeStart).Magnitude > 18 then
		return route.bridgeStart
	end
	return route.gate
end

local function updateGuide(t)
	if not guide.model then
		return
	end
	local area = player:GetAttribute("Area")
	if not guide.greeted and area == 1 then
		guide.greeted = true
		Menus.notify("🌿 You made it! Walk over the grass to mow it. When your bag is full, follow the red arrow to sell.", "good")
	end
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	local d = State.data
	local target, color
	if head and UI.settings.arrow and (player:GetAttribute("BossFight") or 0) == 0 then
		local pos = head.Position
		if d.bagCount > 0 and d.bagCount >= State.bagCapacity() - 0.001 then
			target, color = nearestSell(pos, d.areasUnlocked), GUIDE_RED
		else
			target, color = farmTarget(pos, area, d.areasUnlocked, t), GUIDE_GREEN
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
	atmosphere.Haze = Style.HAZE
	atmosphere.Glare = Style.GLARE
	atmosphere.Offset = Style.AIR_OFFSET
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
		predictCuts()
		updateGuide(t)
	end)

	connectRemotes()
	startGuide()

	-- Stepping into a boss's circle opens the fight prompt (Solo / Invite friends / Exit).
	task.spawn(function()
		while true do
			task.wait(0.2)
			local zone
			local pos = myPos()
			local area = player:GetAttribute("Area") or 0
			local a = Areas.List[area]
			if pos and a and area <= State.data.areasUnlocked and (player:GetAttribute("BossFight") or 0) == 0 then
				local dx, dz = pos.X - a.bossPos.X, pos.Z - a.bossPos.Z
				if dx * dx + dz * dz <= Areas.BOSS_ZONE ^ 2 then
					zone = area
				end
			end
			Menus.setBossZone(zone)
			-- the boss portal in town
			local onPortal = false
			if pos and area == 0 and (player:GetAttribute("BossFight") or 0) == 0 then
				local dx, dz = pos.X - Areas.PORTAL_POS.X, pos.Z - Areas.PORTAL_POS.Z
				onPortal = dx * dx + dz * dz <= Areas.PORTAL_RADIUS ^ 2
			end
			Menus.setPortal(onPortal)
		end
	end)

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
