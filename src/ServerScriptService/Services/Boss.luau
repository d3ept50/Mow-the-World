-- Boss battles. Each area shows its boss on a stone circle in the main world. Walking
-- into the circle opens a prompt on the client (Solo / Invite friends / Exit). A fight
-- then gets its own arena, built far away from the islands, and everyone in it is
-- teleported there. The boss walks around the arena and repeats its own sequence of
-- attacks (Areas.Moves). Attacks only hurt workers: a worker that runs out of health is
-- knocked out until the fight ends. Players cannot be hurt.
-- All damage and rewards are calculated on the server.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")

local Areas = require(RS.Shared.Config.Areas)
local Game = require(RS.Shared.Config.Game)
local Util = require(RS.Shared.Util)
local Models = require(RS.Shared.Models)
local Data = require(script.Parent.Data)
local Crates = require(script.Parent.Crates)
local Character = require(script.Parent.Character)
local Remotes = RS.Remotes

local Boss = {}
local fights = {} -- [fight id] = fight
local byPlayer = {} -- [player] = the fight they are in
local lobbies = {} -- [host player] = { host, areaId, invited, members, endsAt }
local slots = {} -- [arena slot] = fight id
local nextId = 0
local rng = Random.new()
local bossFolder, arenaFolder

local CFG = Game.Boss
local R = Areas.FIGHT_RADIUS
local V, CF, ANG, rad = Vector3.new, CFrame.new, CFrame.Angles, math.rad
local Quad, Linear, Back = Enum.EasingStyle.Quad, Enum.EasingStyle.Linear, Enum.EasingStyle.Back
local In, Out = Enum.EasingDirection.In, Enum.EasingDirection.Out

local function fail(msg)
	return false, msg
end

