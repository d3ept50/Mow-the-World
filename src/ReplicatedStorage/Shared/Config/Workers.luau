-- Workers, rarities and worker crates. Append entries to expand.
local W = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

W.Rarities = {
	{ id = "Common", color = rgb(190, 190, 190) },
	{ id = "Uncommon", color = rgb(90, 210, 90) },
	{ id = "Rare", color = rgb(70, 150, 255) },
	{ id = "Epic", color = rgb(180, 90, 255) },
	{ id = "Legendary", color = rgb(255, 190, 40) },
	{ id = "Mythic", color = rgb(255, 70, 110) },
	{ id = "Secret", color = rgb(40, 40, 50) },
	{ id = "Divine", color = rgb(255, 245, 190) },
}
W.RarityById = {}
for i, r in ipairs(W.Rarities) do
	r.order = i
	W.RarityById[r.id] = r
end

W.MAX_LEVEL = 25
W.MAX_TIER = 3
W.MAX_INVENTORY = 250
W.BASE_SLOTS = 3

-- look: body colour, skin colour, hat, hat colour, tool
W.List = {
	{ id = "RookieRaker", name = "Rookie Raker", rarity = "Common", damage = 2, look = { rgb(90, 130, 200), rgb(245, 205, 160), "cap", rgb(220, 60, 60), "rake" } },
	{ id = "LawnLad", name = "Lawn Lad", rarity = "Common", damage = 3, look = { rgb(80, 170, 90), rgb(235, 190, 150), "straw", rgb(230, 200, 120), "shears" } },
	{ id = "GardenGnome", name = "Garden Gnome", rarity = "Common", damage = 4, look = { rgb(60, 110, 200), rgb(250, 215, 180), "cone", rgb(220, 50, 50), "rake" } },
	{ id = "HedgeTim", name = "Hedge Trimmer Tim", rarity = "Uncommon", damage = 8, look = { rgb(230, 140, 40), rgb(215, 170, 130), "cap", rgb(40, 40, 40), "trimmer" } },
	{ id = "SprinklerSam", name = "Sprinkler Sam", rarity = "Uncommon", damage = 11, look = { rgb(70, 190, 230), rgb(245, 205, 160), "helmet", rgb(250, 250, 250), "rake" } },
	{ id = "WhackerWendy", name = "Weed Whacker Wendy", rarity = "Uncommon", damage = 15, look = { rgb(230, 90, 160), rgb(240, 200, 165), "straw", rgb(250, 240, 200), "trimmer" } },
	{ id = "TurboGardener", name = "Turbo Gardener", rarity = "Rare", damage = 40, look = { rgb(220, 50, 50), rgb(225, 180, 140), "helmet", rgb(250, 210, 40), "shears" } },
	{ id = "MowerMechanic", name = "Mower Mechanic", rarity = "Rare", damage = 55, look = { rgb(70, 80, 110), rgb(200, 150, 110), "cap", rgb(250, 140, 30), "trimmer" } },
	{ id = "BeeKeeper", name = "Bee Keeper", rarity = "Rare", damage = 75, look = { rgb(250, 215, 60), rgb(245, 235, 220), "straw", rgb(40, 40, 40), "rake" } },
	{ id = "RoboMower", name = "Robo-Mower Bot", rarity = "Epic", damage = 400, look = { rgb(170, 175, 190), rgb(120, 125, 140), "antenna", rgb(255, 60, 60), "trimmer" } },
	{ id = "ScarecrowSlicer", name = "Scarecrow Slicer", rarity = "Epic", damage = 550, look = { rgb(150, 100, 50), rgb(235, 200, 110), "straw", rgb(90, 60, 30), "scythe" } },
	{ id = "TopiaryKnight", name = "Topiary Knight", rarity = "Epic", damage = 750, look = { rgb(40, 140, 60), rgb(60, 170, 80), "helmet", rgb(190, 195, 205), "shears" } },
	{ id = "GoldenGroundskeeper", name = "Golden Groundskeeper", rarity = "Legendary", damage = 5000, look = { rgb(255, 200, 50), rgb(255, 225, 130), "tophat", rgb(255, 215, 70), "rake" } },
	{ id = "StormReaper", name = "Storm Reaper", rarity = "Legendary", damage = 7000, look = { rgb(50, 70, 130), rgb(170, 200, 255), "hood", rgb(40, 50, 100), "scythe" } },
	{ id = "LawnSamurai", name = "Lawn Samurai", rarity = "Legendary", damage = 9500, look = { rgb(180, 30, 40), rgb(240, 200, 160), "horns", rgb(250, 210, 60), "shears" } },
	{ id = "Dragonling", name = "Verdant Dragonling", rarity = "Mythic", damage = 80000, look = { rgb(40, 190, 110), rgb(60, 220, 130), "horns", rgb(250, 240, 200), "scythe" } },
	{ id = "PhantomHarvester", name = "Phantom Harvester", rarity = "Mythic", damage = 110000, look = { rgb(120, 90, 200), rgb(200, 190, 255), "hood", rgb(70, 40, 140), "scythe" } },
	{ id = "TitanTrimmer", name = "Titan Trimmer", rarity = "Mythic", damage = 150000, look = { rgb(200, 60, 60), rgb(255, 170, 120), "crown", rgb(255, 200, 50), "trimmer" } },
	{ id = "ShadowScythe", name = "Shadow Scythe", rarity = "Secret", damage = 1.5e6, look = { rgb(20, 20, 28), rgb(50, 50, 65), "hood", rgb(10, 10, 14), "scythe" } },
	{ id = "Lawnfather", name = "The Lawnfather", rarity = "Secret", damage = 2.1e6, look = { rgb(25, 25, 30), rgb(235, 195, 160), "tophat", rgb(15, 15, 18), "shears" } },
	{ id = "GlitchGardener", name = "Glitch Gardener", rarity = "Secret", damage = 2.9e6, look = { rgb(0, 255, 170), rgb(255, 0, 200), "antenna", rgb(0, 255, 255), "trimmer" } },
	{ id = "GaiasChosen", name = "Gaia's Chosen", rarity = "Divine", damage = 3e7, look = { rgb(120, 230, 140), rgb(255, 250, 225), "halo", rgb(255, 235, 130), "rake" } },
	{ id = "CelestialMower", name = "Celestial Mower", rarity = "Divine", damage = 4.2e7, look = { rgb(160, 200, 255), rgb(255, 255, 255), "halo", rgb(255, 240, 160), "trimmer" } },
	{ id = "EternalReaper", name = "Eternal Reaper", rarity = "Divine", damage = 6e7, look = { rgb(255, 235, 170), rgb(255, 255, 240), "crown", rgb(255, 215, 80), "scythe" } },
}
W.ById = {}
W.ByRarity = {}
for _, w in ipairs(W.List) do
	W.ById[w.id] = w
	W.ByRarity[w.rarity] = W.ByRarity[w.rarity] or {}
	table.insert(W.ByRarity[w.rarity], w)
