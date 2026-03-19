# WaveSystemPack

Current periodic wave system export based on the code present in `src`.

## Included

- `ReplicatedStorage/Modules/Configs/LavaWaves.lua`
- `ReplicatedStorage/ddd/LavaWaves.lua`
- `ServerScriptService/Server-Scripts/SpawnWaves.server.lua`
- `ServerScriptService/PBAR.server.lua`
- `StarterPlayer/StarterPlayerScripts/AAAAAAAAAAAAAAA.client.lua`

## What This Covers

- periodic wave spawning logic on the client
- server-side kill remote handling
- wave config data
- progress bar remote setup/sync
- collision-based player death requests via `KillMe`

## Important Limitation

This is **not** a fully self-contained export of the current live wave system, because several required live instances are not represented under `src`.

## Missing Live-Place Dependencies

The current code expects these to already exist in the destination place:

- `ReplicatedStorage/Waves`
  - the actual wave templates/models cloned by the client
- `Workspace/Map/WaveFolder`
  - must contain at least:
  - `Start`
  - `End`
- `PlayerGui/HUD/ProgressBar`
  - with the expected `PFP` and `Disaster` UI templates

## Why It Cannot Be Fully Exported From This Repo Alone

- `src` contains the scripts and configs for the wave system
- `src` does **not** contain the `ReplicatedStorage/Waves` folder
- `src` does **not** contain the `Workspace/Map/WaveFolder` objects
- `src` does **not** contain the `HUD.ProgressBar` GUI structure the client script mounts into

So I can export the code side accurately, but not a true drop-in complete wave feature without copying those unmanaged live assets from Studio.

## Recommendation

If you want a real complete export, the next step is:

1. copy the live `ReplicatedStorage/Waves` folder into Rojo-managed source
2. copy the live `Workspace/Map/WaveFolder` structure into `src`
3. copy the live `HUD.ProgressBar` GUI into `src`
4. then regenerate the pack
