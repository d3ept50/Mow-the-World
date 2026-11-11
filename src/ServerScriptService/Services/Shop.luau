-- Every client request goes through the single "Action" RemoteFunction handled here.
-- Each handler validates its arguments, ownership, prices and location on the server.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local Config = RS.Shared.Config
local Items = require(Config.Items)
local W = require(Config.Workers)
local Game = require(Config.Game)
local Areas = require(Config.Areas)
local Util = require(RS.Shared.Util)
local Data = require(script.Parent.Data)
local Crates = require(script.Parent.Crates)
local Character = require(script.Parent.Character)
local Boss = require(script.Parent.Boss)
local Remotes = RS.Remotes

local Shop = {}
local handlers = {}
local buckets = {}
local RATE, BURST = 8, 16

local function fail(msg)
	return false, msg
end

---------------------------------------------------------------- mowers / bags / vehicles
function handlers.BuyMower(player, pr, id)
	local def = type(id) == "string" and Items.MowerById[id]
	if not def or def.rebirth then
		return fail("Invalid item.")
	end
	if pr.mowers[id] then
		return fail("You already own this mower.")
	end
	if not Data.nearShop(player, "Mowers") then
		return fail("Visit the Mower Shop in the marketplace to buy mowers.")
	end
	if pr.areasUnlocked < def.area then
		return fail("Unlock " .. Areas.List[def.area].name .. " first.")
	end
	if pr.cash < def.price then
		return fail("Not enough cash.")
	end
	Data.addCash(player, -def.price)
	pr.mowers[id] = true
	pr.equippedMower = id
	Data.sync(player, "mowers", "equippedMower")
	Character.refresh(player)
	return true, "Bought " .. def.name .. "!"
end

function handlers.EquipMower(player, pr, id)
	if type(id) ~= "string" or not Data.ownsMower(player, id) then
		return fail("You don't own that mower.")
	end
	pr.equippedMower = id
	Data.sync(player, "equippedMower")
	Character.refresh(player)
	return true
end

function handlers.BuyBag(player, pr, id)
	local def = type(id) == "string" and Items.BagById[id]
	if not def then
		return fail("Invalid item.")
	end
	local current = Items.BagById[pr.bag] or Items.Bags[1]
	if def.order <= current.order then
		return fail("You already have a bag this size or better.")
	end
	if not Data.nearShop(player, "Bags") then
		return fail("Visit the Bag Shop in the marketplace to buy bags.")
	end
	if pr.cash < def.price then
		return fail("Not enough cash.")
	end
	Data.addCash(player, -def.price)
	pr.bag = id
	Data.sync(player, "bag")
	return true, "Bought " .. def.name .. "!"
end

function handlers.BuyVehicle(player, pr, id)
	local def = type(id) == "string" and Items.VehicleById[id]
	if not def or def.rebirth or def.pass then
		return fail("Invalid item.")
	end
	if pr.vehicles[id] then
		return fail("You already own this vehicle.")
	end
	if not Data.nearShop(player, "Vehicles") then
		return fail("Visit the Vehicle Garage in the marketplace to buy vehicles.")
	end
	if pr.areasUnlocked < def.area then
		return fail("Unlock " .. Areas.List[def.area].name .. " first.")
	end
	if pr.cash < def.price then
		return fail("Not enough cash.")
	end
	Data.addCash(player, -def.price)
	pr.vehicles[id] = true
	pr.equippedVehicle = id
	Data.sync(player, "vehicles", "equippedVehicle")
	Character.refresh(player)
	return true, "Bought " .. def.name .. "! Press the 🚜 Ride button to drive it."
end

function handlers.EquipVehicle(player, pr, id)
	if type(id) ~= "string" or not Data.ownsVehicle(player, id) then
		return fail("You don't own that vehicle.")
	end
	pr.equippedVehicle = id
	Data.sync(player, "equippedVehicle")
	Character.refresh(player)
	return true
end

function handlers.ToggleRide(player, pr)
	if pr.equippedVehicle == "" or not Data.ownsVehicle(player, pr.equippedVehicle) then
		return fail("Buy a vehicle at the Vehicle Garage first.")
	end
	player:SetAttribute("Riding", not player:GetAttribute("Riding"))
	Character.refresh(player)
	return true
end

---------------------------------------------------------------- workers
local function isEquipped(pr, uid)
	return table.find(pr.equipped, uid)
end

local function workersChanged(player)
	Data.refreshPublic(player)
	Data.sync(player, "workers", "equipped")
end

function handlers.EquipWorker(player, pr, uid)
	if type(uid) ~= "number" or not Data.findWorker(pr, uid) then
		return fail("Worker not found.")
	end
	if isEquipped(pr, uid) then
		return fail("Already equipped.")
	end
	if #pr.equipped >= Data.workerSlots(player) then
		return fail("All worker slots are full. Unequip one first.")
	end
	table.insert(pr.equipped, uid)
	workersChanged(player)
	return true
