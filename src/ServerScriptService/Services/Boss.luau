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
local WCFG = Game.WorldBoss
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
	local ang, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(6, f.R - 24)
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
			-- the world boss takes a share of the worker's own health, so it is as dangerous to a strong squad as to a weak one
			local dmg = (f.world and w.maxHp * WCFG.hitPct or B.attack) * mult * rng:NextNumber(0.9, 1.1)
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
	local mult = move.mult * f.rage * (f.fury or 1)
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
		local target = out.Magnitude > 8 and (f.center - out.Unit * (f.R - 22)) or (f.center + f.dir * (f.R - 22))
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
		local untilT = os.clock() + B.tempo / (f.fury or 1)
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

---------------------------------------------------------------- world boss: fury and rewards
-- Called 5 times a second during the world fight: the boss gets angrier as it weakens,
-- and every player's share of the damage is sent out once a second.
local function worldTick(f, everySecond: boolean)
	local frac = f.maxHp > 0 and math.clamp(f.hp / f.maxHp, 0, 1) or 0
	local fury = 1
	for _, phase in ipairs(WCFG.fury) do
		if frac <= phase[1] then
			fury = math.max(fury, phase[2])
		end
	end
	if fury > f.fury then
		f.fury = fury
		fire(f, "move", f.areaId, f.id, "roar", f.pos, 0.8)
		for player in pairs(f.players) do
			Data.notify(player, "😡 The " .. Areas.List[f.areaId].boss.name .. " is furious! It hits harder and faster.", "bad")
		end
	end
	if everySecond then
		local total, n = 0, 0
		for _, entry in pairs(f.players) do
			total += entry.dealt
			n += 1
		end
		for player, entry in pairs(f.players) do
			player:SetAttribute("BossShare", total > 0 and math.floor(entry.dealt / total * 100 + 0.5) or 0)
		end
		workspace:SetAttribute("WorldBossHp", math.ceil(frac * 100))
		workspace:SetAttribute("WorldBossPlayers", n)
	end
end

