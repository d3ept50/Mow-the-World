-- Builds the whole map from config when the server starts.
-- The world is an archipelago: a central marketplace island with one island per area around it,
-- joined by wooden bridges. Terrain (islands, beaches, sea) is baked once and stored in the place;
-- everything else (bridges, fences, props, landmarks, shops) is rebuilt on every start.
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
local LAYOUT_VERSION = 7 -- bump to force the terrain to be baked again
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
local COTTAGES = { V(0, 0, -275), V(275, 0, 0), V(0, 0, 275), V(-275, 0, 0), V(248, 0, -248), V(248, 0, 248), V(-248, 0, 248), V(-248, 0, -248) }
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
	local segs = {}
	for _, o in ipairs(openingsOf[0] or {}) do
		local d = SIDE_DIR[o.side]
		local perp = (o.side == "x+" or o.side == "x-") and V(0, 0, 1) or V(1, 0, 0)
		local target = d * (MH + 2) + perp * o.offset
		local knee = d * (MH - 70) + perp * o.offset
		table.insert(segs, { target.Unit * 128, knee, 18, main = true })
		table.insert(segs, { knee, target, 18, main = true })
	end
	for _, p in ipairs(COTTAGES) do
		table.insert(segs, { p - p.Unit * 14, p.Unit * 128, 8 })
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

local ISLETS = {
	{ 400, 400, 17 }, { -400, 400, 15 }, { 400, -400, 16 }, { -400, -400, 18 },
	{ 0, 835, 20 }, { 0, -835, 18 }, { 835, 0, 19 }, { -835, 0, 21 },
	{ 860, 860, 24 }, { -860, 860, 20 }, { 860, -860, 22 }, { -860, -860, 24 },
	{ 400, 845, 13 }, { -400, -845, 14 }, { 845, -400, 13 }, { -845, 400, 14 },
}

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
	terrain.WaterColor = Style.WATER
	terrain.WaterTransparency = 0.3
	terrain.WaterReflectance = 0.35
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 9
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
	local SEA, STEP = 1400, 700
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
	islandShape(terrain, V(0, 0, 0), MH + 14, 84, BEACH, -30, Enum.Material.Sand)
	islandShape(terrain, V(0, 0, 0), MH, 70, TOP, -30, Enum.Material.Grass)
	task.wait()
	computeOpenings(links())
	local segs = marketPaths()
	local function marketPaved(x, z)
		if x * x + z * z < 129 * 129 then
			return true
		end
		for _, seg in ipairs(segs) do
			if segDist(x, z, seg[1], seg[2]) < seg[3] / 2 - 2 then
				return true
			end
		end
		return false
	end
	for _, q in ipairs({ { -MH, -MH, 0, 0 }, { 0, -MH, MH, 0 }, { -MH, 0, 0, MH }, { 0, 0, MH, MH } }) do
		repave(terrain, q[1], q[2], q[3], q[4], marketPaved)
		task.wait()
	end
	local side = Areas.GRID * Areas.TILE
	for _, a in ipairs(Areas.List) do
		islandShape(terrain, a.center, H + 14, 54, BEACH, -30, Enum.Material.Sand)
		islandShape(terrain, a.center, H, 40, TOP, -30, Enum.Material[a.terrain])
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
	Lighting.ColorShift_Top = rgb(255, 244, 225)
	Lighting.ExposureCompensation = look.exposure
	local grade = Lighting:FindFirstChild("Grade") or Instance.new("ColorCorrectionEffect")
	grade.Name = "Grade"
	grade.Saturation = look.saturation
	grade.Contrast = look.contrast
	grade.Brightness = look.gradeBrightness
	grade.Parent = Lighting
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.35
	bloom.Size = 24
	bloom.Threshold = 2
	bloom.Parent = Lighting
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect") or Instance.new("SunRaysEffect")
	rays.Intensity = 0.06
	rays.Spread = 0.8
	rays.Parent = Lighting
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if dof then
		dof.FarIntensity = 0.12
		dof.FocusDistance = 60
		dof.InFocusRadius = 260
		dof.NearIntensity = 0
	end
end

---------------------------------------------------------------- fences
-- One straight run of fence: low visible posts and rails plus a tall invisible wall.
local function fenceRun(parent, p1, p2, color)
	local len = (p2 - p1).Magnitude
	if len < 1 then
		return
	end
	local cf = CFrame.lookAt((p1 + p2) / 2, p2)
	local wallPart = part(parent, V(1, 90, len), cf * CF(0, 41, 0), WHITE)
	wallPart.Transparency = 1
	wallPart.CastShadow = false
	wallPart.Name = "Barrier"
	local railC = color:Lerp(WHITE, 0.18)
	deco(parent, V(0.5, 0.6, len), cf * CF(0, 3.5, 0), railC, "Wood")
	deco(parent, V(0.5, 0.6, len), cf * CF(0, 1.9, 0), railC, "Wood")
	local n = math.max(1, math.floor(len / 9 + 0.5))
	for i = 0, n do
		local post = deco(parent, V(1.1, 6, 1.1), cf * CF(0, 1.6, -len / 2 + len * i / n), color, "Wood")
		post.CastShadow = false
	end
end

