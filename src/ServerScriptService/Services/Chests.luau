-- Hidden treasure chests. A chest only exists on the server as a hidden tile index until
-- somebody mows that tile, so it cannot be found or claimed by exploits. Opening one spins
-- a reel of prizes (cash, diamonds, boosts, crates, luck, and workers found nowhere else).
local RS = game:GetService("ReplicatedStorage")
local Areas = require(RS.Shared.Config.Areas)
local Game = require(RS.Shared.Config.Game)
local Util = require(RS.Shared.Util)
local Models = require(RS.Shared.Models)
local Assets = require(RS.Shared.Assets)
local Data = require(script.Parent.Data)
local Grass = require(script.Parent.Grass)
local Crates = require(script.Parent.Crates)
local W = require(RS.Shared.Config.Workers)
local Remotes = RS.Remotes

local Chests = {}
local SPIN = Game.ChestSpin
local rgb = Color3.fromRGB
local rng = Random.new()
local hidden = {} -- [areaId] = { [tileIdx] = chestDef }
local folder

local V, CF = Vector3.new, CFrame.new

local function rollRarity()
	local total = 0
	for _, c in ipairs(Game.Chests) do
		total += c.weight
	end
	local r = rng:NextNumber() * total
	for i, c in ipairs(Game.Chests) do
		r -= c.weight
		if r <= 0 then
			return i
		end
	end
	return 1
end

local function spawnHidden(areaId)
	for _ = 1, 30 do
		local idx = rng:NextInteger(1, Areas.TILES)
		if not hidden[areaId][idx] and Grass.isAlive(areaId, idx) then
			hidden[areaId][idx] = rollRarity()
			return
		end
	end
end

