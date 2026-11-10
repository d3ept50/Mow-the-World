-- Procedural 3D model builders (workers, mowers, vehicles, crates, bosses, props).
-- Shared so the server can place them in the world and the client can show them in menus.
local Config = script.Parent.Config
local Workers = require(Config.Workers)
local Items = require(Config.Items)
local Areas = require(Config.Areas)

local Models = {}

local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local rad = math.rad
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local DARK = rgb(35, 35, 40)
local GREY = rgb(150, 150, 160)

local function P(parent, size, cf, color, mat, shape)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = Enum.PartType[shape]
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat and Enum.Material[mat] or Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end
Models.P = P

-- vertical cylinder
local function cyl(parent, h, d, pos, color, mat)
	return P(parent, V(h, d, d), CF(pos) * ANG(0, 0, rad(90)), color, mat, "Cylinder")
end
Models.cyl = cyl

local function rootPart(model)
	local r = P(model, V(1, 1, 1), CF(0, 0.5, 0), DARK)
	r.Transparency = 1
	r.Name = "Root"
	r.PivotOffset = CF(0, -0.5, 0)
	model.PrimaryPart = r
	return r
end

local function glow(part, color, range, particles)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range or 10
	l.Brightness = 1.5
	l.Parent = part
	if particles then
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(color)
		e.Rate = particles
		e.Lifetime = NumberRange.new(0.6, 1.2)
		e.Speed = NumberRange.new(1, 3)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		e.LightEmission = 0.8
		e.Parent = part
	end
end
Models.glow = glow

-- Weld every part to the model's root and unanchor them (root stays as it is).
function Models.weld(model: Model)
	local root = model.PrimaryPart
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			if d.Name == "ScissorBlade" then
				-- a classic Weld, not a WeldConstraint, so clients can turn the blade by its C0
				local j = Instance.new("Weld")
				j.Name = "BladeJoint"
				j.Part0 = root
				j.Part1 = d
				j.C0 = root.CFrame:ToObjectSpace(d.CFrame)
				j.Parent = d
			else
				local w = Instance.new("WeldConstraint")
				w.Part0 = root
				w.Part1 = d
				w.Parent = d
			end
			d.Anchored = false
		end
	end
end

---------------------------------------------------------------- Workers
function Models.worker(id: string): Model
	local def = Workers.ById[id]
	local rar = Workers.RarityById[def.rarity]
	local order = rar.order
	local bodyC, skinC, hat, hatC, tool = table.unpack(def.look)
	local m = Instance.new("Model")
	m.Name = id
	rootPart(m)
	local fancy = order >= 6 and "Neon" or nil
	local trim = bodyC:Lerp(rgb(0, 0, 0), 0.35)
	P(m, V(0.5, 0.7, 0.5), CF(-0.32, 0.6, 0), rgb(60, 70, 100))
	P(m, V(0.5, 0.7, 0.5), CF(0.32, 0.6, 0), rgb(60, 70, 100))
	P(m, V(0.58, 0.32, 0.78), CF(-0.32, 0.16, -0.1), DARK)
	P(m, V(0.58, 0.32, 0.78), CF(0.32, 0.16, -0.1), DARK)
	local body = P(m, V(1.3, 1.3, 0.8), CF(0, 1.55, 0), bodyC, order >= 8 and "Neon" or nil)
	body.Name = "Body"
	P(m, V(1.36, 0.22, 0.86), CF(0, 1.02, 0), trim)
	P(m, V(0.3, 0.26, 0.1), CF(0, 1.02, -0.44), rgb(255, 215, 80), "Metal")
	P(m, V(0.22, 1.3, 0.1), CF(-0.38, 1.6, -0.42), trim)
	P(m, V(0.22, 1.3, 0.1), CF(0.38, 1.6, -0.42), trim)
	P(m, V(0.4, 1.1, 0.4), CF(-0.85, 1.6, 0), bodyC)
	P(m, V(0.4, 1.1, 0.4), CF(0.85, 1.75, -0.3) * ANG(rad(50), 0, 0), bodyC)
	P(m, V(0.46, 0.46, 0.46), CF(-0.85, 0.95, 0), skinC, nil, "Ball")
	P(m, V(0.46, 0.46, 0.46), CF(0.85, 1.38, -0.74), skinC, nil, "Ball")
	-- grass bag on the back
	P(m, V(0.95, 1.05, 0.5), CF(0, 1.6, 0.62), rgb(96, 130, 70), "Fabric")
	P(m, V(0.8, 0.3, 0.4), CF(0, 2.2, 0.62), rgb(120, 200, 90), "Grass")
	P(m, V(1, 1, 1), CF(0, 2.7, 0), skinC)
	P(m, V(0.4, 0.08, 0.06), CF(0, 2.42, -0.5), rgb(120, 60, 50))
	local eyeC = order >= 6 and rar.color or rgb(20, 20, 20)
	if def.rarity == "Secret" then
		eyeC = rgb(255, 40, 60)
	end
	P(m, V(0.16, 0.26, 0.06), CF(-0.22, 2.8, -0.5), eyeC, order >= 6 and "Neon" or nil)
	P(m, V(0.16, 0.26, 0.06), CF(0.22, 2.8, -0.5), eyeC, order >= 6 and "Neon" or nil)
	-- hats
	if hat == "cap" then
		cyl(m, 0.35, 1.1, V(0, 3.35, 0), hatC)
		P(m, V(0.9, 0.1, 0.5), CF(0, 3.22, -0.7), hatC)
	elseif hat == "straw" then
		cyl(m, 0.1, 2.1, V(0, 3.25, 0), hatC)
		cyl(m, 0.5, 1.05, V(0, 3.5, 0), hatC)
	elseif hat == "cone" then
		cyl(m, 0.45, 1.05, V(0, 3.4, 0), hatC)
		cyl(m, 0.45, 0.75, V(0, 3.85, 0), hatC)
		cyl(m, 0.45, 0.4, V(0, 4.3, 0), hatC)
	elseif hat == "helmet" then
		P(m, V(1.35, 1.35, 1.35), CF(0, 2.95, 0.05), hatC, "Metal", "Ball")
	elseif hat == "antenna" then
		cyl(m, 0.8, 0.1, V(0, 3.6, 0), GREY, "Metal")
		P(m, V(0.35, 0.35, 0.35), CF(0, 4.1, 0), hatC, "Neon", "Ball")
	elseif hat == "tophat" then
		cyl(m, 0.1, 1.6, V(0, 3.25, 0), hatC)
		cyl(m, 0.9, 1.0, V(0, 3.75, 0), hatC)
	elseif hat == "hood" then
		P(m, V(1.2, 1.2, 1.1), CF(0, 2.78, 0.12), hatC, "Fabric")
	elseif hat == "horns" then
		P(m, V(0.25, 0.9, 0.25), CF(-0.45, 3.45, 0) * ANG(0, 0, rad(25)), hatC, fancy)
		P(m, V(0.25, 0.9, 0.25), CF(0.45, 3.45, 0) * ANG(0, 0, rad(-25)), hatC, fancy)
	elseif hat == "crown" then
		cyl(m, 0.3, 1.1, V(0, 3.35, 0), hatC, "Neon")
		for i = 0, 3 do
			local a = rad(i * 90)
			P(m, V(0.2, 0.45, 0.2), CF(math.sin(a) * 0.45, 3.7, math.cos(a) * 0.45), hatC, "Neon")
		end
	elseif hat == "halo" then
		cyl(m, 0.1, 1.5, V(0, 3.9, 0), hatC, "Neon")
	end
	-- tools (held in the right hand, pointing forward)
	local hx, hz = 0.95, -0.75
	if tool == "rake" then
		P(m, V(0.14, 2.6, 0.14), CF(hx, 1.6, hz), rgb(120, 85, 50), "Wood")
		P(m, V(0.9, 0.14, 0.14), CF(hx, 0.35, hz), GREY, "Metal")
	elseif tool == "shears" then
		P(m, V(0.1, 1.3, 0.3), CF(hx, 2.1, hz) * ANG(0, 0, rad(14)), GREY, "Metal")
		P(m, V(0.1, 1.3, 0.3), CF(hx, 2.1, hz) * ANG(0, 0, rad(-14)), GREY, "Metal")
		P(m, V(0.3, 0.5, 0.3), CF(hx, 1.3, hz), rgb(220, 60, 60))
	elseif tool == "scythe" then
		P(m, V(0.14, 3.2, 0.14), CF(hx, 1.9, hz), rgb(70, 50, 40), "Wood")
		P(m, V(1.5, 0.35, 0.08), CF(hx - 0.7, 3.4, hz) * ANG(0, 0, rad(-12)), order >= 6 and rar.color or GREY, order >= 6 and "Neon" or "Metal")
	else -- trimmer
		P(m, V(0.14, 0.14, 2.4), CF(hx, 1.1, hz - 0.8) * ANG(rad(-30), 0, 0), DARK, "Metal")
		cyl(m, 0.12, 0.9, V(hx, 0.4, hz - 1.9), rgb(250, 140, 30))
	end
	if order >= 5 then
		local c = def.rarity == "Secret" and rgb(255, 40, 60) or rar.color
		glow(body, c, 8 + order, 4 + order * 2)
	end
	m:ScaleTo(0.85 + order * 0.07)
	return m
