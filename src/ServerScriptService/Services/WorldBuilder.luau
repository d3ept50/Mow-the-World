-- Builds the whole map from config when the server starts.
-- The world is an archipelago: a central marketplace island with one island per area around it,
-- joined by wooden bridges. Terrain (islands, beaches, sea) is baked once and stored in the place;
-- everything else (bridges, cliffs and walls, props, landmarks, the town) is rebuilt on every start.
-- Grass tiles and bosses are created by their own services.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local RS = game:GetService("ReplicatedStorage")

local Areas = require(RS.Shared.Config.Areas)
local W = require(RS.Shared.Config.Workers)
local Util = require(RS.Shared.Util)
local Models = require(RS.Shared.Models)
local Style = require(RS.Shared.Style)
local Scenery = require(script.Parent.Scenery)

local WB = {}

local V, CF, ANG, rad = Vector3.new, CFrame.new, CFrame.Angles, math.rad
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local WHITE = rgb(255, 255, 255)
local CELL, PITCH, GAP, MH = Areas.CELL, Areas.PITCH, Areas.GAP, Areas.MARKET_HALF
local H = CELL / 2
local GATE_W = 26
local FENCE_INSET = 5
local MARKET_CUT = 30 -- how much of each corner of the town island is cut off
local EDGE_BACK = 9 -- how far inside the cliff line the invisible wall stands
local LAYOUT_VERSION = 9 -- bump to force the terrain to be baked again
local WATER_Y = -4
-- Smooth terrain renders 2 studs above the filled volume, so the islands are filled up to TOP:
-- the visible ground then sits at about y = -0.3, just below where the parts are built (y = 0).
local TOP = -2.3
local BEACH = -4.6
local SINK = V(0, -0.3, 0) -- props are pushed down onto the ground so nothing floats

local function part(parent, size, cf, color, mat, shape)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = Enum.PartType[shape]
	end
	p.Size = size
	p.CFrame = typeof(cf) == "Vector3" and CF(cf) or cf
	p.Color = Style.color(color)
	p.Material = Style.material(Enum.Material[mat or "SmoothPlastic"])
	p.Parent = parent
	return p
end

local function deco(parent, size, cf, color, mat, shape)
	local p = part(parent, size, cf, color, mat, shape)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function label(p, face, text, color)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 25
	sg.LightInfluence = 0
	sg.Parent = p
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = color or WHITE
	t.TextStrokeTransparency = 0.4
	t.Parent = sg
	return t
end

local function billboard(p, text, w, h, offsetY, color)
	local bg = Instance.new("BillboardGui")
	bg.Size = UDim2.fromScale(w, h)
	bg.StudsOffset = V(0, offsetY or 0, 0)
	bg.MaxDistance = 220
	bg.LightInfluence = 0
	bg.Parent = p
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = color or WHITE
	t.TextStrokeTransparency = 0.3
	t.Parent = bg
	return bg
end
WB.billboard = billboard
WB.label = label
WB.part = part

local function emitter(p, color, rate, speed)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.Rate = rate
	e.Lifetime = NumberRange.new(1, 2)
	e.Speed = NumberRange.new(speed or 3, (speed or 3) + 2)
	e.SpreadAngle = Vector2.new(25, 25)
	e.EmissionDirection = Enum.NormalId.Top
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	e.LightEmission = 0.7
	e.Parent = p
	return e
end

local function placeProp(parent, kind, pal, rng, pos, scale, neon)
	local m = Models.prop(kind, pal, rng, neon)
	m.WorldPivot = CF(0, 0, 0)
	if scale and math.abs(scale - 1) > 0.01 then
		m:ScaleTo(scale)
	end
	m:PivotTo(CF(pos + SINK) * ANG(0, rng:NextNumber(0, math.pi * 2), 0))
	m.Parent = parent
	return m
end

local function segDist(px, pz, a, b)
	local abx, abz = b.X - a.X, b.Z - a.Z
	local t = math.clamp(((px - a.X) * abx + (pz - a.Z) * abz) / (abx * abx + abz * abz), 0, 1)
	local dx, dz = px - (a.X + abx * t), pz - (a.Z + abz * t)
	return math.sqrt(dx * dx + dz * dz)
end

---------------------------------------------------------------- layout (bridges, entrances, paths)
local SIDE_DIR = { ["x+"] = V(1, 0, 0), ["x-"] = V(-1, 0, 0), ["z+"] = V(0, 0, 1), ["z-"] = V(0, 0, -1) }
local openingsOf = {} -- [areaId] = { { side, offset } }, 0 = marketplace

-- every bridge: marketplace <-> neighbouring areas, and each area <-> the next one
local function links()
	local map = Areas.CellMap
	local list = {}
	local function edge(axis, fixed, mid, a, b)
		if a == nil or b == nil or (a == 0 and b == 0) then
			return
		end
		if a == 0 or b == 0 or math.abs(a - b) == 1 then
			table.insert(list, { axis = axis, fixed = fixed, lateral = mid, low = a, high = b })
		end
	end
	for r = 0, 3 do
		for c = 0, 2 do
			edge("x", (c - 1) * PITCH, (r - 1.5) * PITCH, map[c .. "," .. r], map[(c + 1) .. "," .. r])
		end
	end
	for c = 0, 3 do
		for r = 0, 2 do
			edge("z", (r - 1) * PITCH, (c - 1.5) * PITCH, map[c .. "," .. r], map[c .. "," .. (r + 1)])
		end
	end
	return list
end

local function computeOpenings(list)
	openingsOf = {}
	local function add(id, side, offset)
		openingsOf[id] = openingsOf[id] or {}
		table.insert(openingsOf[id], { side = side, offset = offset })
	end
	for _, l in ipairs(list) do
		add(l.low, l.axis .. "+", l.low == 0 and l.lateral or 0)
		add(l.high, l.axis .. "-", l.high == 0 and l.lateral or 0)
	end
end

-- path segments on the marketplace island: { from, to, width }
local function marketPaths()
	local segs, seen = {}, {}
	for _, o in ipairs(openingsOf[0] or {}) do
		local d = SIDE_DIR[o.side]
		local perp = (o.side == "x+" or o.side == "x-") and V(0, 0, 1) or V(1, 0, 0)
		local target = d * (MH + 2) + perp * o.offset
		local knee = d * (MH - 70) + perp * o.offset
		-- the street leaves the plaza through the nearest gap between two shops (one every 40 degrees)
		local gap = rad(math.floor(math.deg(math.atan2(knee.X, -knee.Z)) / 40 + 0.5) * 40)
		local start = V(math.sin(gap), 0, -math.cos(gap)) * 128
		-- two bridges that share a corner of the town share the street up to it
		local key = math.floor(knee.X + 0.5) .. "," .. math.floor(knee.Z + 0.5)
		if not seen[key] then
			seen[key] = true
			table.insert(segs, { start, knee, 18, main = true })
		end
		table.insert(segs, { knee, target, 18, main = true })
	end
	return segs
end

---------------------------------------------------------------- terrain
local PAVE = Enum.Material.Pavement

-- Swap grass for a material without grass blades (under paths, plazas, fields) by editing the
-- voxel materials directly, which keeps the surface perfectly flat.
local function repave(terrain, minX, minZ, maxX, maxZ, inside)
	local region = Region3.new(V(minX, -8, minZ), V(maxX, 4, maxZ)):ExpandToGrid(4)
	local mats, occ = terrain:ReadVoxels(region, 4)
	local size = mats.Size
	local origin = region.CFrame.Position - region.Size / 2
	for x = 1, size.X do
		local wx = origin.X + (x - 0.5) * 4
		for z = 1, size.Z do
			local wz = origin.Z + (z - 0.5) * 4
			if inside(wx, wz) then
				for y = 1, size.Y do
					if mats[x][y][z] == Enum.Material.Grass then
						mats[x][y][z] = PAVE
					end
				end
			end
		end
	end
	terrain:WriteVoxels(region, 4, mats, occ)
end

local function islandShape(terrain, center, half, r, top, bottom, material)
	local depth, cy = top - bottom, (top + bottom) / 2
	local c = V(center.X, cy, center.Z)
	terrain:FillBlock(CF(c), V(2 * half - 2 * r, depth, 2 * half), material)
	terrain:FillBlock(CF(c), V(2 * half, depth, 2 * half - 2 * r), material)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			terrain:FillCylinder(CF(c + V(sx * (half - r), 0, sz * (half - r))), depth, r, material)
		end
	end
end

-- little sand islets out at sea: { x, z, size }
local ISLETS = {}
do
	local P, E = PITCH, 1.5 * PITCH + H + 105 -- between the islands / beyond the outer ring
	local sizes = { 17, 15, 16, 18, 20, 18, 19, 21, 24, 20, 22, 24, 13, 14, 13, 14 }
	local spots = {
		{ P, P }, { -P, P }, { P, -P }, { -P, -P }, { 0, E }, { 0, -E }, { E, 0 }, { -E, 0 },
		{ E, E }, { -E, E }, { E, -E }, { -E, -E }, { P, E }, { -P, -E }, { E, -P }, { -E, P },
	}
	for i, spot in ipairs(spots) do
		ISLETS[i] = { spot[1], spot[2], sizes[i] }
	end