end

-- Total damage of an owned worker instance { id, lvl, tier }
function W.power(inst): number
	local def = W.ById[inst.id]
	if not def then
		return 0
	end
	return math.floor(def.damage * (1 + 0.2 * ((inst.lvl or 1) - 1)) * 1.5 ^ (inst.tier or 0))
end

function W.levelCost(inst): number
	local def = W.ById[inst.id]
	return math.floor(def.damage * 30 * 1.28 ^ ((inst.lvl or 1) - 1))
end

-- Star upgrade cost in diamonds
function W.tierCost(inst): number
	local def = W.ById[inst.id]
	local r = W.RarityById[def.rarity].order
	return (5 + r * 5) * ((inst.tier or 0) + 1)
end

-- Crates. odds = rarity weights (percent). currency = "cash" or "diamonds".
W.Crates = {
	{ id = "Basic", name = "Basic Crate", price = 100, currency = "cash", area = 1, anim = "shake", odds = { Common = 70, Uncommon = 25, Rare = 5 },
		look = { color = rgb(160, 110, 60), trim = rgb(90, 60, 30), mat = "WoodPlanks" } },
	{ id = "Grass", name = "Grass Crate", price = 6000, currency = "cash", area = 3, anim = "bounce", odds = { Uncommon = 65, Rare = 28, Epic = 7 },
		look = { color = rgb(70, 170, 70), trim = rgb(200, 240, 120), mat = "Grass", top = "leaf" } },
	{ id = "Golden", name = "Golden Crate", price = 500000, currency = "cash", area = 5, anim = "spin", odds = { Rare = 70, Epic = 25, Legendary = 5 },
		look = { color = rgb(255, 200, 50), trim = rgb(255, 245, 190), mat = "Metal", top = "gem" } },
	{ id = "Mythic", name = "Mythic Crate", price = 3e7, currency = "cash", area = 7, anim = "pulse", odds = { Epic = 75, Legendary = 22, Mythic = 3 },
		look = { color = rgb(90, 40, 140), trim = rgb(255, 70, 150), mat = "Slate", top = "gem", neon = true } },
	{ id = "Secret", name = "Secret Crate", price = 3e9, currency = "cash", area = 9, anim = "float", odds = { Legendary = 80, Mythic = 18.5, Secret = 1.5 },
		look = { color = rgb(25, 25, 32), trim = rgb(255, 40, 60), mat = "Metal", top = "skull", neon = true } },
	{ id = "Divine", name = "Divine Crate", price = 300, currency = "diamonds", area = 11, rebirth = 1, anim = "ascend", odds = { Mythic = 85, Secret = 14, Divine = 1 },
		look = { color = rgb(255, 250, 240), trim = rgb(255, 215, 90), mat = "Marble", top = "halo", neon = true } },
}
W.CrateById = {}
for i, c in ipairs(W.Crates) do
	c.order = i
	W.CrateById[c.id] = c
end

-- Flattened odds per worker for display: { {worker=def, chance=percent}, ... }
function W.crateOdds(crateId: string)
	local crate = W.CrateById[crateId]
	local out = {}
	for rarity, pct in pairs(crate.odds) do
		local list = W.ByRarity[rarity]
		for _, w in ipairs(list) do
			table.insert(out, { worker = w, chance = pct / #list })
		end
	end
	table.sort(out, function(a, b)
		return a.chance > b.chance
	end)
	return out
end

return W
