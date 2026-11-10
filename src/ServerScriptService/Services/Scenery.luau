-- Large set pieces: one landmark per area plus the cottages of the marketplace town.
-- Everything is built around the origin and returned as a Model pivoted at ground level.
local CollectionService = game:GetService("CollectionService")
local RS = game:GetService("ReplicatedStorage")
local Models = require(RS.Shared.Models)
local Style = require(RS.Shared.Style)

local Scenery = {}

local V, CF, ANG, rad = Vector3.new, CFrame.new, CFrame.Angles, math.rad
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local WHITE, DARK = rgb(250, 250, 250), rgb(35, 35, 42)

local function make(class, parent, size, cf, color, mat, shape)
	local p = Instance.new(class)
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

-- solid block / decorative block (no collisions) / wedge / vertical cylinder
local function B(parent, size, cf, color, mat, shape)
	return make("Part", parent, size, cf, color, mat, shape)
end
local function D(parent, size, cf, color, mat, shape)
	local p = make("Part", parent, size, cf, color, mat, shape)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end
local function Wg(parent, size, cf, color, mat)
	return make("WedgePart", parent, size, cf, color, mat)
end
local function cylV(parent, h, d, pos, color, mat, deco)
	local cf = (typeof(pos) == "Vector3" and CF(pos) or pos) * ANG(0, 0, rad(90))
	return (deco and D or B)(parent, V(h, d, d), cf, color, mat, "Cylinder")
end
-- gable roof: ridge runs along X, eaves at +-depth/2
local function roof(parent, cf, width, depth, height, color, mat)
	Wg(parent, V(width, height, depth / 2), cf * CF(0, height / 2, -depth / 4), color, mat)
	Wg(parent, V(width, height, depth / 2), cf * CF(0, height / 2, depth / 4) * ANG(0, rad(180), 0), color, mat)
end
local function light(part, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1.5
	l.Parent = part
	return l
end
local function particles(part, color, rate, speed, size, life)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.Rate = rate
	e.Lifetime = NumberRange.new(life or 1.5, (life or 1.5) * 1.6)
	e.Speed = NumberRange.new(speed, speed * 1.5)
	e.SpreadAngle = Vector2.new(20, 20)
	e.EmissionDirection = Enum.NormalId.Top
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size or 1), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.LightEmission = 0.6
	e.Parent = part
	return e
end
-- sub model that the client spins around its primary part's Y axis
local function spinner(parent, primary)
	local m = Instance.new("Model")
	m.Name = "Spinner"
	primary.Parent = m
	m.PrimaryPart = primary
	m.Parent = parent
	CollectionService:AddTag(m, "SpinModel")
	return m
end

---------------------------------------------------------------- landmarks
local L = {}

L[1] = function(m, rng) -- red barn and silo
	local red, trim = rgb(176, 52, 46), rgb(245, 240, 230)
	B(m, V(24, 3, 18), CF(-3, -0.5, 0), rgb(120, 110, 100), "Cobblestone")
	B(m, V(22, 12, 16), CF(-3, 7, 0), red, "WoodPlanks")
	roof(m, CF(-3, 13, 0), 24, 19, 7, rgb(70, 62, 62), "Slate")
	D(m, V(7, 8.5, 0.4), CF(-3, 5.2, -8.1), rgb(120, 40, 36), "WoodPlanks")
	D(m, V(7.6, 0.6, 0.5), CF(-3, 9.6, -8.15), trim)
	D(m, V(0.6, 9, 0.5), CF(-6.8, 5.2, -8.15), trim)
	D(m, V(0.6, 9, 0.5), CF(0.8, 5.2, -8.15), trim)
	D(m, V(0.5, 10.5, 0.45), CF(-3, 5.2, -8.2) * ANG(0, 0, rad(40)), trim)
	D(m, V(0.5, 10.5, 0.45), CF(-3, 5.2, -8.2) * ANG(0, 0, rad(-40)), trim)
	D(m, V(3, 3, 0.4), CF(-3, 15.5, -9.6), trim)
	for _, x in ipairs({ -14, 8 }) do
		D(m, V(0.6, 12, 16.4), CF(x, 7, 0), trim)
	end
	cylV(m, 18, 8, V(14, 9, 3), rgb(200, 205, 212), "Metal")
	D(m, V(8, 8, 8), CF(14, 18, 3), rgb(170, 60, 55), "Metal", "Ball")
	for i = 0, 3 do
		cylV(m, 0.4, 8.2, V(14, 3 + i * 4.5, 3), rgb(150, 155, 165), "Metal", true)
	end
	for i = 1, 3 do
		B(m, V(4, 3.6, 3.6), CF(-13 + i * 4.2, 2.3, -12 - (i % 2) * 2) * ANG(0, rng:NextNumber(0, 1), 0), rgb(225, 195, 95), "Fabric", "Cylinder")
	end
