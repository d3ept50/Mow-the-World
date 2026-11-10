-- Mow the World: client entry point.
local RS = game:GetService("ReplicatedStorage")
RS:WaitForChild("Shared")
RS:WaitForChild("Remotes")

local State = require(script.Parent.State)
local UI = require(script.Parent.UI)
local Menus = require(script.Parent.Menus)

State.init() -- waits for the server to load our data
Menus.init()
require(script.Parent.Panels)
local World = require(script.Parent.World)
World.init()

Menus.notify("🌿 Welcome to Mow the World! Walk through the Starter Meadow gate and start mowing.", "info")
if State.data.daily.last ~= State.now() // 86400 then
	task.delay(2.5, function()
		if not Menus.isOpen() then
			Menus.open("Daily", {})
		end
	end)
end
