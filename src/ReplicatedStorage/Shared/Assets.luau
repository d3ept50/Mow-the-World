-- Imported 3D models (made in Blender, see /models in the repo).
--
-- Meshes cannot be synced by Rojo: each .fbx has to be imported once in Studio with the
-- 3D Importer and the resulting Model dragged into ReplicatedStorage > Assets. Until a
-- model is there, the game falls back to its part-built version, so nothing breaks.
--
-- Expected names in the Assets folder (capital letters don't matter):
--   mower            <- models/mower/mower.fbx      (the Basic Push Mower)
--   chest_common     <- models/chests/chest_common.fbx
--   chest_uncommon, chest_rare, chest_epic, chest_legendary
local RS = game:GetService("ReplicatedStorage")

local Assets = {}

-- Which imported model each mower id uses.
Assets.MOWERS = { Push = "mower" }

-- If an imported model faces the wrong way in game, turn it here (degrees, by asset name).
-- Models are expected to face Roblox "front" (-Z).
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
	local yaw = Assets.YAW[string.lower(name :: string)]
	if yaw then
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

function Assets.moveBy(model: Model, delta: Vector3)
	model:PivotTo(model:GetPivot() + delta)
end

return Assets