end

L[2] = function(m) -- windmill
	local cream = rgb(238, 228, 205)
	B(m, V(1, 18, 18), CF(0, 0.5, 0) * ANG(0, 0, rad(90)), rgb(150, 140, 125), "Cobblestone", "Cylinder")
	for i = 0, 4 do
		cylV(m, 5.2, 13 - i * 1.4, V(0, 3.5 + i * 5, 0), cream, "Brick")
	end
	cylV(m, 1, 9.5, V(0, 26.5, 0), rgb(120, 85, 50), "Wood", true)
	cylV(m, 3.5, 8, V(0, 28.5, 0), rgb(150, 70, 50), "WoodPlanks", true)
	D(m, V(8, 6, 8), CF(0, 30.2, 0), rgb(150, 70, 50), "WoodPlanks", "Ball")
	D(m, V(3.4, 6, 0.4), CF(0, 4, -6.6), rgb(110, 75, 45), "WoodPlanks")
	for i = 1, 3 do
		local win = D(m, V(1.8, 2.4, 0.4), CF(0, 6 + i * 5.4, -5.9 + i * 0.75), rgb(255, 225, 140), "Neon")
		if i == 2 then
			light(win, rgb(255, 220, 140), 16, 1)
		end
	end
	local hub = D(nil, V(1.6, 1.6, 1.6), CF(0, 27, -5.6) * ANG(rad(90), 0, 0), DARK, "Metal", "Ball")
	local blades = spinner(m, hub)
	for i = 0, 3 do
		local cf = CF(0, 27, -5.6) * ANG(0, 0, rad(i * 90))
		D(blades, V(0.6, 15, 0.5), cf * CF(0, 7.5, 0), rgb(110, 80, 50), "Wood")
		D(blades, V(3.6, 11, 0.2), cf * CF(1.9, 9, 0), WHITE, "Fabric")
	end
	D(m, V(1, 1, 4), CF(0, 27, -3.6), DARK, "Metal")
end

L[3] = function(m, rng) -- giant tree house
	local bark, leaf, glow = rgb(78, 56, 44), rgb(30, 140, 115), rgb(200, 130, 255)
	for i = 0, 5 do
		local a = rad(i * 60 + 20)
		B(m, V(3.2, 8, 3.2), CF(math.cos(a) * 5.5, 2.4, math.sin(a) * 5.5) * ANG(math.sin(a) * 0.7, 0, -math.cos(a) * 0.7), bark, "Wood")
	end
	cylV(m, 16, 10, V(0, 8, 0), bark, "Wood")
	cylV(m, 14, 8, V(0, 23, 0), bark, "Wood")
	for i = 1, 9 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = i == 1 and 0 or rng:NextNumber(6, 12)
		local s = i == 1 and 26 or rng:NextNumber(13, 19)
		D(m, V(s, s * 0.85, s), CF(math.cos(a) * r, 33 + rng:NextNumber(-4, 5), math.sin(a) * r), Models.tone(leaf, rng, 0.07), "Grass", "Ball")
	end
	D(m, V(3.4, 5.5, 0.6), CF(0, 3.2, -5.1), rgb(120, 80, 50), "WoodPlanks")
	D(m, V(4.2, 0.6, 0.8), CF(0, 6.2, -5.1), rgb(60, 42, 34), "Wood")
	for i, y in ipairs({ 9.5, 14, 19.5 }) do
		local a = rad(-90 + (i - 2) * 38)
		local win = D(m, V(0.5, 2.4, 2.4), CF(math.cos(a) * 4.9, y, math.sin(a) * 4.9) * ANG(0, -a, 0), rgb(255, 225, 140), "Neon", "Cylinder")
		light(win, rgb(255, 220, 140), 14, 1)
	end
	for i = 1, 6 do
		local a = rng:NextNumber(0, math.pi * 2)
		local pos = V(math.cos(a) * rng:NextNumber(9, 15), rng:NextNumber(13, 22), math.sin(a) * rng:NextNumber(9, 15))
		D(m, V(0.1, 7, 0.1), CF(pos + V(0, 4, 0)), DARK)
		local orb = D(m, V(1.2, 1.2, 1.2), CF(pos), glow, "Neon", "Ball")
		if i <= 2 then
			light(orb, glow, 22, 1.4)
		end
	end
	for i = 1, 5 do
		local a = rad(i * 72)
		local p = V(math.cos(a) * 14, 0, math.sin(a) * 14)
		cylV(m, 2.4, 1.1, p + V(0, 1.2, 0), rgb(240, 235, 220))
		cylV(m, 1, 4.4, p + V(0, 2.8, 0), glow, "Neon", true)
	end
