# ReactPolishedUiPack

Current export of the polished React-based inventory and shop UI, based on the latest source in this repo.

## Included

- `ReplicatedStorage/UI`
  - React inventory UI component tree
  - React shop UI component tree
- `StarterPlayer/StarterPlayerScripts/UI`
  - `App.client.lua`
  - `Shop.client.lua`
- `ReplicatedStorage/Modules/GrandLineRushMetaClient.lua`
- `ReplicatedStorage/Modules/GrandLineRushChestVisuals.lua`
- `ReplicatedStorage/Modules/DevilFruits/Assets.lua`
- `ReplicatedStorage/Modules/Configs/Brainrots.lua`
- `ReplicatedStorage/Modules/Configs/Gears.lua`
- `ReplicatedStorage/Modules/Configs/DevilFruits.lua`
- `ReplicatedStorage/Modules/Configs/GrandLineRushEconomy.lua`
- `ReplicatedStorage/Modules/Configs/PlotUpgrade.lua`
- `ReplicatedStorage/Packages`
  - `React.lua`
  - `ReactRoblox.lua`
  - `_Index`
- `StarterGui/Frames/Store`
- `StarterGui/OpenUI`

## What This Covers

- polished React inventory UI
- polished React shop UI
- Captain's Log rendering and sorting logic
- quick-equip hotbar rendering
- chest preview rendering
- devil fruit preview support
- client meta-state bridge used by the React UI

## Important Runtime Dependencies

This pack is source-complete for the polished UI layer, but it still expects the destination game to provide these runtime systems:

- `ReplicatedStorage/InventoryGearRemote`
- `ReplicatedStorage/EquipToggleRemote`
- `ReplicatedStorage/Remotes/ShipUpgradeResultRemote`
- `ReplicatedStorage/Remotes/<GrandLineRushEconomy.VerticalSlice.Remotes.*>`
- player inventory/data folders populated at runtime
  - `Inventory`
  - `IncomeBrainrots`
  - `Ship`
  - `StandsLevels`
  - `Materials`
  - `UnopenedChests`
  - `leaderstats`
  - `HiddenLeaderstats`

## Legacy Shells Still Referenced

The new UI still hooks into a few older objects for placement and compatibility:

- `PlayerGui/Frames/Store`
  - used as the shop mount shell
- `PlayerGui/OpenUI/Open_UI`
  - used by the shop close/toggle path
- `PlayerGui/HUD/Inventory`
  - the React inventory hides this legacy UI and may reuse its icon art if present

If the destination place does not have those shells yet, the React UI may still need small integration edits.

## Notes

- This export intentionally packages the current polished UI, not the older placeholder pack.
- The inventory polish and Captain's Log sorting live primarily in `StarterPlayer/StarterPlayerScripts/UI/App.client.lua` and `ReplicatedStorage/UI/App.lua`.
- The shop polish lives primarily in `StarterPlayer/StarterPlayerScripts/UI/Shop.client.lua` and `ReplicatedStorage/UI/Shop`.
