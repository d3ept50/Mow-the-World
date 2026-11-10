-- Achievements and the marketplace leaderboards.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local Game = require(RS.Shared.Config.Game)
local W = require(RS.Shared.Config.Workers)
local Util = require(RS.Shared.Util)
local Data = require(script.Parent.Data)

local Progress = {}
local LB_REFRESH = 90
local byStat = {}
for _, a in ipairs(Game.Achievements) do
	byStat[a.stat] = byStat[a.stat] or {}
	table.insert(byStat[a.stat], a)
end

local function checkAchievements(player, key, value)
	local list = byStat[key]
	if not list then
		return
	end
	local pr = Data.get(player)
	for _, a in ipairs(list) do
		local tier = pr.achievements[a.id] or 0
		local changed = false
		while tier < #a.tiers and value >= a.tiers[tier + 1] do
			tier += 1
			changed = true
			pr.achievements[a.id] = tier
			local d = Data.addDiamonds(player, a.reward * tier, true)
			Data.notify(player, "🏆 Achievement: " .. a.name .. " " .. string.rep("⭐", tier) .. "  +" .. d .. " 💎", "big")
			if tier == #a.tiers and a.title then
				Data.addTitle(player, a.title)
			end
		end
		if changed then
			Data.sync(player, "achievements")
		end
	end
end

---------------------------------------------------------------- leaderboards
local boards = {} -- [statKey] = { rows = {TextLabel}, store = OrderedDataStore? }
local nameCache = {}
local localOnly = false

local function statValue(player, key)
	local pr = Data.get(player)
	if not pr then
		return 0
	end
	if key == "workerPower" then
		local total = 0
		for _, inst in ipairs(pr.workers) do
			total += W.power(inst)
		end
		return total
	end
	return pr.stats[key] or 0
end

local function nameOf(userId)
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	name = ok and name or ("Player " .. userId)
	nameCache[userId] = name
	return name
end

local function buildBoard(part)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.LightInfluence = 0
	sg.Parent = part
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.12, 0)
	title.BackgroundColor3 = Color3.fromRGB(250, 200, 50)
	title.BorderSizePixel = 0
	title.Text = part:GetAttribute("Title") or part.Name
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.TextColor3 = Color3.fromRGB(40, 30, 10)
	title.Parent = sg
	local rows = {}
	for i = 1, 10 do
		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(1, -16, 0.08, 0)
		row.Position = UDim2.new(0, 8, 0.13 + (i - 1) * 0.086, 0)
		row.BackgroundColor3 = i % 2 == 0 and Color3.fromRGB(45, 45, 58) or Color3.fromRGB(55, 55, 70)
		row.BorderSizePixel = 0
		row.Text = ""
		row.TextScaled = true
		row.Font = Enum.Font.GothamBold
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = i == 1 and Color3.fromRGB(255, 215, 80) or i == 2 and Color3.fromRGB(210, 215, 225) or i == 3 and Color3.fromRGB(225, 150, 90) or Color3.fromRGB(240, 240, 240)
		row.Parent = sg
		rows[i] = row
	end
	return rows
end

local function refreshBoard(key, board)
	local entries
	if not localOnly and board.store then
		local ok = pcall(function()
			for _, player in ipairs(Players:GetPlayers()) do
				local v = math.floor(math.min(statValue(player, key), 9e15))
				if v > 0 and Data.get(player) then
					board.store:SetAsync(tostring(player.UserId), v)
				end
			end
			local page = board.store:GetSortedAsync(false, 10):GetCurrentPage()
			entries = {}
			for _, e in ipairs(page) do
				table.insert(entries, { name = nameOf(tonumber(e.key)), value = e.value })
			end
		end)
		if not ok then
			entries = nil
			if RunService:IsStudio() then
				localOnly = true
			end
		end
	end
	if not entries then
		entries = {}
		for _, player in ipairs(Players:GetPlayers()) do
			table.insert(entries, { name = player.Name, value = statValue(player, key) })
		end
		table.sort(entries, function(a, b)
			return a.value > b.value
		end)
	end
	for i, row in ipairs(board.rows) do
		local e = entries[i]
		row.Text = e and string.format("  #%d  %s  —  %s", i, e.name, Util.fmt(e.value)) or string.format("  #%d  ---", i)
	end
end

function Progress.init()
	Data.onStat(checkAchievements)
	for _, part in ipairs(CollectionService:GetTagged("Leaderboard")) do
		local store
		pcall(function()
			store = DataStoreService:GetOrderedDataStore("MTW_LB_" .. part.Name)
		end)
		boards[part.Name] = { rows = buildBoard(part), store = store }
	end
	task.spawn(function()
		task.wait(8)
		while true do
			for key, board in pairs(boards) do
				refreshBoard(key, board)
				task.wait(1)
			end
			task.wait(LB_REFRESH)
		end
	end)
end

return Progress