end

---------------------------------------------------------------- Mowers
function Models.mower(id: string): Model
	local def = Items.MowerById[id]
	local L = def.look
	local m = Instance.new("Model")
	m.Name = "Mower"
	rootPart(m)
	m:SetAttribute("Kind", L.kind)
	if L.kind == "scissors" then
		-- hand held, origin at the hand, pointing forward (-Z)
		-- the blades are named so Models.weld gives them a joint that clients can animate
		for _, side in ipairs({ 1, -1 }) do
			local blade = P(m, V(0.18, 0.08, 1.7), CF(0, side == 1 and 1 or 1.08, -0.9) * ANG(0, rad(10 * side), 0), L.color, "Metal")
			blade.Name = "ScissorBlade"
			blade:SetAttribute("Side", side)
		end
		P(m, V(0.45, 0.14, 0.45), CF(-0.25, 1.04, 0.1), L.accent)
		P(m, V(0.45, 0.14, 0.45), CF(0.25, 1.04, 0.1), L.accent)
	else
		local w = L.wide and 3.1 or 2.2
		local deck = P(m, V(w, 0.6, 2.8), CF(0, 0.6, -1.8), L.color, L.mat)
		deck.Name = "Deck"
		P(m, V(w + 0.15, 0.18, 0.5), CF(0, 0.38, -3.1), L.accent)
		for _, sx in ipairs({ -1, 1 }) do
			for _, z in ipairs({ -0.8, -2.8 }) do
				P(m, V(0.3, 0.85, 0.85), CF(sx * (w / 2 + 0.12), 0.43, z), DARK, nil, "Cylinder")
			end
			P(m, V(0.12, 0.12, 2.5), CF(sx * 0.8, 1.75, 0.35) * ANG(rad(-52), 0, 0), GREY, "Metal")
		end
		P(m, V(1.9, 0.16, 0.16), CF(0, 2.72, 1.1), L.accent)
		if L.engine then
			local ez = L.seat and -2.5 or -1.9
			if L.twin then
				P(m, V(0.9, 0.8, 1.1), CF(-0.6, 1.3, ez), L.accent, "Metal")
				P(m, V(0.9, 0.8, 1.1), CF(0.6, 1.3, ez), L.accent, "Metal")
			else
				P(m, V(1.2, 0.8, 1.2), CF(0, 1.3, ez), L.accent, "Metal")
			end
			if L.stack then
				local st = cyl(m, 1.1, 0.22, V(0.75, 1.9, ez), GREY, "Metal")
				if L.fire then
					local f = Instance.new("Fire")
					f.Size = 3
					f.Heat = 6
					f.Color = L.glow or rgb(255, 120, 30)
					f.SecondaryColor = L.accent
					f.Parent = st
				end
			end
		end
		if L.seat then
			P(m, V(1, 0.3, 1), CF(0, 1.05, -1.1), DARK, "Fabric")
			P(m, V(1, 0.9, 0.25), CF(0, 1.5, -0.65), DARK, "Fabric")
		end
		if L.bag then
			P(m, V(1.5, 1.1, 1), CF(0, 1.35, 0.15), rgb(60, 60, 65), "Fabric")
		end
		if L.rainbow then
			local cols = { rgb(255, 60, 60), rgb(255, 160, 40), rgb(255, 235, 60), rgb(70, 220, 90), rgb(60, 150, 255), rgb(170, 80, 255) }
			for i, c in ipairs(cols) do
				P(m, V(w + 0.05, 0.62, 0.4), CF(0, 0.6, -0.65 - i * 0.4), c, "Neon")
			end
		end
		if L.halo then
			cyl(m, 0.12, 2.2, V(0, 3.4, -1.8), L.glow, "Neon")
		end
		if L.glow then
			P(m, V(w + 0.2, 0.2, 0.2), CF(0, 0.7, -3.25), L.glow, "Neon")
			P(m, V(0.15, 0.2, 2.8), CF(w / 2 + 0.05, 0.9, -1.8), L.glow, "Neon")
			P(m, V(0.15, 0.2, 2.8), CF(-w / 2 - 0.05, 0.9, -1.8), L.glow, "Neon")
			glow(deck, L.glow, 12, 10)
		end
	end
	m:ScaleTo(L.scale or 1)
	return m