end

function WB.applyTerrainLook()
	local terrain = workspace.Terrain
	local function col(mat, c)
		pcall(function()
			terrain:SetMaterialColor(Enum.Material[mat], Style.color(c))
		end)
	end
	for _, a in ipairs(Areas.List) do
		col(a.terrain, a.ground)
	end
	col("Sand", rgb(232, 210, 158))
	col("Pavement", rgb(205, 190, 170))
	col("Rock", rgb(120, 118, 116))
	local water = Style.Water
	terrain.WaterColor = water.color
	terrain.WaterTransparency = water.transparency
	terrain.WaterReflectance = water.reflectance
	terrain.WaterWaveSize = water.waveSize
	terrain.WaterWaveSpeed = water.waveSpeed
	local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.52
	clouds.Density = 0.55
	clouds.Color = rgb(255, 255, 255)
	clouds.Parent = terrain
end

-- Islands, beaches, seabed and sea. Slow (a few seconds), so the result is kept in the place file.
function WB.buildTerrain(force: boolean?)
	local terrain = workspace.Terrain
	WB.applyTerrainLook()
	if not force and terrain:GetAttribute("MTWLayout") == LAYOUT_VERSION then
		return false
	end
	terrain:Clear()
	task.wait()
	local SEA, STEP = 2100, 700
	for x = -SEA, SEA - STEP, STEP do
		for z = -SEA, SEA - STEP, STEP do
			terrain:FillBlock(CF(x + STEP / 2, -32, z + STEP / 2), V(STEP, 8, STEP), Enum.Material.Sand)
		end
		task.wait()
	end
	for _, it in ipairs(ISLETS) do
		terrain:FillBall(V(it[1], -it[3] * 0.72, it[2]), it[3], Enum.Material.Sand)
		terrain:FillBall(V(it[1] + it[3] * 0.5, -it[3] * 0.9, it[2] - it[3] * 0.4), it[3] * 0.8, Enum.Material.Rock)
	end
	islandShape(terrain, V(0, 0, 0), MH + 14, 44, BEACH, -30, Enum.Material.Sand)
	-- the town in the middle is paved from edge to edge
	islandShape(terrain, V(0, 0, 0), MH, MARKET_CUT, TOP, -30, PAVE)
	task.wait()
	computeOpenings(links())
	local side = Areas.GRID * Areas.TILE
	for _, a in ipairs(Areas.List) do
		islandShape(terrain, a.center, H + 14, 70, BEACH, -30, Enum.Material.Sand)
		islandShape(terrain, a.center, H, 56, TOP, -30, Enum.Material[a.terrain])
		if a.terrain == "Grass" then
			local c = a.center
			local ar = Areas.ARENA_RADIUS - 1
			repave(terrain, c.X - H, c.Z - H, c.X + H, c.Z + H, function(x, z)
				local dx, dz = x - c.X, z - c.Z
				if math.abs(dx) < side / 2 - 1 and math.abs(dz) < side / 2 - 1 then
					return true
				end
				if (V(x, 0, z) - a.bossPos).Magnitude < ar or (V(x, 0, z) - a.sellPos).Magnitude < 7 then
					return true
				end
				for _, o in ipairs(openingsOf[a.id] or {}) do
					local d = SIDE_DIR[o.side]
					if dx * d.X + dz * d.Z > 0 and math.abs(dx * d.Z + dz * d.X) < 7 then
						return true
					end
				end
				return false
			end)
		end
		task.wait()
	end
	for x = -SEA, SEA - STEP, STEP do
		for z = -SEA, SEA - STEP, STEP do
			local region = Region3.new(V(x, -28, z), V(x + STEP, WATER_Y, z + STEP)):ExpandToGrid(4)
			terrain:ReplaceMaterial(region, 4, Enum.Material.Air, Enum.Material.Water)
			task.wait()
		end
	end
	terrain:SetAttribute("MTWLayout", LAYOUT_VERSION)
	return true
end

local function buildLighting()
	local look = Style.Lighting
	Lighting.Brightness = look.brightness
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.ShadowSoftness = look.shadowSoftness
	Lighting.GeographicLatitude = 35
	Lighting.ColorShift_Top = look.sunTint
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = look.exposure
	local grade = Lighting:FindFirstChild("Grade") or Instance.new("ColorCorrectionEffect")
	grade.Name = "Grade"
	grade.Saturation = look.saturation
	grade.Contrast = look.contrast
	grade.Brightness = look.gradeBrightness
	grade.Parent = Lighting
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = look.bloomIntensity
	bloom.Size = look.bloomSize
	bloom.Threshold = look.bloomThreshold
	bloom.Parent = Lighting
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect") or Instance.new("SunRaysEffect")
	rays.Intensity = look.sunRays
	rays.Spread = 0.8
	rays.Parent = Lighting
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect") or Instance.new("DepthOfFieldEffect")
	dof.FarIntensity = look.farBlur
	dof.FocusDistance = look.focusDistance
	dof.InFocusRadius = look.inFocusRadius
	dof.NearIntensity = 0
	dof.Parent = Lighting
end

---------------------------------------------------------------- island edges: cliffs and walls
-- Every island is ringed by something tall instead of a fence, and each area has its own:
-- rocky cliffs with different rock, height and tops, or a built wall with towers.
-- kind "cliff": color/mat of the rock, minH..maxH, cap = { color, mat } on top (grass, snow...),
--   lava = glowing cracks down the face, crystal = glowing shards on top.
-- kind "wall": color/mat, height, thick (6), towerD = tower width (12), trim colour, tower roof colour, stripe = second wall colour,
--   glow = true makes the trim and tower tops neon.
local EDGES = {
	[0] = { kind = "wall", color = rgb(226, 212, 186), mat = "Brick", height = 48, thick = 11, towerD = 22, trim = rgb(150, 112, 84), tower = rgb(214, 74, 62) },
	{ kind = "cliff", color = rgb(132, 124, 112), mat = "Slate", minH = 24, maxH = 44, cap = { rgb(96, 180, 74), "Grass" } },
	{ kind = "cliff", color = rgb(204, 168, 116), mat = "Sandstone", minH = 20, maxH = 38, cap = { rgb(170, 196, 84), "Grass" } },
	{ kind = "cliff", color = rgb(64, 78, 70), mat = "Slate", minH = 34, maxH = 62, cap = { rgb(36, 132, 104), "Grass" } },
	{ kind = "cliff", color = rgb(212, 150, 96), mat = "Sandstone", minH = 30, maxH = 42, flat = true, cap = { rgb(232, 190, 130), "Sandstone" } },
	{ kind = "cliff", color = rgb(118, 132, 156), mat = "Slate", minH = 40, maxH = 76, cap = { rgb(246, 249, 255), "Snow" } },
	{ kind = "wall", color = rgb(255, 168, 204), mat = "SmoothPlastic", height = 26, trim = rgb(255, 250, 245), tower = rgb(255, 86, 150), stripe = rgb(255, 250, 245) },
	{ kind = "cliff", color = rgb(50, 40, 40), mat = "Basalt", minH = 34, maxH = 62, lava = rgb(255, 110, 30) },
	{ kind = "cliff", color = rgb(72, 82, 58), mat = "Slate", minH = 18, maxH = 34, cap = { rgb(120, 160, 52), "Grass" }, lava = rgb(170, 255, 60) },
	{ kind = "cliff", color = rgb(92, 108, 162), mat = "Slate", minH = 28, maxH = 50, crystal = rgb(130, 226, 255) },
	{ kind = "wall", color = rgb(32, 26, 70), mat = "SmoothPlastic", height = 30, trim = rgb(160, 110, 255), tower = rgb(255, 240, 150), glow = true },
	{ kind = "wall", color = rgb(246, 241, 230), mat = "Marble", height = 28, trim = rgb(255, 210, 80), tower = rgb(255, 210, 80), glow = true },
	{ kind = "cliff", color = rgb(26, 12, 40), mat = "Basalt", minH = 40, maxH = 72, lava = rgb(255, 60, 220), crystal = rgb(80, 255, 240) },
}

local function tone(c: Color3, rng: Random, amt: number): Color3
	local h, sat, v = c:ToHSV()
	return Color3.fromHSV(h, sat, math.clamp(v + rng:NextNumber(-amt, amt), 0, 1))
end

