-- Chests, rebirth, diamond shop, monetization, achievements, daily rewards, sounds.
local G = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

---------------------------------------------------------------- Chests
G.CHESTS_PER_AREA = 4
G.CHEST_RESPAWN = 40
G.Chests = {
	{ id = "Common", weight = 60, cash = 60, color = rgb(160, 110, 60) },
	{ id = "Uncommon", weight = 25, cash = 180, color = rgb(90, 210, 90), boostChance = 0.1 },
	{ id = "Rare", weight = 10, cash = 600, color = rgb(70, 150, 255), diamonds = { 1, 3 }, boostChance = 0.2, crateChance = 0.2 },
	{ id = "Epic", weight = 4, cash = 2500, color = rgb(180, 90, 255), diamonds = { 3, 8 }, boostChance = 0.3, crateChance = 0.6 },
	{ id = "Legendary", weight = 1, cash = 12000, color = rgb(255, 190, 40), diamonds = { 10, 25 }, boostChance = 0.5, crateChance = 1, workerChance = 0.3, title = "Treasure Hunter" },
}

---------------------------------------------------------------- Rebirth
G.Rebirth = {}
function G.Rebirth.cost(n: number): number -- diamonds for rebirth n -> n+1
	return 40 + 30 * n + 5 * n * n
end
function G.Rebirth.areaReq(n: number): number -- areas that must be unlocked
	return math.min(12, 4 + n)
end
function G.Rebirth.cashMult(n: number): number
	return 1 + 0.5 * n
end
function G.Rebirth.powerMult(n: number): number
	return 1 + 0.5 * n
end
function G.Rebirth.workerMult(n: number): number
	return 1 + 0.25 * n
end
function G.Rebirth.slots(n: number): number
	return (n >= 2 and 1 or 0) + (n >= 5 and 1 or 0) + (n >= 10 and 1 or 0)
end
G.Rebirth.Titles = { [1] = "Reborn", [5] = "Lawn Legend", [10] = "Grass God", [25] = "Eternal Mower" }

---------------------------------------------------------------- Boosts
G.Boosts = {
	cash = { name = "2x Cash", icon = "💰" },
	speed = { name = "Speed Boost", icon = "⚡" },
	luck = { name = "Lucky Boost", icon = "🍀" },
}

---------------------------------------------------------------- Diamond shop
G.DiamondShop = {
	{ id = "AutoSell", name = "Auto Sell (permanent)", desc = "Sells your grass automatically when the bag is full.", price = 250, icon = "🤖", kind = "perk" },
	{ id = "Slot", name = "+1 Worker Slot", desc = "Equip one more worker. Can be bought twice.", price = 200, icon = "👷", kind = "slot", max = 2 },
	{ id = "BoostCash", name = "2x Cash (15 min)", desc = "Doubles cash from selling.", price = 20, icon = "💰", kind = "boost", boost = "cash", minutes = 15 },
	{ id = "BoostSpeed", name = "Speed Boost (15 min)", desc = "Walk and mow 50% faster.", price = 15, icon = "⚡", kind = "boost", boost = "speed", minutes = 15 },
	{ id = "BoostLuck", name = "Lucky Boost (15 min)", desc = "Better crate and chest luck.", price = 25, icon = "🍀", kind = "boost", boost = "luck", minutes = 15 },
	{ id = "CrateMythic", name = "Mythic Crate", desc = "One Mythic Crate added to your inventory.", price = 45, icon = "📦", kind = "crate", crate = "Mythic" },
	{ id = "CrateSecret", name = "Secret Crate", desc = "One Secret Crate added to your inventory.", price = 130, icon = "📦", kind = "crate", crate = "Secret" },
}

---------------------------------------------------------------- Robux
-- Create these in the Creator Dashboard, then paste the ids here (0 = not set up yet).
G.Passes = {
	{ key = "VIP", id = 0, name = "VIP", icon = "👑", desc = "VIP title, +20% cash and +10% luck." },
	{ key = "Cash2x", id = 0, name = "2x Cash", icon = "💵", desc = "Double cash from selling grass." },
	{ key = "Grass2x", id = 0, name = "2x Grass", icon = "🌿", desc = "Double grass from every cut." },
	{ key = "AutoSell", id = 0, name = "Auto Sell", icon = "🤖", desc = "Sell automatically when your bag is full." },
	{ key = "FastMow", id = 0, name = "Faster Mowing", icon = "⚡", desc = "Mow 50% faster." },
	{ key = "ExtraSlots", id = 0, name = "Extra Worker Slots", icon = "👷", desc = "+2 equipped workers." },
	{ key = "StartBag", id = 0, name = "Bigger Starting Bag", icon = "🎒", desc = "Always start with at least a Medium Bag." },
	{ key = "PremiumVehicles", id = 0, name = "Premium Vehicle Pack", icon = "🚗", desc = "Unlocks the Royal Limo-Mower." },
	{ key = "Diamonds2x", id = 0, name = "2x Diamonds", icon = "💎", desc = "Double diamonds from every source." },
	{ key = "AllAccess", id = 0, name = "All Access Bundle", icon = "🌟", desc = "Every gamepass in one." },
}
-- cash packs scale with your best area: amount = mult x best area's grass value
G.Products = {
	{ key = "CashS", id = 0, name = "Small Cash Pack", icon = "💵", kind = "cash", mult = 5000 },
	{ key = "CashM", id = 0, name = "Big Cash Pack", icon = "💰", kind = "cash", mult = 30000 },
	{ key = "CashL", id = 0, name = "Huge Cash Pack", icon = "🏦", kind = "cash", mult = 200000 },
	{ key = "DiaS", id = 0, name = "100 Diamonds", icon = "💎", kind = "diamonds", amount = 100 },
	{ key = "DiaM", id = 0, name = "600 Diamonds", icon = "💎", kind = "diamonds", amount = 600 },
	{ key = "DiaL", id = 0, name = "3,000 Diamonds", icon = "💎", kind = "diamonds", amount = 3000 },
	{ key = "BCash", id = 0, name = "2x Cash (30 min)", icon = "💰", kind = "boost", boost = "cash", minutes = 30 },
	{ key = "BSpeed", id = 0, name = "Speed Boost (30 min)", icon = "⚡", kind = "boost", boost = "speed", minutes = 30 },
	{ key = "BLuck", id = 0, name = "Lucky Boost (30 min)", icon = "🍀", kind = "boost", boost = "luck", minutes = 30 },
}

