-- Mowers, bags and vehicles. Append entries to expand.
local Items = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- damage per hit, speed = hits/sec, radius in studs, eff = grass units per tile
Items.Mowers = {
	{ id = "Scissors", name = "Scissors", damage = 5, speed = 2.0, radius = 5, eff = 1, price = 0, area = 1, look = { kind = "scissors", color = rgb(200, 200, 210), accent = rgb(230, 60, 60), scale = 1 } },
	{ id = "Shears", name = "Garden Shears", damage = 9, speed = 2.2, radius = 6, eff = 1, price = 75, area = 1, look = { kind = "scissors", color = rgb(170, 180, 190), accent = rgb(60, 160, 70), scale = 1.6 } },
	{ id = "Push", name = "Basic Push Mower", damage = 40, speed = 2.4, radius = 7, eff = 1.25, price = 500, area = 2, look = { kind = "push", color = rgb(210, 60, 50), accent = rgb(40, 40, 40), scale = 0.9 } },
	{ id = "Electric", name = "Electric Mower", damage = 180, speed = 2.7, radius = 7.5, eff = 1.5, price = 3500, area = 3, look = { kind = "push", color = rgb(60, 170, 230), accent = rgb(250, 250, 250), scale = 1, engine = true } },
	{ id = "Petrol", name = "Petrol Mower", damage = 820, speed = 3.0, radius = 8, eff = 1.5, price = 25000, area = 4, look = { kind = "push", color = rgb(240, 150, 30), accent = rgb(50, 50, 50), scale = 1.1, engine = true, stack = true } },
	{ id = "Pro", name = "Professional Mower", damage = 3700, speed = 3.2, radius = 8.5, eff = 1.75, price = 175000, area = 5, look = { kind = "push", color = rgb(50, 160, 80), accent = rgb(250, 220, 60), scale = 1.2, engine = true, stack = true, bag = true } },
	{ id = "RideOn", name = "Ride-On Mower", damage = 16600, speed = 3.4, radius = 9.5, eff = 2, price = 1.2e6, area = 6, look = { kind = "push", color = rgb(200, 40, 40), accent = rgb(240, 240, 240), scale = 1.35, engine = true, stack = true, seat = true } },
	{ id = "ZeroTurn", name = "Zero-Turn Mower", damage = 74700, speed = 3.7, radius = 10.5, eff = 2, price = 8.5e6, area = 7, look = { kind = "push", color = rgb(250, 210, 40), accent = rgb(30, 30, 30), scale = 1.45, engine = true, stack = true, seat = true, wide = true } },
	{ id = "Commercial", name = "Commercial Mower", damage = 336000, speed = 4.0, radius = 11.5, eff = 2.25, price = 6e7, area = 8, look = { kind = "push", color = rgb(40, 90, 200), accent = rgb(250, 140, 30), scale = 1.6, engine = true, stack = true, seat = true, wide = true, bag = true } },
	{ id = "Industrial", name = "Industrial Mower", damage = 1.5e6, speed = 4.3, radius = 12.5, eff = 2.5, price = 4.2e8, area = 9, look = { kind = "push", color = rgb(90, 90, 100), accent = rgb(250, 200, 30), scale = 1.8, engine = true, stack = true, seat = true, wide = true, bag = true, twin = true } },
	{ id = "Mega", name = "Mega Mower", damage = 6.8e6, speed = 4.6, radius = 14, eff = 3, price = 3e9, area = 10, look = { kind = "push", color = rgb(150, 50, 220), accent = rgb(60, 255, 200), scale = 2.1, engine = true, stack = true, seat = true, wide = true, bag = true, twin = true, glow = rgb(60, 255, 200) } },
	-- Rebirth exclusives: unlocked automatically (and kept forever) at a rebirth milestone
	{ id = "Golden", name = "Golden Mower", damage = 600, speed = 3.5, radius = 9, eff = 2, price = 0, area = 1, rebirth = 1, look = { kind = "push", color = rgb(255, 205, 50), accent = rgb(255, 245, 180), scale = 1.3, engine = true, stack = true, glow = rgb(255, 220, 80), mat = "Metal" } },
	{ id = "Diamond", name = "Diamond Mower", damage = 6000, speed = 3.8, radius = 10, eff = 2.25, price = 0, area = 1, rebirth = 2, look = { kind = "push", color = rgb(120, 230, 255), accent = rgb(240, 255, 255), scale = 1.4, engine = true, stack = true, glow = rgb(140, 240, 255), mat = "Glass" } },
	{ id = "Plasma", name = "Plasma Mower", damage = 50000, speed = 4.1, radius = 11, eff = 2.5, price = 0, area = 1, rebirth = 3, look = { kind = "push", color = rgb(60, 60, 80), accent = rgb(90, 160, 255), scale = 1.5, engine = true, twin = true, wide = true, glow = rgb(90, 160, 255), mat = "Neon" } },
	{ id = "Toxic", name = "Toxic Mower", damage = 500000, speed = 4.4, radius = 12, eff = 2.75, price = 0, area = 1, rebirth = 5, look = { kind = "push", color = rgb(50, 70, 40), accent = rgb(170, 255, 50), scale = 1.6, engine = true, stack = true, twin = true, wide = true, glow = rgb(170, 255, 50) } },
	{ id = "Inferno", name = "Inferno Mower", damage = 4e6, speed = 4.7, radius = 13, eff = 3, price = 0, area = 1, rebirth = 7, look = { kind = "push", color = rgb(60, 30, 30), accent = rgb(255, 110, 30), scale = 1.7, engine = true, stack = true, twin = true, wide = true, seat = true, glow = rgb(255, 110, 30), fire = true } },
	{ id = "Galaxy", name = "Galaxy Mower", damage = 3e7, speed = 5.0, radius = 14, eff = 3.5, price = 0, area = 1, rebirth = 10, look = { kind = "push", color = rgb(40, 20, 90), accent = rgb(190, 130, 255), scale = 1.8, engine = true, twin = true, wide = true, seat = true, glow = rgb(190, 130, 255), mat = "Neon" } },
	{ id = "Rainbow", name = "Rainbow Mower", damage = 2e8, speed = 5.3, radius = 15, eff = 4, price = 0, area = 1, rebirth = 15, look = { kind = "push", color = rgb(255, 80, 80), accent = rgb(80, 220, 255), scale = 1.9, engine = true, twin = true, wide = true, seat = true, bag = true, glow = rgb(255, 255, 255), rainbow = true } },
	{ id = "Divine", name = "Divine Mower", damage = 1.5e9, speed = 5.6, radius = 16, eff = 5, price = 0, area = 1, rebirth = 20, look = { kind = "push", color = rgb(255, 250, 235), accent = rgb(255, 215, 90), scale = 2.0, engine = true, twin = true, wide = true, seat = true, bag = true, glow = rgb(255, 235, 150), mat = "Marble", halo = true } },
	{ id = "CosmicMega", name = "Cosmic Mega Mower", damage = 1.2e10, speed = 6.0, radius = 18, eff = 6, price = 0, area = 1, rebirth = 30, look = { kind = "push", color = rgb(20, 10, 35), accent = rgb(255, 60, 220), scale = 2.4, engine = true, stack = true, twin = true, wide = true, seat = true, bag = true, glow = rgb(255, 60, 220), mat = "Neon", halo = true, fire = true } },
}

