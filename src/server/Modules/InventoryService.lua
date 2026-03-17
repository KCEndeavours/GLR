local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryShared = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Inventory"))

local Constants = InventoryShared.Constants
local Registry = InventoryShared.Registry

type ItemTypeDefinition = {
	Name: string,
	Stackable: boolean,
	Equippable: boolean,
	MaxStack: number?,
	MaxEquipped: number?,
}

type ItemState = {
	ItemType: string,
	ItemId: string,
	Quantity: number,
	Equipped: boolean,
}

type InventoryTypeState = {
	[string]: ItemState,
}

type InventoryState = {
	[string]: InventoryTypeState,
}

local InventoryService = {}

local started = false
local commandRemote: RemoteEvent
local playerStates: { [Player]: InventoryState } = {}

local function isNonEmptyString(value)
	return typeof(value) == "string" and value ~= ""
end

local function validateItemKey(itemType, itemId)
	if not isNonEmptyString(itemType) or not isNonEmptyString(itemId) then
		return false
	end

	if itemType:find("%.") or itemId:find("%.") then
		return false
	end

	return true
end

local function getRemotesFolder()
	local folder = ReplicatedStorage:FindFirstChild(Constants.RemotesFolderName)
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = Constants.RemotesFolderName
	folder.Parent = ReplicatedStorage
	return folder
end

local function getOrCreateRemote(folder, className, name)
	local remote = folder:FindFirstChild(name)
	if remote and remote.ClassName == className then
		return remote
	end

	remote = Instance.new(className)
	remote.Name = name
	remote.Parent = folder
	return remote
end

local function getDefinition(itemType): ItemTypeDefinition?
	return Registry.GetItemType(itemType)
end

local function getValueObject(parent, className, name, defaultValue)
	local valueObject = parent:FindFirstChild(name)
	if valueObject and valueObject.ClassName == className then
		return valueObject
	end

	valueObject = Instance.new(className)
	valueObject.Name = name
	valueObject.Value = defaultValue
	valueObject.Parent = parent
	return valueObject
end

local function getInventoryRoot(player: Player): Folder
	local root = player:FindFirstChild(Constants.RootFolderName)
	if root and root:IsA("Folder") then
		return root
	end

	root = Instance.new("Folder")
	root.Name = Constants.RootFolderName
	root.Parent = player
	return root
end

local function getTypeFolder(player: Player, itemType: string): Folder
	local root = getInventoryRoot(player)
	local typeFolder = root:FindFirstChild(itemType)
	if typeFolder and typeFolder:IsA("Folder") then
		return typeFolder
	end

	typeFolder = Instance.new("Folder")
	typeFolder.Name = itemType
	typeFolder.Parent = root
	return typeFolder
end

local function getItemFolder(player: Player, itemType: string, itemId: string): Folder
	local typeFolder = getTypeFolder(player, itemType)
	local itemFolder = typeFolder:FindFirstChild(itemId)
	if itemFolder and itemFolder:IsA("Folder") then
		return itemFolder
	end

	itemFolder = Instance.new("Folder")
	itemFolder.Name = itemId
	itemFolder.Parent = typeFolder
	return itemFolder
end

local function destroyUnknownChildren(parent: Instance, keepNames: { [string]: boolean })
	for _, child in ipairs(parent:GetChildren()) do
		if not keepNames[child.Name] then
			child:Destroy()
		end
	end
end

local function deepCopyItemState(itemState: ItemState): ItemState
	return {
		ItemType = itemState.ItemType,
		ItemId = itemState.ItemId,
		Quantity = itemState.Quantity,
		Equipped = itemState.Equipped,
	}
end

local function createEmptyInventoryState(): InventoryState
	local state: InventoryState = {}

	for itemType in pairs(Registry.GetAll()) do
		state[itemType] = {}
	end

	return state
end

local function getPlayerState(player: Player): InventoryState
	local state = playerStates[player]
	if state then
		return state
	end

	state = createEmptyInventoryState()
	playerStates[player] = state
	return state
end

local function syncItemToMirror(player: Player, itemState: ItemState)
	local itemFolder = getItemFolder(player, itemState.ItemType, itemState.ItemId)

	getValueObject(itemFolder, "StringValue", Constants.ValueNames.ItemType, itemState.ItemType).Value = itemState.ItemType
	getValueObject(itemFolder, "StringValue", Constants.ValueNames.ItemId, itemState.ItemId).Value = itemState.ItemId
	getValueObject(itemFolder, "NumberValue", Constants.ValueNames.Quantity, 0).Value = itemState.Quantity
	getValueObject(itemFolder, "BoolValue", Constants.ValueNames.Equipped, false).Value = itemState.Equipped
end

