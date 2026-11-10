# Mow the World

A Roblox mowing simulator. Players cut grass, sell it, buy better gear, collect workers, beat area bosses to unlock new islands, and rebirth for permanent bonuses.

## What's in this repo

| Folder | Contents |
|---|---|
| `docs/` | The design doc: game loop, areas, items, code layout, launch checklist |
| `models/` | 3D models made in Blender, with the scripts that build them |

The game's scripts are not here yet. They will go in `src/` and sync into Roblox Studio with [Rojo](https://rojo.space).

## Models

Each model folder has a Python build script, a `.blend` file, `.fbx` exports and preview images.

- `models/mower/` — low-poly push mower. Wheels and blade are separate meshes so they can spin.
- `models/chests/` — five treasure chests (Common, Uncommon, Rare, Epic, Legendary). Each is a `Base` and a `Lid`; the lid pivots on its back hinge.

To rebuild a model after editing its script:

```bash
blender --background --factory-startup --python models/mower/build_mower.py
```

To use one in Studio, open the 3D Importer and pick the `.fbx`. Colours are stored as vertex colours, so leave each MeshPart's colour white. Models are sized so 1 Blender unit is 1 stud.