---------------------------------------------------------------- Achievements
-- stat = key in profile.stats, tiers = goals, reward = diamonds per tier (x tier index)
G.Achievements = {
	{ id = "grass", name = "Grass Cutter", icon = "🌿", stat = "grassCut", tiers = { 100, 2500, 50000, 1e6, 2.5e7 }, reward = 3, title = "Master Mower" },
	{ id = "cash", name = "Money Maker", icon = "💵", stat = "cashEarned", tiers = { 1000, 1e5, 1e7, 1e9, 1e12 }, reward = 3, title = "Tycoon" },
	{ id = "chests", name = "Treasure Seeker", icon = "🧰", stat = "chests", tiers = { 1, 10, 50, 250 }, reward = 4, title = "Chest Master" },
	{ id = "bosses", name = "Boss Slayer", icon = "⚔️", stat = "bosses", tiers = { 1, 5, 25, 100 }, reward = 5, title = "Boss Slayer" },
	{ id = "areas", name = "Explorer", icon = "🗺️", stat = "maxArea", tiers = { 2, 4, 8, 12 }, reward = 5, title = "World Mower" },
	{ id = "rebirths", name = "Born Again", icon = "🔁", stat = "rebirths", tiers = { 1, 3, 10, 25 }, reward = 8 },
	{ id = "crates", name = "Crate Opener", icon = "📦", stat = "cratesOpened", tiers = { 1, 25, 150, 1000 }, reward = 3, title = "Crate Addict" },
	{ id = "rare", name = "Rare Recruiter", icon = "🔵", stat = "rareFound", tiers = { 1, 10, 50 }, reward = 4 },
	{ id = "legendary", name = "Legend Collector", icon = "🟡", stat = "legendaryFound", tiers = { 1, 5, 25 }, reward = 10, title = "Legendary" },
	{ id = "secret", name = "Secret Finder", icon = "⚫", stat = "secretFound", tiers = { 1, 3, 10 }, reward = 30, title = "Secret Keeper" },
}

---------------------------------------------------------------- Daily rewards (7 day streak calendar)
G.Daily = {
	{ kind = "cash", mult = 400, label = "Cash" },
	{ kind = "diamonds", amount = 5, label = "5 Diamonds" },
	{ kind = "crate", count = 1, label = "Worker Crate" },
	{ kind = "boost", boost = "cash", minutes = 15, label = "2x Cash 15m" },
	{ kind = "diamonds", amount = 15, label = "15 Diamonds" },
	{ kind = "crate", count = 3, label = "3 Worker Crates" },
	{ kind = "diamonds", amount = 40, label = "40 Diamonds + Title", title = "Dedicated" },
}

---------------------------------------------------------------- Movement & clicking
G.Sprint = { mult = 1.4 } -- walk speed multiplier while Shift is held
-- Clicking (or holding the mouse / a touch) makes the mower hit this many times faster.
-- window = how long one click keeps the boost going, in seconds.
G.Click = { mult = 2, window = 0.45 }

---------------------------------------------------------------- Sounds
G.Sounds = {
	music = "rbxassetid://113283307098724",
	cut = "rbxasset://sounds/snap.mp3",
	sell = "rbxassetid://135483737426662",
	click = "rbxasset://sounds/clickfast.wav",
	buy = "rbxasset://sounds/electronicpingshort.wav",
	error = "rbxasset://sounds/button.wav",
	chest = "rbxasset://sounds/unsheath.wav",
	reveal = "rbxasset://sounds/victory.wav",
	boss = "rbxasset://sounds/bass.wav",
	hit = "rbxasset://sounds/swordslash.wav",
	win = "rbxassetid://9067124098",
	pop = "rbxasset://sounds/button.wav",
}

return G
