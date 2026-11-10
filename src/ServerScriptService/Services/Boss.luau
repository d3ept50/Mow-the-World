-- Boss battles. One boss per area; solo or multiplayer (health scales with participants).
-- All damage and rewards are calculated on the server.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")

local Areas = require(RS.Shared.Config.Areas)
local Util = require(RS.Shared.Util)
local Models = require(RS.Shared.Models)
local Data = require(script.Parent.Data)
local Crates = require(script.Parent.Crates)
local Remotes = RS.Remotes

local Boss = {}
local fights = {}
local rng = Random.new()
local folder

local FIGHT_TIME = 120
local LEAVE_RANGE = 95
local EXTRA_PLAYER_HP = 0.6
local R = Areas.ARENA_RADIUS
local V, CF, ANG, rad = Vector3.new, CFrame.new, CFrame.Angles, math.rad

local function hrpOf(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		return char:FindFirstChild("HumanoidRootPart"), hum
	end
	return nil
end

local function setHealth(f)
	local hp = math.max(0, f.hp)
	f.model:SetAttribute("Health", hp)
	f.model:SetAttribute("MaxHealth", f.maxHp)
	f.fill.Size = UDim2.fromScale(math.clamp(hp / f.maxHp, 0, 1), 1)
	f.hpText.Text = Util.fmt(hp) .. " / " .. Util.fmt(f.maxHp)
end

local function tween(f, cf, t, style, dir)
	local tw = TweenService:Create(f.model.PrimaryPart, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), { CFrame = cf })
	tw:Play()
	return tw
end

local function hurt(f, center, radius, dmg)
	for player in pairs(f.participants) do
		local hrp, hum = hrpOf(player)
		if hrp then
			local d = hrp.Position - center
			if d.X * d.X + d.Z * d.Z <= radius * radius then
				hum:TakeDamage(dmg)
			end
		end
	end
end