local function removeItemFromMirror(player: Player, itemType: string, itemId: string)
	local root = getInventoryRoot(player)
	local typeFolder = root:FindFirstChild(itemType)
	if not typeFolder or not typeFolder:IsA("Folder") then
		return
	end

	local itemFolder = typeFolder:FindFirstChild(itemId)
	if itemFolder and itemFolder:IsA("Folder") then
		itemFolder:Destroy()
	end
end

local function syncStateToMirror(player: Player)
	local state = getPlayerState(player)
	local root = getInventoryRoot(player)
	local knownTypeFolders = {}

	for itemType in pairs(Registry.GetAll()) do
		knownTypeFolders[itemType] = true
		local typeFolder = getTypeFolder(player, itemType)
		local knownItems = {}

		for itemId, itemState in pairs(state[itemType] or {}) do
			knownItems[itemId] = true
			syncItemToMirror(player, itemState)
		end

		destroyUnknownChildren(typeFolder, knownItems)
	end

	destroyUnknownChildren(root, knownTypeFolders)
end

local function getSnapshot(player: Player): InventoryState
	local snapshot: InventoryState = {}
	local state = getPlayerState(player)

	for itemType in pairs(Registry.GetAll()) do
		snapshot[itemType] = {}

		for itemId, itemState in pairs(state[itemType] or {}) do
			snapshot[itemType][itemId] = deepCopyItemState(itemState)
		end
	end

	return snapshot
end

local function getOrCreateItemState(player: Player, itemType: string, itemId: string): ItemState
	local state = getPlayerState(player)
	state[itemType] = state[itemType] or {}

	local itemState = state[itemType][itemId]
	if itemState then
		return itemState
	end

	itemState = {
		ItemType = itemType,
		ItemId = itemId,
		Quantity = 0,
		Equipped = false,
	}

	state[itemType][itemId] = itemState
	return itemState
end

local function getItemState(player: Player, itemType: string, itemId: string): ItemState?
	local state = getPlayerState(player)
	local typeState = state[itemType]
	if not typeState then
		return nil
	end

	return typeState[itemId]
end

local function removeItemState(player: Player, itemType: string, itemId: string)
	local state = getPlayerState(player)
	local typeState = state[itemType]
	if not typeState then
		return
	end

	typeState[itemId] = nil
end

local function enforceTypeEquipLimit(player: Player, itemType: string, keepItemId: string?)
	local definition = getDefinition(itemType)
	if not definition or not definition.Equippable then
		return
	end

	local state = getPlayerState(player)
	local typeState = state[itemType]
	if not typeState then
		return
	end

	local maxEquipped = definition.MaxEquipped or 0
	local equippedItems = {}

	for _, itemState in pairs(typeState) do
		if itemState.Equipped and itemState.Quantity > 0 then
			table.insert(equippedItems, itemState)
		end
	end

	table.sort(equippedItems, function(left, right)
		if keepItemId ~= nil then
			local leftIsKeep = left.ItemId == keepItemId
			local rightIsKeep = right.ItemId == keepItemId
			if leftIsKeep ~= rightIsKeep then
				return leftIsKeep
			end
		end

		return left.ItemId < right.ItemId
	end)

	for index, itemState in ipairs(equippedItems) do
		local shouldStayEquipped = maxEquipped > 0 and index <= maxEquipped
		if itemState.Equipped ~= shouldStayEquipped then
			itemState.Equipped = shouldStayEquipped
			syncItemToMirror(player, itemState)
		end
	end
end

function InventoryService.EnsurePlayerInventory(player: Player): Folder
	getPlayerState(player)
	syncStateToMirror(player)
	return getInventoryRoot(player)
end

function InventoryService.RegisterItemType(definition: ItemTypeDefinition)
	local registered = Registry.RegisterItemType(definition)

	for player in pairs(playerStates) do
		local state = getPlayerState(player)
		if not state[registered.Name] then
			state[registered.Name] = {}
			syncStateToMirror(player)
		end
	end

	return registered
end

function InventoryService.GetSnapshot(player: Player)
	return getSnapshot(player)
end

function InventoryService.ExportSnapshot(player: Player)
	return getSnapshot(player)
end

function InventoryService.ClearPlayerInventory(player: Player)
	playerStates[player] = createEmptyInventoryState()
	syncStateToMirror(player)
end

function InventoryService.ImportSnapshot(player: Player, snapshot, replaceExisting: boolean?): boolean
	if typeof(snapshot) ~= "table" then
		return false
	end

	if replaceExisting == true or not playerStates[player] then
		playerStates[player] = createEmptyInventoryState()
	else
		getPlayerState(player)
	end

	for itemType, entries in pairs(snapshot) do
		if typeof(itemType) == "string" and typeof(entries) == "table" and Registry.IsRegistered(itemType) then
			for itemId, itemState in pairs(entries) do
				if typeof(itemId) == "string" and typeof(itemState) == "table" then
					local quantity = tonumber(itemState.Quantity) or 0
					local equipped = itemState.Equipped == true

					InventoryService.SetQuantity(player, itemType, itemId, quantity)
					if quantity > 0 and equipped then
						InventoryService.SetEquipped(player, itemType, itemId, true)
					end
				end
			end
		end
	end

	syncStateToMirror(player)
	return true