end

L[4] = function(m) -- pyramid
	local stone = rgb(222, 190, 128)
	for i = 0, 8 do
		local s = 38 - i * 4.2
		B(m, V(s, 3, s), CF(0, 1.5 + i * 3, 0), i % 2 == 0 and stone or rgb(208, 174, 112), "Sandstone")
	end
	local cap = D(m, V(3.4, 3.4, 3.4), CF(0, 29.5, 0) * ANG(rad(45), 0, rad(45)), rgb(255, 210, 70), "Neon")
	light(cap, rgb(255, 210, 90), 40, 2)
	D(m, V(6, 7, 1), CF(0, 3.5, -19.1), rgb(40, 30, 25))
	D(m, V(8, 1.2, 1.6), CF(0, 7.6, -19.2), rgb(190, 150, 90), "Sandstone")
	for _, x in ipairs({ -9, 9 }) do
		B(m, V(2.4, 14, 2.4), CF(x, 7, -23), rgb(200, 165, 105), "Sandstone")
		D(m, V(1.8, 1.8, 1.8), CF(x, 15, -23) * ANG(rad(45), 0, rad(45)), rgb(255, 210, 70), "Neon")
	end
end

L[5] = function(m, rng) -- snowy peak and igloo
	local rock = rgb(120, 132, 152)
	for i = 0, 6 do
		local s = 34 - i * 4.6
		local snow = i >= 4
		B(m, V(s, 6.5, s * rng:NextNumber(0.8, 1)), CF(rng:NextNumber(-2, 2), 3 + i * 5.6, 4 + rng:NextNumber(-2, 2)) * ANG(rng:NextNumber(-0.12, 0.12), rng:NextNumber(0, 1.5), rng:NextNumber(-0.12, 0.12)), snow and rgb(245, 248, 255) or Models.tone(rock, rng, 0.05), snow and "Snow" or "Slate")
	end
	for _ = 1, 6 do
		local a = rng:NextNumber(0, math.pi * 2)
		D(m, V(7, 1.2, 6), CF(math.cos(a) * 11, rng:NextNumber(8, 20), 4 + math.sin(a) * 11) * ANG(0, a, 0), rgb(245, 248, 255), "Snow")
	end
	B(m, V(14, 14, 14), CF(-10, 0, -15), rgb(240, 246, 255), "Snow", "Ball")
	B(m, V(5, 5, 6), CF(-10, 2, -22.5), rgb(230, 240, 252), "Snow")
	D(m, V(3, 3.4, 0.5), CF(-10, 1.8, -25.6), rgb(30, 40, 60))
	for i = 1, 4 do
		local ice = D(m, V(1.6, rng:NextNumber(5, 10), 1.6), CF(8 + i * 2.2, 3, -16 + rng:NextNumber(-3, 3)) * ANG(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)), rgb(150, 220, 255), "Glass")
		ice.Transparency = 0.3
	end
end