-- Octagonal fence around an island. openings = { { side = "x+"|"x-"|"z+"|"z-", offset = lateral } }
local function fenceLoop(parent, center, half, cut, openings, color)
	local h = half - FENCE_INSET
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
local function gate(parent, axis, along, lateral, areaId)
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
	CollectionService:AddTag(barrier, "Gate")
	local prev = Areas.List[areaId - 1]
	local bb = billboard(barrier, "🔒 " .. a.name .. (prev and ("\nDefeat the " .. prev.boss.name) or ""), 22, 7, 0, WHITE)
	bb.Name = "LockGui"
	bb.AlwaysOnTop = false
end

local function bridge(parent, axis, fixed, lateral, idLow, idHigh)
	local len = GAP + 10
	local function cfAt(alongOff, y, lat)
		local pos = axis == "x" and V(fixed + alongOff, y, lateral + (lat or 0)) or V(lateral + (lat or 0), y, fixed + alongOff)
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
	gate(parent, axis, fixed + (plusHigh and 1 or -1) * (GAP / 2 - 1), lateral, id)
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

	local openings = openingsOf[a.id] or {}
	local fence = Instance.new("Folder")
	fence.Name = "Fence"
	fenceLoop(fence, c, H, 30, openings, a.wall)
	fence.Parent = folder
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
	local lim = H - 10
	local function free(x, z, margin)
		if math.abs(x) < side / 2 + margin and math.abs(z) < side / 2 + margin then
			return false
		end
		if math.abs(x) + math.abs(z) > 2 * lim - 34 then
			return false
		end
		local p = V(x, 0, z)
		if (p - Areas.BOSS_OFFSET).Magnitude < Areas.ARENA_RADIUS + 8 or (p - Areas.SELL_OFFSET).Magnitude < 15 then
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
		if placed >= 92 then
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
		if placed >= 70 then
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
			lamp:PivotTo((CFrame.lookAt(c + d * (H - 26) + perp * s * 13, c + d * (H - 26)) + SINK) * ANG(0, rad(-90), 0))
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
	local npc = Models.figure(def.color, rgb(240, 200, 160), dark)
	npc:PivotTo(cf * CF(0, 1.2, 2))
	npc.Parent = parent
	CollectionService:AddTag(npc, "Bob")
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
		-- signpost near the fountain pointing at this shop
		local dir = pos.Unit
		local sp = CFrame.lookAt(dir * 36, V(0, 0, 0))
		part(f, V(0.6, 7, 0.6), sp * CF(0, 3.9, 0), rgb(110, 80, 50), "Wood")
		local board = part(f, V(9, 2.6, 0.5), sp * CF(0, 7, 0), def.color)
		label(board, Enum.NormalId.Front, def.title .. " ⬆", WHITE)
		label(board, Enum.NormalId.Back, def.title, WHITE)
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

	local fence = Instance.new("Folder")
	fence.Name = "Fence"
	fenceLoop(fence, V(0, 0, 0), MH, 46, openings, rgb(120, 86, 56))
	fence.Parent = m

	-- cottages: a little town around the plaza
	local cottages = COTTAGES
	for _, p in ipairs(cottages) do
		local cot = Scenery.cottage(rng)
		cot:PivotTo(CFrame.lookAt(p, V(0, 0, 0)))
		cot.Parent = m
	end

	-- trees, bushes and flowers on the lawn
	local pal = { rgb(70, 160, 60), rgb(110, 80, 50), rgb(255, 150, 200) }
	local lim = MH - 14
	local function free(x, z, margin)
		if math.sqrt(x * x + z * z) < 138 + margin then
			return false
		end
		if math.abs(x) + math.abs(z) > 2 * lim - 60 then
			return false
		end
		for _, seg in ipairs(paths) do
			if segDist(x, z, seg[1], seg[2]) < 13 + margin then
				return false
			end
		end
		for _, cp in ipairs(cottages) do
			if (cp - V(x, 0, z)).Magnitude < 22 + margin then
				return false
			end
		end
		return true
	end
	local kinds = { "tree", "tree", "tree", "bush", "flower", "flower", "tuft", "tuft", "rock" }
	local count = 0
	for _ = 1, 1500 do
		if count >= 230 then
			break
		end
		local x, z = rng:NextNumber(-lim, lim), rng:NextNumber(-lim, lim)
		local kind = kinds[rng:NextInteger(1, #kinds)]
		if free(x, z, kind == "tree" and 5 or 0) then
			count += 1
			local scale = kind == "tree" and rng:NextNumber(1.1, 1.9) or (kind == "rock" and rng:NextNumber(0.4, 0.8) or rng:NextNumber(0.9, 1.4))
			placeProp(m, kind, pal, rng, V(x, 0, z), scale)
		end
	end
	-- wandering townsfolk (animated on the client)
	for i = 1, 10 do
		local npc = Models.figure(Color3.fromHSV(rng:NextNumber(), 0.6, 0.9), rgb(240, 200, 160), i % 3 == 0 and Color3.fromHSV(rng:NextNumber(), 0.5, 0.8) or nil)
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(26, 90)
		npc:PivotTo(CF(math.sin(a) * r, 0.4, math.cos(a) * r))
		npc.Parent = m
		CollectionService:AddTag(npc, "Wander")
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