-- Share out the rewards by damage dealt. Cash is scaled to each player's own best area,
-- so the reward matters to a new player and a veteran alike.
local function worldRewards(f, won: boolean)
	local B = Areas.List[f.areaId].boss
	local RW = WCFG.reward
	local list, total = {}, 0
	for player, entry in pairs(f.players) do
		if player.Parent and entry.dealt > 0 and Data.get(player) then
			table.insert(list, { player = player, dealt = entry.dealt })
			total += entry.dealt
		end
	end
	table.sort(list, function(x, y)
		return x.dealt > y.dealt
	end)
	local done = f.maxHp > 0 and math.clamp(1 - math.max(0, f.hp) / f.maxHp, 0, 1) or 0
	for rank, it in ipairs(list) do
		local player = it.player
		local pr = Data.get(player)
		local share = it.dealt / total
		local best = Areas.List[math.clamp(math.max(pr.areasUnlocked, pr.stats.maxArea or 1), 1, Areas.COUNT)]
		local parts = {}
		local cash
		if won then
			cash = math.floor(best.boss.cash * (RW.cashBase + RW.cashShare * share) * Data.cashMult(player))
			local dia = Data.addDiamonds(player, math.floor(RW.diamondsBase + RW.diamondsShare * share), true)
			table.insert(parts, "+" .. dia .. " 💎")
			local crates = (rank == 1 and #list > 1 and 1 or 0) + (share >= RW.crateShare and 1 or 0)
			if crates > 0 then
				local crateId = Crates.forArea(best.id)
				Data.addCrate(player, crateId, crates)
				table.insert(parts, crates .. "x " .. crateId .. " Crate")
			end
			Data.addStat(player, "bosses", 1)
		else
			cash = math.floor(best.boss.cash * RW.failCash * share * done * Data.cashMult(player))
		end
		if cash > 0 then
			Data.addCash(player, cash, true)
			table.insert(parts, 1, "+$" .. Util.fmt(cash))
		end
		local pct = math.floor(share * 100 + 0.5)
		local head = won and ("🌍 " .. B.name .. " defeated!") or ("🌍 The " .. B.name .. " survived with " .. math.ceil((1 - done) * 100) .. "% health.")
		Data.notify(player, head .. " You dealt " .. pct .. "% of the damage (#" .. rank .. " of " .. #list .. ")" .. (#parts > 0 and (": " .. table.concat(parts, ", ")) or "."), "big")
		Data.sync(player, "crates")
	end
	if won and list[1] then
		local top = list[1]
		local text = "🌍 The " .. B.name .. " has fallen! Top damage: " .. top.player.DisplayName .. " (" .. math.floor(top.dealt / total * 100 + 0.5) .. "%)"
		for _, other in ipairs(Players:GetPlayers()) do
			if not f.players[other] then
				Data.notify(other, text, "info")
			end
		end
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
	player:SetAttribute("BossShare", nil)
	if back then
		-- players who came through the portal in town (the world boss) go back there
		local pos = f.back[player] or Areas.bossReturnPos(f.areaId)
		f.back[player] = nil
		teleport(player, CFrame.lookAt(pos, pos + V(0, 0, 1))) -- facing away from the boss, towards the grass
	end
end

local function finish(f, won: boolean)
	if not f.active then
		return
	end
	f.active = false
	f.model:SetAttribute("Active", false)
	if f.world then
		worldRewards(f, won)
	end
	for player, entry in pairs(f.players) do
		if player.Parent then
			if won and entry.dealt > 0 and not f.world then
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
	fights[f.id] = nil
	if f.world then
		-- the arena stays; the boss rests for a while before it can be fought again
		f.onEnd()
	else
		f.arena:Destroy()
		slots[f.slot] = nil
	end
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
		if f.world then
			worldTick(f, doWorkers)
		end
		if f.hp <= 0 then
			finish(f, true)
			break
		end
	end
end

-- Put a player into a fight: their squad, their attributes, and a place at the arena's edge
-- (spot i of n, fanned out around the side the players come in by).
local function enter(f, player, i: number, n: number)
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
	player:SetAttribute("BossFight", f.id)
	player:SetAttribute("BossArea", f.areaId)
	local ang = (i - (n + 1) / 2) * 0.3
	local p = f.center + V(math.sin(ang) * (f.R - 18), 4, math.cos(ang) * (f.R - 18))
	teleport(player, CFrame.lookAt(p, V(f.center.X, p.Y, f.center.Z)))
	Remotes.BossFx:FireClient(player, "start", f.areaId, f.id, n)
	return entry
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
		id = id, areaId = areaId, slot = slot, arena = arena, center = center, R = R, model = model,
		pos = center, dir = V(0, 0, 1), rage = 1, active = true, players = {},
		hp = hp, maxHp = hp, endsAt = os.clock() + CFG.time, fill = fill, hpText = hpText,
		back = {}, -- [player] = where to put them afterwards, if not beside the boss's plaza
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
		enter(f, player, i, #list)
	end
	task.spawn(run, f)
	task.spawn(brain, f)
	return f
end

---------------------------------------------------------------- requests from players (called by Shop)
local function validArea(areaId): boolean
	return type(areaId) == "number" and areaId % 1 == 0 and areaId >= 1 and areaId <= Areas.COUNT
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

---------------------------------------------------------------- the world boss
-- One boss the whole server fights together, reached from the green portal in front of
-- the castle. The first player through the portal starts the fight; anyone can join while
-- it runs. Its health is worked out from the strength of the players who join, so it is
-- hard for a new player and a veteran alike, and its attacks take a share of each worker's
-- own health. Rewards are shared by how much of the damage each player dealt.
local WORLD = Areas.WORLD_ID
local worldFight = nil
local worldArena = nil
local rgb = Color3.fromRGB

local function setWorld(state: string, seconds: number?)
	workspace:SetAttribute("WorldBoss", state)
	workspace:SetAttribute("WorldBossUntil", workspace:GetServerTimeNow() + (seconds or 0))
	if state ~= "fighting" then
		workspace:SetAttribute("WorldBossHp", 100)
		workspace:SetAttribute("WorldBossPlayers", 0)
	end
end

-- The arena: a ruined colosseum on a floating rock, taken over by giant vines.
local function buildWorldArena()
	local C, WR = Areas.WORLD_CENTER, Areas.WORLD_RADIUS
	local arena = Instance.new("Model")
	arena.Name = "WorldArena"
	local flat = ANG(0, 0, rad(90))
	local stone, stone2, dark = rgb(128, 132, 128), rgb(104, 108, 106), rgb(52, 56, 60)
	local moss, leaf, bark = rgb(70, 128, 66), rgb(52, 150, 70), rgb(74, 54, 40)
	local glowC, gold = rgb(120, 255, 110), rgb(255, 214, 90)
	local prng = Random.new(4242)
	local function P(size, cf, color, mat, shape)
		return Models.P(arena, size, cf, color, mat, shape)
	end
	local function solid(p)
		p.CanCollide = true
		p.CanQuery = true
		return p
	end
	local function disc(d, y, h, color, mat)
		return P(V(h, d, d), CF(C + V(0, y, 0)) * flat, color, mat, "Cylinder")
	end

	-- floor: the fighting ring, with paving rings and glowing runes, and mossy ground around it
	solid(disc((WR + 70) * 2, -5, 8, moss, "Grass")).Name = "Ground"
	solid(disc(WR * 2 + 12, -4, 8, dark, "Slate")).Name = "Floor"
	disc(WR * 2 - 6, 0.05, 0.3, stone, "Cobblestone")
	disc(WR * 1.56, 0.1, 0.3, moss, "Grass")
	disc(WR * 1.48, 0.15, 0.3, stone2, "Slate")
	disc(WR * 0.86, 0.2, 0.3, glowC, "Neon")
	disc(WR * 0.82, 0.25, 0.3, dark, "Slate")
	disc(WR * 0.34, 0.3, 0.3, moss, "Grass")
	disc(WR * 0.2, 0.35, 0.3, glowC, "Neon").Transparency = 0.3
	for i = 0, 23 do
		local rune = i % 3 == 0
		local spoke = P(V(rune and 1.6 or 2.4, 0.5, WR * (rune and 0.3 or 0.2)), CF(C + V(0, 0.12, 0)) * ANG(0, rad(i * 15), 0) * CF(0, 0, -WR * (rune and 0.58 or 0.86)), rune and glowC or dark, rune and "Neon" or "Slate")
		if rune then
			spoke.Transparency = 0.15
		end
	end
	-- the rock it all floats on, with crystals hanging underneath
	for i, scale in ipairs({ 0.95, 0.74, 0.5, 0.28 }) do
		disc((WR + 70) * 2 * scale, -20 - (i - 1) * 24, 24, i % 2 == 1 and stone2 or dark, "Slate")
	end
	for i = 1, 14 do
		local ang = prng:NextNumber(0, math.pi * 2)
		local r = prng:NextNumber(20, WR + 40)
		local len = prng:NextNumber(14, 34)
		P(V(5, len, 5), CF(C + V(math.sin(ang) * r, -34 - len / 2 - (WR + 40 - r) * 0.5, math.cos(ang) * r)) * ANG(prng:NextNumber(-0.2, 0.2), prng:NextNumber(0, 3), prng:NextNumber(-0.2, 0.2)), glowC, "Neon").Transparency = 0.2
	end

	-- the colosseum: a ring wall, two tiers of stands behind it, and great pillars
	local SEG = 36
	local function width(r)
		return 2 * r * math.tan(math.pi / SEG) + 0.6
	end
	for i = 0, SEG - 1 do
		local ang = (i / SEG) * math.pi * 2
		local dir = V(math.sin(ang), 0, math.cos(ang))
		local at = C + dir * WR
		local face = CFrame.lookAt(at, C) -- local +Z points away from the middle
		local barrier = solid(P(V(width(WR), 160, 2), face * CF(0, 80, 0), stone))
		barrier.Transparency = 1
		barrier.Name = "Barrier"
		local gate = i == 0 -- the gap the players walk in through (it is only for show)
		if not gate then
			solid(P(V(width(WR + 2), 16, 5), face * CF(0, 8, 2.5), prng:NextNumber() < 0.5 and stone or stone2, "Cobblestone"))
			P(V(width(WR + 2), 1.6, 6.4), face * CF(0, 16.6, 2.5), dark, "Slate")
			if i % 2 == 0 then
				P(V(width(WR + 2) * 0.5, 3.6, 5), face * CF(0, 19, 2.5), stone2, "Cobblestone")
			end
			if prng:NextNumber() < 0.6 then
				local h = prng:NextNumber(4, 11)
				P(V(width(WR) * prng:NextNumber(0.4, 0.8), h, 0.7), face * CF(prng:NextNumber(-3, 3), 16 - h / 2, -0.2), moss, "Grass")
			end
		end
		-- stands: broken in places, like a ruin
		local broken = prng:NextNumber() < 0.14
		P(V(width(WR + 12), 22, 14), face * CF(0, 9, 12), stone2, "Slate")
		P(V(width(WR + 12), 1.4, 3), face * CF(0, 20.6, 6.5), dark, "Slate")
		if not broken then
			P(V(width(WR + 26), 34, 14), face * CF(0, 15, 26), stone, "Slate")
			P(V(width(WR + 26), 1.4, 3), face * CF(0, 32.6, 20.5), dark, "Slate")
			if i % 3 == 1 then
				-- a banner pole on the top tier
				P(V(0.8, 24, 0.8), face * CF(0, 44, 31), dark, "Metal")
				P(V(0.4, 12, 6), face * CF(0, 48, 27.6), i % 2 == 0 and glowC or gold, "Fabric")
			end
		else
			P(V(width(WR + 26) * 0.6, prng:NextNumber(10, 20), 12), face * CF(prng:NextNumber(-4, 4), 6, 26) * ANG(0, 0, prng:NextNumber(-0.2, 0.2)), stone, "Slate")
		end
		if i % 4 == 2 then
			-- a great pillar just inside the wall with a burning green beacon on top
			local base = at - dir * 5
			solid(P(V(11, 5, 11), CF(base + V(0, 2.5, 0)) * ANG(0, ang, 0), dark, "Slate"))
			solid(Models.cyl(arena, 44, 7.5, base + V(0, 27, 0), stone, "Slate"))
			for k = 0, 2 do
				Models.cyl(arena, 1.4, 8.8, base + V(0, 12 + k * 14, 0), dark, "Slate")
			end
			P(V(12, 3, 12), CF(base + V(0, 50.5, 0)) * ANG(0, ang, 0), dark, "Slate")
			Models.cyl(arena, 2.4, 9, base + V(0, 53.2, 0), gold, "Metal")
			local orb = P(V(7, 7, 7), CF(base + V(0, 58, 0)), glowC, "Neon", "Ball")
			Models.glow(orb, glowC, 60, 14)
			local beam = Models.cyl(arena, 150, 1.6, base + V(0, 135, 0), glowC, "Neon")
			beam.Transparency = 0.7
			-- a vine winding up the pillar
			for k = 0, 9 do
				local va = ang + k * 0.9
				P(V(1.6, 6.5, 1.6), CF(base + V(math.sin(va) * 4.2, 6 + k * 4.4, math.cos(va) * 4.2)) * ANG(rad(24), va, 0), leaf, "Grass")
			end
		end
	end
	-- the gate the players come in by: two towers and an arch
	do
		local at = C + V(0, 0, WR)
		for _, sx in ipairs({ -1, 1 }) do
			solid(P(V(9, 30, 9), CF(at + V(sx * 13, 15, 3)), stone, "Cobblestone"))
			P(V(11, 2, 11), CF(at + V(sx * 13, 31, 3)), dark, "Slate")
			local orb = P(V(4, 4, 4), CF(at + V(sx * 13, 35, 3)), glowC, "Neon", "Ball")
			Models.glow(orb, glowC, 30)
		end
		P(V(36, 5, 7), CF(at + V(0, 27, 3)), stone2, "Cobblestone")
		P(V(18, 9, 1), CF(at + V(0, 20, -0.6)), rgb(30, 60, 36), "Fabric")
		P(V(5, 5, 1.2), CF(at + V(0, 20, -0.9)) * ANG(0, 0, rad(45)), glowC, "Neon")
	end

	-- giant vines pouring over the walls into the ring
	for j = 0, 6 do
		local ang = rad(j * 51 + 24)
		local dir = V(math.sin(ang), 0, math.cos(ang))
		local side = V(dir.Z, 0, -dir.X)
		local sway = prng:NextNumber(-14, 14)
		local last
		for k = 0, 9 do
			local t = k / 9
			local r = WR + 38 - t * 41 -- over the stands and down the inside of the wall
			local y = 2 + 44 * math.sin(math.min(1, t * 1.25) * math.pi) * (1 - t * 0.55)
			local p = C + dir * r + side * math.sin(t * 3) * sway + V(0, y, 0)
			if last then
				local thick = 6.5 - t * 3.5
				P(V(thick, thick, (p - last).Magnitude + 1.5), CFrame.lookAt((p + last) / 2, p), k % 2 == 0 and leaf or moss, "Grass")
				if k % 3 == 0 and k < 9 then
					P(V(9, 1, 5), CF(p + V(0, thick * 0.6, 0)) * ANG(rad(20), ang + k, 0), leaf, "Grass")
				end
			end
			last = p
		end
		local bud = P(V(6, 6, 6), CF(last), glowC, "Neon", "Ball")
		Models.glow(bud, glowC, 26, 4)
	end
	-- huge old trees behind the stands, and rocks drifting in the sky around the arena
	for j = 0, 8 do
		local ang = rad(j * 40 + 12)
		local base = C + V(math.sin(ang), 0, math.cos(ang)) * (WR + 52)
		local h = prng:NextNumber(58, 78)
		Models.cyl(arena, h, 10, base + V(0, h / 2 - 2, 0), bark, "Wood")
		for k = 1, 4 do
			local off = V(prng:NextNumber(-13, 13), prng:NextNumber(-6, 8), prng:NextNumber(-13, 13))
			P(V(34, 26, 34) * prng:NextNumber(0.75, 1.1), CF(base + V(0, h, 0) + off), k % 2 == 0 and leaf or moss, "Grass", "Ball")
		end
		local fruit = P(V(3, 3, 3), CF(base + V(prng:NextNumber(-10, 10), h - 12, prng:NextNumber(-10, 10))), glowC, "Neon", "Ball")
		Models.glow(fruit, glowC, 22)
	end
	for _ = 1, 12 do
		local ang = prng:NextNumber(0, math.pi * 2)
		local at = C + V(math.sin(ang), 0, math.cos(ang)) * prng:NextNumber(WR + 110, WR + 190) + V(0, prng:NextNumber(-40, 60), 0)
		local s = prng:NextNumber(14, 34)
		local turn = ANG(prng:NextNumber(-0.3, 0.3), prng:NextNumber(0, 3), prng:NextNumber(-0.3, 0.3))
		P(V(s, s * 0.6, s * 0.8), CF(at) * turn, stone2, "Slate")
		P(V(s * 0.9, 2, s * 0.7), CF(at) * turn * CF(0, s * 0.3 + 0.8, 0), moss, "Grass")
	end
	-- glowing spores drifting up from the floor
	local mist = P(V(WR * 1.7, 1, WR * 1.7), CF(C + V(0, 1, 0)), glowC)
	mist.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(glowC)
	e.Rate = 26
	e.Lifetime = NumberRange.new(5, 8)
	e.Speed = NumberRange.new(1.5, 3.5)
	e.SpreadAngle = Vector2.new(25, 25)
	e.EmissionDirection = Enum.NormalId.Top
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.7), NumberSequenceKeypoint.new(1, 0) })
	e.LightEmission = 0.9
	e.Parent = mist
	return arena