end

function handlers.UnequipWorker(player, pr, uid)
	local i = type(uid) == "number" and isEquipped(pr, uid)
	if not i then
		return fail("That worker is not equipped.")
	end
	table.remove(pr.equipped, i)
	workersChanged(player)
	return true
end

function handlers.EquipBest(player, pr)
	local sorted = table.clone(pr.workers)
	table.sort(sorted, function(a, b)
		return W.power(a) > W.power(b)
	end)
	pr.equipped = {}
	for i = 1, math.min(#sorted, Data.workerSlots(player)) do
		table.insert(pr.equipped, sorted[i].uid)
	end
	workersChanged(player)
	return true, "Equipped your strongest workers!"
end

function handlers.LevelWorker(player, pr, uid)
	local inst = type(uid) == "number" and Data.findWorker(pr, uid)
	if not inst then
		return fail("Worker not found.")
	end
	if inst.lvl >= W.MAX_LEVEL then
		return fail("This worker is max level.")
	end
	local cost = W.levelCost(inst)
	if pr.cash < cost then
		return fail("Not enough cash.")
	end
	Data.addCash(player, -cost)
	inst.lvl += 1
	workersChanged(player)
	return true
end

function handlers.TierWorker(player, pr, uid)
	local inst = type(uid) == "number" and Data.findWorker(pr, uid)
	if not inst then
		return fail("Worker not found.")
	end
	if inst.tier >= W.MAX_TIER then
		return fail("This worker is fully upgraded.")
	end
	local cost = W.tierCost(inst)
	if pr.diamonds < cost then
		return fail("Not enough diamonds.")
	end
	Data.addDiamonds(player, -cost)
	inst.tier += 1
	workersChanged(player)
	return true, "Worker upgraded! ⭐"
end

function handlers.LockWorker(player, pr, uid)
	local inst = type(uid) == "number" and Data.findWorker(pr, uid)
	if not inst then
		return fail("Worker not found.")
	end
	inst.locked = not inst.locked
	Data.sync(player, "workers")
	return true
end

function handlers.DeleteWorker(player, pr, uid)
	local inst, index = nil, nil
	if type(uid) == "number" then
		inst, index = Data.findWorker(pr, uid)
	end
	if not inst then
		return fail("Worker not found.")
	end
	if inst.locked then
		return fail("This worker is locked. Unlock it first.")
	end
	local e = isEquipped(pr, uid)
	if e then
		table.remove(pr.equipped, e)
	end
	table.remove(pr.workers, index)
	workersChanged(player)
	return true
end

function handlers.OpenCrate(player, pr, crateId, count, owned)
	return Crates.open(player, crateId, count, owned == true)
end

---------------------------------------------------------------- rebirth
function handlers.Rebirth(player, pr)
	local n = pr.rebirths
	if not Data.nearShop(player, "Rebirth") then
		return fail("Visit the Rebirth Shrine in the marketplace to rebirth.")
	end
	if (player:GetAttribute("BossArea") or 0) ~= 0 then
		return fail("Finish your boss fight first.")
	end
	local req = Game.Rebirth.areaReq(n)
	if pr.areasUnlocked < req then
		return fail("Unlock " .. Areas.List[req].name .. " first.")
	end
	local cost = Game.Rebirth.cost(n)
	if pr.diamonds < cost then
		return fail("You need " .. cost .. " diamonds.")
	end
	Data.addDiamonds(player, -cost)
	pr.rebirths = n + 1
	-- reset normal progression (diamonds, workers, crates, titles, perks and stats are kept)
	pr.cash = 0
	pr.areasUnlocked = 1
	pr.mowers = { Scissors = true }
	pr.bag = "Tiny"
	pr.vehicles = {}
	pr.bagCount = 0
	pr.bagValue = 0
	pr.progress = {}
	pr.bossKills = {}
	local best = "Scissors"
	for _, m in ipairs(Items.Mowers) do
		if m.rebirth and pr.rebirths >= m.rebirth then
			best = m.id
		end
	end
	pr.equippedMower = best
	if pr.equippedVehicle ~= "" and not Data.ownsVehicle(player, pr.equippedVehicle) then
		pr.equippedVehicle = ""
		for _, v in ipairs(Items.Vehicles) do
			if Data.ownsVehicle(player, v.id) then
				pr.equippedVehicle = v.id
			end
		end
	end
	player:SetAttribute("Riding", false)
	Data.addStat(player, "rebirths", 1)
	local title = Game.Rebirth.Titles[pr.rebirths]
	if title then
		Data.addTitle(player, title)
	end
	Data.addCash(player, 0)
	Data.sync(player, "rebirths", "areasUnlocked", "mowers", "equippedMower", "bag", "vehicles", "equippedVehicle", "bagCount", "bagValue", "progress", "bossKills")
	Data.refreshPublic(player)
	local char = player.Character
	if char then
		char:PivotTo(CFrame.new(0, 6, 26))
	end
	Character.refresh(player)
	Remotes.Notify:FireClient(player, "🔁 REBIRTH " .. pr.rebirths .. "! Permanent bonuses increased.", "rebirth")
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			Remotes.Notify:FireClient(other, "🔁 " .. player.DisplayName .. " reached Rebirth " .. pr.rebirths .. "!", "info")
		end
	end
	task.spawn(Data.save, player)
	return true
end

---------------------------------------------------------------- daily rewards
function handlers.ClaimDaily(player, pr)
	local today = os.time() // 86400
	if pr.daily.last == today then
		return fail("Already claimed today. Come back tomorrow!")
	end
	local streak = pr.daily.last == today - 1 and pr.daily.streak + 1 or 1
	pr.daily.last = today
	pr.daily.streak = streak
	local r = Game.Daily[(streak - 1) % #Game.Daily + 1]
	local text
	if r.kind == "cash" then
		local cash = r.mult * Data.bestAreaValue(player)
		Data.addCash(player, cash, true)
		text = "$" .. Util.fmt(cash)
	elseif r.kind == "diamonds" then
		text = Data.addDiamonds(player, r.amount, true) .. " 💎"
	elseif r.kind == "crate" then
		local crateId = Crates.forArea(math.max(pr.areasUnlocked, pr.stats.maxArea or 1))
		Data.addCrate(player, crateId, r.count)
		text = r.count .. "x " .. crateId .. " Crate"
	elseif r.kind == "boost" then
		Data.addBoost(player, r.boost, r.minutes)
		text = Game.Boosts[r.boost].name .. " (" .. r.minutes .. " min)"
	end
	if r.title then
		Data.addTitle(player, r.title)
	end
	Data.sync(player, "daily")
	return true, "🎁 Day " .. streak .. " reward: " .. text
end

---------------------------------------------------------------- diamond shop
function handlers.BuyDiamond(player, pr, id)
	local item
	for _, it in ipairs(Game.DiamondShop) do
		if it.id == id then
			item = it
		end
	end
	if not item then
		return fail("Invalid item.")
	end
	if not Data.nearShop(player, "Diamonds") then
		return fail("Visit the Diamond Shop in the marketplace.")
	end
	local price = item.price
	if item.kind == "perk" then
		if pr.perks.autoSell then
			return fail("You already own this.")
		end
	elseif item.kind == "slot" then
		if (pr.perks.slots or 0) >= item.max then
			return fail("You have bought the maximum.")
		end
		price = item.price * ((pr.perks.slots or 0) + 1)
	end
	if pr.diamonds < price then
		return fail("Not enough diamonds.")
	end
	Data.addDiamonds(player, -price)
	if item.kind == "perk" then
		pr.perks.autoSell = true
		Data.sync(player, "perks")
	elseif item.kind == "slot" then
		pr.perks.slots = (pr.perks.slots or 0) + 1
		Data.sync(player, "perks")
	elseif item.kind == "boost" then
		Data.addBoost(player, item.boost, item.minutes)
		Character.updateSpeed(player)
	elseif item.kind == "crate" then
		Data.addCrate(player, item.crate, 1)
	end
	return true, "Bought " .. item.name .. "!"
end

---------------------------------------------------------------- misc
function handlers.EquipTitle(player, pr, title)
	if type(title) ~= "string" or (title ~= "" and not pr.titles[title]) then
		return fail("You don't own that title.")
	end
	pr.title = title
	Data.sync(player, "title")
	Data.refreshPublic(player)
	Character.refresh(player)
	return true
end

function handlers.Setting(player, pr, key, value)
	if key ~= "autoSell" or type(value) ~= "boolean" then
		return fail("Invalid setting.")
	end
	pr.settings[key] = value
	Data.sync(player, "settings")
	return true
end

---------------------------------------------------------------- codes
local lastRedeem = {}

function handlers.Redeem(player, pr, text)
	if type(text) ~= "string" or #text > 40 then
		return fail("That code doesn't exist.")
	end
	local now = os.clock()
	if now - (lastRedeem[player] or 0) < 1.5 then
		return fail("Wait a moment before trying another code.")
	end
	lastRedeem[player] = now
	-- capitals and extra spaces don't matter
	local key = string.upper(text):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	local code = Game.Codes[key]
	if not code then
		return fail("That code doesn't exist.")
	end
	if code.dev then
		if not RunService:IsStudio() and not table.find(Game.Devs, player.UserId) then
			return fail("That code doesn't exist.")
		end
	else
		pr.codes = pr.codes or {}
		if pr.codes[key] then
			return fail("You have already used that code.")
		end
		pr.codes[key] = true
	end
	local parts = {}
	if code.cash then
		Data.addCash(player, code.cash)
		table.insert(parts, "+$" .. Util.fmt(code.cash))
	end
	if code.diamonds then
		Data.addDiamonds(player, code.diamonds)
		table.insert(parts, "+" .. Util.fmt(code.diamonds) .. " 💎")
	end
	if code.rebirths and pr.rebirths < code.rebirths then
		Data.addStat(player, "rebirths", code.rebirths - pr.rebirths)
		pr.rebirths = code.rebirths
		for n, title in pairs(Game.Rebirth.Titles) do
			if n <= pr.rebirths then
				Data.addTitle(player, title)
			end
		end
		table.insert(parts, "Rebirth " .. pr.rebirths)
	end
	if code.allAreas and pr.areasUnlocked < Areas.COUNT then
		pr.areasUnlocked = Areas.COUNT
		Data.setStatMax(player, "maxArea", Areas.COUNT)
		table.insert(parts, "all areas unlocked")
	end
	Data.addCash(player, 0) -- refreshes the leaderboard numbers beside the player's name
	Data.sync(player, "cash", "diamonds", "rebirths", "areasUnlocked", "titles", "stats")
	Data.refreshPublic(player)
	Character.refresh(player)
	return true, "🎁 Code redeemed: " .. table.concat(parts, ", ")
end

---------------------------------------------------------------- teleporting
local lastTeleport = {}

-- Jump straight to the marketplace (0) or to any area the player has unlocked.
function handlers.Teleport(player, pr, areaId)
	if type(areaId) ~= "number" or areaId % 1 ~= 0 or (areaId ~= 0 and not Areas.List[areaId]) then
		return fail("Invalid place.")
	end
	if areaId > pr.areasUnlocked then
		return fail("🔒 Unlock " .. Areas.List[areaId].name .. " first.")
	end
	if Boss.inFight(player) then
		return fail("Finish your boss fight first.")
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return fail("You can't teleport right now.")
	end
	local now = os.clock()
	if now - (lastTeleport[player] or 0) < Game.Teleport.cooldown then
		return fail("Wait a moment before teleporting again.")
	end
	lastTeleport[player] = now
	local pos = Areas.teleportPos(areaId)
	pcall(function()
		player:RequestStreamAroundAsync(pos, 3)
	end)
	if player.Character ~= char then
		return fail("You can't teleport right now.")
	end
	local center = areaId == 0 and Vector3.zero or Areas.List[areaId].center
	char:PivotTo(CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z)))
	return true, "Teleported to " .. (areaId == 0 and "the Marketplace" or Areas.List[areaId].name) .. "!"
