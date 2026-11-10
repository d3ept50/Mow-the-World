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
- `models/chests/` — five treasure chests (Common, Uncommon, Rare, Epic, Legendary). Each is a `Base` and a `Lid`; the lid pivots on its back hinge.

To rebuild a model after editing its script:

```bash
blender --background --factory-startup --python models/mower/build_mower.py
```

To use one in Studio, open the 3D Importer and pick the `.fbx`. Colours are stored as vertex colours, so leave each MeshPart's colour white. Models are sized so 1 Blender unit is 1 stud.