end

-- The boss itself: the biggest model in the game, dressed in vines and thorns.
local function worldModel()
	local B = Areas.List[WORLD].boss
	local S = B.size
	local m = Models.boss(WORLD)
	local leaf, bark, thorn, glowC = rgb(52, 150, 70), rgb(74, 54, 40), rgb(232, 240, 205), B.color2
	local function P(size, cf, color, mat, shape)
		return Models.P(m, size, cf, color, mat, shape)
	end
	-- a glowing heart and bigger, burning eyes
	local core = P(V(S * 0.32, S * 0.32, S * 0.14), CF(0, S * 0.56, -S * 0.42), glowC, "Neon", "Ball")
	Models.glow(core, glowC, S * 2.2, 14)
	for _, sx in ipairs({ -1, 1 }) do
		P(V(S * 0.13, S * 0.13, S * 0.08), CF(sx * S * 0.12, S * 1.33, -S * 0.27), glowC, "Neon", "Ball")
		-- thorns on the shoulders
		for k = 0, 2 do
			P(V(S * 0.1, S * 0.5, S * 0.1), CF(sx * S * 0.6, S * 1.02, 0) * ANG(0, 0, rad(-sx * (18 + k * 26))) * CF(0, S * 0.3, 0), thorn, "Slate")
		end
		-- vines hanging from the arms
		for k = 0, 2 do
			P(V(S * 0.05, S * 0.34, S * 0.05), CF(sx * S * (0.6 + k * 0.07), S * 0.3, S * 0.06 * (k - 1)), leaf, "Grass")
		end
	end
	-- bands of vine and bark round the body
	for i = 0, 3 do
		P(V(S * 0.96, S * 0.08, S * 0.76), CF(0, S * (0.18 + i * 0.24), 0) * ANG(0, 0, rad(i % 2 == 0 and 8 or -8)), i % 2 == 0 and leaf or bark, i % 2 == 0 and "Grass" or "Wood")
	end
	-- a mane of leaves behind the head, spines down the back, roots at the feet
	for i = 0, 6 do
		P(V(S * 0.2, S * 0.52, S * 0.05), CF(0, S * 1.26, S * 0.2) * ANG(0, 0, rad(-90 + i * 30)) * CF(0, S * 0.46, 0), i % 2 == 0 and leaf or rgb(90, 190, 84), "Grass")
	end
	for i = 0, 3 do
		P(V(S * 0.1, S * 0.36, S * 0.1), CF(0, S * (0.3 + i * 0.24), S * 0.4) * ANG(rad(48), 0, 0), thorn, "Slate")
	end
	for i = 0, 5 do
		P(V(S * 0.62, S * 0.11, S * 0.13), CF(0, S * 0.05, 0) * ANG(0, rad(i * 60 + 30), rad(-6)) * CF(S * 0.52, 0, 0), bark, "Wood")
	end
	-- shards of light circling the crown
	for i = 0, 5 do
		local a = rad(i * 60)
		P(V(S * 0.05, S * 0.18, S * 0.05), CF(math.sin(a) * S * 0.42, S * 1.86, math.cos(a) * S * 0.42) * ANG(rad(15), a, 0), glowC, "Neon")
	end
	return m