Items.Bags = {
	{ id = "Tiny", name = "Tiny Bag", capacity = 25, price = 0, color = rgb(160, 120, 80) },
	{ id = "Small", name = "Small Bag", capacity = 100, price = 60, color = rgb(120, 170, 90) },
	{ id = "Medium", name = "Medium Bag", capacity = 400, price = 800, color = rgb(80, 150, 220) },
	{ id = "Large", name = "Large Bag", capacity = 1500, price = 12000, color = rgb(230, 150, 50) },
	{ id = "Huge", name = "Huge Bag", capacity = 6000, price = 180000, color = rgb(220, 70, 70) },
	{ id = "Massive", name = "Massive Bag", capacity = 25000, price = 2.5e6, color = rgb(160, 80, 220) },
	{ id = "Professional", name = "Professional Bag", capacity = 100000, price = 4e7, color = rgb(60, 60, 70) },
	{ id = "Industrial", name = "Industrial Bag", capacity = 500000, price = 7e8, color = rgb(250, 200, 40) },
	{ id = "Infinite", name = "Infinite Bag", capacity = math.huge, price = 2e10, color = rgb(255, 80, 230) },
}

-- dmg = multiplier on mower damage while riding, storage = bag capacity multiplier
Items.Vehicles = {
	{ id = "Tractor", name = "Basic Lawn Tractor", speed = 24, dmg = 1.25, radius = 8, storage = 1.5, price = 2000, area = 2, look = { color = rgb(60, 150, 70), accent = rgb(250, 220, 60), scale = 0.9 } },
	{ id = "RideOn", name = "Ride-On Mower", speed = 28, dmg = 1.5, radius = 9, storage = 2, price = 40000, area = 4, look = { color = rgb(210, 50, 50), accent = rgb(240, 240, 240), scale = 1 } },
	{ id = "Buggy", name = "Fast Mowing Buggy", speed = 44, dmg = 1.5, radius = 9, storage = 2, price = 600000, area = 5, look = { color = rgb(250, 150, 30), accent = rgb(30, 30, 30), scale = 0.95, spoiler = true } },
	{ id = "ProTractor", name = "Professional Tractor", speed = 34, dmg = 2, radius = 11, storage = 3, price = 9e6, area = 7, look = { color = rgb(40, 100, 210), accent = rgb(250, 250, 250), scale = 1.15, roof = true } },
	{ id = "HeavyDuty", name = "Heavy-Duty Mower", speed = 36, dmg = 2.5, radius = 13, storage = 4, price = 1.5e8, area = 8, look = { color = rgb(90, 90, 100), accent = rgb(250, 200, 40), scale = 1.3, roof = true, stacks = true } },
	{ id = "IndustrialMachine", name = "Industrial Mowing Machine", speed = 40, dmg = 3, radius = 15, storage = 6, price = 2.5e9, area = 9, look = { color = rgb(240, 200, 40), accent = rgb(40, 40, 40), scale = 1.45, roof = true, stacks = true, wideDeck = true } },
	{ id = "MegaVehicle", name = "Mega Mowing Vehicle", speed = 46, dmg = 4, radius = 18, storage = 10, price = 5e10, area = 11, look = { color = rgb(150, 50, 220), accent = rgb(60, 255, 200), scale = 1.65, roof = true, stacks = true, wideDeck = true, spoiler = true, glow = rgb(60, 255, 200) } },
	{ id = "Phoenix", name = "Phoenix Cruiser", speed = 50, dmg = 4.5, radius = 16, storage = 8, price = 0, area = 1, rebirth = 3, look = { color = rgb(255, 110, 30), accent = rgb(255, 220, 80), scale = 1.3, spoiler = true, wings = true, glow = rgb(255, 150, 40) } },
	{ id = "Starship", name = "Starship Mower", speed = 60, dmg = 6, radius = 20, storage = 15, price = 0, area = 1, rebirth = 8, look = { color = rgb(40, 20, 90), accent = rgb(190, 130, 255), scale = 1.5, roof = true, wings = true, wideDeck = true, glow = rgb(190, 130, 255) } },
	{ id = "RoyalLimo", name = "Royal Limo-Mower", speed = 42, dmg = 3, radius = 14, storage = 5, price = 0, area = 1, pass = "PremiumVehicles", look = { color = rgb(250, 250, 250), accent = rgb(255, 205, 50), scale = 1.35, roof = true, spoiler = true, glow = rgb(255, 220, 90) } },
}

local function index(list)
	local map = {}
	for i, item in ipairs(list) do
		item.order = i
		map[item.id] = item
	end
	return map
end
Items.MowerById = index(Items.Mowers)
Items.BagById = index(Items.Bags)
Items.VehicleById = index(Items.Vehicles)

return Items
