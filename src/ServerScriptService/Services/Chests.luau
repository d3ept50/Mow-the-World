-- Hidden treasure chests. A chest only exists on the server as a hidden tile index until
-- somebody mows that tile, so it cannot be found or claimed by exploits.
local RS = game:GetService("ReplicatedStorage")
local Areas = require(RS.Shared.Config.Areas)
local Game = require(RS.Shared.Config.Game)
local Util = require(RS.Shared.Util)
local Models = require(RS.Shared.Models)
local Data = require(script.Parent.Data)
local Grass = require(script.Parent.Grass)
local Crates = require(script.Parent.Crates)
local Remotes = RS.Remotes

local Chests = {}
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

local function grant(player, pr, areaId, def)
	local a = Areas.List[areaId]
	local parts = {}
	local cash = math.floor(def.cash * a.grassValue * Data.cashMult(player))
	Data.addCash(player, cash, true)
	table.insert(parts, "+$" .. Util.fmt(cash))
	if def.diamonds then
		local d = Data.addDiamonds(player, rng:NextInteger(def.diamonds[1], def.diamonds[2]), true)
		table.insert(parts, "+" .. d .. " 💎")
	end
	if def.boostChance and rng:NextNumber() < def.boostChance then
		local names = { "cash", "speed", "luck" }
		local b = names[rng:NextInteger(1, 3)]
		Data.addBoost(player, b, 5)
		table.insert(parts, Game.Boosts[b].name .. " (5 min)")
	end
	if def.crateChance and rng:NextNumber() < def.crateChance then
		local crateId = Crates.forArea(areaId)
		Data.addCrate(player, crateId, 1)
		table.insert(parts, crateId .. " Crate")
	end
	if def.workerChance and rng:NextNumber() < def.workerChance then
		local w = Crates.roll(Crates.forArea(areaId), 2.5)
		if Data.addWorker(player, w.id) then
			Data.sync(player, "workers", "equipped")
			table.insert(parts, "Worker: " .. w.name)
		end
	end
	if def.title then
		Data.addTitle(player, def.title)
	end
	Data.addStat(player, "chests", 1)
	Data.notify(player, "🧰 " .. def.id .. " Chest: " .. table.concat(parts, ", "), def.weight <= 10 and "big" or "good")
end

local function reveal(player, areaId, idx)
	local tier = hidden[areaId][idx]
	hidden[areaId][idx] = nil
	if tier < #Game.Chests and rng:NextNumber() < 0.3 * (Data.luck(player) - 1) then
		tier += 1
	end
	local def = Game.Chests[tier]
	local pos = Areas.tilePos(areaId, idx) + V(0, 0.2, 0)

	local m = Instance.new("Model")
	m.Name = def.id .. "Chest"
	local wood = Color3.fromRGB(140, 95, 50):Lerp(def.color, 0.35)
	local base = Models.P(m, V(4, 2.4, 3), CF(pos + V(0, 1.2, 0)), wood, "WoodPlanks")
	base.CanCollide = true
	Models.P(m, V(4.2, 1, 3.2), CF(pos + V(0, 2.9, 0)), wood, "WoodPlanks")
	Models.P(m, V(4.3, 0.4, 3.3), CF(pos + V(0, 2.4, 0)), def.color, "Neon")
	Models.P(m, V(0.5, 3.5, 3.35), CF(pos + V(-1.2, 1.75, 0)), def.color, "Metal")
	Models.P(m, V(0.5, 3.5, 3.35), CF(pos + V(1.2, 1.75, 0)), def.color, "Metal")
	Models.P(m, V(0.8, 0.9, 0.3), CF(pos + V(0, 2.3, -1.6)), Color3.fromRGB(255, 220, 80), "Neon")
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
		grant(who, pr, areaId, def)
		Remotes.ChestFx:FireAllClients("open", pos, def.id)
		task.delay(1, function()
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
