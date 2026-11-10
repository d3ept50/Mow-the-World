-- Gamepasses and developer products (ids are set in ReplicatedStorage.Shared.Config.Game).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Game = require(RS.Shared.Config.Game)
local Util = require(RS.Shared.Util)
local Data = require(script.Parent.Data)
local Character = require(script.Parent.Character)

local M = {}

local function apply(player)
	if Data.hasPass(player, "VIP") then
		Data.addTitle(player, "VIP")
	end
	Data.sync(player, "passes")
	Character.refresh(player)
end

local function grantProduct(player, pr, product)
	if product.kind == "cash" then
		local amount = product.mult * Data.bestAreaValue(player)
		Data.addCash(player, amount)
		Data.notify(player, "💵 +$" .. Util.fmt(amount) .. " — thank you!", "big")
	elseif product.kind == "diamonds" then
		Data.addDiamonds(player, product.amount)
		Data.notify(player, "💎 +" .. product.amount .. " diamonds — thank you!", "big")
	elseif product.kind == "boost" then
		Data.addBoost(player, product.boost, product.minutes)
		Character.updateSpeed(player)
		Data.notify(player, Game.Boosts[product.boost].icon .. " " .. product.name .. " activated!", "big")
	end
end

-- Idempotent: a purchase id is recorded in the profile and only reported as granted once saved.
local function processReceipt(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local pr = player and Data.get(player)
	if not pr then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(info.PurchaseId)
	if not pr.receipts[purchaseId] then
		local product
		for _, p in ipairs(Game.Products) do
			if p.id == info.ProductId then
				product = p
			end
		end
		if not product then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		grantProduct(player, pr, product)
		pr.receipts[purchaseId] = os.time()
		-- keep the receipt log small
		local count, oldestKey, oldest = 0, nil, math.huge
		for k, t in pairs(pr.receipts) do
			count += 1
			if t < oldest then
				oldest, oldestKey = t, k
			end
		end
		if count > 80 and oldestKey then
			pr.receipts[oldestKey] = nil
		end
	end
	if Data.save(player) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function M.init()
	Data.onLoaded(function(player)
		local owned = {}
		for _, pass in ipairs(Game.Passes) do
			if pass.id > 0 then
				local ok, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.id)
				if ok and has then
					owned[pass.key] = true
				end
			end
		end
		if player.Parent then
			Data.passes[player] = owned
			apply(player)
		end
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for _, pass in ipairs(Game.Passes) do
			if pass.id == passId and Data.passes[player] then
				Data.passes[player][pass.key] = true
				apply(player)
				Data.notify(player, pass.icon .. " " .. pass.name .. " unlocked — thank you!", "big")
			end
		end
	end)
	MarketplaceService.ProcessReceipt = processReceipt
end

return M