end

local function countPlayers(f): number
	local n = 0
	for _ in pairs(f.players) do
		n += 1
	end
	return n
end

-- Put a player into the world fight. The boss gains health to match what they bring.
local function worldEnter(f, player)
	local before = countPlayers(f)
	local entry = enter(f, player, rng:NextInteger(1, 11), 11)
	local s = Data.mowStats(player)
	local dps = s.damage * s.speed -- the mower (it only hits while the player stands beside the boss)
	for _, w in ipairs(entry.squad) do
		dps += w.dmg
	end
	local left = math.clamp((f.endsAt - os.clock()) / WCFG.time, 0, 1)
	local add = dps * (before == 0 and WCFG.firstHp or WCFG.extraHp) * left
	f.hp += add
	f.maxHp += add
	f.back[player] = Areas.PORTAL_POS + V(0, 5, Areas.PORTAL_RADIUS + 8)
	player:SetAttribute("BossShare", 0)
	setHealth(f)
end

local function startWorld(first: Player)
	local B = Areas.List[WORLD].boss
	nextId += 1
	local id = nextId
	local center = Areas.WORLD_CENTER
	local model = worldModel()
	Models.weld(model)
	model.Name = "F" .. id
	model:PivotTo(CFrame.lookAt(center + V(0, 0.7, 0), center + V(0, 0.7, 1)))
	local fill, hpText = bossGui(model, B, true)
	local f = {
		id = id, areaId = WORLD, world = true, slot = 0, arena = worldArena, center = center, R = Areas.WORLD_RADIUS, model = model,
		pos = center, dir = V(0, 0, 1), rage = 1, fury = 1, active = true, players = {},
		hp = 0, maxHp = 0, endsAt = os.clock() + WCFG.time, fill = fill, hpText = hpText, back = {},
	}
	f.onEnd = function()
		worldFight = nil
		setWorld("cooldown", WCFG.cooldown)
		task.delay(WCFG.cooldown, function()
			if not worldFight then
				setWorld("ready")
			end
		end)
	end
	fights[id] = f
	worldFight = f
	model:SetAttribute("Active", true)
	model:SetAttribute("BossName", B.name)
	model:SetAttribute("Area", WORLD)
	model:SetAttribute("Pos", f.pos)
	model:SetAttribute("EndsAt", workspace:GetServerTimeNow() + WCFG.time)
	model.Parent = bossFolder
	worldEnter(f, first)
	setWorld("fighting", WCFG.time)
	workspace:SetAttribute("WorldBossPlayers", 1)
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= first then
			Data.notify(other, "🌍 " .. first.DisplayName .. " woke the " .. B.name .. "! Step on the green portal by the castle to join the fight.", "big")
		end
	end
	task.spawn(run, f)
	task.spawn(brain, f)