end

---------------------------------------------------------------- Vehicles
function Models.vehicle(id: string): Model
	local def = Items.VehicleById[id]
	local L = def.look
	local m = Instance.new("Model")
	m.Name = "Vehicle"
	rootPart(m)
	local c, a = L.color, L.accent
	P(m, V(4.4, 0.5, 7), CF(0, 0.95, 0), DARK)
	P(m, V(0.4, 1.7, 7), CF(-2, 1.9, 0), c)
	P(m, V(0.4, 1.7, 7), CF(2, 1.9, 0), c)
	local hood = P(m, V(4, 1.6, 2.6), CF(0, 1.9, -2.3), c)
	P(m, V(3.4, 0.9, 0.2), CF(0, 1.9, -3.65), a)
	P(m, V(0.6, 0.4, 0.15), CF(-1.3, 2.4, -3.68), rgb(255, 250, 200), "Neon")
	P(m, V(0.6, 0.4, 0.15), CF(1.3, 2.4, -3.68), rgb(255, 250, 200), "Neon")
	P(m, V(4, 1.9, 2), CF(0, 2.05, 2.5), c)
	P(m, V(2.6, 2.3, 0.4), CF(0, 3.3, 1.35), a, "Fabric")
	P(m, V(0.15, 1.5, 0.15), CF(0, 3.1, -1.25) * ANG(rad(-25), 0, 0), DARK)
	P(m, V(0.15, 1, 1), CF(0, 3.75, -0.95) * ANG(rad(-25), 0, 0) * ANG(0, rad(90), 0), DARK, nil, "Cylinder")
	for _, sx in ipairs({ -1, 1 }) do
		P(m, V(0.9, 1.9, 1.9), CF(sx * 2.6, 0.95, -2.3), DARK, nil, "Cylinder")
		P(m, V(1, 2.5, 2.5), CF(sx * 2.65, 1.25, 2.3), DARK, nil, "Cylinder")
		P(m, V(1.05, 1, 1), CF(sx * 2.65, 1.25, 2.3), a, nil, "Cylinder")
	end
	local dw = L.wideDeck and 8 or 5.4
	P(m, V(dw, 0.5, 2), CF(0, 0.5, -4.7), a)
	P(m, V(dw + 0.2, 0.2, 0.3), CF(0, 0.3, -5.7), L.glow or rgb(220, 220, 230), L.glow and "Neon" or "Metal")
	if L.roof then
		for _, sx in ipairs({ -1, 1 }) do
			for _, z in ipairs({ -1.2, 1.5 }) do
				P(m, V(0.2, 4, 0.2), CF(sx * 2, 4.7, z), DARK, "Metal")
			end
		end
		P(m, V(4.6, 0.25, 3.4), CF(0, 6.8, 0.15), a)
	end
	if L.stacks then
		cyl(m, 2.4, 0.4, V(-1.5, 4.1, 3), GREY, "Metal")
		cyl(m, 2.4, 0.4, V(1.5, 4.1, 3), GREY, "Metal")
	end
	if L.spoiler then
		P(m, V(0.2, 1, 0.2), CF(-1.6, 3.5, 3.3), DARK)
		P(m, V(0.2, 1, 0.2), CF(1.6, 3.5, 3.3), DARK)
		P(m, V(4.8, 0.2, 1.1), CF(0, 4.05, 3.4), a)
	end
	if L.wings then
		P(m, V(4.5, 0.2, 2.2), CF(-4.2, 3.2, 1.5) * ANG(0, rad(-20), rad(-18)), L.glow or a, "Neon")
		P(m, V(4.5, 0.2, 2.2), CF(4.2, 3.2, 1.5) * ANG(0, rad(20), rad(18)), L.glow or a, "Neon")
	end
	if L.glow then
		P(m, V(0.12, 0.2, 7), CF(-2.22, 1.3, 0), L.glow, "Neon")
		P(m, V(0.12, 0.2, 7), CF(2.22, 1.3, 0), L.glow, "Neon")
		glow(hood, L.glow, 16, 12)
	end
	m:ScaleTo(L.scale or 1)
	return m