L[6] = function(m) -- candy castle
	local pink, mag, cream = rgb(255, 170, 205), rgb(255, 80, 150), rgb(255, 248, 240)
	B(m, V(34, 1.2, 34), CF(0, 0.6, 0), cream, "SmoothPlastic")
	B(m, V(18, 15, 18), CF(0, 8.5, 0), pink)
	B(m, V(20, 1.4, 20), CF(0, 16.5, 0), cream)
	for i = -2, 2 do
		for _, s in ipairs({ -1, 1 }) do
			D(m, V(2.2, 2, 1.4), CF(i * 4.2, 18.2, s * 9.3), mag)
			D(m, V(1.4, 2, 2.2), CF(s * 9.3, 18.2, i * 4.2), mag)
		end
	end
	D(m, V(5, 8, 0.6), CF(0, 5.2, -9.2), rgb(150, 85, 60), "WoodPlanks")
	D(m, V(5, 5, 0.6), CF(0, 9.2, -9.2) * ANG(rad(90), 0, 0), rgb(150, 85, 60), "WoodPlanks", "Cylinder")
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local p = V(sx * 11, 0, sz * 11)
			cylV(m, 24, 7, p + V(0, 12, 0), cream)
			for i = 0, 3 do
				cylV(m, 1.6, 7.2, p + V(0, 4 + i * 6, 0), i % 2 == 0 and mag or rgb(120, 220, 255), nil, true)
			end
			for i = 0, 4 do
				cylV(m, 1.7, 8.6 - i * 1.9, p + V(0, 24.8 + i * 1.7, 0), mag, nil, true)
			end
			D(m, V(1.6, 1.6, 1.6), CF(p + V(0, 33.8, 0)), rgb(255, 230, 90), "Neon", "Ball")
		end
	end
	cylV(m, 10, 0.6, V(0, 22, 0), WHITE, nil, true)
	local swirl = D(m, V(1, 7, 7), CF(0, 29, 0) * ANG(0, rad(90), 0), mag, nil, "Cylinder")
	D(m, V(1.1, 4.4, 4.4), swirl.CFrame, WHITE, nil, "Cylinder")
	D(m, V(1.2, 2, 2), swirl.CFrame, rgb(120, 220, 255), nil, "Cylinder")
end

L[7] = function(m, rng) -- volcano
	local basalt = rgb(52, 42, 42)
	for i = 0, 6 do
		cylV(m, 4.6, 40 - i * 4.6, V(0, 2.3 + i * 4.6, 0), Models.tone(basalt, rng, 0.04), "Basalt")
	end
	local lava = cylV(m, 1, 9.5, V(0, 32.3, 0), rgb(255, 110, 20), "Neon", true)
	light(lava, rgb(255, 120, 40), 60, 3)
	particles(lava, rgb(90, 80, 80), 10, 9, 7, 4).LightEmission = 0
	particles(lava, rgb(255, 150, 40), 24, 14, 1.4, 1.2)
	for i = 0, 4 do
		local a = rad(i * 72 + 15)
		local dir = V(math.cos(a), 0, math.sin(a))
		local top, bottom = dir * 6 + V(0, 32, 0), dir * 20.5 + V(0, 2, 0)
		D(m, V(rng:NextNumber(1.6, 2.8), 0.7, (top - bottom).Magnitude), CFrame.lookAt((top + bottom) / 2 + dir * 0.9, bottom + dir * 0.9), rgb(255, 100, 20), "Neon")
	end
	for i = 1, 6 do
		local a = rng:NextNumber(0, math.pi * 2)
		B(m, V(5, 4, 5), CF(math.cos(a) * 22, 1.5, math.sin(a) * 22) * ANG(rng:NextNumber(-0.4, 0.4), a, rng:NextNumber(-0.4, 0.4)), basalt, "Basalt")
	end
end

