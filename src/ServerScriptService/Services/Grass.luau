-- Grass tiles, mowing, worker mowing, bag, selling and area completion.
-- Fully server-driven: the client never tells the server what it cut.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local Areas = require(RS.Shared.Config.Areas)
local Game = require(RS.Shared.Config.Game)
local Util = require(RS.Shared.Util)
local Style = require(RS.Shared.Style)
local Data = require(script.Parent.Data)
local Remotes = RS.Remotes

local Grass = {}
local GRID, TILE, TILES = Areas.GRID, Areas.TILE, Areas.TILES
local SELL_RANGE = 9

local state = {} -- [areaId] = { hp, alive, parts, queue, head }
local cutCallbacks = {}
local nextHit = {}
local lastHit = {}
local clickUntil = {} -- [player] = time the click boost runs out
local mowingUntil = {} -- [player] = time the "Mowing" attribute switches off
local nextWorker = {}
local lastFullWarn = {}
local fxBatch = {}
local dirty = {} -- [player] = { progress = bool, gain = n, pos = Vector3 }
local crateForArea -- injected by Crates service

function Grass.onCut(cb)
	table.insert(cutCallbacks, cb)
end
function Grass.setCrateForArea(fn)
	crateForArea = fn
end
function Grass.isAlive(areaId, idx)
	return state[areaId].alive[idx]
end

local function bagFull(player, pr)
	return pr.bagCount >= Data.bagCapacity(player) - 0.001
end

function Grass.sell(player: Player)
	local pr = Data.get(player)
	if not pr or pr.bagCount <= 0 then
		return
	end
	local amount = math.floor(pr.bagValue * Data.cashMult(player) + 0.5)
	pr.bagCount = 0
	pr.bagValue = 0
	Data.addCash(player, amount, true)
	Data.sync(player, "bagCount", "bagValue")
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	Remotes.Gain:FireClient(player, "cash", amount, hrp and hrp.Position or Vector3.zero)
end

local function canAutoSell(player, pr)
	return (pr.perks.autoSell or Data.hasPass(player, "AutoSell")) and pr.settings.autoSell ~= false
end

local function milestones(player, pr, areaId, p)
	local a = Areas.List[areaId]
	local pct = p.count / TILES * 100
	while p.ms < #Areas.MILESTONES and pct >= Areas.MILESTONES[p.ms + 1] do
		p.ms += 1
		local cash = math.floor(Areas.MILESTONE_CASH[p.ms] * a.grassValue * Data.cashMult(player))
		Data.addCash(player, cash, true)
		local text = "+$" .. Util.fmt(cash)
		if p.ms == #Areas.MILESTONES and crateForArea then
			local crateId = crateForArea(areaId)
			Data.addCrate(player, crateId, 1)
			text ..= " + " .. crateId .. " Crate"
		end
		Remotes.Milestone:FireClient(player, areaId, Areas.MILESTONES[p.ms], text)
	end
end

local function cut(player, pr, areaId, idx, eff)
	local st = state[areaId]
	local a = Areas.List[areaId]
	st.alive[idx] = false
	st.parts[idx].Transparency = 1
	table.insert(st.queue, { idx, os.clock() + Areas.RESPAWN })
	local batch = fxBatch[areaId]
	if not batch then
		batch = {}
		fxBatch[areaId] = batch
	end
	table.insert(batch, idx)

	local d = dirty[player]
	if not d then
		d = { gain = 0 }
		dirty[player] = d
	end
	local cap = Data.bagCapacity(player)
	local units = math.min(eff, cap - pr.bagCount)
	if units > 0 then
		pr.bagCount += units
		pr.bagValue += units * a.grassValue
		d.gain += units
		d.pos = Areas.tilePos(areaId, idx)
		Data.addStat(player, "grassCut", units)
	end
	local p = Data.progress(pr, areaId)
	if not p.set[idx] then
		p.set[idx] = true
		p.count += 1
		d.progress = true
		milestones(player, pr, areaId, p)
	end
	for _, cb in ipairs(cutCallbacks) do
		cb(player, areaId, idx)
	end