end

---------------------------------------------------------------- Crates
function Models.crate(id: string): Model
	local def = Workers.CrateById[id]
	local L = def.look
	local m = Instance.new("Model")
	m.Name = "Crate"
	rootPart(m)
	local trimMat = L.neon and "Neon" or "Metal"
	local body = P(m, V(3, 2.4, 3), CF(0, 1.2, 0), L.color, L.mat)
	body.Name = "Body"
	local lid = P(m, V(3.3, 0.6, 3.3), CF(0, 2.7, 0), L.color, L.mat)
	lid.Name = "Lid"
	P(m, V(3.4, 0.2, 3.4), CF(0, 2.45, 0), L.trim, trimMat)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			P(m, V(0.4, 2.4, 0.4), CF(sx * 1.4, 1.2, sz * 1.4), L.trim, trimMat)
		end
	end
	P(m, V(0.7, 0.9, 0.2), CF(0, 1.9, -1.55), L.trim, trimMat)
	if L.top == "leaf" then
		P(m, V(1.6, 0.15, 0.8), CF(0.3, 3.15, 0) * ANG(0, rad(30), rad(15)), rgb(120, 220, 80))
		P(m, V(1.2, 0.15, 0.6), CF(-0.4, 3.2, 0.2) * ANG(0, rad(-40), rad(-15)), rgb(90, 190, 70))
	elseif L.top == "gem" then
		local g = P(m, V(1, 1, 1), CF(0, 3.5, 0) * ANG(rad(45), 0, rad(45)), L.trim, "Neon")
		g.Name = "Gem"
	elseif L.top == "skull" then
		P(m, V(1.2, 1.2, 1.2), CF(0, 3.55, 0), rgb(235, 235, 235), nil, "Ball")
		P(m, V(0.25, 0.3, 0.1), CF(-0.25, 3.6, -0.56), L.trim, "Neon")
		P(m, V(0.25, 0.3, 0.1), CF(0.25, 3.6, -0.56), L.trim, "Neon")
	elseif L.top == "halo" then
		cyl(m, 0.15, 2.6, V(0, 4, 0), L.trim, "Neon")
		P(m, V(0.9, 0.9, 0.9), CF(0, 3.5, 0), rgb(255, 255, 255), "Neon", "Ball")
	end
	if L.neon then
		glow(body, L.trim, 12, 8)
	end
	return m
end

