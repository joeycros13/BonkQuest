# DiceBattles

A Roblox action game: fight enemies with real-time melee weapons across themed worlds (Sunny Meadows, Redwood Forest, Crystal Caverns), collect weapon drops and crafting materials, craft armour, and follow each world's questline.

## Folder layout

| Folder | What it holds | In git |
|---|---|---|
| `src/` | All game code: `shared/`, `server/`, `client/` | yes |
| `art/` | FBX meshes and offsets, icons, UI art, portraits, and the scripts that generate them | yes |
| `blender/` | `models.blend`, the source of every mesh | no (Google Drive backup) |
| `place/` | `DiceBattles.rbxlx`, the live place opened in Roblox Studio | no (Google Drive backup) |

`CLAUDE.md` has the detailed project notes.

## Working on the code

The code is synced into Studio with [Rojo](https://rojo.space) 7.7.1 (installed through Aftman).

1. Open `place/DiceBattles.rbxlx` in Roblox Studio.
2. In this folder, run:

   ```bash
   rojo serve
   ```

3. In Studio, open the Rojo plugin and press **Connect**.

Edit the `.luau` files in `src/`; Rojo copies every change into Studio within about a second. Don't edit scripts in Studio's own script editor while Rojo is connected, because the next sync overwrites them. The map, UI and models are built in Studio itself; save them with Ctrl+S.