-- One straight stretch of an island's edge, from p1 to p2. out = which way is out to sea.
local function edgeRun(parent, p1, p2, st, rng, out)
	local len = (p2 - p1).Magnitude
	if len < 1 then
		return
	end
	local cf = CFrame.lookAt((p1 + p2) / 2, p2)
	local o = cf.RightVector:Dot(out) >= 0 and 1 or -1 -- local +X or -X points out to sea
	-- the invisible wall stands in front of the rock so nobody walks into the scenery
	local wallPart = part(parent, V(1, 110, len + 2), cf * CF(-o * EDGE_BACK, 50, 0), WHITE)
	wallPart.Transparency = 1
	wallPart.CastShadow = false
	wallPart.Name = "Barrier"
	-- and closes off both ends, so there is no way round it at a bridge
	for _, e in ipairs({ -1, 1 }) do
		local cap = part(parent, V(EDGE_BACK + 6, 110, 1), cf * CF(o * (3 - EDGE_BACK / 2), 50, e * (len / 2 + 1)), WHITE)
		cap.Transparency = 1
		cap.CastShadow = false
		cap.Name = "Barrier"
	end

	if st.kind == "wall" then
		local hgt = st.height
		local thick = st.thick or 6
		local big = hgt > 40
		local trimMat = st.glow and "Neon" or st.mat
		local n = math.max(1, math.floor(len / 13 + 0.5))
		local seg = len / n
		for i = 1, n do
			local z = -len / 2 + (i - 0.5) * seg
			local col = (st.stripe and i % 2 == 0) and st.stripe or st.color
			deco(parent, V(thick, hgt + 4, seg + 0.05), cf * CF(0, hgt / 2 - 2, z), col, st.mat).CastShadow = i % 2 == 0
			-- battlements along the top
			deco(parent, V(thick + 1, big and 5 or 3, seg * 0.5), cf * CF(0, hgt + (big and 2.5 or 1.5), z), st.trim, trimMat).CastShadow = false
		end
		deco(parent, V(thick + 1.4, big and 2.4 or 1.4, len), cf * CF(0, hgt - 0.4, 0), st.trim, trimMat).CastShadow = false
		deco(parent, V(thick + 1.4, big and 6 or 3, len), cf * CF(0, big and 2 or 0.5, 0), st.color:Lerp(rgb(0, 0, 0), 0.25), st.mat).CastShadow = false
		if big then
			-- a second band half way up breaks up the tall face
			deco(parent, V(thick + 0.8, 1.6, len), cf * CF(0, hgt * 0.55, 0), st.trim, trimMat).CastShadow = false
		end
		-- a round tower with a pointed roof every so often
		local td = st.towerD or 12
		local k = td / 12
		local towers = math.max(1, math.floor(len / (big and 90 or 70) + 0.5))
		for i = 1, towers do
			local z = -len / 2 + len * (i - 0.5) / towers
			local at = (cf * CF(o * 1, 0, z)).Position
			local th = hgt + 12 * k
			deco(parent, V(th, td, td), CF(at + V(0, th / 2 - 2, 0)) * ANG(0, 0, rad(90)), st.color, st.mat, "Cylinder")
			deco(parent, V(2 * k, td + 2 * k, td + 2 * k), CF(at + V(0, th - 2, 0)) * ANG(0, 0, rad(90)), st.trim, trimMat, "Cylinder").CastShadow = false
			for j = 0, 3 do
				local d = (13 - j * 3.2) * k
				deco(parent, V(3.2 * k, d, d), CF(at + V(0, th + (0.6 + j * 3.2) * k, 0)) * ANG(0, 0, rad(90)), st.tower, st.glow and "Neon" or "Slate", "Cylinder").CastShadow = false
			end
			local tip = deco(parent, V(2.4 * k, 2.4 * k, 2.4 * k), at + V(0, th + 14.5 * k, 0), st.trim, "Neon", "Ball")
			tip.CastShadow = false
			if i == 1 then
				Models.glow(tip, st.trim, 30)
			end
			if big then
				-- lit windows looking into town
				local inward = -out
				for _, wy in ipairs({ hgt * 0.45, hgt * 0.85 }) do
					local wcf = CFrame.lookAt(at + V(0, wy, 0) + inward * (td / 2 - 0.2), at + V(0, wy, 0) + inward * td)
					deco(parent, V(2.6, 5, 0.8), wcf, rgb(255, 226, 140), "Neon").CastShadow = false
				end
			end
		end
		return
	end

	-- cliffs: a row of big leaning rocks of different heights, with smaller rocks at their feet
	local n = math.max(1, math.floor(len / 17 + 0.5))
	local seg = len / n
	local tilt = st.flat and 0.03 or 0.1
	for i = 1, n do
		local z = -len / 2 + (i - 0.5) * seg
		local h = rng:NextNumber(st.minH, st.maxH)
		local w, d = seg + rng:NextNumber(3, 7), rng:NextNumber(13, 19)
		local rock = cf * CF(o * 3, h / 2 - 4, z) * ANG(rng:NextNumber(-tilt, tilt), rng:NextNumber(-0.3, 0.3), rng:NextNumber(-tilt, tilt))
		deco(parent, V(d, h + 8, w), rock, tone(st.color, rng, 0.05), st.mat)
		local foot = deco(parent, V(8, h * 0.4, w * 0.7), cf * CF(-o * 5, h * 0.16 - 2, z + rng:NextNumber(-3, 3)) * ANG(rng:NextNumber(-0.15, 0.15), rng:NextNumber(-0.5, 0.5), rng:NextNumber(-0.15, 0.15)), tone(st.color, rng, 0.07), st.mat)
		foot.CastShadow = false
		if st.cap then
			deco(parent, V(d * 0.94, 3, w * 0.94), rock * CF(0, h / 2 + 4.6, 0), tone(st.cap[1], rng, 0.04), st.cap[2]).CastShadow = false
			if h > (st.minH + st.maxH) / 2 then
				deco(parent, V(8.4, 1.6, w * 0.66), foot.CFrame * CF(0, h * 0.2 + 0.5, 0), tone(st.cap[1], rng, 0.04), st.cap[2]).CastShadow = false
			end
		end
		if st.lava and i % 2 == 0 then
			-- a glowing crack running down the face that looks into the island
			local crack = deco(parent, V(0.6, h * 0.7, rng:NextNumber(1.2, 2.4)), rock * CF(-o * (d / 2 + 0.1), rng:NextNumber(-2, 4), rng:NextNumber(-3, 3)) * ANG(rng:NextNumber(-0.25, 0.25), 0, 0), st.lava, "Neon")
			crack.CastShadow = false
			if i % 6 == 0 then
				Models.glow(crack, st.lava, 26)
			end
		end
		if st.crystal and i % 2 == 1 then
			for k = 1, 2 do
				local shard = deco(parent, V(2.6, rng:NextNumber(9, 18), 2.6), rock * CF(rng:NextNumber(-4, 4), h / 2 + 6, rng:NextNumber(-4, 4)) * ANG(rng:NextNumber(-0.45, 0.45), rng:NextNumber(0, 3), rng:NextNumber(-0.45, 0.45)), st.crystal, "Neon")
				shard.Transparency = 0.15
				shard.CastShadow = false
				if k == 1 and i % 5 == 0 then
					Models.glow(shard, st.crystal, 26)
				end
			end
		end
	end
end

-- The cliffs or walls around an island, in an octagon, with a gap at every bridge.
-- openings = { { side = "x+"|"x-"|"z+"|"z-", offset = lateral } }
local function edgeLoop(parent, center, half, cut, openings, st, seed)
	local h = half - FENCE_INSET
	local rng = Random.new(seed)
	local function fenceRun(_, p1, p2)
		local mid = (p1 + p2) / 2 - center
		edgeRun(parent, p1, p2, st, rng, V(mid.X, 0, mid.Z).Unit)
	end
	local color = nil
	local function side(name, from, to)
		local gaps = {}
		for _, o in ipairs(openings) do
			if o.side == name then
				table.insert(gaps, o.offset)
			end
		end
		table.sort(gaps)
		local dir = (to - from).Unit
		local len = (to - from).Magnitude
		local mid = (from + to) / 2
		local cursor = 0
		for _, off in ipairs(gaps) do
			-- offset is measured along the positive world axis of this side
			local axisDir = (name == "z-" or name == "z+") and V(1, 0, 0) or V(0, 0, 1)
			local t = (center + axisDir * off - from):Dot(dir)
			local a, b = t - GATE_W / 2 - 1, t + GATE_W / 2 + 1
			if a > cursor then
				fenceRun(parent, from + dir * cursor, from + dir * a, color)
			end
			cursor = math.max(cursor, b)
		end
		if cursor < len then
			fenceRun(parent, from + dir * cursor, to, color)
		end
		local _ = mid
	end
	local c = center
	local pts = {
		c + V(-h + cut, 0, -h), c + V(h - cut, 0, -h), -- z- side
		c + V(h, 0, -h + cut), c + V(h, 0, h - cut), -- x+ side
		c + V(h - cut, 0, h), c + V(-h + cut, 0, h), -- z+ side (runs towards -x)
		c + V(-h, 0, h - cut), c + V(-h, 0, -h + cut), -- x- side (runs towards -z)
	}
	side("z-", pts[1], pts[2])
	fenceRun(parent, pts[2], pts[3], color)
	side("x+", pts[3], pts[4])
	fenceRun(parent, pts[4], pts[5], color)
	side("z+", pts[6], pts[5])
	fenceRun(parent, pts[6], pts[7], color)
	side("x-", pts[8], pts[7])
	fenceRun(parent, pts[8], pts[1], color)