---------------------------------------------------------------- Bosses
function Models.boss(areaId: number): Model
	local B = Areas.List[areaId].boss
	local S = B.size
	local m = Instance.new("Model")
	m.Name = "Boss"
	local root = rootPart(m)
	local body
	if B.body == "ball" then
		body = P(m, V(S, S, S), CF(0, S * 0.55, 0), B.color, B.mat, "Ball")
	elseif B.body == "cyl" then
		body = cyl(m, S * 1.1, S * 0.75, V(0, S * 0.58, 0), B.color, B.mat)
	else
		body = P(m, V(S * 0.9, S, S * 0.7), CF(0, S * 0.55, 0), B.color, B.mat)
	end
	body.Name = "Body"
	local headY = S * 1.28
	local head = P(m, V(S * 0.5, S * 0.45, S * 0.5), CF(0, headY, 0), B.color2, B.mat == "Neon" and "SmoothPlastic" or B.mat)
	head.Name = "Head"
	local eyeC = rgb(255, 50, 50)
	P(m, V(S * 0.1, S * 0.1, S * 0.1), CF(-S * 0.12, headY + S * 0.05, -S * 0.25), eyeC, "Neon", "Ball")
	P(m, V(S * 0.1, S * 0.1, S * 0.1), CF(S * 0.12, headY + S * 0.05, -S * 0.25), eyeC, "Neon", "Ball")
	P(m, V(S * 0.26, S * 0.05, S * 0.05), CF(0, headY - S * 0.1, -S * 0.25), DARK)
	P(m, V(S * 0.25, S * 0.75, S * 0.25), CF(-S * 0.65, S * 0.6, 0) * ANG(0, 0, rad(-12)), B.color2, B.mat).Name = "ArmL"
	P(m, V(S * 0.25, S * 0.75, S * 0.25), CF(S * 0.65, S * 0.6, 0) * ANG(0, 0, rad(12)), B.color2, B.mat).Name = "ArmR"
	-- extra detail: shoulders, fists, feet, belly plate, brows and teeth
	local shade = B.color:Lerp(rgb(0, 0, 0), 0.3)
	local light = B.color:Lerp(rgb(255, 255, 255), 0.35)
	for _, sx in ipairs({ -1, 1 }) do
		P(m, V(S * 0.36, S * 0.36, S * 0.36), CF(sx * S * 0.58, S * 0.95, 0), shade, B.mat == "Neon" and "SmoothPlastic" or B.mat, "Ball")
		P(m, V(S * 0.34, S * 0.3, S * 0.34), CF(sx * S * 0.73, S * 0.2, 0), shade, B.mat == "Neon" and "SmoothPlastic" or B.mat, "Ball")
		P(m, V(S * 0.3, S * 0.16, S * 0.42), CF(sx * S * 0.24, S * 0.08, -S * 0.08), shade, B.mat == "Neon" and "SmoothPlastic" or B.mat)
		P(m, V(S * 0.15, S * 0.035, S * 0.05), CF(sx * S * 0.12, headY + S * 0.13, -S * 0.25) * ANG(0, 0, rad(sx * -22)), DARK)
	end
	P(m, V(S * 0.5, S * 0.5, S * 0.12), CF(0, S * 0.5, -S * (B.body == "block" and 0.33 or 0.4)), light, B.mat == "Neon" and "SmoothPlastic" or B.mat)
	for i = -1, 1 do
		P(m, V(S * 0.05, S * 0.07, S * 0.04), CF(i * S * 0.08, headY - S * 0.14, -S * 0.25), rgb(250, 250, 245))
	end
	local f = B.feature
	if f == "petals" then
		for i = 0, 7 do
			local a = rad(i * 45)
			P(m, V(S * 0.22, S * 0.36, S * 0.06), CF(0, headY, S * 0.05) * ANG(0, 0, a) * CF(0, S * 0.42, 0), rgb(255, 235, 90))
		end
	elseif f == "horns" then
		P(m, V(S * 0.1, S * 0.45, S * 0.1), CF(-S * 0.24, headY + S * 0.4, 0) * ANG(0, 0, rad(28)), rgb(240, 235, 220))
		P(m, V(S * 0.1, S * 0.45, S * 0.1), CF(S * 0.24, headY + S * 0.4, 0) * ANG(0, 0, rad(-28)), rgb(240, 235, 220))
	elseif f == "spikes" then
		for i = -2, 2 do
			P(m, V(S * 0.14, S * 0.4, S * 0.14), CF(i * S * 0.2, S * 1.12, S * 0.3) * ANG(rad(35), rad(45), 0), B.color2, B.color2 == B.color and nil or "Neon")
		end
	elseif f == "crown" then
		cyl(m, S * 0.1, S * 0.5, V(0, headY + S * 0.28, 0), rgb(255, 210, 60), "Neon")
		for i = 0, 4 do
			local a = rad(i * 72)
			P(m, V(S * 0.07, S * 0.2, S * 0.07), CF(math.sin(a) * S * 0.2, headY + S * 0.42, math.cos(a) * S * 0.2), rgb(255, 210, 60), "Neon")
		end
	elseif f == "crystals" then
		local rng = Random.new(areaId)
		for i = 1, 7 do
			P(m, V(S * 0.12, S * 0.5, S * 0.12), CF(rng:NextNumber(-0.5, 0.5) * S, S * rng:NextNumber(0.9, 1.2), S * rng:NextNumber(0.1, 0.4)) * ANG(rng:NextNumber(-0.6, 0.6), 0, rng:NextNumber(-0.6, 0.6)), B.color2, "Neon")
		end
	elseif f == "wings" then
		P(m, V(S * 0.9, S * 0.6, S * 0.06), CF(-S * 0.75, S * 0.95, S * 0.35) * ANG(0, rad(25), rad(20)), B.color2, "Neon")
		P(m, V(S * 0.9, S * 0.6, S * 0.06), CF(S * 0.75, S * 0.95, S * 0.35) * ANG(0, rad(-25), rad(-20)), B.color2, "Neon")
	elseif f == "heads" then
		for _, sx in ipairs({ -1, 1 }) do
			P(m, V(S * 0.12, S * 0.5, S * 0.12), CF(sx * S * 0.4, S * 1.1, 0) * ANG(0, 0, rad(-sx * 30)), B.color, B.mat)
			P(m, V(S * 0.3, S * 0.28, S * 0.3), CF(sx * S * 0.55, S * 1.38, 0), B.color2, "SmoothPlastic")
			P(m, V(S * 0.07, S * 0.07, S * 0.07), CF(sx * S * 0.55, S * 1.42, -S * 0.15), eyeC, "Neon", "Ball")
		end
	end
	glow(body, B.color2, S * 2.5, 6)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			d.CastShadow = true
		end
	end
	return m
end

---------------------------------------------------------------- Simple figure (NPCs)
function Models.figure(shirt: Color3, skin: Color3, hatC: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "NPC"
	rootPart(m)
	P(m, V(0.9, 2, 0.9), CF(-0.5, 1, 0), rgb(50, 60, 90))
	P(m, V(0.9, 2, 0.9), CF(0.5, 1, 0), rgb(50, 60, 90))
	P(m, V(2, 2, 1), CF(0, 3, 0), shirt)
	P(m, V(0.9, 2, 0.9), CF(-1.5, 3, 0), shirt)
	P(m, V(0.9, 2, 0.9), CF(1.5, 3, 0), shirt)
	P(m, V(1.3, 1.3, 1.3), CF(0, 4.65, 0), skin)
	P(m, V(0.18, 0.3, 0.06), CF(-0.28, 4.75, -0.66), DARK)
	P(m, V(0.18, 0.3, 0.06), CF(0.28, 4.75, -0.66), DARK)
	P(m, V(0.5, 0.1, 0.06), CF(0, 4.35, -0.66), DARK)
	if hatC then
		cyl(m, 0.15, 2.4, V(0, 5.35, 0), hatC)
		cyl(m, 0.6, 1.3, V(0, 5.7, 0), hatC)
	end
	return m
end

---------------------------------------------------------------- Props
local function solid(p)
	p.CanCollide = true
	p.CastShadow = true
	return p
end

-- small random shift in saturation / brightness so repeated props do not look identical
local function tone(c: Color3, rng: Random, amt: number): Color3
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, math.clamp(s + rng:NextNumber(-amt, amt) * 0.6, 0, 1), math.clamp(v + rng:NextNumber(-amt, amt), 0, 1))
end
Models.tone = tone

-- a clump of leaf blobs around a centre point
local function foliage(m, rng, center, radius, count, color, mat)
	for i = 1, count do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = i == 1 and 0 or rng:NextNumber(0.4, 0.75) * radius
		local s = radius * (i == 1 and 1.55 or rng:NextNumber(0.8, 1.2))
		local p = P(m, V(s, s * rng:NextNumber(0.8, 0.95), s), CF(center + V(math.cos(a) * r, rng:NextNumber(-0.3, 0.4) * radius, math.sin(a) * r)), tone(color, rng, 0.07), mat, "Ball")
		p.CastShadow = i <= 2
	end
