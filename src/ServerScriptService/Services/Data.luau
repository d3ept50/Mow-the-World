-- Player data: loading, saving, replication to the client and all derived stats.
-- Everything that grants currency or items goes through this module (server only).
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")

local Config = RS.Shared.Config
local Items = require(Config.Items)
local W = require(Config.Workers)
local Game = require(Config.Game)
local Areas = require(Config.Areas)
local Remotes = RS.Remotes

local STORE_NAME = "MowTheWorld_v1"
local AUTOSAVE = 120

local Data = {}
Data.passes = {} -- [player] = { PassKey = true }

local profiles = {}
local meta = {}
local loadedCallbacks = {}
local statCallbacks = {}
local leavingCallbacks = {}

local store
pcall(function()
	store = DataStoreService:GetDataStore(STORE_NAME)
end)

local function template()
	return {
		version = 1,
		cash = 0,
		diamonds = 0,
		rebirths = 0,
		areasUnlocked = 1,
		mowers = { Scissors = true },
		equippedMower = "Scissors",
		bag = "Tiny",
		vehicles = {},
		equippedVehicle = "",
		bagCount = 0,
		bagValue = 0,
		workers = {},
		equipped = {},
		nextUid = 1,
		crates = {},
		progress = {},
		bossKills = {},
		stats = {},
		achievements = {},
		daily = { last = 0, streak = 0 },
		boosts = {},
		perks = { autoSell = false, slots = 0 },
		titles = {},
		title = "",
		settings = { autoSell = true },
		receipts = {},
	}
end

local function serialize(profile)
	local copy = table.clone(profile)
	copy.progress = {}
	for k, p in pairs(profile.progress) do
		local chars = table.create(Areas.TILES, "0")
		for idx in pairs(p.set) do
			chars[idx] = "1"
		end
		copy.progress[k] = { bits = table.concat(chars), ms = p.ms }
	end
	return copy
end