L[8] = function(m) -- swamp witch hut on stilts
	local wood, moss, glow = rgb(74, 60, 46), rgb(86, 120, 54), rgb(170, 255, 60)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			B(m, V(1.4, 11, 1.4), CF(sx * 7, 5.5, sz * 6) * ANG(sz * 0.06, 0, -sx * 0.06), wood, "Wood")
		end
	end
	B(m, V(18, 1, 16), CF(0, 11, 0), rgb(96, 76, 56), "WoodPlanks")
	B(m, V(14, 9, 12), CF(0, 16, 1), wood, "WoodPlanks")
	roof(m, CF(0, 20.5, 1), 17, 16, 7, moss, "Grass")
	D(m, V(3, 5.5, 0.4), CF(-3, 14.3, -5.1), rgb(50, 40, 32), "WoodPlanks")
	local win = D(m, V(3, 3, 0.4), CF(3.2, 16.5, -5.1), glow, "Neon")
	light(win, glow, 24, 1.6)
	for i = 0, 6 do
		D(m, V(3.4, 0.4, 0.6), CF(-3, 1 + i * 1.6, -9.2 + i * 0.25), wood, "Wood")
	end
	D(m, V(0.4, 12, 0.4), CF(-4.7, 6, -8.5) * ANG(rad(8), 0, 0), wood, "Wood")
	D(m, V(0.4, 12, 0.4), CF(-1.3, 6, -8.5) * ANG(rad(8), 0, 0), wood, "Wood")
	B(m, V(6, 5, 6), CF(13, 2.2, -8), DARK, "Metal", "Ball")
	local brew = cylV(m, 0.4, 4.6, V(13, 4.3, -8), glow, "Neon", true)
	light(brew, glow, 26, 2)
	particles(brew, glow, 14, 4, 0.9, 1.6)
	cylV(m, 3, 0.5, V(4.5, 25, 3), DARK, "Metal", true)
end

