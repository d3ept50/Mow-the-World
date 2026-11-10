-- Mow the World: server entry point. Each system lives in its own module under Services.
local Services = script.Parent.Services

local WorldBuilder = require(Services.WorldBuilder)
local Data = require(Services.Data)
local Character = require(Services.Character)
local Grass = require(Services.Grass)
local Crates = require(Services.Crates)
local Chests = require(Services.Chests)
local Boss = require(Services.Boss)
local Shop = require(Services.Shop)
local Monetization = require(Services.Monetization)
local Progress = require(Services.Progress)

WorldBuilder.build() -- static map first so players always have a spawn
Shop.init()
Data.init()
Character.init()
Monetization.init()
Boss.init()
Grass.setCrateForArea(Crates.forArea)
Grass.init()
Chests.init()
Progress.init()
print("[MowTheWorld] Server ready")