local function deserialize(profile)
	for k, p in pairs(profile.progress) do
		local set, count = {}, 0
		if type(p) == "table" and type(p.bits) == "string" then
			for i = 1, math.min(#p.bits, Areas.TILES) do
				if string.byte(p.bits, i) == 49 then
					set[i] = true
					count += 1
				end
			end
		end
		profile.progress[k] = { set = set, count = count, ms = type(p) == "table" and tonumber(p.ms) or 0 }
	end
end

local function progressView(profile)
	local v = {}
	for k, p in pairs(profile.progress) do
		v[k] = { count = p.count, ms = p.ms }
	end
	return v
end

local SNAPSHOT_KEYS = { "cash", "diamonds", "rebirths", "areasUnlocked", "mowers", "equippedMower", "bag", "vehicles", "equippedVehicle", "bagCount", "bagValue", "workers", "equipped", "crates", "progress", "bossKills", "stats", "achievements", "daily", "boosts", "perks", "titles", "title", "settings", "passes" }

local function view(player, profile, keys)
	local out = {}
	for _, key in ipairs(keys) do
		if key == "progress" then
			out.progress = progressView(profile)
		elseif key == "passes" then
			out.passes = Data.passes[player] or {}
		else
			out[key] = profile[key]
		end
	end
	return out
end

---------------------------------------------------------------- access
function Data.get(player: Player)
	return profiles[player]
end

function Data.snapshot(player: Player)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local snap = view(player, profile, SNAPSHOT_KEYS)
	snap.serverTime = os.time()
	snap.noSave = meta[player].noSave
	return snap
end

function Data.sync(player: Player, ...: string)
	local profile = profiles[player]
	if profile then
		Remotes.DataSync:FireClient(player, view(player, profile, { ... }))
	end
end

function Data.notify(player: Player, text: string, kind: string?)
	Remotes.Notify:FireClient(player, text, kind or "info")
end

function Data.onLoaded(cb)
	table.insert(loadedCallbacks, cb)
	for player in pairs(profiles) do
		task.spawn(cb, player, profiles[player])
	end
end
function Data.onStat(cb)
	table.insert(statCallbacks, cb)
end
function Data.onLeaving(cb)
	table.insert(leavingCallbacks, cb)
end

---------------------------------------------------------------- derived values
function Data.hasPass(player: Player, key: string): boolean
	local p = Data.passes[player]
	return p ~= nil and (p[key] == true or p.AllAccess == true)
end

function Data.boost(profile, name: string): boolean
	return (profile.boosts[name] or 0) > os.time()
end

function Data.cashMult(player: Player): number
	local pr = profiles[player]
	local m = Game.Rebirth.cashMult(pr.rebirths)
	if Data.hasPass(player, "Cash2x") then
		m *= 2
	end
	if Data.hasPass(player, "VIP") then
		m *= 1.2
	end
	if Data.boost(pr, "cash") then
		m *= 2
	end
	return m
end

function Data.diamondMult(player: Player): number
	return Data.hasPass(player, "Diamonds2x") and 2 or 1
end

function Data.luck(player: Player): number
	local pr = profiles[player]
	local l = 1
	if Data.boost(pr, "luck") then
		l *= 1.6
	end
	if Data.hasPass(player, "VIP") then
		l *= 1.1
	end
	return l
end

function Data.ownsMower(player: Player, id: string): boolean
	local pr, def = profiles[player], Items.MowerById[id]
	if not pr or not def then
		return false
	end
	if def.rebirth then
		return pr.rebirths >= def.rebirth
	end
	return pr.mowers[id] == true
end

function Data.ownsVehicle(player: Player, id: string): boolean
	local pr, def = profiles[player], Items.VehicleById[id]
	if not pr or not def then
		return false
	end
	if def.pass then
		return Data.hasPass(player, def.pass)
	end
	if def.rebirth then
		return pr.rebirths >= def.rebirth
	end
	return pr.vehicles[id] == true
end

function Data.ridingVehicle(player: Player)
	local pr = profiles[player]
	if pr and player:GetAttribute("Riding") and pr.equippedVehicle ~= "" and Data.ownsVehicle(player, pr.equippedVehicle) then
		return Items.VehicleById[pr.equippedVehicle]
	end
	return nil
end

function Data.bagDef(player: Player)
	local pr = profiles[player]
	local def = Items.BagById[pr.bag] or Items.Bags[1]
	if Data.hasPass(player, "StartBag") and def.order < 3 then
		def = Items.Bags[3]
	end
	return def
end

function Data.bagCapacity(player: Player): number
	local cap = Data.bagDef(player).capacity
	local v = Data.ridingVehicle(player)
	if v then
		cap *= v.storage
	end
	return cap
end

function Data.mowStats(player: Player)
	local pr = profiles[player]
	local def = Items.MowerById[pr.equippedMower]
	if not def or not Data.ownsMower(player, def.id) then
		def = Items.Mowers[1]
	end
	local damage = def.damage * Game.Rebirth.powerMult(pr.rebirths)
	local speed, radius, eff = def.speed, def.radius, def.eff
	if Data.hasPass(player, "FastMow") then
		speed *= 1.5
	end
	if Data.boost(pr, "speed") then
		speed *= 1.5
	end
	if Data.hasPass(player, "Grass2x") then
		eff *= 2
	end
	local v = Data.ridingVehicle(player)
	if v then
		damage *= v.dmg
		radius = math.max(radius, v.radius)
	end
	return { damage = damage, speed = speed, radius = radius, eff = eff }
end

function Data.workerSlots(player: Player): number
	local pr = profiles[player]
	return W.BASE_SLOTS + Game.Rebirth.slots(pr.rebirths) + (pr.perks.slots or 0) + (Data.hasPass(player, "ExtraSlots") and 2 or 0)
end

function Data.findWorker(profile, uid)
	for i, inst in ipairs(profile.workers) do
		if inst.uid == uid then
			return inst, i
	end
	end
	return nil
end

-- Total damage per hit of all equipped workers (with rebirth bonus)
function Data.workerDamages(player: Player): { number }
	local pr = profiles[player]
	local mult = Game.Rebirth.workerMult(pr.rebirths)
	local out = {}
	for _, uid in ipairs(pr.equipped) do
		local inst = Data.findWorker(pr, uid)
		if inst then
			table.insert(out, W.power(inst) * mult)
		end
	end
	return out
end

function Data.bestAreaValue(player: Player): number
	local pr = profiles[player]
	local best = math.max(pr.areasUnlocked, pr.stats.maxArea or 1)
	return Areas.List[math.clamp(best, 1, Areas.COUNT)].grassValue
end

function Data.nearShop(player: Player, name: string, range: number?): boolean
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local pos = Areas.Shops[name]
	if not hrp or not pos then
		return false
	end
	local dx, dz = hrp.Position.X - pos.X, hrp.Position.Z - pos.Z
	return dx * dx + dz * dz <= (range or 48) ^ 2
end

---------------------------------------------------------------- public attributes (seen by other clients)
function Data.refreshPublic(player: Player)
	local pr = profiles[player]
	if not pr then
		return
	end
	local list = {}
	for _, uid in ipairs(pr.equipped) do
		local inst = Data.findWorker(pr, uid)
		if inst then
			table.insert(list, { id = inst.id, lvl = inst.lvl, tier = inst.tier })
		end
	end
	player:SetAttribute("Workers", HttpService:JSONEncode(list))
	player:SetAttribute("Title", pr.title)
	player:SetAttribute("Rebirths", pr.rebirths)
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls.Cash.Value = math.floor(math.min(pr.cash, 9e18))
		ls.Diamonds.Value = pr.diamonds
		ls.Rebirths.Value = pr.rebirths
	end
end

---------------------------------------------------------------- mutations
function Data.addStat(player: Player, key: string, n: number)
	local pr = profiles[player]
	if not pr then
		return
	end
	pr.stats[key] = (pr.stats[key] or 0) + n
	meta[player].statsDirty = true
	for _, cb in ipairs(statCallbacks) do
		cb(player, key, pr.stats[key])
	end
end

function Data.setStatMax(player: Player, key: string, v: number)
	local pr = profiles[player]
	if pr and (pr.stats[key] or 0) < v then
		Data.addStat(player, key, v - (pr.stats[key] or 0))
	end
end

function Data.addCash(player: Player, amount: number, earned: boolean?)
	local pr = profiles[player]
	if not pr then
		return
	end
	pr.cash = math.max(0, pr.cash + amount)
	if earned and amount > 0 then
		Data.addStat(player, "cashEarned", amount)
	end
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls.Cash.Value = math.floor(math.min(pr.cash, 9e18))
	end
	Data.sync(player, "cash")
end

-- earned = true applies the 2x Diamonds pass and counts towards stats. Returns the amount added.
function Data.addDiamonds(player: Player, amount: number, earned: boolean?): number
	local pr = profiles[player]
	if not pr then
		return 0
	end
	if earned and amount > 0 then
		amount = math.floor(amount * Data.diamondMult(player))
		Data.addStat(player, "diamondsEarned", amount)
	end
	pr.diamonds = math.max(0, pr.diamonds + amount)
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls.Diamonds.Value = pr.diamonds
	end
	Data.sync(player, "diamonds")
	return amount
end

function Data.addWorker(player: Player, id: string)
	local pr = profiles[player]
	local def = W.ById[id]
	if not pr or not def or #pr.workers >= W.MAX_INVENTORY then
		return nil
	end
	local inst = { uid = pr.nextUid, id = id, lvl = 1, tier = 0, locked = false }
	pr.nextUid += 1
	table.insert(pr.workers, inst)
	local order = W.RarityById[def.rarity].order
	if order >= 3 then
		Data.addStat(player, "rareFound", 1)
	end
	if order >= 5 then
		Data.addStat(player, "legendaryFound", 1)
	end
	if order >= 7 then
		Data.addStat(player, "secretFound", 1)
	end
	-- auto equip while there are free slots
	if #pr.equipped < Data.workerSlots(player) then
		table.insert(pr.equipped, inst.uid)
		Data.refreshPublic(player)
	end
	return inst
end

function Data.addCrate(player: Player, crateId: string, n: number)
	local pr = profiles[player]
	if pr and W.CrateById[crateId] then
		pr.crates[crateId] = (pr.crates[crateId] or 0) + n
		Data.sync(player, "crates")
	end
end

function Data.addBoost(player: Player, name: string, minutes: number)
	local pr = profiles[player]
	if pr and Game.Boosts[name] then
		pr.boosts[name] = math.max(os.time(), pr.boosts[name] or 0) + minutes * 60
		Data.sync(player, "boosts")
		player:SetAttribute("BoostTick", os.time())
	end
end

function Data.addTitle(player: Player, title: string)
	local pr = profiles[player]
	if pr and not pr.titles[title] then
		pr.titles[title] = true
		Data.sync(player, "titles")
		Data.notify(player, "🏷️ New title unlocked: " .. title, "good")
	end
end

function Data.progress(profile, areaId: number)
	local key = tostring(areaId)
	local p = profile.progress[key]
	if not p then
		p = { set = {}, count = 0, ms = 0 }
		profile.progress[key] = p
	end
	return p
end

---------------------------------------------------------------- load / save
function Data.save(player: Player): boolean
	local profile, m = profiles[player], meta[player]
	if not profile or not m then
		return false
	end
	if m.noSave then
		return true
	end
	local payload = serialize(profile)
	local ok, err
	for attempt = 1, 3 do
		ok, err = pcall(function()
			store:UpdateAsync(m.key, function()
				return payload
			end)
		end)
		if ok then
			break
		end
		task.wait(1.5 * attempt)
	end
	if not ok then
		warn("[Data] Save failed for", player.Name, err)
	end
	return ok
end

local function onJoin(player: Player)
	local key = "p_" .. player.UserId
	local ok, data = false, nil
	if store then
		for attempt = 1, 3 do
			ok, data = pcall(store.GetAsync, store, key)
			if ok then
				break
			end
			task.wait(1)
		end
	end
	local noSave = false
	if not ok then
		if RunService:IsStudio() then
			-- unpublished place / API access off: play with a temporary profile
			noSave, data = true, nil
		else
			player:Kick("Mow the World could not load your data. Please rejoin in a moment.")
			return
		end
	end
	if not player.Parent then
		return
	end
	local profile = template()
	if type(data) == "table" then
		for k, v in pairs(data) do
			profile[k] = v
		end
		local fresh = template()
		for _, k in ipairs({ "daily", "perks", "settings" }) do
			for k2, v2 in pairs(fresh[k]) do
				if profile[k][k2] == nil then
					profile[k][k2] = v2
				end
			end
		end
	end
	deserialize(profile)
	profiles[player] = profile
	meta[player] = { key = key, noSave = noSave, statsDirty = false }
	Data.passes[player] = Data.passes[player] or {}

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	for _, n in ipairs({ "Cash", "Diamonds", "Rebirths" }) do
		local v = Instance.new("IntValue")
		v.Name = n
		v.Parent = ls
	end
	ls.Parent = player
	Data.refreshPublic(player)
	player:SetAttribute("Loaded", true)
	for _, cb in ipairs(loadedCallbacks) do
		task.spawn(cb, player, profile)
	end
	if noSave then
		Data.notify(player, "Studio test mode: progress is not being saved (publish the place and enable API access).", "info")
	end
end

local function onLeave(player: Player)
	for _, cb in ipairs(leavingCallbacks) do
		pcall(cb, player)
	end
	if profiles[player] then
		Data.save(player)
	end
	profiles[player] = nil
	meta[player] = nil
	Data.passes[player] = nil
end

function Data.init()
	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(onLeave)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onJoin, p)
	end
	-- periodic autosave + throttled stat replication
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(3)
			for player, m in pairs(meta) do
				if m.statsDirty then
					m.statsDirty = false
					Data.sync(player, "stats")
				end
			end
			if os.clock() - last >= AUTOSAVE then
				last = os.clock()
				for player in pairs(profiles) do
					task.spawn(Data.save, player)
					task.wait(0.2)
				end
			end
		end
	end)
	game:BindToClose(function()
		local pending = 0
		for player in pairs(profiles) do
			pending += 1
			task.spawn(function()
				Data.save(player)
				pending -= 1
			end)
		end
		local t = os.clock()
		while pending > 0 and os.clock() - t < 25 do
			task.wait(0.1)
		end
	end)
end

return Data