L[9] = function(m, rng) -- crystal spires
	local cols = { rgb(120, 220, 255), rgb(210, 140, 255), rgb(150, 240, 255) }
	for i = 1, 5 do
		local a = rng:NextNumber(0, math.pi * 2)
		B(m, V(8, 4, 7), CF(math.cos(a) * 9, 1.2, math.sin(a) * 9) * ANG(rng:NextNumber(-0.3, 0.3), a, rng:NextNumber(-0.3, 0.3)), rgb(92, 104, 150), "Slate")
	end
	for i = 1, 11 do
		local main = i == 1
		local a = rad(i * 33)
		local r = main and 0 or rng:NextNumber(5, 14)
		local h = main and 40 or rng:NextNumber(12, 28)
		local w = main and 7 or rng:NextNumber(2.4, 4.6)
		local tilt = main and ANG(0, 0.6, 0) or ANG(math.sin(a) * 0.38, rng:NextNumber(0, 3), -math.cos(a) * 0.38)
		local c = cols[i % #cols + 1]
		local sp = B(m, V(w, h, w), CF(math.cos(a) * r, 0, math.sin(a) * r) * tilt * CF(0, h / 2 - 1, 0), c, i % 2 == 0 and "Neon" or "Glass")
		sp.Transparency = 0.18
		D(m, V(w * 0.7, w, w * 0.7), sp.CFrame * CF(0, h / 2, 0) * ANG(rad(45), 0, rad(45)), c, "Neon").Transparency = 0.1
		if main or i % 4 == 0 then
			light(sp, c, main and 60 or 26, 2)
		end
	end
end

L[10] = function(m, rng) -- floating ringed planet
	local purple, gold = rgb(150, 100, 255), rgb(255, 240, 150)
	for i = 0, 2 do
		cylV(m, 1.4, 22 - i * 5, V(0, 0.7 + i * 1.4, 0), i % 2 == 0 and rgb(40, 30, 90) or rgb(70, 50, 140), "Marble")
	end
	local beam = cylV(m, 16, 3, V(0, 12, 0), purple, "Neon", true)
	beam.Transparency = 0.6
	local planet = D(nil, V(17, 17, 17), CF(0, 27, 0) * ANG(rad(18), 0, rad(12)), rgb(110, 70, 220), "Glass", "Ball")
	local sp = spinner(m, planet)
	light(planet, purple, 60, 2.4)
	D(sp, V(15, 15, 15), planet.CFrame, rgb(190, 130, 255), "Neon", "Ball").Transparency = 0.55
	local ring = D(sp, V(0.5, 31, 31), planet.CFrame * ANG(0, 0, rad(90)), gold, "Neon", "Cylinder")
	ring.Transparency = 0.25
	D(sp, V(0.6, 25, 25), planet.CFrame * ANG(0, 0, rad(90)), rgb(22, 16, 48), "SmoothPlastic", "Cylinder")
	D(sp, V(3.4, 3.4, 3.4), planet.CFrame * CF(19, 0, 0), rgb(220, 220, 235), "Slate", "Ball")
	D(sp, V(2.2, 2.2, 2.2), planet.CFrame * CF(-14, 2, 12), rgb(120, 220, 255), "Neon", "Ball")
	for _ = 1, 10 do
		local a = rng:NextNumber(0, math.pi * 2)
		local p = V(math.cos(a) * rng:NextNumber(12, 22), rng:NextNumber(8, 40), math.sin(a) * rng:NextNumber(12, 22))
		D(m, V(1.6, 0.35, 0.35), CF(p), gold, "Neon")
		D(m, V(0.35, 1.6, 0.35), CF(p), gold, "Neon")
	end
end

L[11] = function(m) -- marble temple
	local marble, gold = rgb(246, 241, 230), rgb(255, 210, 80)
	for i = 0, 2 do
		B(m, V(38 - i * 3, 1.4, 28 - i * 3), CF(0, 0.7 + i * 1.4, 0), marble, "Marble")
	end
	for _, z in ipairs({ -9.5, 9.5 }) do
		for i = -2, 2 do
			local p = V(i * 7, 0, z)
			B(m, V(3.4, 1, 3.4), CF(p + V(0, 4.7, 0)), marble, "Marble")
			cylV(m, 14, 2.5, p + V(0, 12.2, 0), marble, "Marble")
			D(m, V(3.4, 1, 3.4), CF(p + V(0, 19.7, 0)), marble, "Marble")
		end
	end
	B(m, V(34, 2, 24), CF(0, 21.2, 0), marble, "Marble")
	D(m, V(34.4, 0.5, 24.4), CF(0, 22.4, 0), gold, "Foil")
	roof(m, CF(0, 22.6, 0), 34, 25, 6, rgb(235, 226, 205), "Marble")
	B(m, V(5, 4, 5), CF(0, 6.2, 0), marble, "Marble")
	local orb = D(m, V(5, 5, 5), CF(0, 12, 0), gold, "Neon", "Ball")
	light(orb, rgb(255, 225, 140), 46, 2.4)
	particles(orb, rgb(255, 235, 160), 10, 2, 0.7, 2).SpreadAngle = Vector2.new(180, 180)
	D(m, V(0.3, 8, 8), CF(0, 12, 0) * ANG(0, rad(90), 0), gold, "Neon", "Cylinder").Transparency = 0.6
end

L[12] = function(m, rng) -- void portal
	local mag, cyan, void = rgb(255, 60, 220), rgb(80, 255, 240), rgb(14, 6, 24)
	for i = 0, 2 do
		cylV(m, 1.4, 34 - i * 6, V(0, 0.7 + i * 1.4, 0), i == 1 and mag or void, i == 1 and "Neon" or "SmoothPlastic")
	end
	local c = CF(0, 21, 0)
	local disc = D(m, V(0.6, 27, 27), c * ANG(0, rad(90), 0), void, "SmoothPlastic", "Cylinder")
	local swirl = D(nil, V(0.8, 20, 20), c * ANG(rad(90), 0, 0) * ANG(0, 0, rad(90)), mag, "Neon", "Cylinder")
	swirl.Transparency = 0.45
	light(disc, mag, 70, 3)
	for i = 0, 15 do
		local a = rad(i * 22.5)
		local seg = D(m, V(6.4, 3, 3), c * ANG(0, 0, a) * CF(0, 15, 0), i % 2 == 0 and mag or cyan, "Neon")
		seg.Name = "Ring"
	end
	local hub = D(nil, V(1, 1, 1), c * ANG(rad(90), 0, 0), void)
	hub.Transparency = 1
	local sp = spinner(m, hub)
	swirl.Parent = sp
	for i = 0, 7 do
		local a = rad(i * 45)
		local shard = D(sp, V(1.2, rng:NextNumber(3, 6), 1.2), c * ANG(0, 0, a) * CF(0, rng:NextNumber(5, 11), -1.5) * ANG(rng:NextNumber(0, 3), 0, rng:NextNumber(0, 3)), i % 2 == 0 and cyan or mag, "Neon")
		shard.Transparency = 0.1
	end
	particles(disc, mag, 20, 3, 1.2, 2).SpreadAngle = Vector2.new(180, 180)
	for _, sx in ipairs({ -1, 1 }) do
		B(m, V(4, 30, 4), CF(sx * 19, 15, 0), void, "SmoothPlastic")
		D(m, V(4.3, 1, 4.3), CF(sx * 19, 26, 0), cyan, "Neon")
		D(m, V(2.6, 2.6, 2.6), CF(sx * 19, 32, 0) * ANG(rad(45), 0, rad(45)), mag, "Neon")
	end
end

function Scenery.landmark(areaId: number): Model?
	local fn = L[areaId]
	if not fn then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = "Landmark"
	fn(m, Random.new(areaId * 131))
	m.WorldPivot = CF(0, 0, 0)
	return m
end

---------------------------------------------------------------- marketplace cottages
local WALLS = { rgb(245, 235, 215), rgb(232, 214, 190), rgb(214, 226, 236), rgb(240, 222, 200) }
local ROOFS = { rgb(176, 72, 60), rgb(70, 110, 160), rgb(96, 130, 84), rgb(120, 86, 140) }

function Scenery.cottage(rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "Cottage"
	local w, d, h = rng:NextInteger(18, 24), rng:NextInteger(15, 19), rng:NextInteger(10, 13)
	local wall, rc = WALLS[rng:NextInteger(1, #WALLS)], ROOFS[rng:NextInteger(1, #ROOFS)]
	local beam = rgb(110, 78, 52)
	B(m, V(w + 2, 3, d + 2), CF(0, -0.5, 0), rgb(140, 132, 122), "Cobblestone")
	B(m, V(w, h, d), CF(0, 1 + h / 2, 0), wall, "Plaster")
	roof(m, CF(0, 1 + h, 0), w + 3, d + 4, 7, rc, "Slate")
	for _, sx in ipairs({ -1, 1 }) do
		D(m, V(0.7, h, 0.7), CF(sx * (w / 2), 1 + h / 2, -d / 2), beam, "Wood")
		D(m, V(0.7, h, 0.7), CF(sx * (w / 2), 1 + h / 2, d / 2), beam, "Wood")
	end
	D(m, V(w + 0.4, 0.7, 0.5), CF(0, 1 + h * 0.55, -d / 2 - 0.05), beam, "Wood")
	D(m, V(3.4, 6.4, 0.5), CF(0, 4.2, -d / 2 - 0.1), rgb(128, 84, 52), "WoodPlanks")
	D(m, V(0.4, 0.4, 0.4), CF(1.1, 4.2, -d / 2 - 0.45), rgb(255, 215, 80), "Metal", "Ball")
	D(m, V(4.6, 0.5, 2), CF(0, 1.25, -d / 2 - 1), rgb(150, 142, 132), "Cobblestone")
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (w / 2 - 4)
		local win = D(m, V(3.2, 3.2, 0.4), CF(x, 5.6, -d / 2 - 0.1), rgb(255, 228, 150), "Neon")
		D(m, V(3.8, 0.4, 0.5), CF(x, 3.8, -d / 2 - 0.2), beam, "Wood")
		D(m, V(0.3, 3.2, 0.5), CF(x, 5.6, -d / 2 - 0.2), beam, "Wood")
		D(m, V(3.2, 0.3, 0.5), CF(x, 5.6, -d / 2 - 0.2), beam, "Wood")
		D(m, V(3.6, 0.9, 1), CF(x, 3.3, -d / 2 - 0.6), rgb(120, 84, 56), "WoodPlanks")
		D(m, V(3.2, 1.2, 0.8), CF(x, 4.2, -d / 2 - 0.6), Color3.fromHSV(rng:NextNumber(), 0.6, 1), "Grass")
		if sx == 1 then
			light(win, rgb(255, 220, 150), 18, 0.8)
		end
	end
	B(m, V(2.6, 9, 2.6), CF(w / 2 - 4, h + 5, d / 4), rgb(150, 100, 86), "Brick")
	local top = D(m, V(3.2, 0.8, 3.2), CF(w / 2 - 4, h + 9.8, d / 4), rgb(110, 76, 66), "Brick")
	local smoke = particles(top, rgb(230, 230, 235), 3, 3, 2.4, 3.5)
	smoke.LightEmission = 0
	m.WorldPivot = CF(0, 0, 0)
	return m
end

Scenery.B, Scenery.D, Scenery.Wg, Scenery.cylV, Scenery.light, Scenery.particles = B, D, Wg, cylV, light, particles

return Scenery
