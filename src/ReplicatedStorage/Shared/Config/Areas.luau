-- Area definitions + world layout maths.
-- The world is a set of islands: a central marketplace island and one island per area,
-- joined by bridges. To add a new area: append to DEFS and add a free cell to RING
-- (and widen the grid if needed).
local Areas = {}

Areas.CELL = 400 -- size of one area island (studs)
Areas.PITCH = 520 -- distance between neighbouring island centres
Areas.GAP = Areas.PITCH - Areas.CELL -- water between islands (bridge length)
Areas.MARKET_HALF = 330 -- half size of the town island in the middle (its bridges are longer than the rest)
Areas.LANDMARK_OFFSET = Vector3.new(148, 0, -148)
Areas.TILE = 6 -- grass tile size
Areas.GRID = 30 -- tiles per side of a field
Areas.TILES = Areas.GRID * Areas.GRID -- tile numbers run from 1 to this
-- The boss stands on a stone plaza in the very middle of the island. The grass field
-- wraps around it: the middle HOLE x HOLE tiles of the grid have no grass.
Areas.HOLE = 10
Areas.TILE_COUNT = Areas.TILES - Areas.HOLE * Areas.HOLE -- grass tiles that really exist
Areas.RESPAWN = 16 -- seconds for grass to regrow
Areas.BOSS_OFFSET = Vector3.new(0, 0, 0) -- the centre of the island
Areas.SELL_OFFSET = Vector3.new(-138, 0, -138)
Areas.ARENA_RADIUS = 21
-- Grass milestones: clear this many grass tiles in an area to earn each reward.
-- These are the goals for area 1; every later area needs MILESTONE_GROWTH x more per area.
Areas.MILESTONES = { 250, 500, 1000, 2000 }
Areas.MILESTONE_GROWTH = 0.5
Areas.MILESTONE_CASH = { 150, 400, 900, 2500 } -- x grass value

-- Boss fights happen in a separate arena, one per fight, built far away from the islands.
Areas.BOSS_ZONE = Areas.ARENA_RADIUS + 2 -- stepping this close to a boss opens the fight prompt
Areas.FIGHT_RADIUS = 58 -- size of the fight arena
Areas.FIGHT_ORIGIN = Vector3.new(0, 300, 5000) -- first arena; more are placed along +X
Areas.FIGHT_SPACING = 420

-- Boss attacks. rule = which of each player's workers are hit:
--   front (the first `count` still standing), random (`count` at random), half, all,
--   strongest, weakest, none.
-- mult = damage as a multiple of the boss's attack. windup = warning time in seconds.
-- repeats = hits in a row. rage = the boss's next attack is multiplied by this.
Areas.Moves = {
	swipe = { label = "Swipe", icon = "💥", rule = "front", count = 2, mult = 1, windup = 0.7 },
	slam = { label = "Ground Slam", icon = "🌋", rule = "all", mult = 0.6, windup = 0.9 },
	spin = { label = "Whirlwind", icon = "🌀", rule = "all", mult = 0.45, windup = 0.6 },
	charge = { label = "Charge", icon = "🐗", rule = "half", mult = 0.9, windup = 0.8 },
	smash = { label = "Crushing Blow", icon = "🔨", rule = "strongest", mult = 2.2, windup = 1.1 },
	snipe = { label = "Cull the Weak", icon = "🎯", rule = "weakest", mult = 1.6, windup = 0.7 },
	barrage = { label = "Barrage", icon = "☄️", rule = "random", count = 1, mult = 0.7, windup = 0.5, repeats = 3 },
	quake = { label = "Earthquake", icon = "🪨", rule = "all", mult = 0.85, windup = 1.6 },
	roar = { label = "Enrage", icon = "😡", rule = "none", mult = 0, windup = 0.8, rage = 1.6 },
}

