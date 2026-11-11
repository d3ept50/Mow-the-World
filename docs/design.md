# Mow the World

A Roblox mowing simulator built in Place3.rbxl (local, unpublished). Players cut grass, sell it, buy better gear, collect workers, beat area bosses to unlock new islands, and rebirth for permanent bonuses.

## Status (10 Nov 2026)

**Working, tested in play mode:** daily reward, mowing, selling, crate opening, equipping workers, bag purchase, area 1 boss fight, unlocking area 2, bridges, locked gates. No console errors.

**Before launch:**
1. **Save the place in Studio (Ctrl+S).** The rework was done in the open session.
2. **Publish and enable Studio access to API services** (Game Settings → Security). Until then profiles load with `noSave = true` and nothing is saved.
3. **Create gamepasses and developer products** in the Creator Dashboard and paste their ids into `Config.Game` (`G.Passes`, `G.Products`). All ids are 0 now.

**Untested:** vehicles, rebirth, bosses and balance from area 3 onward, multiplayer, mobile and console controls.

**Possible polish:** grass is still flat 6-stud tiles; mower and vehicle models are basic parts.

## Core loop

1. Walk over a bridge into an unlocked area. The equipped mower cuts grass automatically around the player.
2. Grass fills the bag. Sell at a 💰 pad (one per area, one in the marketplace) or with Auto Sell.
3. Spend cash on mowers, bags, vehicles and worker crates.
4. Find treasure chests hidden under the grass.
5. Equipped workers follow the player, mow nearby grass and fight bosses.
6. Beat the area boss to unlock the next area. Clearing 100% of the grass does not unlock anything.
7. Spend diamonds to rebirth.

## Map

- An archipelago: a central town island (660 studs wide, `Areas.MARKET_HALF`) and twelve 400-stud area islands around it on a 4×4 grid. Area islands sit 520 studs apart with 120 studs of sea between them; the town is smaller than its cell, so its eight bridges are 250 studs long.
- Wooden bridges join the marketplace to its neighbours and each area to the next. A locked gate (force field) stands at the far end of each bridge until the previous boss is beaten.
- Each area has a 30×30 grass field (6-stud tiles) with a 10×10 hole in the middle: the boss plaza, a paved square with four glowing obelisks where the boss stands. No grass grows on the plaza (`Areas.tileExists`), so each area has 800 tiles.
- There are no fences. Each area is ringed by its own edge (`EDGES` in WorldBuilder): rock cliffs whose colour, height, caps, lava cracks or crystals change with the theme, or high walls with battlements and towers. An invisible barrier inside the edge keeps players in; the only gaps are the bridges.
- The marketplace is a paved cartoon town inside a 48-stud town wall with big round towers: the fountain, nine shops in a ring, four diagonal streets that each fork to two bridges, about a hundred pastel houses with bright roofs, trees in stone planters, lamps, benches and bunting. It has no NPCs, no signposts round the fountain and almost no grass.
- A castle (`Scenery.castle`) stands at the north end of town, at the end of an avenue from the plaza. It is scenery only: an invisible wall all the way round keeps players out.
- Terrain (islands, beaches, sea) is baked into the place file and only re-bakes when `LAYOUT_VERSION` in WorldBuilder changes. Smooth terrain renders 2 studs above the filled volume, so islands are filled to y = -2.3 and parts are built at y = 0.
- Everything else is rebuilt by `WorldBuilder.build()` on every server start.

## Areas

Grass HP = 5 × 5^(n−1). Grass value = 4^(n−1). Boss HP = grass HP × 120, boss cash = value × 1,500, boss diamonds = 5 + 3n.