end

function Models.prop(kind: string, pal, rng: Random, neon: boolean?): Model
	local m = Instance.new("Model")
	m.Name = kind
	local leaf, trunk, accent = pal[1], pal[2], pal[3]
	local nm = neon and "Neon" or nil
	if kind == "tree" or kind == "goldtree" then
		local gold = kind == "goldtree"
		local tc = gold and rgb(245, 240, 230) or tone(trunk, rng, 0.05)
		local h = rng:NextNumber(5, 7.5)
		cyl(m, 0.5, 2.2, V(0, 0.25, 0), tc, "Wood")
		solid(cyl(m, h * 0.55, 1.5, V(0, h * 0.275, 0), tc, "Wood"))
		cyl(m, h * 0.5, 1.05, V(0, h * 0.75, 0), tc, "Wood")
		P(m, V(0.45, 2.6, 0.45), CF(0.9, h * 0.82, 0) * ANG(0, 0, rad(-42)), tc, "Wood")
		P(m, V(0.4, 2.2, 0.4), CF(-0.7, h * 0.9, 0.4) * ANG(rad(25), 0, rad(38)), tc, "Wood")
		foliage(m, rng, V(0, h + 2.2, 0), 4.2, 6, leaf, gold and "Foil" or "Grass")
		if gold then
			local orb = P(m, V(0.9, 0.9, 0.9), CF(1.6, h + 0.4, 1.2), accent, "Neon", "Ball")
			glow(orb, accent, 12)
		end
	elseif kind == "bigtree" then
		local tc = tone(trunk, rng, 0.05)
		for i = 0, 4 do
			local a = rad(i * 72 + rng:NextNumber(-15, 15))
			P(m, V(1.3, 3.4, 1.3), CF(math.cos(a) * 1.9, 1.1, math.sin(a) * 1.9) * ANG(math.sin(a) * 0.6, 0, -math.cos(a) * 0.6), tc, "Wood")
		end
		solid(cyl(m, 8, 3.4, V(0, 4, 0), tc, "Wood"))
		cyl(m, 7, 2.6, V(0, 11, 0), tc, "Wood")
		P(m, V(1, 6, 1), CF(2.6, 12.5, 0) * ANG(0, 0, rad(-48)), tc, "Wood")
		P(m, V(1, 6, 1), CF(-2.4, 12, 1) * ANG(rad(20), 0, rad(46)), tc, "Wood")
		foliage(m, rng, V(0, 18, 0), 8.5, 9, leaf, "Grass")
		for i = 1, 3 do
			local a = rng:NextNumber(0, math.pi * 2)
			local pos = V(math.cos(a) * 4.5, rng:NextNumber(8, 11), math.sin(a) * 4.5)
			P(m, V(0.08, 3, 0.08), CF(pos + V(0, 1.8, 0)), DARK)
			local orb = P(m, V(0.9, 0.9, 0.9), CF(pos), accent, "Neon", "Ball")
			if i == 1 then
				glow(orb, accent, 16, 2)
			end
		end
	elseif kind == "pine" then
		solid(cyl(m, 3.2, 1.1, V(0, 1.6, 0), tone(trunk, rng, 0.05), "Wood"))
		for i = 0, 4 do
			local d = 7.2 - i * 1.4
			local tier = cyl(m, 2.1, d, V(0, 3.4 + i * 1.75, 0), tone(leaf, rng, 0.05), "Grass")
			tier.CastShadow = i == 0
			cyl(m, 0.3, d * 0.8, V(0, 4.5 + i * 1.75, 0), rgb(250, 250, 255), "Snow")
		end
		cyl(m, 1.4, 0.7, V(0, 12.6, 0), rgb(250, 250, 255), "Snow")
	elseif kind == "palm" then
		local tc = tone(rgb(150, 115, 75), rng, 0.05)
		local lean = rng:NextNumber(0.08, 0.2)
		local cf = CF(0, 0, 0)
		for i = 1, 6 do
			cf = cf * ANG(0, 0, -lean * 0.5) * CF(0, 1.9, 0)
			local seg = P(m, V(1.9, 1.25 - i * 0.07, 1.25 - i * 0.07), cf * CF(0, -0.95, 0) * ANG(0, 0, rad(90)), tc, "Wood", "Cylinder")
			if i <= 2 then
				solid(seg)
			end
		end
		for i = 0, 6 do
			local f = cf * ANG(0, rad(i * 51.4), 0) * ANG(0, 0, rad(-28))
			P(m, V(4.6, 0.25, 1.5), f * CF(2.4, 0, 0), tone(rgb(70, 165, 75), rng, 0.06), "Grass")
			P(m, V(3, 0.22, 1.1), f * CF(4.4, 0, 0) * ANG(0, 0, rad(-32)) * CF(1.3, 0, 0), tone(rgb(70, 165, 75), rng, 0.06), "Grass")
		end
		P(m, V(0.9, 0.9, 0.9), cf * CF(0.5, -0.5, 0.3), rgb(95, 65, 40), nil, "Ball")
		P(m, V(0.9, 0.9, 0.9), cf * CF(-0.4, -0.6, -0.4), rgb(95, 65, 40), nil, "Ball")
	elseif kind == "bush" then
		foliage(m, rng, V(0, 1.3, 0), 2.2, 4, leaf, "Grass")
		for _ = 1, 4 do
			local a = rng:NextNumber(0, math.pi * 2)
			P(m, V(0.5, 0.5, 0.5), CF(math.cos(a) * 1.5, rng:NextNumber(1.2, 2.4), math.sin(a) * 1.5), accent, nm, "Ball")
		end
	elseif kind == "tuft" then
		for _ = 1, 6 do
			local x, z = rng:NextNumber(-1.2, 1.2), rng:NextNumber(-1.2, 1.2)
			local h = rng:NextNumber(1, 2.2)
			P(m, V(0.28, h, 0.12), CF(x, h / 2, z) * ANG(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)), tone(leaf, rng, 0.1), "Grass")
		end
	elseif kind == "lamp" then
		cyl(m, 0.6, 1.6, V(0, 0.3, 0), DARK, "Metal")
		solid(cyl(m, 9, 0.45, V(0, 4.8, 0), DARK, "Metal"))
		P(m, V(2.4, 0.3, 0.3), CF(0.9, 9.2, 0), DARK, "Metal")
		P(m, V(1.5, 0.3, 1.5), CF(1.9, 9.1, 0), DARK, "Metal")
		local bulb = P(m, V(1.1, 1.3, 1.1), CF(1.9, 8.3, 0), accent, "Neon")
		glow(bulb, accent, 30)
	elseif kind == "bench" then
		local wood = rgb(150, 105, 60)
		for i = 0, 2 do
			solid(P(m, V(6, 0.25, 0.55), CF(0, 1.6, -0.65 + i * 0.65), tone(wood, rng, 0.04), "WoodPlanks"))
		end
		for i = 0, 1 do
			P(m, V(6, 0.55, 0.22), CF(0, 2.3 + i * 0.7, 0.95) * ANG(rad(-10), 0, 0), tone(wood, rng, 0.04), "WoodPlanks")
		end
		for _, sx in ipairs({ -1, 1 }) do
			P(m, V(0.3, 1.6, 1.8), CF(sx * 2.6, 0.8, 0), DARK, "Metal")
			P(m, V(0.3, 1.9, 0.3), CF(sx * 2.6, 2.3, 0.95) * ANG(rad(-10), 0, 0), DARK, "Metal")
		end
	elseif kind == "deadtree" then
		solid(cyl(m, 7, 1, V(0, 3.5, 0), trunk, "Wood"))
		P(m, V(0.4, 3.5, 0.4), CF(1.2, 6.5, 0) * ANG(0, 0, rad(-40)), trunk, "Wood")
		P(m, V(0.4, 3, 0.4), CF(-1, 7, 0.3) * ANG(rad(20), 0, rad(35)), trunk, "Wood")
		P(m, V(0.3, 2.2, 0.3), CF(0.2, 8, -0.8) * ANG(rad(-35), 0, 0), trunk, "Wood")
	elseif kind == "rock" or kind == "icerock" or kind == "lavarock" then
		local c = kind == "icerock" and accent or trunk
		local mat = kind == "icerock" and "Ice" or "Slate"
		local a = solid(P(m, V(4.2, 3.2, 3.6), CF(0, 1.3, 0) * ANG(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)), tone(c, rng, 0.05), mat))
		solid(P(m, V(2.6, 2.1, 2.6), CF(2.1, 0.8, 1) * ANG(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 3), 0), tone(c, rng, 0.06), mat))
		P(m, V(2, 1.5, 2.2), CF(-2, 0.55, -0.9) * ANG(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)), tone(c, rng, 0.06), mat)
		P(m, V(1.2, 0.9, 1.3), CF(0.6, 0.35, -2.2) * ANG(0, rng:NextNumber(0, 3), 0), tone(c, rng, 0.06), mat)
		if kind == "rock" then
			P(m, V(2.6, 0.5, 2.2), a.CFrame * CF(0, 1.5, 0), tone(leaf, rng, 0.05), "Grass")
		end
		if kind == "lavarock" then
			local l = P(m, V(1.6, 0.4, 1.6), CF(0, 2.75, 0) * ANG(0, rng:NextNumber(0, 3), 0), leaf, "Neon")
			glow(l, leaf, 14, 4)
		elseif kind == "icerock" then
			a.Transparency = 0.25
		end
	elseif kind == "flower" then
		local cols = { accent, rgb(255, 255, 255), rgb(255, 150, 190), rgb(255, 215, 80), rgb(170, 130, 255) }
		for i = 1, 4 do
			local x, z = rng:NextNumber(-1.8, 1.8), rng:NextNumber(-1.8, 1.8)
			local h = rng:NextNumber(1.2, 2)
			local c = cols[rng:NextInteger(1, #cols)]
			P(m, V(0.14, h, 0.14), CF(x, h / 2, z), rgb(70, 160, 60))
			P(m, V(0.7, 0.12, 0.3), CF(x + 0.3, h * 0.45, z) * ANG(0, rng:NextNumber(0, 3), rad(20)), rgb(80, 175, 70))
			for k = 0, 3 do
				local a = rad(k * 90 + i * 20)
				P(m, V(0.5, 0.3, 0.5), CF(x + math.cos(a) * 0.36, h + 0.05, z + math.sin(a) * 0.36), c, nil, "Ball")
			end
			P(m, V(0.4, 0.4, 0.4), CF(x, h + 0.12, z), rgb(255, 225, 90), nil, "Ball")
		end
	elseif kind == "sunflower" then
		P(m, V(0.3, 5, 0.3), CF(0, 2.5, 0), rgb(70, 160, 60))
		P(m, V(0.3, 2.4, 2.4), CF(0, 5.4, 0) * ANG(0, rad(90), 0), accent, nil, "Cylinder")
		P(m, V(0.4, 1.1, 1.1), CF(0, 5.4, 0) * ANG(0, rad(90), 0), rgb(90, 60, 30), nil, "Cylinder")
		P(m, V(1.4, 0.1, 0.6), CF(0.6, 2.5, 0) * ANG(0, 0, rad(25)), rgb(70, 160, 60))
	elseif kind == "haybale" then
		solid(P(m, V(4, 3.6, 3.6), CF(0, 1.8, 0), rgb(225, 195, 95), "Fabric", "Cylinder"))
	elseif kind == "mushroom" then
		solid(cyl(m, 2.2, 1, V(0, 1.1, 0), rgb(240, 235, 220)))
		local cap = cyl(m, 0.9, 3.8, V(0, 2.6, 0), accent, "Neon")
		cyl(m, 0.5, 2.4, V(0, 3.2, 0), accent, "Neon")
		glow(cap, accent, 12)
	elseif kind == "cactus" then
		solid(cyl(m, 6, 1.5, V(0, 3, 0), leaf))
		P(m, V(1.6, 0.8, 0.8), CF(1.2, 3.2, 0), leaf, nil, "Cylinder")
		cyl(m, 2, 0.8, V(1.8, 4.1, 0), leaf)
		P(m, V(1.4, 0.8, 0.8), CF(-1.1, 2.2, 0), leaf, nil, "Cylinder")
		cyl(m, 1.6, 0.8, V(-1.6, 3, 0), leaf)
		P(m, V(0.6, 0.6, 0.6), CF(0, 6.2, 0), accent, nil, "Ball")
	elseif kind == "snowman" then
		solid(P(m, V(2.8, 2.8, 2.8), CF(0, 1.3, 0), rgb(250, 250, 255), "Snow", "Ball"))
		P(m, V(2.1, 2.1, 2.1), CF(0, 3.3, 0), rgb(250, 250, 255), "Snow", "Ball")
		P(m, V(1.5, 1.5, 1.5), CF(0, 4.8, 0), rgb(250, 250, 255), "Snow", "Ball")
		P(m, V(0.2, 0.2, 0.8), CF(0, 4.8, -0.9), rgb(255, 140, 40))
		cyl(m, 0.7, 1, V(0, 5.8, 0), DARK)
	elseif kind == "lollipop" then
		solid(cyl(m, 6, 0.4, V(0, 3, 0), rgb(255, 255, 255)))
		P(m, V(0.6, 4, 4), CF(0, 7.4, 0) * ANG(0, rad(90), 0), leaf, nil, "Cylinder")
		P(m, V(0.7, 2.4, 2.4), CF(0, 7.4, 0) * ANG(0, rad(90), 0), accent, nil, "Cylinder")
		P(m, V(0.8, 1, 1), CF(0, 7.4, 0) * ANG(0, rad(90), 0), rgb(255, 255, 255), nil, "Cylinder")
	elseif kind == "candycane" then
		for i = 0, 5 do
			solid(cyl(m, 1, 0.8, V(0, 0.5 + i, 0), i % 2 == 0 and accent or rgb(255, 255, 255)))
		end
		P(m, V(1.8, 0.8, 0.8), CF(0.7, 6.3, 0), accent, nil, "Cylinder")
		cyl(m, 1, 0.8, V(1.5, 5.7, 0), rgb(255, 255, 255))
	elseif kind == "gumdrop" then
		local cols = { leaf, accent, rgb(255, 220, 80), rgb(150, 230, 120) }
		local c = cols[rng:NextInteger(1, #cols)]
		local b = solid(cyl(m, 1.6, 3.2, V(0, 0.8, 0), c, "Glass"))
		b.Transparency = 0.15
		P(m, V(3.2, 3.2, 3.2), CF(0, 1.6, 0), c, "Glass", "Ball").Transparency = 0.15
	elseif kind == "spike" then
		local tilt = ANG(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, 3), rng:NextNumber(-0.2, 0.2))
		solid(P(m, V(2.2, 4, 2.2), CF(0, 2, 0) * tilt, trunk, "Basalt"))
		P(m, V(1.4, 3.5, 1.4), tilt * CF(0, 5.5, 0), trunk, "Basalt")
		local tip = P(m, V(0.7, 3, 0.7), tilt * CF(0, 8.5, 0), leaf, "Neon")
		glow(tip, leaf, 12)
	elseif kind == "barrel" then
		local tilt = ANG(0, rng:NextNumber(0, 3), rng:NextNumber(-0.25, 0.25))
		solid(P(m, V(3, 2.2, 2.2), CF(0, 1.5, 0) * tilt * ANG(0, 0, rad(90)), rgb(60, 80, 50), "Metal", "Cylinder"))
		local band = P(m, V(0.5, 2.3, 2.3), CF(0, 1.5, 0) * tilt * ANG(0, 0, rad(90)), accent, "Neon", "Cylinder")
		glow(band, accent, 10, 3)
	elseif kind == "crystal" then
		for i = 1, 3 do
			local c = i == 2 and accent or leaf
			local h = rng:NextNumber(3, 7)
			local p = solid(P(m, V(1.3, h, 1.3), CF((i - 2) * 1.3, h / 2 - 0.3, rng:NextNumber(-0.6, 0.6)) * ANG(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, 3), rng:NextNumber(-0.35, 0.35)), c, "Neon"))
			p.Transparency = 0.2
			if i == 2 then
				glow(p, c, 14)
			end
		end
	elseif kind == "star" then
		local y = rng:NextNumber(9, 18)
		local s = P(m, V(2.4, 0.5, 0.5), CF(0, y, 0), accent, "Neon")
		P(m, V(0.5, 2.4, 0.5), CF(0, y, 0), accent, "Neon")
		P(m, V(0.5, 0.5, 2.4), CF(0, y, 0), accent, "Neon")
		glow(s, accent, 18, 3)
	elseif kind == "pillar" then
		solid(P(m, V(3.4, 1, 3.4), CF(0, 0.5, 0), trunk, "Marble"))
		solid(cyl(m, 9, 2.2, V(0, 5.5, 0), trunk, "Marble"))
		P(m, V(3.4, 1, 3.4), CF(0, 10.5, 0), trunk, "Marble")
		local orb = P(m, V(1.6, 1.6, 1.6), CF(0, 12, 0), leaf, "Neon", "Ball")
		glow(orb, leaf, 16)
	end
	return m
end

return Models