end

---------------------------------------------------------------- bridges & gates
local function gate(parent, axis, along, lateral, areaId, span)
	local a = Areas.List[areaId]
	local function at(l, y)
		return axis == "x" and V(along, y, lateral + l) or V(lateral + l, y, along)
	end
	local stone = a.wall
	for _, s in ipairs({ -1, 1 }) do
		local l = s * (GATE_W / 2 + 2.5)
		part(parent, V(6.4, 6, 6.4), at(l, 0), stone:Lerp(rgb(0, 0, 0), 0.25), "Slate")
		part(parent, V(5, 30, 5), at(l, 17), stone, "Slate")
		part(parent, V(6, 1.6, 6), at(l, 32.6), a.grass)
		local orb = deco(parent, V(3.2, 3.2, 3.2), at(l, 35.6), a.grass, "Neon", "Ball")
		Models.glow(orb, a.grass, 26)
	end
	local beam = part(parent, axis == "x" and V(4, 6.5, GATE_W + 10) or V(GATE_W + 10, 6.5, 4), at(0, 27), rgb(34, 34, 44))
	deco(parent, axis == "x" and V(4.4, 0.6, GATE_W + 10.4) or V(GATE_W + 10.4, 0.6, 4.4), at(0, 30.5), a.grass, "Neon")
	deco(parent, axis == "x" and V(4.4, 0.6, GATE_W + 10.4) or V(GATE_W + 10.4, 0.6, 4.4), at(0, 23.5), a.grass, "Neon")
	local faces = axis == "x" and { Enum.NormalId.Left, Enum.NormalId.Right } or { Enum.NormalId.Front, Enum.NormalId.Back }
	for _, f in ipairs(faces) do
		label(beam, f, a.name, a.grass:Lerp(WHITE, 0.25))
	end
	local barrier = part(parent, axis == "x" and V(1.5, 24, GATE_W) or V(GATE_W, 24, 1.5), at(0, 12), a.grass, "ForceField")
	barrier.Transparency = 0.55
	barrier.Name = "Gate"
	barrier.CastShadow = false
	barrier:SetAttribute("Area", areaId)
	barrier:SetAttribute("Span", span) -- length of the bridge behind it, for the guide arrow
	CollectionService:AddTag(barrier, "Gate")
	local prev = Areas.List[areaId - 1]
	local bb = billboard(barrier, "🔒 " .. a.name .. (prev and ("\nDefeat the " .. prev.boss.name) or ""), 22, 7, 0, WHITE)
	bb.Name = "LockGui"
	bb.AlwaysOnTop = false
end

local function bridge(parent, axis, fixed, lateral, idLow, idHigh)
	-- the bridge spans the water between the two islands; the town island is smaller than
	-- its cell, so bridges that start there are longer
	local from, to = fixed - GAP / 2, fixed + GAP / 2
	if idLow == 0 then
		from = MH
	elseif idHigh == 0 then
		to = -MH
	end
	local len = to - from + 10
	local centre = (from + to) / 2
	local function cfAt(alongOff, y, lat)
		local pos = axis == "x" and V(centre + alongOff, y, lateral + (lat or 0)) or V(lateral + (lat or 0), y, centre + alongOff)
		return axis == "x" and CF(pos) * ANG(0, rad(90), 0) or CF(pos)
	end
	local wood, dark = rgb(156, 112, 70), rgb(96, 68, 44)
	local id = math.max(idLow, idHigh)
	local accent = Areas.List[id].grass
	-- deck (local Z runs along the bridge)
	part(parent, V(GATE_W, 1.2, len), cfAt(0, -0.45), wood, "WoodPlanks").Name = "Deck"
	deco(parent, V(GATE_W + 1.6, 0.8, len), cfAt(0, -1.3), dark, "Wood")
	for _, s in ipairs({ -1, 1 }) do
		local lat = s * (GATE_W / 2 - 0.5)
		deco(parent, V(1, 0.7, len), cfAt(0, 0.5, lat), dark, "Wood")
		deco(parent, V(0.45, 0.45, len), cfAt(0, 4.2, lat), dark, "Wood")
		deco(parent, V(0.3, 0.3, len), cfAt(0, 2.5, lat), rgb(200, 180, 140), "Fabric")
		local wallPart = part(parent, V(1, 90, len), cfAt(0, 41, s * (GATE_W / 2 + 0.2)), WHITE)
		wallPart.Transparency = 1
		wallPart.CastShadow = false
		wallPart.Name = "Barrier"
		local n = math.floor(len / 13)
		for i = 0, n do
			local off = -len / 2 + 1 + (len - 2) * i / n
			local tall = i % 3 == 1
			deco(parent, V(1.2, tall and 9 or 5, 1.2), cfAt(off, tall and 4.2 or 2.2, lat), dark, "Wood")
			if tall then
				local lamp = deco(parent, V(1.5, 1.7, 1.5), cfAt(off, 9.5, lat), accent, "Neon")
				deco(parent, V(1.9, 0.4, 1.9), cfAt(off, 10.55, lat), dark, "Wood")
				Models.glow(lamp, accent, 24)
			end
			if i % 2 == 0 then
				deco(parent, V(28, 2.6, 2.6), cfAt(off, -15, s * (GATE_W / 2 - 2)) * ANG(0, 0, rad(90)), dark, "Wood", "Cylinder")
			end
		end
	end
	local plusHigh = idHigh == id
	gate(parent, axis, fixed + (plusHigh and 1 or -1) * (GAP / 2 - 1), lateral, id, to - from)
end

local function pathStrip(parent, p1, p2, width, color, mat)
	local len = (p2 - p1).Magnitude
	local p = deco(parent, V(width, 1.6, len), CFrame.lookAt((p1 + p2) / 2 + V(0, -0.5, 0), p2 + V(0, -0.5, 0)), color, mat)
	p.CastShadow = false
	p.Name = "Path"
	local edgeC = color:Lerp(rgb(0, 0, 0), 0.25)
	for _, s in ipairs({ -1, 1 }) do
		deco(parent, V(1, 1.7, len), p.CFrame * CF(s * (width / 2 + 0.4), 0.05, 0), edgeC, mat).CastShadow = false
	end
	return p
end

---------------------------------------------------------------- sell stations
local function sellStation(parent, pos)
	local m = Instance.new("Model")
	m.Name = "SellStation"
	local ring = part(m, V(0.4, 17, 17), CF(pos + V(0, 0.2, 0)) * ANG(0, 0, rad(90)), rgb(40, 40, 50), "SmoothPlastic", "Cylinder")
	ring.CanCollide = false
	local pad = part(m, V(0.6, 14, 14), CF(pos + V(0, 0.3, 0)) * ANG(0, 0, rad(90)), rgb(70, 220, 100), "Neon", "Cylinder")
	pad.CanCollide = false
	pad.Name = "Pad"
	CollectionService:AddTag(pad, "SellPad")
	emitter(pad, rgb(255, 225, 80), 8, 5).EmissionDirection = Enum.NormalId.Right
	for i = 0, 3 do
		local a = rad(45 + i * 90)
		local p = pos + V(math.cos(a) * 9.5, 0, math.sin(a) * 9.5)
		deco(m, V(5, 0.9, 0.9), CF(p + V(0, 2.5, 0)) * ANG(0, 0, rad(90)), rgb(60, 60, 72), "Metal", "Cylinder")
		deco(m, V(1.3, 1.3, 1.3), p + V(0, 5.4, 0), rgb(255, 215, 60), "Neon", "Ball")
	end
	local icon = part(m, V(3, 3, 3), CF(pos + V(0, 9, 0)) * ANG(rad(45), 0, rad(45)), rgb(255, 215, 60), "Neon")
	icon.CanCollide = false
	CollectionService:AddTag(icon, "Spin")
	billboard(icon, "💰 SELL", 12, 3.5, 4, rgb(120, 255, 140))
	m.Parent = parent
	return m
end

---------------------------------------------------------------- areas
local GRASSY = { [1] = true, [2] = true, [3] = true, [8] = true, [11] = true }