| # | Area | Boss | Landmark |
|---|---|---|---|
| 1 | Starter Meadow | Dandelion Brute | Red barn and silo |
| 2 | Sunny Fields | Sunflower Titan | Windmill |
| 3 | Enchanted Forest | Elder Treant | Giant tree house |
| 4 | Desert Dunes | Scorpion King | Pyramid |
| 5 | Snowy Mountains | Frost Yeti | Snowy peak and igloo |
| 6 | Candy Kingdom | Gummy Golem | Candy castle |
| 7 | Volcanic Lands | Magma Lord | Volcano |
| 8 | Toxic Swamp | Sludge Hydra | Witch hut on stilts |
| 9 | Crystal Valley | Crystal Colossus | Crystal spires |
| 10 | Galaxy Fields | Nebula Wraith | Ringed planet |
| 11 | Divine Gardens | Seraph Guardian | Marble temple |
| 12 | Cosmic Dimension | Void Emperor | Void portal |

- **Grass rewards:** clearing 250 / 500 / 1,000 / 2,000 grass tiles in area 1 pays 150 / 400 / 900 / 2,500 × grass value; the last one also gives a crate. Each later area needs 50% more grass (area 2: 375, 750, 1,500, 3,000). Settings are in `Config.Areas` (`MILESTONES`, `MILESTONE_GROWTH`).
- **Regrowth:** grass regrows after 16 seconds.
- **Boss fights:** walking onto the boss plaza in the middle of an area opens a prompt: Solo, Invite friends (everyone on the server who has the area unlocked gets 15 seconds to join) or Exit. Each fight gets its own arena, built far from the islands, and its players are teleported there and back. Fights last 120 seconds and each extra player adds 60% boss HP.
- **Boss attacks:** the boss walks around the arena and repeats its own attack sequence (`BOSS_MOVES` and `Areas.Moves` in `Config.Areas`). Attacks only hit workers, never players. Boss attack = 6 × grass value per hit.
- **Worker health:** 10 × power. A worker at 0 health is knocked out until the fight ends.
- **Teleport:** the Teleport menu jumps to the marketplace or any unlocked area (3 second cooldown).

## Items

- **Mowers (20):** Scissors, Garden Shears, Push, Electric, Petrol, Professional, Ride-On, Zero-Turn, Commercial, Industrial, Mega. Rebirth-only: Golden (R1), Diamond (R2), Plasma (R3), Toxic (R5), Inferno (R7), Galaxy (R10), Rainbow (R15), Divine (R20), Cosmic Mega (R30). Each has damage, speed, radius, efficiency, price and area requirement.
- **Bags (9):** Tiny 25 → Small 100 → Medium 400 → Large 1.5K → Huge 6K → Massive 25K → Professional 100K → Industrial 500K → Infinite.
- **Vehicles (10):** Lawn Tractor, Ride-On, Buggy, Pro Tractor, Heavy-Duty, Industrial Machine, Mega Vehicle. Rebirth: Phoenix Cruiser (R3), Starship (R8). Gamepass: Royal Limo-Mower. Each has speed, damage multiplier, radius and storage multiplier. Toggle with the 🚜 Ride button.

## Workers and crates

- **Workers:** 24 across 8 rarities (Common, Uncommon, Rare, Epic, Legendary, Mythic, Secret, Divine). Higher rarities glow and have particles.
- **Upgrades:** level up with cash (max level 25), add stars with diamonds (max 3 stars).
- **Inventory:** holds 250. Players can lock, delete, sort by power or rarity, and use Equip Best.
- **Slots:** 3 base, plus rebirth milestones, the diamond shop (+2) and a gamepass (+2).
- **Crates (6):** Basic, Grass, Golden, Mythic, Secret, Divine. They have area requirements and show odds before opening. Players can open 1 or 3, Auto Open, or use crates they already own. A rarity-coloured reveal animation plays on opening. Crates also come from chests, bosses, milestones and daily rewards.

## Chests, diamonds, rebirth