-- Every boss repeats its own sequence of attacks.
local BOSS_MOVES = {
	{ "swipe", "slam", "swipe", "spin" }, -- Dandelion Brute
	{ "barrage", "swipe", "slam" }, -- Sunflower Titan
	{ "smash", "quake", "swipe", "smash" }, -- Elder Treant
	{ "charge", "snipe", "swipe", "charge", "barrage" }, -- Scorpion King
	{ "roar", "slam", "smash", "spin" }, -- Frost Yeti
	{ "slam", "slam", "spin", "charge" }, -- Gummy Golem
	{ "quake", "barrage", "roar", "smash" }, -- Magma Lord
	{ "barrage", "barrage", "snipe", "spin" }, -- Sludge Hydra
	{ "smash", "charge", "quake", "snipe" }, -- Crystal Colossus
	{ "charge", "snipe", "charge", "roar", "spin" }, -- Nebula Wraith
	{ "roar", "quake", "smash", "barrage", "slam" }, -- Seraph Guardian
	{ "roar", "charge", "quake", "snipe", "barrage", "smash" }, -- Void Emperor
}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- Ring of cells (col,row on a 4x4 grid) around the 2x2 central marketplace.
local RING = { { 1, 0 }, { 2, 0 }, { 3, 0 }, { 3, 1 }, { 3, 2 }, { 3, 3 }, { 2, 3 }, { 1, 3 }, { 0, 3 }, { 0, 2 }, { 0, 1 }, { 0, 0 } }

