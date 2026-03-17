# ChestCrewProgressPack

Portable bundle for the current chest rewards, food resources, and crew progression systems.

## Copy Targets

- `ReplicatedStorage/Modules/Configs/GrandLineRushEconomy.lua`
- `ReplicatedStorage/Modules/Configs/GrandLineRushCrewCatalog.lua`
- `ReplicatedStorage/Modules/GrandLineRushMetaClient.lua`
- `ReplicatedStorage/Modules/GrandLineRushChestVisuals.lua`
- `ReplicatedStorage/Modules/PopUpModule.lua`
- `ServerScriptService/Modules/GrandLineRushVerticalSliceService.lua`
- `ServerScriptService/Modules/GrandLineRushChestToolService.lua`
- `ServerScriptService/Server-Scripts/GrandLineRushChestToolService.server.lua`
- `StarterPlayer/StarterPlayerScripts/GrandLineRushBasePlaceholder.client.lua`

## Data Merge Required

The current implementation depends on profile fields defined in:

- `DataReference/ProfileTemplate.lua`
- `DataReference/ProfileMigrations.lua`

Do not blindly overwrite your destination data files unless that is intentional. Merge the needed sections instead:

- `UnopenedChests`
- `FoodInventory`
- `CrewInventory`
- supporting `Materials`, `Ship`, `Chef`, and currency fields used by `GrandLineRushVerticalSliceService`

## Important Dependency

`GrandLineRushVerticalSliceService.lua` currently references `ReplicatedStorage.Modules.Configs.DevilFruits` for legendary chest fruit drops.

If your destination project does not include the Devil Fruit pack yet, either:

- port the Devil Fruit config/service too, or
- set `Legendary.Rewards.DevilFruitChance = 0` in `GrandLineRushEconomy.lua`

## Not Included

This pack does not include the full corridor/world-run spawning controller. It includes the chest opening, food resource gain, crew XP progression, client meta API, and placeholder management UI.
