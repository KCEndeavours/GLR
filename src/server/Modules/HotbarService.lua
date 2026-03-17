local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local InventoryService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("InventoryService"))

local HotbarService = {}

local HOTBAR_FOLDER_NAME = "InventoryHotbar"
local SLOT_COUNT = 5
local REMOTE_NAME = "InventoryHotbarRequest"

type HotbarSlot = {
	ItemType: string,
	ItemId: string,
}

type HotbarState = {
	[number]: HotbarSlot?,
}

local started = false
local requestRemote: RemoteEvent
local hotbarStates: { [Player]: HotbarState } = {}

local function getOrCreateRemotesFolder()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes and remotes:IsA("Folder") then
		return remotes
	end

	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
	return remotes
end

local function getOrCreateRemote(parent: Instance, className: string, name: string): RemoteEvent
	local remote = parent:FindFirstChild(name)
	if remote and remote.ClassName == className then
		return remote :: RemoteEvent
	end

	if remote then
		remote:Destroy()
	end

	remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	return remote :: RemoteEvent
end

local function getHotbarState(player: Player): HotbarState
	local state = hotbarStates[player]
	if state then
		return state
	end

	state = {}
	hotbarStates[player] = state
	return state
end

local function getHotbarFolder(player: Player): Folder
	local folder = player:FindFirstChild(HOTBAR_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = HOTBAR_FOLDER_NAME
	folder.Parent = player
	return folder
end

local function getSlotFolder(player: Player, slotIndex: number): Folder
	local hotbarFolder = getHotbarFolder(player)
	local slotName = string.format("Slot%d", slotIndex)
	local slotFolder = hotbarFolder:FindFirstChild(slotName)
	if slotFolder and slotFolder:IsA("Folder") then
		return slotFolder
	end

	slotFolder = Instance.new("Folder")
	slotFolder.Name = slotName
	slotFolder.Parent = hotbarFolder
	return slotFolder
end

local function getValueObject(parent: Instance, className: string, name: string, defaultValue)
	local valueObject = parent:FindFirstChild(name)
	if valueObject and valueObject.ClassName == className then
		return valueObject
	end

	if valueObject then
		valueObject:Destroy()
	end

	valueObject = Instance.new(className)
	valueObject.Name = name
	valueObject.Value = defaultValue
	valueObject.Parent = parent
	return valueObject
end

local function syncSlotToMirror(player: Player, slotIndex: number)
	local slotFolder = getSlotFolder(player, slotIndex)
	local slot = getHotbarState(player)[slotIndex]

	getValueObject(slotFolder, "StringValue", "ItemType", "").Value = slot and slot.ItemType or ""
	getValueObject(slotFolder, "StringValue", "ItemId", "").Value = slot and slot.ItemId or ""
end

local function syncAllSlots(player: Player)
	for slotIndex = 1, SLOT_COUNT do
		syncSlotToMirror(player, slotIndex)
	end
end

local function isValidSlotIndex(slotIndex): boolean
	return typeof(slotIndex) == "number" and slotIndex >= 1 and slotIndex <= SLOT_COUNT and slotIndex % 1 == 0
end

local function clearSlotIfMissingInventory(player: Player, slotIndex: number)
	local slot = getHotbarState(player)[slotIndex]
	if not slot then
		return
	end

	if InventoryService.GetQuantity(player, slot.ItemType, slot.ItemId) > 0 then
		return
	end

	getHotbarState(player)[slotIndex] = nil
	syncSlotToMirror(player, slotIndex)
end

function HotbarService.AssignSlot(player: Player, slotIndex: number, itemType: string, itemId: string): boolean
	if not isValidSlotIndex(slotIndex) then
		return false
	end

	if typeof(itemType) ~= "string" or typeof(itemId) ~= "string" then
		return false
	end

	if InventoryService.GetQuantity(player, itemType, itemId) <= 0 then
		return false
	end

	HotbarService.ClearItem(player, itemType, itemId)
	getHotbarState(player)[slotIndex] = {
		ItemType = itemType,
		ItemId = itemId,
	}
	syncSlotToMirror(player, slotIndex)
	return true
end

function HotbarService.ClearSlot(player: Player, slotIndex: number): boolean
	if not isValidSlotIndex(slotIndex) then
		return false
	end

	getHotbarState(player)[slotIndex] = nil
	syncSlotToMirror(player, slotIndex)
	return true
end

function HotbarService.ClearItem(player: Player, itemType: string, itemId: string)
	local state = getHotbarState(player)
	for slotIndex = 1, SLOT_COUNT do
		local slot = state[slotIndex]
		if slot and slot.ItemType == itemType and slot.ItemId == itemId then
			state[slotIndex] = nil
			syncSlotToMirror(player, slotIndex)
		end
	end
end

function HotbarService.GetSlot(player: Player, slotIndex: number): HotbarSlot?
	if not isValidSlotIndex(slotIndex) then
		return nil
	end

	clearSlotIfMissingInventory(player, slotIndex)
	return getHotbarState(player)[slotIndex]
end

local function handleRequest(player: Player, actionName, payload)
	if typeof(actionName) ~= "string" or typeof(payload) ~= "table" then
		return
	end

	local slotIndex = payload.SlotIndex
	if not isValidSlotIndex(slotIndex) then
		return
	end

	if actionName == "AssignSlot" then
		local itemType = payload.ItemType
		local itemId = payload.ItemId
		HotbarService.AssignSlot(player, slotIndex, itemType, itemId)
		return
	end

	if actionName == "ClearSlot" then
		HotbarService.ClearSlot(player, slotIndex)
	end
end

function HotbarService.Start()
	if started then
		return
	end

	started = true

	local remotesFolder = getOrCreateRemotesFolder()
	requestRemote = getOrCreateRemote(remotesFolder, "RemoteEvent", REMOTE_NAME)

	local function setupPlayer(player: Player)
		getHotbarState(player)
		syncAllSlots(player)
	end

	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(function(player)
		hotbarStates[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(setupPlayer, player)
	end

	requestRemote.OnServerEvent:Connect(handleRequest)
end

return HotbarService