end

function InventoryService.HasItem(player: Player, itemType: string, itemId: string): boolean
	return InventoryService.GetQuantity(player, itemType, itemId) > 0
end

function InventoryService.GetQuantity(player: Player, itemType: string, itemId: string): number
	if not validateItemKey(itemType, itemId) then
		return 0
	end

	local itemState = getItemState(player, itemType, itemId)
	if not itemState then
		return 0
	end

	return itemState.Quantity
end

function InventoryService.SetQuantity(player: Player, itemType: string, itemId: string, quantity: number): boolean
	if not validateItemKey(itemType, itemId) then
		return false
	end

	local definition = getDefinition(itemType)
	if not definition then
		return false
	end

	local nextQuantity = math.max(0, math.floor(tonumber(quantity) or 0))
	if definition.MaxStack then
		nextQuantity = math.min(nextQuantity, definition.MaxStack)
	end

	if nextQuantity <= 0 then
		removeItemState(player, itemType, itemId)
		removeItemFromMirror(player, itemType, itemId)
		return true
	end

	local itemState = getOrCreateItemState(player, itemType, itemId)
	itemState.Quantity = nextQuantity

	if not definition.Equippable then
		itemState.Equipped = false
	end

	enforceTypeEquipLimit(player, itemType)
	syncItemToMirror(player, itemState)
	return true
end

function InventoryService.AddItem(player: Player, itemType: string, itemId: string, amount: number?): boolean
	local current = InventoryService.GetQuantity(player, itemType, itemId)
	return InventoryService.SetQuantity(player, itemType, itemId, current + (tonumber(amount) or 1))
end

function InventoryService.RemoveItem(player: Player, itemType: string, itemId: string, amount: number?): boolean
	local current = InventoryService.GetQuantity(player, itemType, itemId)
	return InventoryService.SetQuantity(player, itemType, itemId, current - (tonumber(amount) or 1))
end

function InventoryService.IsEquipped(player: Player, itemType: string, itemId: string): boolean
	if not validateItemKey(itemType, itemId) then
		return false
	end

	local itemState = getItemState(player, itemType, itemId)
	return itemState ~= nil and itemState.Equipped == true and itemState.Quantity > 0
end

function InventoryService.SetEquipped(player: Player, itemType: string, itemId: string, isEquipped: boolean): boolean
	if not validateItemKey(itemType, itemId) then
		return false
	end

	local definition = getDefinition(itemType)
	if not definition or not definition.Equippable then
		return false
	end

	local itemState = getItemState(player, itemType, itemId)
	if not itemState or itemState.Quantity <= 0 then
		return false
	end

	itemState.Equipped = isEquipped == true
	if itemState.Equipped then
		enforceTypeEquipLimit(player, itemType, itemId)
	end

	syncItemToMirror(player, itemState)
	return true
end

function InventoryService.ToggleEquip(player: Player, itemType: string, itemId: string): boolean
	local nextValue = not InventoryService.IsEquipped(player, itemType, itemId)
	return InventoryService.SetEquipped(player, itemType, itemId, nextValue)
end

function InventoryService.GetFirstEquipped(player: Player, itemType: string): string?
	local state = getPlayerState(player)
	local typeState = state[itemType]
	if not typeState then
		return nil
	end

	for itemId, itemState in pairs(typeState) do
		if itemState.Equipped and itemState.Quantity > 0 then
			return itemId
		end
	end

	return nil
end

function InventoryService.Start()
	if started then
		return
	end

	started = true

	local remotesFolder = getRemotesFolder()
	commandRemote = getOrCreateRemote(remotesFolder, "RemoteEvent", Constants.CommandRemoteName)

	local function setupPlayer(player: Player)
		InventoryService.EnsurePlayerInventory(player)
	end

	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(function(player)
		playerStates[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(setupPlayer, player)
	end

	commandRemote.OnServerEvent:Connect(function(player, commandName, payload)
		if typeof(commandName) ~= "string" then
			return
		end

		if commandName == Constants.Commands.RequestSnapshot then
			syncStateToMirror(player)
			return
		end

		if commandName == Constants.Commands.ToggleEquip then
			if typeof(payload) ~= "table" then
				return
			end

			local itemType = payload.ItemType
			local itemId = payload.ItemId
			if not validateItemKey(itemType, itemId) then
				return
			end

			InventoryService.ToggleEquip(player, itemType, itemId)
		end
	end)
end

return InventoryService