local function alive(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		return char:FindFirstChild("HumanoidRootPart"), char
	end
	return nil
end

local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

---------------------------------------------------------------- boss model helpers
local function label(parent, text, size, pos, color)
	local t = Instance.new("TextLabel")
	t.Size = size
	t.Position = pos or UDim2.new()
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	t.TextStrokeTransparency = 0.2
	t.Parent = parent
	return t
end

-- Name (and, in a fight, a health bar) floating over a boss.
local function bossGui(model, B, withBar: boolean)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(20, 5)
	bb.StudsOffset = V(0, B.size * 1.75 + 2, 0)
	bb.MaxDistance = 260
	bb.LightInfluence = 0
	bb.Adornee = model.PrimaryPart
	label(bb, "💀 " .. B.name, UDim2.fromScale(1, 0.55))
	local fill, hpText
	if withBar then
		local bar = Instance.new("Frame")
		bar.Size = UDim2.fromScale(1, 0.38)
		bar.Position = UDim2.fromScale(0, 0.6)
		bar.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
		bar.BorderSizePixel = 0
		bar.Parent = bb
		Instance.new("UICorner", bar).CornerRadius = UDim.new(0.4, 0)
		fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = Color3.fromRGB(235, 60, 70)
		fill.BorderSizePixel = 0
		fill.Parent = bar
		Instance.new("UICorner", fill).CornerRadius = UDim.new(0.4, 0)
		hpText = label(bar, "", UDim2.fromScale(1, 1))
		hpText.ZIndex = 2
	else
		label(bb, "⚔️ Walk into the circle to fight", UDim2.fromScale(1, 0.34), UDim2.fromScale(0, 0.6), Color3.fromRGB(255, 220, 90))
	end
	bb.Parent = model.PrimaryPart
	return fill, hpText
end

local function setHealth(f)
	local hp = math.max(0, f.hp)
	f.model:SetAttribute("Health", hp)
	f.model:SetAttribute("MaxHealth", f.maxHp)
	f.fill.Size = UDim2.fromScale(math.clamp(hp / f.maxHp, 0, 1), 1)
	f.hpText.Text = Util.fmt(hp) .. " / " .. Util.fmt(f.maxHp)
end

---------------------------------------------------------------- arena
local function buildArena(areaId: number, slot: number)
	local a = Areas.List[areaId]
	local B = a.boss
	local center = Areas.FIGHT_ORIGIN + V((slot - 1) * Areas.FIGHT_SPACING, 0, 0)
	local arena = Instance.new("Model")
	arena.Name = "Arena" .. slot
	local flat = ANG(0, 0, rad(90))

	local floor = Models.P(arena, V(6, R * 2, R * 2), CF(center - V(0, 3, 0)) * flat, a.ground, a.mat, "Cylinder")
	floor.Name = "Floor"
	floor.CanCollide = true
	floor.CanQuery = true
	Models.P(arena, V(0.3, R * 1.2, R * 1.2), CF(center + V(0, 0.02, 0)) * flat, a.cut, a.mat, "Cylinder")
	Models.P(arena, V(0.5, R * 2 + 4, R * 2 + 4), CF(center - V(0, 0.4, 0)) * flat, B.color2, "Neon", "Cylinder")
	-- the rock the arena floats on
	for i, scale in ipairs({ 0.82, 0.56, 0.3 }) do
		Models.P(arena, V(16, R * 2 * scale, R * 2 * scale), CF(center - V(0, 14 + (i - 1) * 16, 0)) * flat, a.wall, "Slate", "Cylinder")
	end

	local SEG = 24
	local segLen = 2 * R * math.tan(math.pi / SEG) + 1
	for i = 0, SEG - 1 do
		local ang = (i / SEG) * math.pi * 2
		local dir = V(math.sin(ang), 0, math.cos(ang))
		local at = center + dir * R
		local face = CFrame.lookAt(at, center)
		-- invisible wall that keeps everyone in, and a low visible one
		local wall = Models.P(arena, V(segLen, 90, 2), face * CF(0, 45, 0), a.wall)
		wall.Transparency = 1
		wall.CanCollide = true
		wall.Name = "Barrier"
		Models.P(arena, V(segLen, 3, 1.6), face * CF(0, 1.5, 0), a.wall, "Slate").CanCollide = true
		if i % 2 == 0 then
			local pillar = Models.cyl(arena, 13, 2.6, at - dir + V(0, 6.5, 0), a.wall, "Slate")
			pillar.CanCollide = true
			local orb = Models.P(arena, V(2.6, 2.6, 2.6), CF(at - dir + V(0, 14.5, 0)), B.color2, "Neon", "Ball")
			Models.glow(orb, B.color2, 28)
		end
	end

	-- scenery from the boss's own area around the edge
	local prng = Random.new(areaId * 31)
	for i = 1, 10 do
		local ang = (i / 10) * math.pi * 2 + 0.3
		local kind = a.props[prng:NextInteger(1, #a.props)]
		local m = Models.prop(kind, a.pal, prng, a.id >= 10)
		m.WorldPivot = CF(0, 0, 0)
		m:ScaleTo(prng:NextNumber(1, 1.5))
		m:PivotTo(CF(center + V(math.sin(ang), 0, math.cos(ang)) * (R - 6)) * ANG(0, prng:NextNumber(0, 6), 0))
		m.Parent = arena
	end
	return arena, center
end

---------------------------------------------------------------- boss movement
local function bossCF(pos: Vector3, dir: Vector3): CFrame
	local at = pos + V(0, 0.7, 0)
	return CFrame.lookAt(at, at + dir) * CF(0, 0.5, 0)
end

-- Tween the boss to where the fight says it is, plus an optional pose on top.
local function place(f, t, pose: CFrame?, style, dir)
	local cf = bossCF(f.pos, f.dir)
	if pose then
		cf *= pose
	end
	TweenService:Create(f.model.PrimaryPart, TweenInfo.new(t, style or Quad, dir or Out), { CFrame = cf }):Play()
end

local function walkTo(f, target: Vector3, speed: number, untilT: number?)
	while f.active and (not untilT or os.clock() < untilT) do
		local delta = target - f.pos
		local dist = delta.Magnitude
		if dist < 0.5 then
			break
		end
		f.dir = delta.Unit
		f.pos += f.dir * math.min(dist, speed * 0.1)
		f.model:SetAttribute("Pos", f.pos)
		place(f, 0.1, nil, Linear)
		task.wait(0.1)
	end
end

local function randomPoint(f): Vector3
	local ang, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(6, R - 24)
	return f.center + V(math.sin(ang) * r, 0, math.cos(ang) * r)
end

-- Turn to face one of the players.
local function facePlayer(f)
	local list = {}
	for player in pairs(f.players) do
		local hrp = alive(player)
		if hrp then
			table.insert(list, hrp.Position)
		end
	end
	if #list > 0 then
		local p = list[rng:NextInteger(1, #list)]
		local flat = V(p.X - f.pos.X, 0, p.Z - f.pos.Z)
		if flat.Magnitude > 1 then
			f.dir = flat.Unit
		end
	end
end

---------------------------------------------------------------- hurting workers
local function hpString(entry): string
	local out = table.create(#entry.squad)
	for i, w in ipairs(entry.squad) do
		out[i] = w.ko and "0" or tostring(math.clamp(math.ceil(w.hp / w.maxHp * 100), 1, 100))
	end
	return table.concat(out, ",")
end

local function fire(f, ...)
	for player in pairs(f.players) do
		Remotes.BossFx:FireClient(player, ...)
	end
end

-- Which workers of one squad an attack hits (indexes into entry.squad).
local function pickTargets(entry, move)
	local up = {}
	for i, w in ipairs(entry.squad) do
		if not w.ko then
			table.insert(up, i)
		end
	end
	local rule = move.rule
	if #up == 0 or rule == "none" then
		return {}
	elseif rule == "all" then
		return up
	elseif rule == "front" then
		local out = {}
		for k = 1, math.min(move.count or 1, #up) do
			out[k] = up[k]
		end
		return out
	elseif rule == "strongest" or rule == "weakest" then
		local best = up[1]
		for _, i in ipairs(up) do
			local w, b = entry.squad[i], entry.squad[best]
			if (rule == "strongest" and w.dmg > b.dmg) or (rule == "weakest" and w.hp < b.hp) then
				best = i
			end
		end
		return { best }
	end
	-- "random" (count) or "half": shuffle, then take the first few
	for i = #up, 2, -1 do
		local j = rng:NextInteger(1, i)
		up[i], up[j] = up[j], up[i]
	end
	local take = rule == "half" and math.ceil(#up / 2) or math.min(move.count or 1, #up)
	local out = {}
	for k = 1, take do
		out[k] = up[k]
	end
	return out
end

local function hit(f, move, mult: number)
	if not f.active or mult <= 0 then
		return
	end
	local B = Areas.List[f.areaId].boss
	for player, entry in pairs(f.players) do
		local hits = {}
		for _, i in ipairs(pickTargets(entry, move)) do
			local w = entry.squad[i]
			local dmg = B.attack * mult * rng:NextNumber(0.9, 1.1)
			w.hp -= dmg
			if w.hp <= 0 then
				w.hp = 0
				w.ko = true
			end
			table.insert(hits, { i = i, dmg = dmg, ko = w.ko })
		end
		if #hits > 0 then
			player:SetAttribute("WorkerHP", hpString(entry))
			Remotes.BossFx:FireClient(player, "hurt", f.areaId, f.id, hits)
			if not entry.wiped then
				local standing = false
				for _, w in ipairs(entry.squad) do
					standing = standing or not w.ko
				end
				if not standing then
					entry.wiped = true
					Data.notify(player, "💫 All your workers are knocked out! Stay close and keep mowing the boss.", "bad")
				end
			end
		end
	end
end

---------------------------------------------------------------- attacks
-- Each attack plays its own animation on the boss, then hurts workers by its rule.
local function doMove(f, name: string)
	local move = Areas.Moves[name]
	if not move then
		return
	end
	local mult = move.mult * f.rage
	facePlayer(f)
	fire(f, "move", f.areaId, f.id, name, f.pos, move.windup)
	local w = move.windup
	local S = Areas.List[f.areaId].boss.size

	if name == "swipe" or name == "snipe" then
		place(f, w, ANG(rad(-20), 0, 0))
		task.wait(w)
		place(f, 0.15, CF(0, 0, -S * 0.4) * ANG(rad(20), 0, 0))
		task.wait(0.15)
		hit(f, move, mult)
		task.wait(0.25)
	elseif name == "slam" or name == "quake" then
		place(f, w, CF(0, name == "slam" and 12 or 5, 0))
		task.wait(w)
		place(f, 0.2, nil, Quad, In)
		task.wait(0.2)
		hit(f, move, mult)
		task.wait(0.2)
	elseif name == "spin" then
		task.wait(w)
		place(f, 0.25, ANG(0, rad(179), 0), Linear)
		task.wait(0.25)
		hit(f, move, mult)
		place(f, 0.25, ANG(0, rad(358), 0), Linear)
		task.wait(0.25)
	elseif name == "charge" then
		place(f, w, ANG(rad(-14), 0, 0))
		task.wait(w)
		-- run right across the arena, through the workers
		local out = f.pos - f.center
		local target = out.Magnitude > 8 and (f.center - out.Unit * (R - 22)) or (f.center + f.dir * (R - 22))
		task.delay(0.25, hit, f, move, mult)
		walkTo(f, target, 75, os.clock() + 1.6)
	elseif name == "smash" then
		place(f, w, CF(0, 5, 0) * ANG(rad(-24), 0, 0))
		task.wait(w)
		place(f, 0.15, CF(0, 0, -S * 0.3) * ANG(rad(30), 0, 0), Quad, In)
		task.wait(0.15)
		hit(f, move, mult)
		task.wait(0.35)
	elseif name == "barrage" then
		task.wait(w)
		for _ = 1, move.repeats or 3 do
			if not f.active then
				return
			end
			place(f, 0.18, CF(0, 3.5, 0))
			task.wait(0.18)
			place(f, 0.12, nil, Quad, In)
			task.wait(0.12)
			hit(f, move, mult)
			task.wait(0.15)
		end
	elseif name == "roar" then
		place(f, w, ANG(rad(-26), 0, 0), Back)
		task.wait(w + 0.3)
	end

	if not f.active then
		return
	end
	if move.rage then
		f.rage = move.rage
	elseif mult > 0 then
		f.rage = 1
	end
	place(f, 0.25)
	task.wait(0.25)
end

-- The boss's behaviour: wander about the arena, then do the next attack of its sequence.
local function brain(f)
	local B = Areas.List[f.areaId].boss
	task.wait(2.5)
	local n = 0
	while f.active do
		local untilT = os.clock() + B.tempo
		walkTo(f, randomPoint(f), B.speed, untilT)
		while f.active and os.clock() < untilT do
			task.wait(0.1)
		end
		if not f.active then
			break
		end
		n += 1
		doMove(f, B.moves[(n - 1) % #B.moves + 1])
	end
end

---------------------------------------------------------------- rewards
local function reward(player, areaId)
	local pr = Data.get(player)
	if not pr then
		return
	end
	local a = Areas.List[areaId]
	local B = a.boss
	local key = tostring(areaId)
	local parts = {}
	local cash = math.floor(B.cash * Data.cashMult(player))
	Data.addCash(player, cash, true)
	table.insert(parts, "+$" .. Util.fmt(cash))
	local first = not pr.bossKills[key]
	local dia = first and math.floor(B.diamonds * (1 + 0.25 * pr.rebirths)) or math.max(1, math.floor(B.diamonds * 0.2))
	dia = Data.addDiamonds(player, dia, true)
	table.insert(parts, "+" .. dia .. " 💎")
	pr.bossKills[key] = true
	Data.addStat(player, "bosses", 1)
	if first or rng:NextNumber() < 0.4 then
		local crateId = Crates.forArea(areaId)
		Data.addCrate(player, crateId, 1)
		table.insert(parts, crateId .. " Crate")
	end
	if rng:NextNumber() < 0.05 then
		local w = Crates.roll(Crates.forArea(areaId), 3)
		if Data.addWorker(player, w.id) then
			table.insert(parts, "Worker: " .. w.name)
		end
	end
	Data.notify(player, "⚔️ " .. B.name .. " defeated! " .. table.concat(parts, ", "), "big")
	if pr.areasUnlocked == areaId and areaId < Areas.COUNT then
		pr.areasUnlocked = areaId + 1
		Data.setStatMax(player, "maxArea", areaId + 1)
		Data.notify(player, "🔓 New area unlocked: " .. Areas.List[areaId + 1].name .. "!", "big")
	elseif areaId == Areas.COUNT and first then
		Data.notify(player, "🌍 You conquered every area! Visit the Rebirth Shrine for permanent bonuses.", "big")
	end
	Data.sync(player, "areasUnlocked", "bossKills", "workers", "equipped")
end

---------------------------------------------------------------- joining and leaving a fight
local function teleport(player, cf: CFrame)
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(cf.Position, 3)
		end)
		local _, char = alive(player)
		if char then
			char:PivotTo(cf)
		end
	end)
end

-- Take a player out of their fight. back = put them back beside the boss's circle.
local function release(f, player, back: boolean)
	f.players[player] = nil
	byPlayer[player] = nil
	if not player.Parent then
		return
	end
	player:SetAttribute("BossArea", 0)
	player:SetAttribute("BossFight", 0)
	player:SetAttribute("WorkerHP", nil)
	if back then
		local pos = Areas.bossReturnPos(f.areaId)
		teleport(player, CFrame.lookAt(pos, pos + V(0, 0, 1))) -- facing away from the boss, towards the grass
	end
end

local function finish(f, won: boolean)
	if not f.active then
		return
	end
	f.active = false
	f.model:SetAttribute("Active", false)
	for player, entry in pairs(f.players) do
		if player.Parent then
			if won and entry.dealt > 0 then
				reward(player, f.areaId)
			end
			Remotes.BossFx:FireClient(player, won and "win" or "fail", f.areaId, f.id)
		end
	end
	if won then
		local S = Areas.List[f.areaId].boss.size
		fire(f, "defeat", f.areaId, f.id, f.pos + V(0, S * 0.6, 0))
		place(f, 1.5, CF(0, -S * 1.8, 0) * ANG(0, rad(170), rad(60)), Back, In)
		task.wait(2.8)
	else
		task.wait(1.6)
	end
	for player in pairs(table.clone(f.players)) do
		release(f, player, true)
	end
	task.wait(0.5) -- let everyone leave before the arena disappears
	f.model:Destroy()
	f.arena:Destroy()
	slots[f.slot] = nil
	fights[f.id] = nil
end

-- Damage dealt to the boss, the timer, and players who left or died.
local function run(f)
	local B = Areas.List[f.areaId].boss
	local reach = B.size * 0.6 + CFG.mowerReach
	local nextWorkers = os.clock() + 1
	while f.active do
		task.wait(0.2)
		local now = os.clock()
		local n = 0
		for player in pairs(table.clone(f.players)) do
			if not player.Parent or not alive(player) then
				if player.Parent then
					Remotes.BossFx:FireClient(player, "left", f.areaId, f.id)
				end
				release(f, player, false)
			else
				n += 1
			end
		end
		if n == 0 or now >= f.endsAt then
			finish(f, false)
			break
		end
		local doWorkers = now >= nextWorkers
		if doWorkers then
			nextWorkers = now + 1
		end
		for player, entry in pairs(f.players) do
			local add = 0
			if doWorkers then
				for _, w in ipairs(entry.squad) do
					if not w.ko then
						add += w.dmg
					end
				end
			end
			local hrp = alive(player)
			if hrp and Data.get(player) and now >= entry.nextHit and flatDist(hrp.Position, f.pos) <= reach then
				local s = Data.mowStats(player)
				entry.nextHit = now + 1 / s.speed
				add += s.damage
			end
			if add > 0 then
				entry.dealt += add
				f.hp -= add
				Remotes.BossFx:FireClient(player, "dmg", f.areaId, f.id, add)
			end
		end
		setHealth(f)
		if f.hp <= 0 then
			finish(f, true)
			break
		end
	end
end

local function start(areaId: number, list)
	local a = Areas.List[areaId]
	local B = a.boss
	local slot = 1
	while slots[slot] do
		slot += 1
	end
	nextId += 1
	local id = nextId
	slots[slot] = id

	local arena, center = buildArena(areaId, slot)
	arena.Parent = arenaFolder
	local model = Models.boss(areaId)
	Models.weld(model)
	model.Name = "F" .. id
	model:PivotTo(CFrame.lookAt(center + V(0, 0.7, 0), center + V(0, 0.7, 1)))
	local fill, hpText = bossGui(model, B, true)

	local hp = B.hp * (1 + CFG.extraPlayerHp * (#list - 1))
	local f = {
		id = id, areaId = areaId, slot = slot, arena = arena, center = center, model = model,
		pos = center, dir = V(0, 0, 1), rage = 1, active = true, players = {},
		hp = hp, maxHp = hp, endsAt = os.clock() + CFG.time, fill = fill, hpText = hpText,
	}
	fights[id] = f
	model:SetAttribute("Active", true)
	model:SetAttribute("BossName", B.name)
	model:SetAttribute("Area", areaId)
	model:SetAttribute("Pos", f.pos)
	model:SetAttribute("EndsAt", workspace:GetServerTimeNow() + CFG.time)
	setHealth(f)
	model.Parent = bossFolder

	for i, player in ipairs(list) do
		if player:GetAttribute("Riding") then
			player:SetAttribute("Riding", false)
			Character.refresh(player)
		end
		local squad = Data.workerSquad(player)
		for _, w in ipairs(squad) do
			w.maxHp = w.hp
			w.ko = false
		end
		local entry = { dealt = 0, squad = squad, nextHit = 0, wiped = false }
		f.players[player] = entry
		byPlayer[player] = f
		player:SetAttribute("WorkerHP", hpString(entry))
		player:SetAttribute("BossFight", id)
		player:SetAttribute("BossArea", areaId)
		local ang = (i - (#list + 1) / 2) * 0.3
		local p = center + V(math.sin(ang) * (R - 18), 4, math.cos(ang) * (R - 18))
		teleport(player, CFrame.lookAt(p, V(center.X, p.Y, center.Z)))
		Remotes.BossFx:FireClient(player, "start", areaId, id, #list)
	end
	task.spawn(run, f)
	task.spawn(brain, f)
	return f
end

---------------------------------------------------------------- requests from players (called by Shop)
local function validArea(areaId): boolean
	return type(areaId) == "number" and areaId % 1 == 0 and Areas.List[areaId] ~= nil
end

-- Can this player enter a fight for this area right now?
local function eligible(player, areaId: number, mustBeNear: boolean)
	local pr = Data.get(player)
	if not pr then
		return fail("Not ready.")
	end
	if byPlayer[player] then
		return fail("You are already in a boss fight.")
	end
	local a = Areas.List[areaId]
	if pr.areasUnlocked < areaId then
		return fail("🔒 Unlock " .. a.name .. " first.")
	end
	local hrp = alive(player)
	if not hrp then
		return fail("You can't do that right now.")
	end
	if mustBeNear and flatDist(hrp.Position, a.bossPos) > Areas.BOSS_ZONE + 14 then
		return fail("Walk up to the " .. a.boss.name .. " first.")
	end
	return true
end

local function closeLobby(lobby, text: string?)
	if lobbies[lobby.host] ~= lobby then
		return
	end
	lobbies[lobby.host] = nil
	local seen = { [lobby.host] = true }
	for player in pairs(lobby.invited) do
		seen[player] = true
	end
	for player in pairs(seen) do
		if player.Parent then
			Remotes.BossFx:FireClient(player, "lobbyEnd", lobby.areaId, lobby.host.UserId)
			if text and player ~= lobby.host and lobby.members[player] then
				Data.notify(player, text, "info")
			end
		end
	end
end

local function begin(lobby)
	if lobbies[lobby.host] ~= lobby then
		return
	end
	local host = lobby.host
	local ok, msg = eligible(host, lobby.areaId, false)
	if not ok then
		closeLobby(lobby, "The boss fight was cancelled.")
		if host.Parent and msg then
			Data.notify(host, msg, "bad")
		end
		return
	end
	local list = { host }
	for player in pairs(lobby.members) do
		if player.Parent and eligible(player, lobby.areaId, false) then
			table.insert(list, player)
		end
	end
	closeLobby(lobby)
	start(lobby.areaId, list)
end

function Boss.solo(player: Player, areaId)
	if not validArea(areaId) then
		return fail("Invalid boss.")
	end
	local ok, msg = eligible(player, areaId, true)
	if not ok then
		return fail(msg)
	end
	if lobbies[player] then
		closeLobby(lobbies[player], "The boss fight was cancelled.")
	end
	start(areaId, { player })
	return true
end

-- Ask everyone else on the server who has this area unlocked to join.
function Boss.invite(player: Player, areaId)
	if not validArea(areaId) then
		return fail("Invalid boss.")
	end
	local ok, msg = eligible(player, areaId, true)
	if not ok then
		return fail(msg)
	end
	if lobbies[player] then
		return fail("You have already sent invites.")
	end
	local invited, count = {}, 0
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and not lobbies[other] and eligible(other, areaId, false) then
			invited[other] = true
			count += 1
		end
	end
	if count == 0 then
		return fail("Nobody else here can fight this boss right now. Try Solo!")
	end
	local lobby = { host = player, areaId = areaId, invited = invited, members = {}, endsAt = os.clock() + CFG.inviteTime }
	lobbies[player] = lobby
	for other in pairs(invited) do
		Remotes.BossFx:FireClient(other, "invite", areaId, player.UserId, player.DisplayName, CFG.inviteTime)
	end
	Remotes.BossFx:FireClient(player, "lobby", areaId, CFG.inviteTime, 0, count)
	task.delay(CFG.inviteTime, begin, lobby)
	return true
end

-- An invited player answers.
function Boss.respond(player: Player, hostId, accept)
	local host = type(hostId) == "number" and Players:GetPlayerByUserId(hostId)
	local lobby = host and lobbies[host]
	if not lobby or not lobby.invited[player] then
		return fail("That invite has ended.")
	end
	if accept ~= true then
		lobby.invited[player] = nil
		lobby.members[player] = nil
		return true
	end
	local ok, msg = eligible(player, lobby.areaId, false)
	if not ok then
		return fail(msg)
	end
	lobby.members[player] = true
	local joined, total = 0, 0
	for _ in pairs(lobby.members) do
		joined += 1
	end
	for _ in pairs(lobby.invited) do
		total += 1
	end
	Remotes.BossFx:FireClient(host, "lobby", lobby.areaId, math.max(0, lobby.endsAt - os.clock()), joined, total)
	Data.notify(host, "👥 " .. player.DisplayName .. " joined your boss fight!", "good")
	return true, "Joined! You will be teleported when the fight starts."
end

-- The host starts early instead of waiting for the invite timer.
function Boss.beginNow(player: Player)
	local lobby = lobbies[player]
	if not lobby then
		return fail("You have no invites out.")
	end
	begin(lobby)
	return true
end

function Boss.cancel(player: Player)
	local lobby = lobbies[player]
	if lobby then
		closeLobby(lobby, "The boss fight was cancelled.")
	end
	return true
end

-- Walk away from a fight that is running.
function Boss.leave(player: Player)
	local f = byPlayer[player]
	if not f or not f.active then
		return fail("You are not in a boss fight.")
	end
	Remotes.BossFx:FireClient(player, "left", f.areaId, f.id)
	release(f, player, true)
	return true
end

function Boss.inFight(player: Player): boolean
	return byPlayer[player] ~= nil
end

---------------------------------------------------------------- setup
function Boss.init()
	bossFolder = Instance.new("Folder")
	bossFolder.Name = "Bosses"
	bossFolder.Parent = workspace
	arenaFolder = Instance.new("Folder")
	arenaFolder.Name = "Arenas"
	arenaFolder.Parent = workspace
	local ZR = Areas.ARENA_RADIUS
	-- the stone circle in each area, with the boss standing on it for show
	for areaId, a in ipairs(Areas.List) do
		local B = a.boss
		local pos = a.bossPos
		local disc = Models.P(arenaFolder, V(1.2, ZR * 2, ZR * 2), CF(pos + V(0, 0.1, 0)) * ANG(0, 0, rad(90)), Color3.fromRGB(45, 42, 50), "Slate", "Cylinder")
		disc.CanCollide = true
		disc.CanQuery = true
		Models.P(arenaFolder, V(0.5, ZR * 2 + 3, ZR * 2 + 3), CF(pos + V(0, 0.15, 0)) * ANG(0, 0, rad(90)), B.color2, "Neon", "Cylinder")
		for i = 0, 5 do
			local ang = rad(i * 60 + 30)
			local pp = pos + V(math.sin(ang) * (ZR + 0.5), 0, math.cos(ang) * (ZR + 0.5))
			local pillar = Models.cyl(arenaFolder, 9, 1.8, pp + V(0, 4.5, 0), a.wall, "Slate")
			pillar.CanCollide = true
			local orb = Models.P(arenaFolder, V(2, 2, 2), CF(pp + V(0, 10, 0)), B.color2, "Neon", "Ball")
			Models.glow(orb, B.color2, 16)
		end
		local model = Models.boss(areaId)
		Models.weld(model)
		model:PivotTo(CFrame.lookAt(pos + V(0, 0.7, 0), pos + V(0, 0.7, 1)))
		model.Name = "Display" .. areaId
		bossGui(model, B, false)
		model.Parent = arenaFolder
	end
	Players.PlayerRemoving:Connect(function(player)
		local lobby = lobbies[player]
		if lobby then
			closeLobby(lobby, "The boss fight was cancelled.")
		end
		for _, other in pairs(lobbies) do
			other.invited[player] = nil
			other.members[player] = nil
		end
		local f = byPlayer[player]
		if f then
			release(f, player, false)
		end
	end)
end

return Boss
