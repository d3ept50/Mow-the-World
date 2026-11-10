-- Worker crates: server-side rolls, purchases and opening.
local RS = game:GetService("ReplicatedStorage")
local W = require(RS.Shared.Config.Workers)
local Areas = require(RS.Shared.Config.Areas)
local Data = require(script.Parent.Data)
local Remotes = RS.Remotes

local Crates = {}
local rng = Random.new()
local ALLOWED_COUNTS = { [1] = true, [3] = true, [10] = true }

-- Best cash crate available for an area (used for chest / boss / milestone rewards)
function Crates.forArea(areaId: number): string
	local best = W.Crates[1]
	for _, c in ipairs(W.Crates) do
		if c.area <= areaId and not c.rebirth and c.currency == "cash" then
			best = c
		end
	end
	return best.id
end

function Crates.roll(crateId: string, luck: number)
	local crate = W.CrateById[crateId]
	local entries = {}
	for rarity, pct in pairs(crate.odds) do
		table.insert(entries, { rarity = rarity, w = pct, order = W.RarityById[rarity].order })
	end
	table.sort(entries, function(a, b)
		return a.order < b.order
	end)
	local total = 0
	for i, e in ipairs(entries) do
		if i > 1 and luck > 1 then
			e.w *= luck
		end
		total += e.w
	end
	local r = rng:NextNumber() * total
	local chosen = entries[1]
	for _, e in ipairs(entries) do
		r -= e.w
		if r <= 0 then
			chosen = e
			break
		end
	end
	local list = W.ByRarity[chosen.rarity]
	return list[rng:NextInteger(1, #list)]
end

-- owned = true opens crates from the inventory, otherwise buys them at the crate shop.
function Crates.open(player: Player, crateId, count, owned)
	local pr = Data.get(player)
	local crate = type(crateId) == "string" and W.CrateById[crateId] or nil
	if not pr or not crate or not ALLOWED_COUNTS[count] then
		return false, "Invalid request."
	end
	if #pr.workers + count > W.MAX_INVENTORY then
		return false, "Your worker inventory is full. Delete some workers first."
	end
	if owned then
		if (pr.crates[crateId] or 0) < count then
			return false, "You don't have enough of those crates."
		end
		pr.crates[crateId] -= count
	else
		if not Data.nearShop(player, "Crates") then
			return false, "Visit the Worker Crate Shop in the marketplace to buy crates."
		end
		if pr.areasUnlocked < crate.area and (pr.stats.maxArea or 1) < crate.area then
			return false, "Unlock " .. Areas.List[crate.area].name .. " first."
		end
		if crate.rebirth and pr.rebirths < crate.rebirth then
			return false, "Requires " .. crate.rebirth .. " rebirth(s)."
		end
		local cost = crate.price * count
		if crate.currency == "diamonds" then
			if pr.diamonds < cost then
				return false, "Not enough diamonds."
			end
			Data.addDiamonds(player, -cost)
		else
			if pr.cash < cost then
				return false, "Not enough cash."
			end
			Data.addCash(player, -cost)
		end
	end
	local luck = Data.luck(player)
	local results = {}
	for _ = 1, count do
		local def = Crates.roll(crateId, luck)
		local inst = Data.addWorker(player, def.id)
		if inst then
			table.insert(results, { id = def.id, uid = inst.uid })
			local order = W.RarityById[def.rarity].order
			if order >= 7 then
				Remotes.Notify:FireAllClients("🌟 " .. player.DisplayName .. " just unboxed a " .. string.upper(def.rarity) .. " worker: " .. def.name .. "!", "big")
			end
		end
	end
	Data.addStat(player, "cratesOpened", count)
	Data.sync(player, "workers", "equipped", "crates")
	return true, results
end

return Crates