end

---------------------------------------------------------------- boss fights (see Boss)
function handlers.BossSolo(player, _pr, areaId)
	return Boss.solo(player, areaId)
end

function handlers.BossInvite(player, _pr, areaId)
	return Boss.invite(player, areaId)
end

function handlers.BossRespond(player, _pr, hostId, accept)
	return Boss.respond(player, hostId, accept)
end

function handlers.BossBegin(player)
	return Boss.beginNow(player)
end

function handlers.BossCancel(player)
	return Boss.cancel(player)
end

function handlers.BossLeave(player)
	return Boss.leave(player)
end

---------------------------------------------------------------- dispatcher
local function allowed(player)
	local now = os.clock()
	local b = buckets[player]
	if not b then
		b = { tokens = BURST, t = now }
		buckets[player] = b
	end
	b.tokens = math.min(BURST, b.tokens + (now - b.t) * RATE)
	b.t = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

function Shop.init()
	Remotes.Action.OnServerInvoke = function(player, action, ...)
		if type(action) ~= "string" or not allowed(player) then
			return false, "Slow down!"
		end
		if action == "Init" then
			local t = os.clock()
			while not Data.get(player) and os.clock() - t < 20 and player.Parent do
				task.wait(0.1)
			end
			return Data.snapshot(player) ~= nil, Data.snapshot(player)
		end
		local handler = handlers[action]
		local pr = Data.get(player)
		if not handler or not pr then
			return false, "Not ready."
		end
		local ok, a, b = pcall(handler, player, pr, ...)
		if not ok then
			warn("[Shop] " .. action .. " failed:", a)
			return false, "Something went wrong."
		end
		return a, b
	end
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
		lastRedeem[player] = nil
		lastTeleport[player] = nil
	end)
end

return Shop