-- terrain material used for each island (coloured with the area's ground colour)
local TERRAIN = { "Grass", "LeafyGrass", "Ground", "Sand", "Snow", "Salt", "Basalt", "Mud", "Slate", "Asphalt", "Limestone", "Concrete" }

local DEFS = {
	{ name = "Starter Meadow", grass = rgb(96, 190, 72), cut = rgb(118, 150, 70), ground = rgb(84, 160, 66), mat = "Grass", wall = rgb(120, 110, 95),
		props = { "tree", "flower", "rock" }, pal = { rgb(70, 160, 60), rgb(110, 80, 50), rgb(255, 220, 90) },
		sky = { clock = 14, ambient = rgb(140, 150, 140), fog = rgb(190, 225, 255), density = 0.25, tint = rgb(255, 255, 255) },
		boss = { name = "Dandelion Brute", body = "ball", color = rgb(250, 220, 70), color2 = rgb(70, 160, 60), mat = "Grass", feature = "petals", size = 7 } },
	{ name = "Sunny Fields", grass = rgb(236, 204, 74), cut = rgb(190, 170, 90), ground = rgb(160, 190, 80), mat = "Grass", wall = rgb(190, 150, 90),
		props = { "haybale", "sunflower", "tree" }, pal = { rgb(120, 180, 60), rgb(120, 85, 50), rgb(255, 200, 40) },
		sky = { clock = 12, ambient = rgb(170, 160, 130), fog = rgb(255, 240, 200), density = 0.22, tint = rgb(255, 250, 230) },
		boss = { name = "Sunflower Titan", body = "cyl", color = rgb(255, 190, 30), color2 = rgb(90, 60, 30), mat = "SmoothPlastic", feature = "petals", size = 8 } },
	{ name = "Enchanted Forest", grass = rgb(40, 180, 150), cut = rgb(40, 100, 80), ground = rgb(36, 92, 64), mat = "Grass", wall = rgb(60, 80, 60),
		props = { "bigtree", "mushroom", "tree" }, pal = { rgb(30, 130, 110), rgb(70, 50, 40), rgb(190, 110, 255) },
		sky = { clock = 18.6, ambient = rgb(110, 100, 150), fog = rgb(120, 90, 170), density = 0.38, tint = rgb(225, 215, 255) },
		boss = { name = "Elder Treant", body = "cyl", color = rgb(90, 65, 45), color2 = rgb(40, 170, 130), mat = "Wood", feature = "horns", size = 9 } },
	{ name = "Desert Dunes", grass = rgb(214, 172, 92), cut = rgb(220, 196, 140), ground = rgb(232, 206, 146), mat = "Sand", wall = rgb(200, 160, 110),
		props = { "cactus", "rock", "deadtree" }, pal = { rgb(80, 150, 80), rgb(150, 120, 80), rgb(240, 130, 80) },
		sky = { clock = 13, ambient = rgb(180, 160, 130), fog = rgb(255, 225, 170), density = 0.3, tint = rgb(255, 240, 215) },
		boss = { name = "Scorpion King", body = "block", color = rgb(190, 120, 50), color2 = rgb(90, 50, 30), mat = "Sandstone", feature = "spikes", size = 9 } },
	{ name = "Snowy Mountains", grass = rgb(170, 225, 245), cut = rgb(225, 235, 245), ground = rgb(242, 246, 252), mat = "Snow", wall = rgb(170, 190, 215),
		props = { "pine", "snowman", "icerock" }, pal = { rgb(40, 110, 80), rgb(90, 65, 45), rgb(150, 220, 255) },
		sky = { clock = 10, ambient = rgb(150, 170, 200), fog = rgb(215, 235, 255), density = 0.4, tint = rgb(225, 240, 255) },
		boss = { name = "Frost Yeti", body = "ball", color = rgb(235, 245, 255), color2 = rgb(110, 190, 255), mat = "Snow", feature = "horns", size = 10 } },
	{ name = "Candy Kingdom", grass = rgb(255, 130, 195), cut = rgb(255, 205, 225), ground = rgb(255, 224, 238), mat = "SmoothPlastic", wall = rgb(255, 160, 200),
		props = { "lollipop", "candycane", "gumdrop" }, pal = { rgb(120, 220, 255), rgb(255, 255, 255), rgb(255, 80, 120) },
		sky = { clock = 15, ambient = rgb(200, 160, 190), fog = rgb(255, 200, 230), density = 0.26, tint = rgb(255, 235, 245) },
		boss = { name = "Gummy Golem", body = "block", color = rgb(255, 90, 150), color2 = rgb(120, 230, 255), mat = "Glass", feature = "crown", size = 10 } },
	{ name = "Volcanic Lands", grass = rgb(255, 112, 30), cut = rgb(70, 50, 45), ground = rgb(52, 42, 42), mat = "Basalt", wall = rgb(60, 40, 40),
		props = { "lavarock", "deadtree", "spike" }, pal = { rgb(255, 90, 20), rgb(45, 35, 35), rgb(255, 180, 40) },
		sky = { clock = 19.4, ambient = rgb(170, 90, 70), fog = rgb(160, 50, 30), density = 0.42, tint = rgb(255, 215, 195) },
		boss = { name = "Magma Lord", body = "block", color = rgb(60, 40, 40), color2 = rgb(255, 100, 20), mat = "Basalt", feature = "spikes", size = 11 } },
	{ name = "Toxic Swamp", grass = rgb(160, 235, 40), cut = rgb(70, 80, 45), ground = rgb(62, 74, 44), mat = "Mud", wall = rgb(60, 80, 50),
		props = { "deadtree", "barrel", "mushroom" }, pal = { rgb(120, 220, 40), rgb(60, 50, 40), rgb(180, 255, 60) },
		sky = { clock = 17.5, ambient = rgb(110, 150, 90), fog = rgb(110, 170, 60), density = 0.5, tint = rgb(220, 255, 205) },
		boss = { name = "Sludge Hydra", body = "ball", color = rgb(90, 160, 40), color2 = rgb(190, 255, 60), mat = "Slate", feature = "heads", size = 11 } },
	{ name = "Crystal Valley", grass = rgb(120, 222, 255), cut = rgb(100, 120, 170), ground = rgb(92, 112, 164), mat = "Slate", wall = rgb(110, 130, 190),
		props = { "crystal", "rock", "crystal" }, pal = { rgb(120, 220, 255), rgb(100, 100, 130), rgb(210, 140, 255) },
		sky = { clock = 16, ambient = rgb(140, 160, 210), fog = rgb(170, 200, 255), density = 0.3, tint = rgb(225, 235, 255) },
		boss = { name = "Crystal Colossus", body = "block", color = rgb(120, 220, 255), color2 = rgb(215, 150, 255), mat = "Glass", feature = "crystals", size = 12 } },
	{ name = "Galaxy Fields", grass = rgb(150, 92, 255), cut = rgb(34, 26, 70), ground = rgb(22, 16, 48), mat = "SmoothPlastic", wall = rgb(40, 30, 90),
		props = { "star", "crystal", "pillar" }, pal = { rgb(150, 100, 255), rgb(40, 30, 80), rgb(255, 240, 150) },
		sky = { clock = 0, ambient = rgb(120, 100, 190), fog = rgb(50, 30, 110), density = 0.32, tint = rgb(225, 215, 255) },
		boss = { name = "Nebula Wraith", body = "ball", color = rgb(60, 40, 130), color2 = rgb(190, 120, 255), mat = "Neon", feature = "wings", size = 12 } },
	{ name = "Divine Gardens", grass = rgb(255, 236, 150), cut = rgb(235, 230, 215), ground = rgb(246, 241, 226), mat = "Marble", wall = rgb(235, 220, 180),
		props = { "pillar", "goldtree", "flower" }, pal = { rgb(255, 215, 90), rgb(240, 235, 225), rgb(255, 245, 190) },
		sky = { clock = 7, ambient = rgb(200, 190, 160), fog = rgb(255, 245, 210), density = 0.3, tint = rgb(255, 250, 230) },
		boss = { name = "Seraph Guardian", body = "cyl", color = rgb(250, 245, 235), color2 = rgb(255, 210, 80), mat = "Marble", feature = "wings", size = 13 } },
	{ name = "Cosmic Dimension", grass = rgb(255, 60, 220), cut = rgb(26, 12, 40), ground = rgb(12, 6, 22), mat = "SmoothPlastic", wall = rgb(40, 10, 60),
		props = { "star", "spike", "crystal" }, pal = { rgb(255, 60, 220), rgb(30, 10, 50), rgb(80, 255, 240) },
		sky = { clock = 0, ambient = rgb(150, 80, 170), fog = rgb(70, 10, 90), density = 0.36, tint = rgb(255, 215, 250) },
		boss = { name = "Void Emperor", body = "block", color = rgb(20, 10, 30), color2 = rgb(255, 60, 220), mat = "Neon", feature = "crown", size = 14 } },
}

Areas.List = {}
Areas.CellMap = {} -- ["c,r"] = areaId (0 = marketplace)
for c = 1, 2 do
	for r = 1, 2 do
		Areas.CellMap[c .. "," .. r] = 0
	end
end
for i, def in ipairs(DEFS) do
	local cell = RING[i]
	def.id = i
	def.cell = cell
	def.center = Vector3.new((cell[1] - 1.5) * Areas.PITCH, 0, (cell[2] - 1.5) * Areas.PITCH)
	def.terrain = TERRAIN[i] or "Grass"
	def.landmarkPos = def.center + Areas.LANDMARK_OFFSET
	def.grassHP = 5 * 5 ^ (i - 1) -- cutting difficulty
	def.grassValue = 4 ^ (i - 1) -- cash per grass unit
	def.boss.hp = def.grassHP * 120
	def.boss.cash = def.grassValue * 1500
	def.boss.diamonds = 5 + 3 * i
	def.boss.attack = 6 * def.grassValue -- damage of one hit on a worker (x the attack's mult)
	def.boss.moves = BOSS_MOVES[i] or BOSS_MOVES[1]
	def.boss.speed = 11 + i -- walking speed in the arena (studs per second)
	def.boss.tempo = math.max(2.4, 4.2 - 0.15 * i) -- seconds between attacks
	def.bossPos = def.center + Areas.BOSS_OFFSET
	def.sellPos = def.center + Areas.SELL_OFFSET
	Areas.List[i] = def
	Areas.CellMap[cell[1] .. "," .. cell[2]] = i
end
Areas.COUNT = #Areas.List

-- Grass tiles to clear in an area for its n-th milestone reward.
function Areas.milestoneGoal(areaId: number, n: number): number?
	local base = Areas.MILESTONES[n]
	return base and math.floor(base * (1 + Areas.MILESTONE_GROWTH * (areaId - 1)) + 0.5) or nil
end

-- Where a player lands when they teleport to an area (0 = marketplace): beside its sell pad.
function Areas.teleportPos(areaId: number): Vector3
	local a = Areas.List[areaId]
	if not a then
		return Vector3.new(0, 6, 26)
	end
	return a.sellPos + Vector3.new(9, 5, 9)
end

-- Where a player is put back after a boss fight: just outside the boss's circle.
function Areas.bossReturnPos(areaId: number): Vector3
	local a = Areas.List[areaId]
	return a.bossPos + Vector3.new(0, 5, Areas.BOSS_ZONE + 5)
end

-- Which area (0 = marketplace, nil = on a bridge / outside) contains this position?
function Areas.at(pos: Vector3): number?
	local mh = Areas.MARKET_HALF
	if math.abs(pos.X) <= mh and math.abs(pos.Z) <= mh then
		return 0
	end
	local c = math.floor(pos.X / Areas.PITCH) + 2
	local r = math.floor(pos.Z / Areas.PITCH) + 2
	local id = Areas.CellMap[c .. "," .. r]
	local a = id and Areas.List[id]
	if a then
		local half = Areas.CELL / 2
		if math.abs(pos.X - a.center.X) <= half and math.abs(pos.Z - a.center.Z) <= half then
			return id
		end
	end
	return nil
end

local HALF = Areas.GRID * Areas.TILE / 2

function Areas.tilePos(areaId: number, idx: number): Vector3
	local a = Areas.List[areaId]
	local col = (idx - 1) % Areas.GRID
	local row = (idx - 1) // Areas.GRID
	return Vector3.new(a.center.X - HALF + (col + 0.5) * Areas.TILE, 0, a.center.Z - HALF + (row + 0.5) * Areas.TILE)
end

-- Is there grass on this tile? (The middle of the grid is the boss's plaza.)
function Areas.tileExists(idx: number): boolean
	local col = (idx - 1) % Areas.GRID
	local row = (idx - 1) // Areas.GRID
	local lo = (Areas.GRID - Areas.HOLE) / 2
	local hi = lo + Areas.HOLE
	return not (col >= lo and col < hi and row >= lo and row < hi)
end

-- Returns col,row (0-based, may be out of range) for a position inside an area
function Areas.tileCoord(areaId: number, pos: Vector3): (number, number)
	local a = Areas.List[areaId]
	return math.floor((pos.X - a.center.X + HALF) / Areas.TILE), math.floor((pos.Z - a.center.Z + HALF) / Areas.TILE)
end

-- Marketplace shop locations (ring around the fountain)
Areas.SHOP_RADIUS = 105
local SHOPS = { "Mowers", "Bags", "Crates", "Vehicles", "Rebirth", "Diamonds", "Robux", "Leaderboards", "Sell" }
Areas.Shops = {}
for i, name in ipairs(SHOPS) do
	local ang = math.rad((i - 1) * 40 + 20)
	Areas.Shops[name] = Vector3.new(math.sin(ang) * Areas.SHOP_RADIUS, 0, -math.cos(ang) * Areas.SHOP_RADIUS)
end
Areas.ShopOrder = SHOPS

return Areas
