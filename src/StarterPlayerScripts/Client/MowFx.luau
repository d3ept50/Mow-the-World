-- Mowing visuals and sounds for every player's equipped tool. Scissors snip their blades
-- and click; mowers and vehicles run an engine sound. It is driven by the "Mowing"
-- attribute the server sets on a player while their mower is landing hits.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local Game = require(RS.Shared.Config.Game)
local UI = require(script.Parent.UI)

local MowFx = {}
local ANG, rad = CFrame.Angles, math.rad

local SNIPS_PER_SEC = 3.2
-- degrees added to the angle each blade was built at
local BLADE_REST, BLADE_OPEN, BLADE_CLOSED = 0, 7, -8
local ENGINE_VOLUME = 0.45
local SNIP_VOLUME = 0.6

-- a click with scissors chops the right arm down and back up
local SWING_TIME = 0.24 -- seconds for the whole down-and-up
local SWING_ANGLE = 50 -- degrees the arm drops at the bottom

local rng = Random.new()
local tracked = {} -- [Player] = { tool, kind, blades = { { weld, base, side } }, sound, phase, closed, angle, nextScan, lastSwing }
local swings = {} -- [Player] = { t, joint, base } while an arm chop is playing

-- Starts (or restarts) the arm chop for a player holding scissors. The local player calls
-- this on every click; other players are started from their "Swing" attribute.
function MowFx.swing(player: Player)
	local entry = tracked[player]
	if not entry or entry.kind ~= "scissors" then
		return
	end
	local sw = swings[player]
	if sw then
		-- already chopping: if the arm is on its way up, send it back down from where it is
		if sw.t > SWING_TIME / 2 then
			sw.t = SWING_TIME - sw.t
		end
		return
	end
	local char = player.Character
	local arm = char and char:FindFirstChild("RightUpperArm")
	local joint = arm and arm:FindFirstChild("RightShoulder")
	if joint and joint:IsA("Motor6D") then
		swings[player] = { t = 0, joint = joint, base = joint.C0 }
	end
end

local function updateSwings(dt: number)
	for player, sw in pairs(swings) do
		sw.t += dt
		if sw.t >= SWING_TIME or not sw.joint.Parent then
			sw.joint.C0 = sw.base
			swings[player] = nil
		else
			local drop = SWING_ANGLE * math.sin(math.pi * sw.t / SWING_TIME)
			sw.joint.C0 = sw.base * ANG(-rad(drop), 0, 0)
		end
	end
end

local function makeSound(parent: Instance, id: string, looped: boolean): Sound
	local s = Instance.new("Sound")
	s.Name = "MowFx"
	s.SoundId = id
	s.Looped = looped
	s.Volume = looped and 0 or SNIP_VOLUME
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 12
	s.RollOffMaxDistance = 70
	s.Parent = parent
	return s
end

local function scanBlades(entry)
	table.clear(entry.blades)
	for _, d in ipairs(entry.tool:GetDescendants()) do
		if d:IsA("Weld") and d.Name == "BladeJoint" and d.Part1 then
			table.insert(entry.blades, { weld = d, base = d.C0, side = d.Part1:GetAttribute("Side") or 1 })
		end
	end
end

local function track(tool: Model)
	local root = tool.PrimaryPart
	if not root then
		return nil -- not fully loaded yet; try again next frame
	end
	local kind = tool.Name == "Vehicle" and "vehicle" or (tool:GetAttribute("Kind") or "push")
	local entry = { tool = tool, kind = kind, blades = {}, phase = 0, closed = false, angle = BLADE_REST, nextScan = 0 }
	-- which sound this kind of tool makes: Config.Game.MowSound
	local soundName = Game.MowSound[kind] or Game.MowSound.default
	if soundName == "snip" then
		scanBlades(entry)
		entry.sound = makeSound(root, Game.Sounds.snip, false)
	else
		local s = makeSound(root, Game.Sounds[soundName], true)
		-- loop only the steady middle of the recording, skipping its start-up and shut-down
		s.PlaybackRegionsEnabled = true
		s.PlaybackRegion = NumberRange.new(Game.MowLoop.from, Game.MowLoop.to)
		s.LoopRegion = NumberRange.new(Game.MowLoop.from, Game.MowLoop.to)
		entry.sound = s
	end
	return entry
end

local function scissors(entry, mowing: boolean, dt: number)
	if #entry.blades < 2 and os.clock() >= entry.nextScan then
		-- the blade joints can arrive a moment after the model does
		entry.nextScan = os.clock() + 0.5
		scanBlades(entry)
	end
	local angle = BLADE_REST
	if mowing then
		entry.phase += dt * SNIPS_PER_SEC * math.pi * 2
		local c = math.cos(entry.phase) -- 1 = fully open, -1 = fully closed
		angle = BLADE_CLOSED + (BLADE_OPEN - BLADE_CLOSED) * (c + 1) / 2
		if c < -0.9 and not entry.closed then
			entry.closed = true
			if UI.settings.sfx then
				entry.sound.PlaybackSpeed = rng:NextNumber(0.92, 1.15)
				entry.sound:Play()
			end
		elseif c > 0 then
			entry.closed = false
		end
	else
		entry.phase = 0
		entry.closed = false
	end
	if angle ~= entry.angle then
		entry.angle = angle
		for _, b in ipairs(entry.blades) do
			b.weld.C0 = b.base * ANG(0, rad(angle) * b.side, 0)
		end
	end
end

local function engine(entry, mowing: boolean, dt: number)
	local s = entry.sound
	local target = (mowing and UI.settings.sfx) and ENGINE_VOLUME or 0
	local volume = s.Volume + math.clamp(target - s.Volume, -dt * 1.5, dt * 2.5)
	if volume ~= s.Volume then
		s.Volume = volume
	end
	if volume > 0.01 then
		if not s.IsPlaying then
			s:Play()
		end
	elseif s.IsPlaying then
		s:Stop()
	end
end

local function update(dt: number)
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local tool = char and (char:FindFirstChild("Vehicle") or char:FindFirstChild("Mower"))
		local entry = tracked[player]
		if not tool then
			tracked[player] = nil
			continue
		end
		if not entry or entry.tool ~= tool then
			entry = track(tool)
			tracked[player] = entry
		end
		if entry then
			-- other players' clicks arrive as a counter that goes up by one each time
			local swingCount = player:GetAttribute("Swing")
			if swingCount ~= entry.lastSwing then
				if entry.lastSwing ~= nil and player ~= Players.LocalPlayer then
					MowFx.swing(player)
				end
				entry.lastSwing = swingCount
			end
			local mowing = player:GetAttribute("Mowing") == true
			if entry.kind == "scissors" then
				scissors(entry, mowing, dt)
			else
				engine(entry, mowing, dt)
			end
		end
	end
	updateSwings(dt)
end

function MowFx.init()
	RunService.Heartbeat:Connect(update)
	Players.PlayerRemoving:Connect(function(player)
		swings[player] = nil
		tracked[player] = nil
	end)
end

return MowFx
