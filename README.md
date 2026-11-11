# Mow the World

A Roblox mowing simulator. Players cut grass, sell it, buy better gear, collect workers, beat area bosses to unlock new islands, and rebirth for permanent bonuses.

## What's in this repo

| Folder | Contents |
|---|---|
| `src/` | Every script in the game, as `.luau` files |
| `docs/` | The design doc: game loop, areas, items, code layout, launch checklist |
| `models/` | 3D models made in Blender, with the scripts that build them |
| `default.project.json` | Tells Rojo where each `src` folder goes in the place |

## Scripts

`src/` mirrors the place:

| Folder | Goes to |
|---|---|
| `src/ServerScriptService` | ServerScriptService (`Main` and `Services`) |
| `src/ReplicatedStorage` | ReplicatedStorage (`Shared` and `Remotes`) |
| `src/StarterPlayerScripts` | StarterPlayer > StarterPlayerScripts (`Client`) |

Terrain and anything else in the place file is not in this repo.

### Working on scripts

1. Install [Rojo](https://rojo.space) 7.7 or newer, and its Studio plugin.
2. Get the latest changes: `git pull`
3. In this folder run `rojo serve`, then press **Connect** in the Rojo plugin in Studio.
4. Edit the `.luau` files. Rojo copies each save into Studio.
5. Share your changes: `git add -A`, `git commit -m "what changed"`, `git push`

Edit scripts in these files, not in Studio. While Rojo is connected it overwrites script edits made in Studio.

To pull scripts out of a saved place file instead (for example after editing in Studio):

```bash
rojo syncback --input Place3.rbxl
```

## Models

Each model folder has a Python build script, a `.blend` file, `.fbx` exports and preview images.

- `models/mower/` — low-poly push mower. Wheels and blade are separate meshes so they can spin.
- `models/mowers/` — the Electric, Petrol, Professional and Ride-On mowers, built by one script.
- `models/chests/` — five treasure chests (Common, Uncommon, Rare, Epic, Legendary). Each is a `Base` and a `Lid`; the lid pivots on its back hinge.

To rebuild a model after editing its script:

```bash
blender --background --factory-startup --python models/mower/build_mower.py
```

### Putting a model into the game

Rojo cannot sync meshes, so each model is imported once by hand:

1. In Studio, open **File > Import 3D** and pick the `.fbx`.
2. Import it as a single Model. Do not rename the parts inside it.
3. Drag the Model into **ReplicatedStorage > Assets**.
4. Make sure it has the right name (capital letters don't matter):

| File | Name in Assets | Used for |
|---|---|---|
| `models/mower/mower.fbx` | `mower` | Basic Push Mower |
| `models/mowers/mower_electric.fbx` | `mower_electric` | Electric Mower |
| `models/mowers/mower_petrol.fbx` | `mower_petrol` | Petrol Mower |
| `models/mowers/mower_pro.fbx` | `mower_pro` | Professional Mower |
| `models/mowers/mower_rideon.fbx` | `mower_rideon` | Ride-On Mower |
| `models/chests/chest_common.fbx` | `chest_common` | Common chest |
| `models/chests/chest_uncommon.fbx` | `chest_uncommon` | Uncommon chest |
| `models/chests/chest_rare.fbx` | `chest_rare` | Rare chest |
| `models/chests/chest_epic.fbx` | `chest_epic` | Epic chest |
| `models/chests/chest_legendary.fbx` | `chest_legendary` | Legendary chest |

5. Save the place. The game uses a model as soon as it is in the folder, and falls back to its part-built version when it is missing. The game sizes and places the model itself.

If a model faces the wrong way in game, set its angle in `Assets.YAW` in `src/ReplicatedStorage/Shared/Assets.luau`.

To use one in Studio, open the 3D Importer and pick the `.fbx`. Colours are stored as vertex colours, so leave each MeshPart's colour white. Models are sized so 1 Blender unit is 1 stud.