---------------------------------------------------------------- the spin
-- Opening a chest is decided here, on the server, and sent to the player as a list of
-- columns to spin. Each column is { luck, from, result }: "from" is the column whose luck
-- prize started it (0 for the chest's own spins). Prizes are given straight away; the
-- client only plays the show.
local function weighted(list)
	local total = 0
	for _, e in ipairs(list) do
		total += e[2]
	end
	local r = rng:NextNumber() * total
	for _, e in ipairs(list) do
		r -= e[2]
		if r <= 0 then
			return e[1]
		end
	end
	return list[#list][1]
end

local function stageOf(areaId: number)
	for _, st in ipairs(SPIN.stages) do
		if areaId <= st.upTo then
			return st
		end
	end
	return SPIN.stages[#SPIN.stages]
end

-- Rarities of an odds table from most common to rarest, with luck applied: the rarest gets
-- luck squared times its normal weight, the most common is unchanged.
local function rarityWeights(odds, luck: number)
	local list = {}
	for rarity, pct in pairs(odds) do
		table.insert(list, { rarity, pct })
	end
	table.sort(list, function(x, y)
		return W.RarityById[x[1]].order < W.RarityById[y[1]].order
	end)
	local n = #list
	for i, e in ipairs(list) do
		e[2] *= luck ^ (n > 1 and 2 * (i - 1) / (n - 1) or 0)
	end
	return list
end

-- What a prize looks like on the reel. ctx = { areaId, tier, mult = the player's cash multiplier }
local function prize(kind: string, ctx, arg)
	local def = Game.Chests[ctx.tier]
	local a = Areas.List[ctx.areaId]
	if kind == "cash" or kind == "bigCash" then
		local amount = math.floor(def.cash * a.grassValue * ctx.mult * (kind == "bigCash" and SPIN.bigCash or 1))
		return { kind = kind, amount = amount, label = "$" .. Util.fmt(amount), sub = kind == "bigCash" and "Jackpot!" or "Cash", icon = kind == "bigCash" and "💰" or "💵", color = kind == "bigCash" and rgb(255, 200, 60) or rgb(90, 210, 110) }
	elseif kind == "diamonds" then
		local range = SPIN.diamonds[ctx.tier]
		local amount = arg or rng:NextInteger(range[1], range[2])
		return { kind = kind, amount = amount, label = "+" .. amount, sub = "Diamonds", icon = "💎", color = rgb(70, 215, 245) }
	elseif kind == "boost" then
		local names = { "cash", "speed", "luck" }
		local b = arg or names[rng:NextInteger(1, 3)]
		return { kind = kind, boost = b, label = Game.Boosts[b].name, sub = "5 minutes", icon = Game.Boosts[b].icon, color = rgb(255, 150, 50) }
	elseif kind == "crate" then
		local crateId = Crates.forArea(ctx.areaId)
		return { kind = kind, crate = crateId, label = crateId .. " Crate", sub = "Worker crate", icon = "📦", color = rgb(172, 96, 250) }
	elseif kind == "worker" then
		local w = W.ChestByRarity[arg]
		local rar = W.RarityById[w.rarity]
		return { kind = kind, worker = w.id, rarity = w.rarity, order = rar.order, label = w.name, sub = w.rarity, icon = "👷", color = rar.color }
	end
	local mult = kind == "luck3" and 3 or 2
	return { kind = "luck", mult = mult, label = mult .. "x LUCK", sub = "Spin again!", icon = "🍀", color = rgb(120, 255, 110) }
end

local function rollPrize(ctx, luck: number, allowLuck: boolean)
	local L = math.min(luck, 6)
	local list = {}
	for kind, weight in pairs(SPIN.kinds) do
		if kind == "worker" then
			weight *= L
		elseif kind == "bigCash" or kind == "diamonds" or kind == "crate" then
			weight *= math.sqrt(L)
		elseif kind == "luck2" or kind == "luck3" then
			weight = allowLuck and weight or 0
		end
		table.insert(list, { kind, weight })
	end
	local kind = weighted(list)
	if kind == "worker" then
		return prize(kind, ctx, weighted(rarityWeights(stageOf(ctx.areaId).odds, luck)))
	end
	return prize(kind, ctx)
end

-- Everything that can come up for this chest, with rough weights, so the reel can show it.
local function pool(ctx)
	local out = {}
	for kind, weight in pairs(SPIN.kinds) do
		if kind ~= "worker" then
			local p = prize(kind, ctx)
			p.w = weight
			table.insert(out, p)
		end
	end
	for rarity, pct in pairs(stageOf(ctx.areaId).odds) do
		local p = prize("worker", ctx, rarity)
		p.w = SPIN.kinds.worker * pct / 100
		table.insert(out, p)
	end
	return out
end

local function give(player, p)
	if p.kind == "cash" or p.kind == "bigCash" then
		Data.addCash(player, p.amount, true)
	elseif p.kind == "diamonds" then
		p.amount = Data.addDiamonds(player, p.amount, true)
		p.label = "+" .. p.amount
	elseif p.kind == "boost" then
		Data.addBoost(player, p.boost, 5)
	elseif p.kind == "crate" then
		Data.addCrate(player, p.crate, 1)
	elseif p.kind == "worker" then
		if not Data.addWorker(player, p.worker) then
			return false -- no room for another worker
		end
	end
	return true
end

local function open(player, pr, areaId, tier, pos)
	local def = Game.Chests[tier]
	local ctx = { areaId = areaId, tier = tier, mult = Data.cashMult(player) }
	local first = (pr.stats.chests or 0) == 0
	local baseLuck = SPIN.tierLuck[tier] * Data.luck(player)
	local columns = {}
	local spins = (not first and rng:NextNumber() < SPIN.double[tier]) and 2 or 1
	for c = 1, spins do
		local luck, chain, from = 1, 0, 0
		while true do
			local p
			if first and c == 1 and chain == 0 then
				-- a new player's first chest: always a strong chest worker
				p = prize("worker", ctx, weighted(rarityWeights(SPIN.first, 1)))
			else
				p = rollPrize(ctx, baseLuck * luck, chain < SPIN.maxChain)
			end
			if not give(player, p) then
				p = prize("bigCash", ctx)
				give(player, p)
			end
			table.insert(columns, { luck = luck, from = from, result = p })
			if p.kind ~= "luck" then
				break
			end
			from = #columns
			luck *= p.mult
			chain += 1
		end
	end
	if def.title then
		Data.addTitle(player, def.title)
	end
	Data.addStat(player, "chests", 1)
	Data.sync(player, "workers", "equipped", "crates")
	Remotes.ChestFx:FireClient(player, "spin", pos, def.id, { columns = columns, pool = pool(ctx), first = first })
end

local function reveal(player, areaId, idx)
	local tier = hidden[areaId][idx]
	hidden[areaId][idx] = nil
	if tier < #Game.Chests and rng:NextNumber() < 0.3 * (Data.luck(player) - 1) then
		tier += 1
	end
	local def = Game.Chests[tier]
	local pos = Areas.tilePos(areaId, idx) + V(0, 0.2, 0)

	-- use the imported Blender chest for this rarity if it is in ReplicatedStorage.Assets
	local m = Assets.clone("chest_" .. string.lower(def.id))
	local base, lid
	if m then
		Assets.fit(m, "X", 4.3)
		local lo, hi = Assets.bounds(m)
		Assets.moveBy(m, V(pos.X - (lo.X + hi.X) / 2, pos.Y - lo.Y, pos.Z - (lo.Z + hi.Z) / 2))
		base = m:FindFirstChild("Base", true)
		lid = m:FindFirstChild("Lid", true)
		if not (base and base:IsA("BasePart")) then
			base = m:FindFirstChildWhichIsA("BasePart", true)
		end
		if lid and not lid:IsA("BasePart") then
			lid = nil
		end
	else
		m = Instance.new("Model")
		local wood = Color3.fromRGB(140, 95, 50):Lerp(def.color, 0.35)
		base = Models.P(m, V(4, 2.4, 3), CF(pos + V(0, 1.2, 0)), wood, "WoodPlanks")
		Models.P(m, V(4.2, 1, 3.2), CF(pos + V(0, 2.9, 0)), wood, "WoodPlanks")
		Models.P(m, V(4.3, 0.4, 3.3), CF(pos + V(0, 2.4, 0)), def.color, "Neon")
		Models.P(m, V(0.5, 3.5, 3.35), CF(pos + V(-1.2, 1.75, 0)), def.color, "Metal")
		Models.P(m, V(0.5, 3.5, 3.35), CF(pos + V(1.2, 1.75, 0)), def.color, "Metal")
		Models.P(m, V(0.8, 0.9, 0.3), CF(pos + V(0, 2.3, -1.6)), Color3.fromRGB(255, 220, 80), "Neon")
	end
	m.Name = def.id .. "Chest"
	base.CanCollide = true
	Models.glow(base, def.color, 10 + tier * 4, 6 + tier * 8)
	m.PrimaryPart = base
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = def.id .. " Chest"
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = base
	m.Parent = folder

	Remotes.ChestFx:FireAllClients("reveal", pos, def.id)
	Data.notify(player, "✨ You uncovered a " .. def.id .. " treasure chest!", "good")

	local claimed = false
	prompt.Triggered:Connect(function(who)
		if claimed then
			return
		end
		local pr = Data.get(who)
		if not pr or pr.areasUnlocked < areaId then
			return
		end
		claimed = true
		prompt.Enabled = false
		open(who, pr, areaId, tier, pos)
		Remotes.ChestFx:FireAllClients("open", pos, def.id)
		if lid then
			-- swing the lid open around its back bottom edge (the chest's front is -Z)
			local lo, hi = Assets.bounds(lid)
			local hinge = CF((lo.X + hi.X) / 2, lo.Y, hi.Z)
			local rel = hinge:ToObjectSpace(lid.CFrame)
			task.spawn(function()
				for i = 1, 10 do
					if not lid.Parent then
						return
					end
					lid.CFrame = hinge * CFrame.Angles(math.rad(70 * i / 10), 0, 0) * rel
					task.wait(0.03)
				end
			end)
		end
		task.delay(lid and 1.4 or 1, function()
			m:Destroy()
		end)
		task.delay(Game.CHEST_RESPAWN, spawnHidden, areaId)
	end)
	task.delay(120, function()
		if not claimed then
			claimed = true
			m:Destroy()
			spawnHidden(areaId)
		end
	end)
end

function Chests.init()
	folder = Instance.new("Folder")
	folder.Name = "Chests"
	folder.Parent = workspace
	for areaId in ipairs(Areas.List) do
		hidden[areaId] = {}
		for _ = 1, Game.CHESTS_PER_AREA do
			spawnHidden(areaId)
		end
	end
	Grass.onCut(function(player, areaId, idx)
		if hidden[areaId][idx] then
			reveal(player, areaId, idx)
		end
	end)
end

return Chests