- **Chests:** 4 per area, respawning after 40 seconds. Rarities Common to Legendary. They give cash, plus diamonds, boosts, crates or workers at higher rarities.
- **Diamonds:** come from bosses, rare chests, achievements, daily rewards and Robux. Never from area completion.
- **Diamond shop:** permanent Auto Sell, +1 worker slot (×2), 15-minute boosts (cash, speed, luck), Mythic and Secret crates.
- **Rebirth** (Rebirth Shrine):
  - Cost 40 + 30n + 5n² diamonds. Requires area min(12, 4 + n).
  - Resets cash, areas, mowers, bags, vehicles and grass progress.
  - Keeps diamonds, workers, crates, titles, perks, stats and passes.
  - Bonuses: cash ×(1 + 0.5n), power ×(1 + 0.5n), worker damage ×(1 + 0.25n), +1 worker slot at R2, R5 and R10.
  - Titles at R1, R5, R10 and R25.

## Progression extras

- **Daily rewards:** 7-day streak. Rewards in order: cash, 5 diamonds, crate, 2× cash for 15 minutes, 15 diamonds, 3 crates, 40 diamonds plus a title.
- **Achievements (10, tiered):** grass cut, cash earned, chests, bosses, areas, rebirths, crates opened, rare / legendary / secret workers found. They reward diamonds and titles.
- **Leaderboards (OrderedDataStore):** grass, cash, bosses, rebirths, diamonds, worker power.

## Robux

- **Gamepasses:** VIP, 2× Cash, 2× Grass, Auto Sell, Faster Mowing, Extra Worker Slots, Bigger Starting Bag, Premium Vehicle Pack, 2× Diamonds, All Access.
- **Developer products:** three cash packs (scaled to the player's best area), 100 / 600 / 3,000 diamonds, and 30-minute cash, speed and luck boosts.
- **Purchase handling:** passes are checked with `UserOwnsGamePassAsync`. Products go through `ProcessReceipt`, which keeps a receipt log so a purchase can't be granted twice.

## Code layout

```
ServerScriptService
  Main                 boots every service in order
  Services/
    Data               profiles, DataStore (UpdateAsync), 120s autosave, BindToClose, leaderstats
    WorldBuilder       terrain, bridges, gates, cliffs and walls, areas, town, lighting
    Scenery            12 landmarks + cartoon town houses
    Grass              grass grid, server-side mowing, bag, selling, milestones, regrowth
    Crates             crate rolls and opening
    Chests             hidden chests and rewards
    Boss               arenas, fights, attacks, rewards
    Character          held mower, vehicles, walk speed (base 20)
    Shop               single Action RemoteFunction: validates and runs every request
    Monetization       gamepasses and receipts
    Progress           achievements, leaderboards
ReplicatedStorage
  Shared/Config/       Areas, Items, Workers, Game   (all tunable numbers live here)
  Shared/Models        procedural models: workers, mowers, vehicles, crates, bosses, props
  Shared/Util
  Remotes/             Action (RemoteFunction); DataSync, Notify, GrassFx, Gain, Milestone, ChestFx, BossFx
StarterPlayerScripts/Client
  Main, State          startup, local copy of player data
  UI                   theme, buttons, bars, sounds, 3D previews
  Menus                HUD, notifications, menu framework
  Panels               contents of every menu, crate reveal
  World                gates, sky per area, animations, effects, worker followers
```

The UI is built in code (ScreenGui `MowUI`), so StarterGui is empty by design.

## Security

- The server does all mowing, damage, rewards and currency. The client never reports what it cut.
- Every `Action` call is rate-limited (8 per second, burst of 16) and type-checked.
- Shop purchases require the player to be near the right shop.
- Crate, chest, boss and receipt rewards are granted only by the server.

## Adding content

- **New area:** append to `DEFS` in `Config.Areas`, give it a free cell in `RING` (widen the grid if needed), add a landmark function in `Scenery`, and bump `LAYOUT_VERSION` in WorldBuilder.
- **Mowers, bags, vehicles:** append to the lists in `Config.Items`.
- **Workers, crates:** add them in `Config.Workers`.
- **Achievements, daily rewards, diamond shop, passes:** edit `Config.Game`.
