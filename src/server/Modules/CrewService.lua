local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local Inventory = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Inventory"))
local InventoryService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("InventoryService"))

local CrewService = {}

type CrewInstance = {
	InstanceId: string,
	DisplayName: string,
	Rarity: string,
	Level: number,
	CurrentXP: number,
	TotalXP: number,
	Source: string,
}

type CrewState = {
	NextCrewId: number,
	ById: {
		[string]: CrewInstance,
	},
}

local ItemTypes = Inventory.ItemTypes

local VALUE_NAMES = {
	DisplayName = "DisplayName",
	Rarity = "Rarity",
	Level = "Level",
	CurrentXP = "CurrentXP",
	TotalXP = "TotalXP",
	NextLevelXP = "NextLevelXP",
	ShipIncomePerHour = "ShipIncomePerHour",
	Source = "Source",
	InstanceId = "InstanceId",
}

local crewStatesByPlayer: { [Player]: CrewState } = {}
local started = false

local function getInventoryRoot(player: Player): Folder?
	local root = player:FindFirstChild(Inventory.Constants.RootFolderName)
	if root and root:IsA("Folder") then
		return root
	end

	return nil
end

local function getCrewTypeFolder(player: Player): Folder?
	local root = getInventoryRoot(player)
	if not root then
		return nil
	end

	local folder = root:FindFirstChild(ItemTypes.Crewmates)
	if folder and folder:IsA("Folder") then
		return folder
	end

	return nil
end

local function getCrewItemFolder(player: Player, instanceId: string): Folder?
	local typeFolder = getCrewTypeFolder(player)
	if not typeFolder then
		return nil
	end

	local itemFolder = typeFolder:FindFirstChild(instanceId)
	if itemFolder and itemFolder:IsA("Folder") then
		return itemFolder
	end

	return nil
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

local function getShipIncomeMultiplier(level: number): number
	for _, band in ipairs(Economy.Crew.ShipIncomeMultiplierByLevelBand) do
		if level >= band.MinLevel and level <= band.MaxLevel then
			return band.Multiplier
		end
	end

	return 1
end

local function getCrewShipIncomePerHour(rarity: string, level: number): number
	local baseIncome = Economy.Crew.ShipIncomePerHourByRarity[rarity] or 0
	return math.floor((baseIncome * getShipIncomeMultiplier(level)) + 0.5)
end

local function getCrewXPRequiredForLevel(rarity: string, level: number): number
	if level >= Economy.Rules.CrewMaxLevel then
		return 0
	end

	local multiplier = Economy.Crew.TotalXPMultiplierByRarity[rarity] or 1
	for _, band in ipairs(Economy.Crew.BaseXPPerLevelBand) do
		if level >= band.MinLevel and level <= band.MaxLevel then
			return math.max(1, math.floor((band.XPPerLevel * multiplier) + 0.5))
		end
	end

	return math.max(1, math.floor(40 * multiplier))
end

local function createEmptyCrewState(): CrewState
	return {
		NextCrewId = 1,
		ById = {},
	}
end

local function getCrewState(player: Player): CrewState
	local state = crewStatesByPlayer[player]
	if state then
		return state
	end

	state = createEmptyCrewState()
	crewStatesByPlayer[player] = state
	return state
end

local function createCrewInstanceId(player: Player): string
	local state = getCrewState(player)
	local instanceId = string.format("Crew%04d", state.NextCrewId)
	state.NextCrewId += 1
	return instanceId
end

