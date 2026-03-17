local Constants = {}

Constants.RootFolderName = "Inventory"
Constants.RemotesFolderName = "InventoryRemotes"
Constants.StateRemoteName = "State"
Constants.CommandRemoteName = "Command"

Constants.ValueNames = {
	Quantity = "Quantity",
	Equipped = "Equipped",
	ItemId = "ItemId",
	ItemType = "ItemType",
}

Constants.Commands = {
	RequestSnapshot = "RequestSnapshot",
	ToggleEquip = "ToggleEquip",
}

Constants.Events = {
	Snapshot = "Snapshot",
	ItemChanged = "ItemChanged",
	ItemRemoved = "ItemRemoved",
}

return Constants