end

local function damage(player, pr, areaId, idx, dmg, eff)
	local st = state[areaId]
	local hp = st.hp[idx] - dmg
	st.hp[idx] = hp
	if hp <= 0 then
		cut(player, pr, areaId, idx, eff)
	end
end

local function handleFull(player, pr, now)
	if canAutoSell(player, pr) then
		Grass.sell(player)
		return false
	end
	if now - (lastFullWarn[player] or 0) > 5 then
		lastFullWarn[player] = now
		Data.notify(player, "🎒 Your bag is full! Sell your grass at a 💰 selling station.", "bad")
	end
	return true
end

local function mowerHit(player, pr, areaId, pos, s)
	local st = state[areaId]
	local col, row = Areas.tileCoord(areaId, pos)
	local reach = math.ceil(s.radius / TILE)
	local r2 = (s.radius + TILE * 0.35) ^ 2
	local a = Areas.List[areaId]
	local ox, oz = a.center.X - GRID * TILE / 2, a.center.Z - GRID * TILE / 2
	local hits = 0
	for dr = -reach, reach do
		local rr = row + dr
		if rr >= 0 and rr < GRID then
			for dc = -reach, reach do
				local cc = col + dc
				if cc >= 0 and cc < GRID then
					local idx = rr * GRID + cc + 1
					if st.alive[idx] then
						local dx = ox + (cc + 0.5) * TILE - pos.X
						local dz = oz + (rr + 0.5) * TILE - pos.Z
						if dx * dx + dz * dz <= r2 then
							damage(player, pr, areaId, idx, s.damage, s.eff)
							hits += 1
						end
					end
				end
			end
		end
	end
	return hits
end

local WORKER_REACH = 7
local function workersHit(player, pr, areaId, pos)
	local dmgs = Data.workerDamages(player)
	local k = #dmgs
	if k == 0 then
		return
	end
	local st = state[areaId]
	local col, row = Areas.tileCoord(areaId, pos)
	local best = {} -- sorted nearest alive tiles { d2, idx }
	for dr = -WORKER_REACH, WORKER_REACH do
		local rr = row + dr
		if rr >= 0 and rr < GRID then
			for dc = -WORKER_REACH, WORKER_REACH do
				local cc = col + dc
				if cc >= 0 and cc < GRID then
					local idx = rr * GRID + cc + 1
					if st.alive[idx] then
						local d2 = dr * dr + dc * dc
						if #best < k or d2 < best[#best][1] then
							local pos2 = #best + 1
							for i = 1, #best do
								if d2 < best[i][1] then
									pos2 = i
									break
								end
							end
							table.insert(best, pos2, { d2, idx })
							if #best > k then
								table.remove(best)
							end
						end
					end
				end
			end
		end
	end
	local eff = Data.hasPass(player, "Grass2x") and 2 or 1
	for i, entry in ipairs(best) do
		if st.alive[entry[2]] then
			damage(player, pr, areaId, entry[2], dmgs[i], eff)
		end
	end
end

local function nearSell(pos, areaId)
	local target
	if areaId == 0 then
		target = Areas.Shops.Sell
	elseif areaId then
		target = Areas.List[areaId].sellPos
	end
	if target then
		local dx, dz = pos.X - target.X, pos.Z - target.Z
		return dx * dx + dz * dz <= SELL_RANGE * SELL_RANGE
	end
	return false
end