local function attack(f, n)
	local a = Areas.List[f.areaId]
	local home = f.home
	local rootHome = home * CF(0, 0.5, 0)
	local kind = ({ "slam", "target", "spin" })[(n - 1) % 3 + 1]
	local base = a.bossPos + V(0, 0.7, 0)
	if kind == "slam" then
		Remotes.BossFx:FireAllClients("attack", f.areaId, "slam", base, 17, 0.8)
		tween(f, rootHome * CF(0, 11, 0), 0.55)
		task.wait(0.55)
		tween(f, rootHome, 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.wait(0.25)
		if f.active then
			hurt(f, base, 17, 30)
		end
	elseif kind == "target" then
		local list = {}
		for player in pairs(f.participants) do
			local hrp = hrpOf(player)
			if hrp then
				table.insert(list, hrp.Position)
			end
		end
		if #list == 0 then
			return
		end
		local p = list[rng:NextInteger(1, #list)]
		local pos = V(p.X, base.Y, p.Z)
		Remotes.BossFx:FireAllClients("attack", f.areaId, "target", pos, 9, 1.3)
		tween(f, rootHome * ANG(rad(-18), 0, 0), 0.5)
		task.wait(0.9)
		tween(f, rootHome * ANG(rad(14), 0, 0), 0.2)
		task.wait(0.4)
		if f.active then
			hurt(f, pos, 9, 35)
			tween(f, rootHome, 0.3)
		end
	else
		Remotes.BossFx:FireAllClients("attack", f.areaId, "spin", base, 14, 0.9)
		task.wait(0.4)
		tween(f, rootHome * ANG(0, rad(179), 0), 0.25, Enum.EasingStyle.Linear)
		task.wait(0.25)
		tween(f, rootHome * ANG(0, rad(358), 0), 0.25, Enum.EasingStyle.Linear)
		task.wait(0.25)
		if f.active then
			hurt(f, base, 14, 22)
			f.model.PrimaryPart.CFrame = rootHome
		end
	end
end

local function reward(player, areaId)
	local pr = Data.get(player)
	if not pr then
		return
	end
	local a = Areas.List[areaId]
	local B = a.boss
	local key = tostring(areaId)
	local parts = {}
	local cash = math.floor(B.cash * Data.cashMult(player))
	Data.addCash(player, cash, true)
	table.insert(parts, "+$" .. Util.fmt(cash))
	local first = not pr.bossKills[key]
	local dia = first and math.floor(B.diamonds * (1 + 0.25 * pr.rebirths)) or math.max(1, math.floor(B.diamonds * 0.2))
	dia = Data.addDiamonds(player, dia, true)
	table.insert(parts, "+" .. dia .. " 💎")
	pr.bossKills[key] = true
	Data.addStat(player, "bosses", 1)
	if first or rng:NextNumber() < 0.4 then
		local crateId = Crates.forArea(areaId)
		Data.addCrate(player, crateId, 1)
		table.insert(parts, crateId .. " Crate")
	end
	if rng:NextNumber() < 0.05 then
		local w = Crates.roll(Crates.forArea(areaId), 3)
		if Data.addWorker(player, w.id) then
			table.insert(parts, "Worker: " .. w.name)
		end
	end
	Data.notify(player, "⚔️ " .. B.name .. " defeated! " .. table.concat(parts, ", "), "big")
	if pr.areasUnlocked == areaId and areaId < Areas.COUNT then
		pr.areasUnlocked = areaId + 1
		Data.setStatMax(player, "maxArea", areaId + 1)
		Data.notify(player, "🔓 New area unlocked: " .. Areas.List[areaId + 1].name .. "!", "big")
	elseif areaId == Areas.COUNT and first then
		Data.notify(player, "🌍 You conquered every area! Visit the Rebirth Shrine for permanent bonuses.", "big")
	end
	Data.sync(player, "areasUnlocked", "bossKills", "workers", "equipped")
end

local function finish(f, won)
	f.active = false
	f.model:SetAttribute("Active", false)
	local a = Areas.List[f.areaId]
	local parts = f.participants
	f.participants = {}
	for player, dealt in pairs(parts) do
		if player.Parent then
			player:SetAttribute("BossArea", 0)
			if won and dealt > 0 then
				reward(player, f.areaId)
			end
			Remotes.BossFx:FireClient(player, won and "win" or "fail", f.areaId)
		end
	end
	if won then
		Remotes.BossFx:FireAllClients("defeat", f.areaId, a.bossPos + V(0, a.boss.size * 0.6, 0))
		f.cooldown = os.clock() + 9
		tween(f, f.home * CF(0, -a.boss.size * 1.8, 0) * ANG(0, rad(170), rad(60)), 1.5, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.wait(1.6)
		f.model.Parent = nil
		task.wait(7)
		f.model:PivotTo(f.home)
		f.model.Parent = folder
	else
		f.cooldown = os.clock() + 3
		task.wait(0.6)
		f.model:PivotTo(f.home)
	end
	f.maxHp = a.boss.hp
	f.hp = f.maxHp
	setHealth(f)
end

local function run(f)
	local a = Areas.List[f.areaId]
	local bossPos = a.bossPos
	local nextAttack = os.clock() + 3
	local nextWorkers = os.clock() + 1
	local attackN = 0
	while f.active do
		task.wait(0.2)
		local now = os.clock()
		local n = 0
		for player in pairs(f.participants) do
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not player.Parent or not hrp or (hrp.Position - bossPos).Magnitude > LEAVE_RANGE then
				f.participants[player] = nil
				if player.Parent then
					player:SetAttribute("BossArea", 0)
					Remotes.BossFx:FireClient(player, "fail", f.areaId)
				end
			else
				n += 1
			end
		end
		if n == 0 or now >= f.endsAt then
			finish(f, false)
			break
		end
		local doWorkers = now >= nextWorkers
		if doWorkers then
			nextWorkers = now + 1
		end
		for player, dealt in pairs(f.participants) do
			local add = 0
			local hrp = hrpOf(player)
			if Data.get(player) then
				if doWorkers and hrp then
					for _, d in ipairs(Data.workerDamages(player)) do
						add += d
					end
				end
				if hrp and (hrp.Position - bossPos).Magnitude <= R + 12 and now >= (f.nextHit[player] or 0) then
					local s = Data.mowStats(player)
					f.nextHit[player] = now + 1 / s.speed
					add += s.damage
				end
			end
			if add > 0 then
				f.participants[player] = dealt + add
				f.hp -= add
				Remotes.BossFx:FireClient(player, "dmg", f.areaId, add)
			end
		end
		setHealth(f)
		if f.hp <= 0 then
			finish(f, true)
			break
		end
		if now >= nextAttack then
			nextAttack = now + 4.5
			attackN += 1
			task.spawn(attack, f, attackN)
		end
	end
end

local function join(f, player)
	local pr = Data.get(player)
	if not pr or f.participants[player] then
		return
	end
	local a = Areas.List[f.areaId]
	if pr.areasUnlocked < f.areaId then
		Data.notify(player, "🔒 Unlock " .. a.name .. " first.", "bad")
		return
	end
	if (player:GetAttribute("BossArea") or 0) ~= 0 then
		return
	end
	local base = a.boss.hp
	if not f.active then
		if f.cooldown and os.clock() < f.cooldown then
			Data.notify(player, "The boss is recovering... try again in a moment.", "info")
			return
		end
		f.active = true
		f.participants = { [player] = 0 }
		f.nextHit = {}
		f.maxHp = base
		f.hp = base
		f.endsAt = os.clock() + FIGHT_TIME
		f.model:SetAttribute("Active", true)
		f.model:SetAttribute("EndsAt", workspace:GetServerTimeNow() + FIGHT_TIME)
		setHealth(f)
		player:SetAttribute("BossArea", f.areaId)
		task.spawn(run, f)
	else
		f.participants[player] = 0
		f.maxHp += base * EXTRA_PLAYER_HP
		f.hp += base * EXTRA_PLAYER_HP
		setHealth(f)
		player:SetAttribute("BossArea", f.areaId)
	end
	Remotes.BossFx:FireClient(player, "start", f.areaId)
end

function Boss.init()
	folder = Instance.new("Folder")
	folder.Name = "Bosses"
	folder.Parent = workspace
	local arenas = Instance.new("Folder")
	arenas.Name = "Arenas"
	arenas.Parent = workspace
	for areaId, a in ipairs(Areas.List) do
		local B = a.boss
		local pos = a.bossPos
		local disc = Models.P(arenas, V(1.2, R * 2, R * 2), CF(pos + V(0, 0.1, 0)) * ANG(0, 0, rad(90)), Color3.fromRGB(45, 42, 50), "Slate", "Cylinder")
		disc.CanCollide = true
		disc.CanQuery = true
		local ring = Models.P(arenas, V(0.5, R * 2 + 3, R * 2 + 3), CF(pos + V(0, 0.15, 0)) * ANG(0, 0, rad(90)), B.color2, "Neon", "Cylinder")
		ring.CanCollide = false
		for i = 0, 5 do
			local ang = rad(i * 60 + 30)
			local pp = pos + V(math.sin(ang) * (R + 0.5), 0, math.cos(ang) * (R + 0.5))
			local pillar = Models.cyl(arenas, 9, 1.8, pp + V(0, 4.5, 0), a.wall, "Slate")
			pillar.CanCollide = true
			local orb = Models.P(arenas, V(2, 2, 2), CF(pp + V(0, 10, 0)), B.color2, "Neon", "Ball")
			Models.glow(orb, B.color2, 16)
		end

		local model = Models.boss(areaId)
		Models.weld(model)
		local toCenter = (a.center - pos).Unit
		local home = CFrame.lookAt(pos + V(0, 0.7, 0), pos + V(0, 0.7, 0) + toCenter)
		model:PivotTo(home)
		model.Name = tostring(areaId)
		model:SetAttribute("Active", false)
		model:SetAttribute("BossName", B.name)

		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromScale(20, 5)
		bb.StudsOffset = V(0, B.size * 1.75 + 2, 0)
		bb.MaxDistance = 260
		bb.LightInfluence = 0
		bb.Adornee = model.PrimaryPart
		local name = Instance.new("TextLabel")
		name.Size = UDim2.fromScale(1, 0.55)
		name.BackgroundTransparency = 1
		name.Text = "💀 " .. B.name
		name.TextScaled = true
		name.Font = Enum.Font.FredokaOne
		name.TextColor3 = Color3.fromRGB(255, 255, 255)
		name.TextStrokeTransparency = 0.2
		name.Parent = bb
		local bar = Instance.new("Frame")
		bar.Size = UDim2.fromScale(1, 0.38)
		bar.Position = UDim2.fromScale(0, 0.6)
		bar.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
		bar.BorderSizePixel = 0
		bar.Parent = bb
		Instance.new("UICorner", bar).CornerRadius = UDim.new(0.4, 0)
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = Color3.fromRGB(235, 60, 70)
		fill.BorderSizePixel = 0
		fill.Parent = bar
		Instance.new("UICorner", fill).CornerRadius = UDim.new(0.4, 0)
		local hpText = Instance.new("TextLabel")
		hpText.Size = UDim2.fromScale(1, 1)
		hpText.BackgroundTransparency = 1
		hpText.TextScaled = true
		hpText.Font = Enum.Font.FredokaOne
		hpText.TextColor3 = Color3.fromRGB(255, 255, 255)
		hpText.TextStrokeTransparency = 0.3
		hpText.ZIndex = 2
		hpText.Parent = bar
		bb.Parent = model.PrimaryPart
		model.Parent = folder

		local stand = Models.P(arenas, V(2.2, 3, 2.2), CF(pos + toCenter * (R - 2) + V(0, 2.2, 0)) * ANG(0, rad(45), 0), Color3.fromRGB(255, 205, 70), "Neon")
		stand.Transparency = 0.25
		stand.Name = "BossPrompt" .. areaId
		local sb = Instance.new("BillboardGui")
		sb.Size = UDim2.fromScale(9, 1.8)
		sb.StudsOffset = V(0, 4, 0)
		sb.MaxDistance = 120
		sb.Parent = stand
		local st = name:Clone()
		st.Size = UDim2.fromScale(1, 1)
		st.Text = "⚔️ FIGHT BOSS"
		st.TextColor3 = Color3.fromRGB(255, 220, 90)
		st.Parent = sb
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Fight!"
		prompt.ObjectText = B.name
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 16
		prompt.RequiresLineOfSight = false
		prompt.Parent = stand

		local f = { areaId = areaId, model = model, home = home, active = false, participants = {}, nextHit = {}, maxHp = B.hp, hp = B.hp, fill = fill, hpText = hpText }
		fights[areaId] = f
		setHealth(f)
		prompt.Triggered:Connect(function(player)
			join(f, player)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		for _, f in pairs(fights) do
			f.participants[player] = nil
		end
	end)
end

return Boss