local function syncCrewMirror(player: Player, crewInstance: CrewInstance)
	local itemFolder = getCrewItemFolder(player, crewInstance.InstanceId)
	if not itemFolder then
		return
	end

	getValueObject(itemFolder, "StringValue", VALUE_NAMES.DisplayName, crewInstance.DisplayName).Value = crewInstance.DisplayName
	getValueObject(itemFolder, "StringValue", VALUE_NAMES.Rarity, crewInstance.Rarity).Value = crewInstance.Rarity
	getValueObject(itemFolder, "NumberValue", VALUE_NAMES.Level, crewInstance.Level).Value = crewInstance.Level
	getValueObject(itemFolder, "NumberValue", VALUE_NAMES.CurrentXP, crewInstance.CurrentXP).Value = crewInstance.CurrentXP
	getValueObject(itemFolder, "NumberValue", VALUE_NAMES.TotalXP, crewInstance.TotalXP).Value = crewInstance.TotalXP
	getValueObject(itemFolder, "NumberValue", VALUE_NAMES.NextLevelXP, 0).Value =
		getCrewXPRequiredForLevel(crewInstance.Rarity, crewInstance.Level)
	getValueObject(itemFolder, "NumberValue", VALUE_NAMES.ShipIncomePerHour, 0).Value =
		getCrewShipIncomePerHour(crewInstance.Rarity, crewInstance.Level)
	getValueObject(itemFolder, "StringValue", VALUE_NAMES.Source, crewInstance.Source).Value = crewInstance.Source
	getValueObject(itemFolder, "StringValue", VALUE_NAMES.InstanceId, crewInstance.InstanceId).Value = crewInstance.InstanceId
end

local function syncAllCrewMirrors(player: Player)
	local state = getCrewState(player)
	for _, crewInstance in pairs(state.ById) do
		syncCrewMirror(player, crewInstance)
	end
end

function CrewService.GetCrew(player: Player, instanceId: string): CrewInstance?
	local state = getCrewState(player)
	return state.ById[instanceId]
end

function CrewService.GrantCrew(player: Player, displayName: string, rarity: string, source: string?): (boolean, string?)
	if typeof(displayName) ~= "string" or displayName == "" then
		return false, nil
	end

	if typeof(rarity) ~= "string" or rarity == "" then
		rarity = "Common"
	end

	local instanceId = createCrewInstanceId(player)
	local granted = InventoryService.AddItem(player, ItemTypes.Crewmates, instanceId, 1)
	if not granted then
		return false, nil
	end

	local state = getCrewState(player)
	local crewInstance: CrewInstance = {
		InstanceId = instanceId,
		DisplayName = displayName,
		Rarity = rarity,
		Level = 1,
		CurrentXP = 0,
		TotalXP = 0,
		Source = source or "Grant",
	}

	state.ById[instanceId] = crewInstance
	syncCrewMirror(player, crewInstance)

	return true, instanceId
end

function CrewService.FeedCrew(player: Player, instanceId: string, foodKey: string): boolean
	local crewInstance = CrewService.GetCrew(player, instanceId)
	local foodConfig = Economy.Food[foodKey]
	if not crewInstance or not foodConfig then
		return false
	end

	if InventoryService.GetQuantity(player, ItemTypes.Consumable, foodKey) <= 0 then
		return false
	end

	if crewInstance.Level >= Economy.Rules.CrewMaxLevel then
		return false
	end

	InventoryService.RemoveItem(player, ItemTypes.Consumable, foodKey, 1)

	local xpToAdd = math.max(1, tonumber(foodConfig.XP) or 0)
	local level = crewInstance.Level
	local currentXP = crewInstance.CurrentXP
	local totalXP = crewInstance.TotalXP

	while xpToAdd > 0 and level < Economy.Rules.CrewMaxLevel do
		local neededXP = getCrewXPRequiredForLevel(crewInstance.Rarity, level)
		local remainingToLevel = math.max(0, neededXP - currentXP)
		local appliedXP = math.min(xpToAdd, remainingToLevel)

		currentXP += appliedXP
		totalXP += appliedXP
		xpToAdd -= appliedXP

		if currentXP >= neededXP then
			level += 1
			currentXP = 0
		end
	end

	if level >= Economy.Rules.CrewMaxLevel then
		currentXP = 0
	end

	crewInstance.Level = level
	crewInstance.CurrentXP = currentXP
	crewInstance.TotalXP = totalXP
	syncCrewMirror(player, crewInstance)

	return true
end

function CrewService.Start()
	if started then
		return
	end

	started = true

	local function setupPlayer(player: Player)
		getCrewState(player)
		task.defer(syncAllCrewMirrors, player)
	end

	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(function(player)
		crewStatesByPlayer[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(setupPlayer, player)
	end
end

return CrewService