local function buildArea(world, a)
	local folder = Instance.new("Folder")
	folder.Name = "Area" .. a.id
	local c = a.center
	local side = Areas.GRID * Areas.TILE
	local field = part(folder, V(side, 2.4, side), c + V(0, -0.95, 0), a.cut, a.mat)
	field.Name = "Field"
	field.CastShadow = false
	-- raised border around the field
	local trim = a.wall:Lerp(rgb(0, 0, 0), 0.15)
	for _, s in ipairs({ -1, 1 }) do
		deco(folder, V(side + 3, 2.4, 1.5), c + V(0, -0.5, s * (side / 2 + 0.75)), trim, "Slate").CastShadow = false
		deco(folder, V(1.5, 2.4, side + 3), c + V(s * (side / 2 + 0.75), -0.5, 0), trim, "Slate").CastShadow = false
	end
	sellStation(folder, a.sellPos)

	-- the boss's plaza: a stone square in the middle of the grass, with a glowing obelisk at each corner
	local hole = Areas.HOLE * Areas.TILE
	local stone = a.wall:Lerp(rgb(70, 66, 72), 0.4)
	part(folder, V(hole, 1.4, hole), c + V(0, -0.25, 0), stone, "Cobblestone").Name = "BossPlaza"
	for _, s in ipairs({ -1, 1 }) do
		deco(folder, V(hole + 2, 1.8, 2), c + V(0, -0.2, s * (hole / 2)), trim, "Slate").CastShadow = false
		deco(folder, V(2, 1.8, hole + 2), c + V(s * (hole / 2), -0.2, 0), trim, "Slate").CastShadow = false
		for _, t in ipairs({ -1, 1 }) do
			local corner = c + V(s * (hole / 2 - 2.5), 0, t * (hole / 2 - 2.5))
			part(folder, V(5, 2, 5), corner + V(0, 1, 0), trim, "Slate")
			part(folder, V(3.4, 18, 3.4), corner + V(0, 11, 0), stone, "Slate")
			deco(folder, V(4.2, 1, 4.2), corner + V(0, 20.5, 0), a.boss.color2, "Neon").CastShadow = false
			local orb = deco(folder, V(3, 3, 3), CF(corner + V(0, 23, 0)) * ANG(rad(45), 0, rad(45)), a.boss.color2, "Neon")
			orb.CastShadow = false
			CollectionService:AddTag(orb, "Spin")
			Models.glow(orb, a.boss.color2, 30)
		end
	end

	local openings = openingsOf[a.id] or {}
	local edge = Instance.new("Folder")
	edge.Name = "Edge"
	edgeLoop(edge, c, H, 44, openings, EDGES[a.id] or EDGES[1], a.id * 13)
	edge.Parent = folder
	local pathC = a.wall:Lerp(a.ground, 0.35)
	for _, o in ipairs(openings) do
		local d = SIDE_DIR[o.side]
		pathStrip(folder, c + d * (H + 2), c + d * (side / 2 + 1.5), 18, pathC, "Cobblestone")
	end

	local lm = Scenery.landmark(a.id)
	if lm then
		lm:ScaleTo(1.25)
		lm:PivotTo(CFrame.lookAt(a.landmarkPos, V(c.X, 0, c.Z)) + SINK)
		lm.Parent = folder
	end

	-- themed decorations around the field
	local rng = Random.new(a.id * 77)
	local props = Instance.new("Folder")
	props.Name = "Props"
	local lim = H - 26
	local function free(x, z, margin)
		if math.abs(x) < side / 2 + margin and math.abs(z) < side / 2 + margin then
			return false
		end
		if math.abs(x) + math.abs(z) > 2 * lim - 30 then
			return false
		end
		local p = V(x, 0, z)
		if (p - Areas.SELL_OFFSET).Magnitude < 15 then
			return false
		end
		if (p - Areas.LANDMARK_OFFSET).Magnitude < 30 then
			return false
		end
		for _, o in ipairs(openings) do
			local d = SIDE_DIR[o.side]
			if p:Dot(d) > 0 and math.abs(p:Dot(V(d.Z, 0, d.X))) < 14 then
				return false
			end
		end
		return true
	end
	local placed = 0
	for _ = 1, 800 do
		if placed >= 130 then
			break
		end
		local x, z = rng:NextNumber(-lim, lim), rng:NextNumber(-lim, lim)
		if free(x, z, 7) then
			placed += 1
			local kind = a.props[rng:NextInteger(1, #a.props)]
			local m = placeProp(props, kind, a.pal, rng, c + V(x, 0, z), rng:NextNumber(1, 1.9), a.id >= 10)
			if kind == "star" then
				for _, d in ipairs(m:GetChildren()) do
					CollectionService:AddTag(d, "Spin")
				end
			end
		end
	end
	local clutter = GRASSY[a.id] and { "tuft", "tuft", "bush", "flower" } or { "tuft", "tuft", "rock" }
	placed = 0
	for _ = 1, 600 do
		if placed >= 100 then
			break
		end
		local x, z = rng:NextNumber(-lim, lim), rng:NextNumber(-lim, lim)
		if free(x, z, 3) then
			placed += 1
			local kind = clutter[rng:NextInteger(1, #clutter)]
			placeProp(props, kind, a.pal, rng, c + V(x, 0, z), kind == "rock" and rng:NextNumber(0.3, 0.55) or rng:NextNumber(0.8, 1.3), a.id >= 10)
		end
	end
	-- lamps beside each entrance
	for _, o in ipairs(openings) do
		local d = SIDE_DIR[o.side]
		local perp = V(d.Z, 0, d.X)
		for _, s in ipairs({ -1, 1 }) do
			local lamp = Models.prop("lamp", { a.grass, a.wall, a.grass:Lerp(WHITE, 0.3) }, rng)
			lamp.WorldPivot = CF(0, 0, 0)
			lamp:PivotTo((CFrame.lookAt(c + d * (H - 34) + perp * s * 13, c + d * (H - 34)) + SINK) * ANG(0, rad(-90), 0))
			lamp.Parent = props
		end
	end
	props.Parent = folder
	folder.Parent = world
end

---------------------------------------------------------------- marketplace
local SHOPS = {
	Mowers = { title = "✂️ MOWER SHOP", icon = "✂️", color = rgb(225, 70, 60) },
	Bags = { title = "🎒 BAG SHOP", icon = "🎒", color = rgb(60, 130, 230) },
	Crates = { title = "📦 WORKER CRATES", icon = "📦", color = rgb(240, 150, 40) },
	Vehicles = { title = "🚜 VEHICLE GARAGE", icon = "🚜", color = rgb(90, 100, 130) },
	Rebirth = { title = "🔁 REBIRTH SHRINE", icon = "🔁", color = rgb(170, 80, 240) },
	Diamonds = { title = "💎 DIAMOND SHOP", icon = "💎", color = rgb(60, 200, 235) },
	Robux = { title = "🛒 ROBUX SHOP", icon = "🛒", color = rgb(60, 190, 100) },
	Leaderboards = { title = "🏆 LEADERBOARD PLAZA", icon = "🏆", color = rgb(250, 200, 50) },
	Sell = { title = "💰 SELLING STATION", icon = "💰", color = rgb(70, 220, 100) },
}

local function shopPrompt(parent, cf, name, title)
	local p = part(parent, V(4, 4, 4), cf, WHITE)
	p.Transparency = 1
	p.CanCollide = false
	p.Name = "Prompt"
	p:SetAttribute("Shop", name)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Open"
	pp.ObjectText = title
	pp.MaxActivationDistance = 18
	pp.RequiresLineOfSight = false
	pp.HoldDuration = 0
	pp.Parent = p
	CollectionService:AddTag(p, "ShopPrompt")
end

local function signAndIcon(parent, cf, def, signY)
	local back = deco(parent, V(23.4, 6.2, 0.8), cf * CF(0, signY, -8.7), def.color)
	CollectionService:AddTag(back, "Sway")
	local sign = part(parent, V(22, 5, 1), cf * CF(0, signY, -9), rgb(30, 30, 40))
	sign.CanCollide = false
	label(sign, Enum.NormalId.Front, def.title, def.color:Lerp(WHITE, 0.2))
	CollectionService:AddTag(sign, "Sway")
	local l = Instance.new("PointLight")
	l.Color = def.color
	l.Range = 30
	l.Brightness = 1.2
	l.Parent = sign
	local icon = part(parent, V(3.5, 3.5, 3.5), cf * CF(0, signY + 8, -9) * ANG(rad(45), 0, rad(45)), def.color, "Neon")
	icon.CanCollide = false
	CollectionService:AddTag(icon, "Spin")
	billboard(icon, def.icon, 7, 7, 0)
end

local function stall(parent, cf, name, def)
	local dark = def.color:Lerp(rgb(0, 0, 0), 0.35)
	local wood = rgb(150, 105, 60)
	part(parent, V(28, 2.6, 22), cf * CF(0, -0.5, 0), rgb(150, 142, 132), "Cobblestone")
	part(parent, V(24, 0.4, 18), cf * CF(0, 1, 0), rgb(235, 225, 205), "WoodPlanks")
	part(parent, V(24, 12, 1), cf * CF(0, 6.8, 8.5), rgb(240, 232, 215), "Plaster")
	deco(parent, V(24.2, 4, 1.1), cf * CF(0, 2.8, 8.5), dark, "WoodPlanks")
	part(parent, V(1, 12, 8), cf * CF(-11.5, 6.8, 4.5), rgb(240, 232, 215), "Plaster")
	part(parent, V(1, 12, 8), cf * CF(11.5, 6.8, 4.5), rgb(240, 232, 215), "Plaster")
	for _, sx in ipairs({ -1, 1 }) do
		part(parent, V(1.2, 12.4, 1.2), cf * CF(sx * 11.5, 6.8, -8.5), wood, "Wood")
		deco(parent, V(1.2, 12.4, 1.2), cf * CF(sx * 11.5, 6.8, 0.5), wood, "Wood")
		deco(parent, V(1.2, 12.4, 1.2), cf * CF(sx * 11.5, 6.8, 8.5), wood, "Wood")
		local lantern = deco(parent, V(1.3, 1.6, 1.3), cf * CF(sx * 9.5, 10.4, -9.2), rgb(255, 225, 150), "Neon")
		Models.glow(lantern, rgb(255, 220, 150), 16)
	end
	deco(parent, V(27, 0.8, 21), cf * CF(0, 13.2, 0), wood, "WoodPlanks")
	-- pitched roof in the shop colour
	local rcf = cf * CF(0, 13.6, 0)
	local w1 = Scenery.Wg(parent, V(28, 5, 11), rcf * CF(0, 2.5, -5.5), def.color, "Slate")
	local w2 = Scenery.Wg(parent, V(28, 5, 11), rcf * CF(0, 2.5, 5.5) * ANG(0, rad(180), 0), def.color, "Slate")
	w1.CanCollide, w2.CanCollide = false, false
	for i = 0, 5 do
		local aw = part(parent, V(4.5, 0.4, 5), cf * CF(-11.25 + i * 4.5, 11.9, -11.3) * ANG(rad(-24), 0, 0), i % 2 == 0 and WHITE or def.color, "Fabric")
		aw.CanCollide = false
	end
	part(parent, V(15, 3, 2.4), cf * CF(0, 2.7, -2), wood, "WoodPlanks")
	deco(parent, V(15.6, 0.5, 3), cf * CF(0, 4.4, -2), rgb(235, 225, 205), "Marble")
	for i = -1, 1 do
		deco(parent, V(1.6, 1.6, 1.6), cf * CF(i * 4.6, 5.4, -2) * ANG(rad(45), rad(i * 30), rad(45)), def.color:Lerp(WHITE, 0.25), "Neon")
	end
	signAndIcon(parent, cf, def, 21.5)
	shopPrompt(parent, cf * CF(0, 3, -6), name, def.title)
end

local function display(parent, model, cf, text)
	local ped = part(parent, V(1, 5, 5), cf * CF(0, 0.9, 0) * ANG(0, 0, rad(90)), rgb(60, 60, 70), "Metal", "Cylinder")
	deco(parent, V(0.3, 5.4, 5.4), cf * CF(0, 1.45, 0) * ANG(0, 0, rad(90)), rgb(255, 215, 90), "Neon", "Cylinder")
	model:PivotTo(cf * CF(0, 1.6, 0))
	-- Centre the model's bounding box over the pedestal, then move its pivot there so
	-- the client spins it around the pedestal's axis instead of around its root part.
	local root = model.PrimaryPart
	if root then
		local boxCf = model:GetBoundingBox()
		local delta = cf.Position - boxCf.Position
		model:PivotTo(model:GetPivot() + V(delta.X, 0, delta.Z))
		local pivot = model:GetPivot()
		local centre = CF(cf.Position.X, pivot.Position.Y, cf.Position.Z) * pivot.Rotation
		root.PivotOffset = root.CFrame:ToObjectSpace(centre)
	end
	model.Parent = parent
	CollectionService:AddTag(model, "SpinModel")
	if text then
		billboard(ped, text, 6, 1.7, 6.5).MaxDistance = 70
	end
end

local function buildMarket(world)
	local m = Instance.new("Folder")
	m.Name = "Market"
	local plaza = part(m, V(3, 262, 262), CF(0, -1.25, 0) * ANG(0, 0, rad(90)), rgb(222, 212, 196), "Cobblestone", "Cylinder")
	plaza.Name = "Plaza"
	deco(m, V(3, 268, 268), CF(0, -1.35, 0) * ANG(0, 0, rad(90)), rgb(150, 140, 128), "Slate", "Cylinder")
	deco(m, V(0.9, 150, 150), CF(0, -0.15, 0) * ANG(0, 0, rad(90)), rgb(205, 190, 170), "Cobblestone", "Cylinder")
	deco(m, V(1, 70, 70), CF(0, -0.15, 0) * ANG(0, 0, rad(90)), rgb(240, 200, 150), "Pavement", "Cylinder")

	-- paving pattern: spokes of darker stone and a pale ring around the fountain
	for i = 0, 7 do
		local spoke = deco(m, V(3, 0.3, 46), CF(0, 0.32, 0) * ANG(0, rad(i * 45 + 22.5), 0) * CF(0, 0, -42), rgb(176, 160, 140), "Cobblestone")
		spoke.CastShadow = false
	end
	deco(m, V(0.3, 39, 39), CF(0, 0.36, 0) * ANG(0, 0, rad(90)), rgb(250, 240, 222), "Marble", "Cylinder").CastShadow = false
	deco(m, V(0.3, 134, 134), CF(0, 0.3, 0) * ANG(0, 0, rad(90)), rgb(176, 160, 140), "Cobblestone", "Cylinder").CastShadow = false
	deco(m, V(0.32, 129, 129), CF(0, 0.3, 0) * ANG(0, 0, rad(90)), rgb(205, 190, 170), "Cobblestone", "Cylinder").CastShadow = false
	deco(m, V(2.2, 33, 33), CF(0, 0.7, 0) * ANG(0, 0, rad(90)), rgb(150, 150, 162), "Marble", "Cylinder")

	-- fountain
	part(m, V(1.8, 30, 30), CF(0, 0.9, 0) * ANG(0, 0, rad(90)), rgb(180, 180, 190), "Marble", "Cylinder")
	local water = part(m, V(1, 26.5, 26.5), CF(0, 1.5, 0) * ANG(0, 0, rad(90)), rgb(80, 180, 255), "Glass", "Cylinder")
	water.Transparency = 0.25
	water.CanCollide = false
	part(m, V(6, 4, 4), CF(0, 4, 0) * ANG(0, 0, rad(90)), rgb(200, 200, 210), "Marble", "Cylinder")
	part(m, V(1, 15, 15), CF(0, 7, 0) * ANG(0, 0, rad(90)), rgb(200, 200, 210), "Marble", "Cylinder")
	local w2 = deco(m, V(0.6, 13, 13), CF(0, 7.4, 0) * ANG(0, 0, rad(90)), rgb(80, 180, 255), "Glass", "Cylinder")
	w2.Transparency = 0.25
	part(m, V(5, 2.6, 2.6), CF(0, 10, 0) * ANG(0, 0, rad(90)), rgb(200, 200, 210), "Marble", "Cylinder")
	part(m, V(0.8, 8, 8), CF(0, 12.6, 0) * ANG(0, 0, rad(90)), rgb(200, 200, 210), "Marble", "Cylinder")
	local spout = part(m, V(1.6, 1.6, 1.6), V(0, 13.8, 0), rgb(120, 210, 255), "Neon", "Ball")
	local e = emitter(spout, rgb(150, 220, 255), 80, 16)
	e.Acceleration = V(0, -40, 0)
	e.SpreadAngle = Vector2.new(38, 38)
	e.Lifetime = NumberRange.new(1.3, 1.8)
	local fl = Instance.new("PointLight")
	fl.Color = rgb(120, 200, 255)
	fl.Range = 44
	fl.Parent = spout
	local title = part(m, V(1, 1, 1), V(0, 27, 0), WHITE)
	title.Transparency = 1
	title.CanCollide = false
	billboard(title, "🌿 MOW THE WORLD 🌿", 44, 7, 0, rgb(140, 255, 120))

	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = V(14, 1, 14)
	spawn.CFrame = CF(0, 0.9, 26)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = m

	-- shops
	for _, name in ipairs(Areas.ShopOrder) do
		local def = SHOPS[name]
		local pos = Areas.Shops[name]
		local cf = CFrame.lookAt(pos, V(0, 0, 0))
		local f = Instance.new("Folder")
		f.Name = name
		if name == "Rebirth" then
			for i, d in ipairs({ 30, 22, 14 }) do
				part(f, V(1.2, d, d), cf * CF(0, 0.4 + i * 1.2 - 0.6, 0) * ANG(0, 0, rad(90)), i % 2 == 0 and rgb(60, 40, 90) or rgb(90, 60, 140), "Marble", "Cylinder")
			end
			local beam = part(f, V(70, 3.5, 3.5), cf * CF(0, 38, 0) * ANG(0, 0, rad(90)), def.color, "Neon", "Cylinder")
			beam.Transparency = 0.45
			beam.CanCollide = false
			beam.CastShadow = false
			emitter(beam, rgb(220, 160, 255), 25, 6).EmissionDirection = Enum.NormalId.Right
			for i = 0, 3 do
				local a = rad(45 + i * 90)
				local pc = cf * CF(math.sin(a) * 12, 0, math.cos(a) * 12)
				part(f, V(1.2, 3.4, 3.4), pc * CF(0, 0.6, 0) * ANG(0, 0, rad(90)), rgb(210, 205, 225), "Marble", "Cylinder")
				part(f, V(10, 1.8, 1.8), pc * CF(0, 6, 0) * ANG(0, 0, rad(90)), rgb(235, 230, 245), "Marble", "Cylinder")
				deco(f, V(0.8, 3, 3), pc * CF(0, 11.2, 0) * ANG(0, 0, rad(90)), rgb(210, 205, 225), "Marble", "Cylinder")
				local orb = part(f, V(2.6, 2.6, 2.6), pc * CF(0, 13, 0), def.color, "Neon", "Ball")
				Models.glow(orb, def.color, 18, 5)
			end
			signAndIcon(f, cf * CF(0, 0, -6), def, 9)
			shopPrompt(f, cf * CF(0, 6, 0), name, def.title)
		elseif name == "Leaderboards" then
			part(f, V(100, 0.5, 20), cf * CF(0, 0.45, 2), rgb(84, 62, 46), "WoodPlanks")
			local boards = { { "grassCut", "🌿 Grass Collected" }, { "cashEarned", "💵 Cash Earned" }, { "bosses", "⚔️ Bosses Defeated" }, { "rebirths", "🔁 Rebirths" }, { "diamondsEarned", "💎 Diamonds Earned" }, { "workerPower", "👷 Worker Power" } }
			for i, b in ipairs(boards) do
				local x = (i - 3.5) * 16
				local bcf = cf * CF(x, 10, 6 + math.abs(i - 3.5) * -1.5) * ANG(0, rad((i - 3.5) * 7), 0)
				local board = part(f, V(14, 18, 1), bcf, rgb(30, 30, 40))
				board.Name = b[1]
				board:SetAttribute("Title", b[2])
				CollectionService:AddTag(board, "Leaderboard")
				part(f, V(15, 1, 1.4), bcf * CF(0, 9.5, 0), def.color, "Neon")
				deco(f, V(15, 1, 1.4), bcf * CF(0, -9.5, 0), rgb(84, 62, 46), "Wood")
				deco(f, V(1, 20, 1.4), bcf * CF(-7.5, 0, 0), rgb(84, 62, 46), "Wood")
				deco(f, V(1, 20, 1.4), bcf * CF(7.5, 0, 0), rgb(84, 62, 46), "Wood")
			end
			signAndIcon(f, cf * CF(0, 0, 4), def, 23)
		elseif name == "Sell" then
			sellStation(f, pos + V(0, 0.4, 0))
			signAndIcon(f, cf * CF(0, 0, 18), def, 14)
		else
			stall(f, cf, name, def)
			if name == "Crates" then
				for i, crate in ipairs(W.Crates) do
					local price = (crate.currency == "diamonds" and "💎 " or "$") .. Util.fmt(crate.price)
					display(f, Models.crate(crate.id), cf * CF((i - 3.5) * 7, 0.4, -15 - math.abs(i - 3.5) * 1.2), crate.name .. "\n" .. price)
				end
			elseif name == "Mowers" then
				display(f, Models.mower("Push"), cf * CF(-19, 0.4, -4))
				display(f, Models.mower("Mega"), cf * CF(19, 0.4, -4))
			elseif name == "Vehicles" then
				display(f, Models.vehicle("Tractor"), cf * CF(-24, 0.4, -4))
				display(f, Models.vehicle("MegaVehicle"), cf * CF(26, 0.4, -4))
			end
		end
		f.Parent = m
	end

	-- lamps with colourful lights
	for i = 0, 11 do
		local a = rad(i * 30)
		local p = V(math.sin(a) * 66, 0, math.cos(a) * 66)
		deco(m, V(0.8, 2, 2), CF(p + V(0, 0.4, 0)) * ANG(0, 0, rad(90)), rgb(50, 50, 60), "Metal", "Cylinder")
		part(m, V(12, 0.7, 0.7), CF(p + V(0, 6.4, 0)) * ANG(0, 0, rad(90)), rgb(50, 50, 60), "Metal", "Cylinder")
		local col = Color3.fromHSV(i / 12, 0.6, 1)
		local bulb = part(m, V(2.2, 2.2, 2.2), p + V(0, 13, 0), col, "Neon", "Ball")
		local l = Instance.new("PointLight")
		l.Color = col
		l.Range = 34
		l.Brightness = 1.3
		l.Parent = bulb
	end
	-- bunting between the lamps
	for i = 0, 11 do
		local a1, a2 = rad(i * 30), rad(i * 30 + 30)
		local p1, p2 = V(math.sin(a1) * 66, 12, math.cos(a1) * 66), V(math.sin(a2) * 66, 12, math.cos(a2) * 66)
		for k = 1, 5 do
			local t = k / 6
			local p = p1:Lerp(p2, t) - V(0, math.sin(t * math.pi) * 2.2, 0)
			local flag = Scenery.Wg(m, V(0.15, 1.6, 1.3), CFrame.lookAt(p, p2) * ANG(rad(180), 0, 0), Color3.fromHSV((i * 5 + k) % 7 / 7, 0.7, 1), "Fabric")
			flag.CanCollide = false
			flag.CastShadow = false
		end
	end
	-- planters and benches
	local rng = Random.new(5)
	for i = 0, 7 do
		local a = rad(i * 45 + 22.5)
		local p = V(math.sin(a) * 50, 0, math.cos(a) * 50)
		part(m, V(7.4, 2.4, 7.4), p + V(0, 1.2, 0), rgb(150, 105, 60), "WoodPlanks")
		deco(m, V(7.9, 0.5, 7.9), p + V(0, 2.5, 0), rgb(110, 78, 46), "Wood")
		local bush = part(m, V(7, 6, 7), p + V(0, 4.8, 0), rgb(70, 160, 70), "Grass", "Ball")
		bush.CanCollide = false
		for _ = 1, 7 do
			local fl2 = part(m, V(1, 1, 1), p + V(rng:NextNumber(-3, 3), rng:NextNumber(5, 8), rng:NextNumber(-3, 3)), Color3.fromHSV(rng:NextNumber(), 0.7, 1), "SmoothPlastic", "Ball")
			fl2.CanCollide = false
		end
		local bp = V(math.sin(a) * 58, 0, math.cos(a) * 58)
		local bench = Models.prop("bench", { WHITE, WHITE, WHITE }, rng)
		bench.WorldPivot = CF(0, 0, 0)
		bench:PivotTo(CFrame.lookAt(bp, V(0, 0, 0)) * ANG(0, rad(180), 0))
		bench.Parent = m
	end

	-- paths from the plaza to every bridge, lined with lamps
	local openings = openingsOf[0] or {}
	local paths = marketPaths()
	local lampPal = { WHITE, WHITE, rgb(255, 225, 150) }
	for _, seg in ipairs(paths) do
		pathStrip(m, seg[1], seg[2], seg[3], seg.main and rgb(205, 190, 170) or rgb(196, 182, 160), "Cobblestone")
		if seg.main then
			deco(m, V(1.6, 20, 20), CF(seg[1] + V(0, -0.5, 0)) * ANG(0, 0, rad(90)), rgb(205, 190, 170), "Cobblestone", "Cylinder").CastShadow = false
			local len = (seg[2] - seg[1]).Magnitude
			local dir = (seg[2] - seg[1]).Unit
			local side = V(dir.Z, 0, -dir.X)
			local n = math.floor(len / 46)
			for i = 1, n do
				local s = i % 2 == 0 and 1 or -1
				local p = seg[1] + dir * (len * i / (n + 1)) + side * s * 12.5
				local lamp = Models.prop("lamp", lampPal, rng)
				lamp.WorldPivot = CF(0, 0, 0)
				lamp:PivotTo((CFrame.lookAt(p, p - side * s) + SINK) * ANG(0, rad(90), 0))
				lamp.Parent = m
			end
		end
	end

	local edge = Instance.new("Folder")
	edge.Name = "Edge"
	edgeLoop(edge, V(0, 0, 0), MH, MARKET_CUT, openings, EDGES[0], 7)
	edge.Parent = m

	-- The castle stands at the north end of town, behind the shops. It is scenery: an
	-- invisible wall all the way round keeps players out.
	local CASTLE_Z, CASTLE_W, CASTLE_D = -248, 70, 60 -- centre, half width, half depth of the fenced-off block
	local castle = Scenery.castle()
	castle:PivotTo(CFrame.lookAt(V(0, 0, CASTLE_Z), V(0, 0, 0)) + SINK)
	castle.Parent = m
	for _, w in ipairs({
		{ V(CASTLE_W * 2 + 2, 150, 1), V(0, 70, CASTLE_Z + CASTLE_D) },
		{ V(CASTLE_W * 2 + 2, 150, 1), V(0, 70, CASTLE_Z - CASTLE_D) },
		{ V(1, 150, CASTLE_D * 2), V(-CASTLE_W, 70, CASTLE_Z) },
		{ V(1, 150, CASTLE_D * 2), V(CASTLE_W, 70, CASTLE_Z) },
	}) do
		local b = part(m, w[1], w[2], WHITE)
		b.Transparency = 1
		b.CastShadow = false
		b.Name = "Barrier"
	end
	pathStrip(m, V(0, 0, -128), V(0, 0, CASTLE_Z + CASTLE_D), 16, rgb(205, 190, 170), "Cobblestone")
	-- the boss portal: a glowing green circle on the ground in front of the castle gate
	do
		local pp, pr = Areas.PORTAL_POS, Areas.PORTAL_RADIUS
		local green = rgb(90, 255, 120)
		local portal = Instance.new("Folder")
		portal.Name = "BossPortal"
		deco(portal, V(0.5, pr * 2 + 3, pr * 2 + 3), CF(pp + V(0, 0.42, 0)) * ANG(0, 0, rad(90)), rgb(40, 60, 46), "Slate", "Cylinder").CastShadow = false
		local ring = deco(portal, V(0.5, pr * 2, pr * 2), CF(pp + V(0, 0.5, 0)) * ANG(0, 0, rad(90)), green, "Neon", "Cylinder")
		ring.CastShadow = false
		deco(portal, V(0.52, pr * 2 - 3, pr * 2 - 3), CF(pp + V(0, 0.52, 0)) * ANG(0, 0, rad(90)), rgb(30, 110, 60), "Slate", "Cylinder").CastShadow = false
		local core = deco(portal, V(0.54, pr * 0.9, pr * 0.9), CF(pp + V(0, 0.54, 0)) * ANG(0, 0, rad(90)), green, "Neon", "Cylinder")
		core.CastShadow = false
		core.Transparency = 0.35
		Models.glow(ring, green, 34)
		local glowPart = deco(portal, V(1, 1, 1), pp + V(0, 1, 0), green)
		glowPart.Transparency = 1
		local e = emitter(glowPart, green, 14, 4)
		e.SpreadAngle = Vector2.new(60, 60)
		e.Lifetime = NumberRange.new(1.5, 2.5)
		for i = 0, 5 do
			local ang = rad(i * 60)
			local at = pp + V(math.sin(ang) * (pr - 1.5), 0, math.cos(ang) * (pr - 1.5))
			local rune = deco(portal, V(1.6, 0.3, 1.6), CF(at + V(0, 0.7, 0)) * ANG(0, ang + rad(45), 0), rgb(200, 255, 210), "Neon")
			rune.CastShadow = false
		end
		local sign = deco(portal, V(1, 1, 1), pp + V(0, 13, 0), WHITE)
		sign.Transparency = 1
		billboard(sign, "🌍 WORLD BOSS\nThe whole server fights together", 30, 7, 0, green)
		portal.Parent = m
	end

	-- The town: cartoon houses along every street and in rings around the plaza.
	local town = Instance.new("Folder")
	town.Name = "Town"
	local houses = {}
	local inner = MH - EDGE_BACK - 24
	local function fits(pos, radius)
		local x, z = pos.X, pos.Z
		if math.sqrt(x * x + z * z) < 136 + radius then
			return false
		end
		if math.max(math.abs(x), math.abs(z)) > inner - radius or math.abs(x) + math.abs(z) > 2 * inner - MARKET_CUT - 6 - radius then
			return false
		end
		if math.abs(x) < CASTLE_W + radius + 3 and math.abs(z - CASTLE_Z) < CASTLE_D + radius + 3 then
			return false
		end
		if math.abs(x) < 12 + radius and z < 0 then
			return false -- the avenue up to the castle
		end
		for _, seg in ipairs(paths) do
			if segDist(x, z, seg[1], seg[2]) < seg[3] / 2 + 2 + radius then
				return false
			end
		end
		for _, hp in ipairs(houses) do
			if (hp - pos).Magnitude < 15 + radius then
				return false
			end
		end
		return true
	end
	local function house(pos, lookAt)
		if #houses >= 96 or not fits(pos, 15) then
			return
		end
		table.insert(houses, pos)
		local model = Scenery.townHouse(rng, #houses % 3 == 0)
		model:PivotTo(CFrame.lookAt(pos, V(lookAt.X, 0, lookAt.Z)) + SINK)
		model.Parent = town
	end
	-- both sides of every street, doors facing the street
	for _, seg in ipairs(paths) do
		local len = (seg[2] - seg[1]).Magnitude
		local dir = (seg[2] - seg[1]).Unit
		local side = V(dir.Z, 0, -dir.X)
		for along = 20, len - 12, 36 do
			local on = seg[1] + dir * along
			house(on + side * 30, on)
			house(on - side * 30, on)
		end
	end
	-- rings facing the plaza fill the blocks between the streets
	for radius = 172, MH * 1.4, 44 do
		local count = math.floor(2 * math.pi * radius / 40)
		for i = 1, count do
			local ang = (i / count) * math.pi * 2 + radius * 0.01
			house(V(math.sin(ang) * radius, 0, math.cos(ang) * radius), V(0, 0, 0))
		end
	end
	town.Parent = m

	-- a few trees in stone planters where there is room: the only green left in town
	local pal = { rgb(70, 170, 70), rgb(110, 80, 50), rgb(255, 150, 200) }
	local count = 0
	for _ = 1, 900 do
		if count >= 36 then
			break
		end
		local pos = V(rng:NextNumber(-inner, inner), 0, rng:NextNumber(-inner, inner))
		if fits(pos, 7) then
			count += 1
			table.insert(houses, pos)
			deco(m, V(2, 11, 11), CF(pos + V(0, 0.4, 0)) * ANG(0, 0, rad(90)), rgb(190, 180, 168), "Cobblestone", "Cylinder")
			deco(m, V(2.1, 9, 9), CF(pos + V(0, 0.5, 0)) * ANG(0, 0, rad(90)), rgb(96, 180, 74), "Grass", "Cylinder").CastShadow = false
			placeProp(m, "tree", pal, rng, pos + V(0, 1.2, 0), rng:NextNumber(1.3, 1.9))
		end
	end
	-- big trees between the shops, at the edge of the plaza
	for i = 1, 8 do -- none at the north end: that is the avenue up to the castle
		local ang = rad(i * 40)
		local pos = V(math.sin(ang), 0, -math.cos(ang)) * 121
		deco(m, V(2.4, 12, 12), CF(pos + V(0, 0.6, 0)) * ANG(0, 0, rad(90)), rgb(250, 240, 222), "Marble", "Cylinder")
		deco(m, V(2.5, 10, 10), CF(pos + V(0, 0.7, 0)) * ANG(0, 0, rad(90)), rgb(96, 180, 74), "Grass", "Cylinder").CastShadow = false
		placeProp(m, "tree", pal, rng, pos + V(0, 1.6, 0), 2.1)
	end
	m.Parent = world
end

-- palms and rocks on the little sand islets out at sea
local function buildSea(world)
	local f = Instance.new("Folder")
	f.Name = "Sea"
	local rng = Random.new(99)
	local pal = { rgb(70, 165, 75), rgb(126, 124, 120), rgb(255, 150, 200) }
	for _, it in ipairs(ISLETS) do
		local top = it[3] * 0.28 + 1.4
		local n = it[3] > 16 and 3 or 2
		for i = 1, n do
			local a = rng:NextNumber(0, math.pi * 2)
			local r = rng:NextNumber(0, it[3] * 0.3)
			placeProp(f, "palm", pal, rng, V(it[1] + math.cos(a) * r, top - 0.6, it[2] + math.sin(a) * r), rng:NextNumber(1.2, 1.9))
		end
		placeProp(f, "tuft", pal, rng, V(it[1] - 3, top - 0.4, it[2] + 2), 1.4)
	end
	f.Parent = world
end

function WB.build()
	local old = workspace:FindFirstChild("World")
	if old then
		old:Destroy()
	end
	local list = links()
	WB.buildTerrain(false)
	computeOpenings(list)
	buildLighting()
	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = workspace
	local bridges = Instance.new("Folder")
	bridges.Name = "Bridges"
	for _, l in ipairs(list) do
		bridge(bridges, l.axis, l.fixed, l.lateral, l.low, l.high)
	end
	bridges.Parent = world
	buildMarket(world)
	task.wait()
	for _, a in ipairs(Areas.List) do
		buildArea(world, a)
		if a.id % 3 == 0 then
			task.wait()
		end
	end
	buildSea(world)
	return world
end

return WB