end

function Boss.worldJoin(player: Player)
	if not Data.get(player) then
		return fail("Not ready.")
	end
	if byPlayer[player] then
		return fail("You are already in a boss fight.")
	end
	local hrp = alive(player)
	if not hrp then
		return fail("You can't do that right now.")
	end
	if flatDist(hrp.Position, Areas.PORTAL_POS) > Areas.PORTAL_RADIUS + 10 then
		return fail("Step onto the green portal by the castle first.")
	end
	if workspace:GetAttribute("WorldBoss") == "cooldown" then
		local left = (workspace:GetAttribute("WorldBossUntil") or 0) - workspace:GetServerTimeNow()
		return fail("The world boss is resting. It returns in " .. Util.clock(left) .. ".")
	end
	if lobbies[player] then
		closeLobby(lobbies[player], "The boss fight was cancelled.")
	end
	local f = worldFight
	if f then
		if not f.active then
			return fail("The last fight is just ending. Try again in a moment.")
		end
		if f.endsAt - os.clock() < WCFG.joinUntil then
			return fail("This fight is nearly over. Catch the next one!")
		end
		worldEnter(f, player)
		return true, "You joined the world boss fight!"
	end
	startWorld(player)
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
	worldArena = buildWorldArena()
	worldArena.Parent = arenaFolder
	setWorld("ready")
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