local function step()
	local now = os.clock()
	-- regrow
	for areaId, st in pairs(state) do
		local q = st.queue
		while q[st.head] and q[st.head][2] <= now do
			local idx = q[st.head][1]
			q[st.head] = nil
			st.head += 1
			st.alive[idx] = true
			st.hp[idx] = Areas.List[areaId].grassHP
			st.parts[idx].Transparency = 0
		end
		if st.head > 4096 and q[st.head] == nil then
			st.queue = {}
			st.head = 1
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local pr = Data.get(player)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if pr and hrp and hum and hum.Health > 0 then
			local pos = hrp.Position
			local areaId = Areas.at(pos)
			if player:GetAttribute("Area") ~= (areaId or -1) then
				player:SetAttribute("Area", areaId or -1)
			end
			if pr.bagCount > 0 and nearSell(pos, areaId) then
				Grass.sell(player)
			end
			if areaId and areaId >= 1 and areaId <= pr.areasUnlocked and (player:GetAttribute("BossArea") or 0) == 0 then
				local full = bagFull(player, pr) and handleFull(player, pr, now)
				if not full then
					if now >= (nextHit[player] or 0) then
						local s = Data.mowStats(player)
						local mult = (clickUntil[player] or 0) > now and Game.Click.mult or 1
						nextHit[player] = now + 1 / (s.speed * mult)
						lastHit[player] = now
						if mowerHit(player, pr, areaId, pos, s) > 0 then
							mowingUntil[player] = now + 1 / (s.speed * mult) + 0.35
						end
					end
					if now >= (nextWorker[player] or 0) then
						nextWorker[player] = now + 1
						workersHit(player, pr, areaId, pos)
					end
				end
			end
			-- clients animate the tool and play its sound while this is true
			local mowing = (mowingUntil[player] or 0) > now
			if player:GetAttribute("Mowing") ~= mowing then
				player:SetAttribute("Mowing", mowing)
			end
		end
	end
	-- flush replication
	for areaId, batch in pairs(fxBatch) do
		Remotes.GrassFx:FireAllClients(areaId, batch)
		fxBatch[areaId] = nil
	end
	for player, d in pairs(dirty) do
		if player.Parent then
			if d.progress then
				Data.sync(player, "bagCount", "bagValue", "progress")
			else
				Data.sync(player, "bagCount", "bagValue")
			end
			if d.gain > 0 then
				Remotes.Gain:FireClient(player, "grass", d.gain, d.pos)
			end
		end
		dirty[player] = nil
	end
end

function Grass.init()
	local root = Instance.new("Folder")
	root.Name = "Grass"
	root.Parent = workspace
	for areaId, a in ipairs(Areas.List) do
		local folder = Instance.new("Folder")
		folder.Name = tostring(areaId)
		local st = { hp = table.create(TILES, a.grassHP), alive = table.create(TILES, true), parts = table.create(TILES), queue = {}, head = 1 }
		local rng = Random.new(areaId)
		local h, s, v = Style.color(a.grass):ToHSV()
		for idx = 1, TILES do
			local pos = Areas.tilePos(areaId, idx)
			local height = 1.3 + rng:NextNumber() * 0.9
			local p = Instance.new("Part")
			p.Name = tostring(idx)
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			p.Material = Style.material(Enum.Material.Grass)
			p.Color = Color3.fromHSV(h, s, math.clamp(v * rng:NextNumber(0.86, 1.06), 0, 1))
			p.Size = Vector3.new(TILE, height, TILE)
			p.Position = Vector3.new(pos.X, 0.2 + height / 2, pos.Z)
			p.Parent = folder
			st.parts[idx] = p
		end
		state[areaId] = st
		folder.Parent = root
		task.wait()
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			step()
		end
	end)
	-- A click never says what was cut: it only shortens the wait until this player's next hit.
	Remotes.Input.OnServerEvent:Connect(function(player, kind)
		if kind ~= "cut" or not Data.get(player) then
			return
		end
		clickUntil[player] = os.clock() + Game.Click.window
		local boosted = (lastHit[player] or 0) + 1 / (Data.mowStats(player).speed * Game.Click.mult)
		nextHit[player] = math.min(nextHit[player] or 0, boosted)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastHit[player] = nil
		clickUntil[player] = nil
		mowingUntil[player] = nil
		nextHit[player] = nil
		nextWorker[player] = nil
		lastFullWarn[player] = nil
		dirty[player] = nil
	end)
end

return Grass
