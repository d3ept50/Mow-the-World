-- Imported 3D models (made in Blender, see /models in the repo).
--
-- Meshes cannot be synced by Rojo: each .fbx has to be imported once in Studio with the
-- 3D Importer and the resulting Model dragged into ReplicatedStorage > Assets. Until a
-- model is there, the game falls back to its part-built version, so nothing breaks.
--
-- Expected names in the Assets folder (capital letters don't matter):
--   mower            <- models/mower/mower.fbx      (the Basic Push Mower)
--   mower_electric, mower_petrol, mower_pro, mower_rideon   <- models/mowers/
--   chest_common     <- models/chests/chest_common.fbx
--   chest_uncommon, chest_rare, chest_epic, chest_legendary
local RS = game:GetService("ReplicatedStorage")

local Assets = {}

-- Which imported model each mower id uses.
Assets.MOWERS = {
	Push = "mower",
	Electric = "mower_electric",
	Petrol = "mower_petrol",
	Pro = "mower_pro",
	RideOn = "mower_rideon",
}

-- Imported mowers the player sits on instead of pushing. All numbers are in the model's
-- own studs, measured from the middle of the model on the ground, with +Z towards the back:
--   width  = full width across the rear wheels (the game sizes the model by this)
--   front  = distance from the middle to the front bumper
--   seat   = top of the seat cushion, where the player sits
--   wheel  = where the right hand holds the steering wheel (the left hand mirrors it)
--   scale  = the mower's look.scale in Config.Items at which the model is this size
Assets.RIDE = {
	mower_rideon = {
		width = 3.84,
		front = 2.83,
		seat = Vector3.new(0, 2.03, 1.0),
		wheel = Vector3.new(0.4, 2.74, -0.02),
		scale = 1.35,
	},
}

-- Blender exports arrive facing backwards (Roblox "front" is -Z), so every imported model
-- is turned half a turn. To turn one model differently, give its angle in degrees here.
Assets.DEFAULT_YAW = 180
Assets.YAW = {}

local function find(name: string): Instance?
	local folder = RS:FindFirstChild("Assets")
	if not folder then
		return nil
	end
	local want = string.lower(name)
	for _, child in ipairs(folder:GetChildren()) do
		if string.lower(child.Name) == want then
			return child
		end
	end
	return nil
end

-- A ready-to-place copy of an imported model, or nil if it has not been imported yet.
-- The copy stands upright at the origin, anchored, and does not collide with anything.
function Assets.clone(name: string?): Model?
	local source = name and find(name)
	if not source then
		return nil
	end
	local copy = source:Clone()
	local model: Model
	if copy:IsA("Model") then
		model = copy
	else
		model = Instance.new("Model")
		copy.Parent = model
	end
	local parts = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	if parts == 0 then
		model:Destroy()
		return nil
	end
	local yaw = Assets.YAW[string.lower(name :: string)] or Assets.DEFAULT_YAW
	if yaw ~= 0 then
		model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(yaw), 0))
	end
	return model
end

-- World-space bounding box (min corner, max corner) of a model or a single part.
function Assets.bounds(target: Instance): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	local function add(part: BasePart)
		local half = part.Size / 2
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local corner = part.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
					lo = lo:Min(corner)
					hi = hi:Max(corner)
				end
			end
		end
	end
	if target:IsA("BasePart") then
		add(target)
	end
	for _, d in ipairs(target:GetDescendants()) do
		if d:IsA("BasePart") then
			add(d)
		end
	end
	return lo, hi
end

-- Scales a model so its size along one axis ("X", "Y" or "Z") becomes `size` studs. This
-- makes the game independent of whatever scale the importer happened to use.
function Assets.fit(model: Model, axis: string, size: number)
	local lo, hi = Assets.bounds(model)
	local current = (hi - lo)[axis]
	if current > 0 then
		model:ScaleTo(model:GetScale() * size / current)
	end
end

-- Prints which imported models the game can see. Called once when the server starts, so
-- a missing or misnamed model shows up in the Output window.
function Assets.report()
	local folder = RS:FindFirstChild("Assets")
	if not folder then
		print("[Assets] ReplicatedStorage.Assets does not exist; using part-built models")
		return
	end
	local found = {}
	for _, child in ipairs(folder:GetChildren()) do
		local parts = child:IsA("BasePart") and 1 or 0
		for _, d in ipairs(child:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		table.insert(found, string.format("%s (%s, %d parts)", child.Name, child.ClassName, parts))
	end
	print("[Assets] in ReplicatedStorage.Assets: " .. (#found > 0 and table.concat(found, "; ") or "nothing"))
	local wanted = { "chest_common", "chest_uncommon", "chest_rare", "chest_epic", "chest_legendary" }
	for _, name in pairs(Assets.MOWERS) do
		table.insert(wanted, name)
	end
	local missing = {}
	for _, name in ipairs(wanted) do
		if not find(name) then
			table.insert(missing, name)
		end
	end
	if #missing > 0 then
		print("[Assets] not found, so part-built versions are used: " .. table.concat(missing, ", "))
	end
end

function Assets.moveBy(model: Model, delta: Vector3)
	model:PivotTo(model:GetPivot() + delta)
end

return Assets
