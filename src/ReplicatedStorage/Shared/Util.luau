-- Shared helpers: number formatting, time formatting
local Util = {}

local SUF = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Util.fmt(n: number): string
	n = tonumber(n) or 0
	if n == math.huge then
		return "∞"
	end
	if n < 1000 then
		return tostring(math.floor(n + 0.5))
	end
	local i = math.min(#SUF, math.floor(math.log10(n) / 3) + 1)
	local v = n / 10 ^ ((i - 1) * 3)
	local s = string.format(v >= 100 and "%.0f" or v >= 10 and "%.1f" or "%.2f", v)
	return s .. SUF[i]
end

function Util.clock(sec: number): string
	sec = math.max(0, math.floor(sec))
	if sec >= 3600 then
		return string.format("%dh %02dm", sec // 3600, (sec % 3600) // 60)
	end
	return string.format("%d:%02d", sec // 60, sec % 60)
end

function Util.hex(c: Color3): string
	return string.format("#%02X%02X%02X", c.R * 255, c.G * 255, c.B * 255)
end

return Util
