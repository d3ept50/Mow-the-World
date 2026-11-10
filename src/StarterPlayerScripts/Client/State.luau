-- Client copy of the player's data (read only; the server is the source of truth).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Config = RS.Shared.Config
local Items = require(Config.Items)
local W = require(Config.Workers)
local Game = require(Config.Game)
local Areas = require(Config.Areas)
local Remotes = RS:WaitForChild("Remotes")

local player = Players.LocalPlayer
local State = { data = nil, listeners = {}, timeOffset = 0 }

function State.notify(_text, _kind) end -- replaced by Menus

function State.onChange(fn)
	table.insert(State.listeners, fn)
end

function State.now(): number
	return os.time() + State.timeOffset
end

function State.hasPass(key: string): boolean
	local p = State.data.passes or {}
	return p[key] == true or p.AllAccess == true
end

function State.boostLeft(name: string): number
	return math.max(0, (State.data.boosts[name] or 0) - State.now())
end

function State.ownsMower(id: string): boolean
	local def = Items.MowerById[id]
	if def.rebirth then
		return State.data.rebirths >= def.rebirth
	end
	return State.data.mowers[id] == true
end

function State.ownsVehicle(id: string): boolean
	local def = Items.VehicleById[id]
	if not def then
		return false
	end
	if def.pass then
		return State.hasPass(def.pass)
	end
	if def.rebirth then
		return State.data.rebirths >= def.rebirth
	end
	return State.data.vehicles[id] == true
end

function State.bagDef()
	local def = Items.BagById[State.data.bag] or Items.Bags[1]
	if State.hasPass("StartBag") and def.order < 3 then
		def = Items.Bags[3]
	end
	return def
end

function State.bagCapacity(): number
	local cap = State.bagDef().capacity
	local d = State.data
	if player:GetAttribute("Riding") and d.equippedVehicle ~= "" and State.ownsVehicle(d.equippedVehicle) then
		cap *= Items.VehicleById[d.equippedVehicle].storage
	end
	return cap
end

function State.slots(): number
	local d = State.data
	return W.BASE_SLOTS + Game.Rebirth.slots(d.rebirths) + (d.perks.slots or 0) + (State.hasPass("ExtraSlots") and 2 or 0)
end

function State.worker(uid)
	for _, inst in ipairs(State.data.workers) do
		if inst.uid == uid then
			return inst
		end
	end
	return nil
end

function State.isEquipped(uid): boolean
	return table.find(State.data.equipped, uid) ~= nil
end

function State.workerPower(inst): number
	return W.power(inst) * Game.Rebirth.workerMult(State.data.rebirths)
end

function State.workerHealth(inst): number
	return W.health(inst) * Game.Rebirth.workerMult(State.data.rebirths)
end

-- Grass milestones of an area: tiles cleared, rewards claimed, and the next goal (nil = all done).
function State.milestone(areaId: number)
	local p = State.data.progress[tostring(areaId)]
	local cut, ms = p and p.cut or 0, p and p.ms or 0
	return cut, ms, Areas.milestoneGoal(areaId, ms + 1), ms > 0 and Areas.milestoneGoal(areaId, ms) or 0
end

function State.action(name: string, ...)
	local ok, res, msg = pcall(Remotes.Action.InvokeServer, Remotes.Action, name, ...)
	if not ok then
		State.notify("⚠️ Couldn't reach the server. Please try again.", "bad")
		return false
	end
	if type(msg) == "string" then
		State.notify(msg, res and "good" or "bad")
	end
	return res, msg
end

function State.init()
	local buffer = {}
	local ready = false
	Remotes.DataSync.OnClientEvent:Connect(function(patch)
		if not ready then
			return
		end
		for k, v in pairs(patch) do
			State.data[k] = v
		end
		for _, fn in ipairs(State.listeners) do
			task.spawn(fn, patch)
		end
	end)
	local snap
	repeat
		local ok, good, s = pcall(Remotes.Action.InvokeServer, Remotes.Action, "Init")
		if ok and good and s then
			snap = s
		else
			task.wait(1)
		end
	until snap
	State.data = snap
	State.timeOffset = snap.serverTime - os.time()
	ready = true
	buffer = nil
end

return State
