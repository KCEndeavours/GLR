local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local CrewCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushCrewCatalog"))
local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local Inventory = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Inventory"))

local InventoryService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("InventoryService"))
local DevilFruitInventoryService =
	require(ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruitInventoryService"))
local CrewService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewService"))

local GrandLineRushChestService = {}

local CHEST_CONSUME_REQUEST_REMOTE_NAME = "GrandLineRushChestConsumeRequest"
local started = false
local chestConsumeRequestRemote: RemoteEvent
local randomObject = Random.new()

local ItemTypes = Inventory.ItemTypes

local MATERIAL_DISPLAY_NAMES = {
	CommonShipMaterial = "Common Ship Material",
	RareShipMaterial = "Rare Ship Material",
}

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

local function ensureLeaderstats(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local doubloons = leaderstats:FindFirstChild("Doubloons")
	if not doubloons or not doubloons:IsA("IntValue") then
		if doubloons then
			doubloons:Destroy()
		end

		doubloons = Instance.new("IntValue")
		doubloons.Name = "Doubloons"
		doubloons.Value = 0
		doubloons.Parent = leaderstats
	end

	local totalStats = player:FindFirstChild("TotalStats")
	if not totalStats then
		totalStats = Instance.new("Folder")
		totalStats.Name = "TotalStats"
		totalStats.Parent = player
	end

	local totalDoubloons = totalStats:FindFirstChild("TotalDoubloons")
	if not totalDoubloons or not totalDoubloons:IsA("IntValue") then
		if totalDoubloons then
			totalDoubloons:Destroy()
		end

		totalDoubloons = Instance.new("IntValue")
		totalDoubloons.Name = "TotalDoubloons"
		totalDoubloons.Value = 0
		totalDoubloons.Parent = totalStats
	end

	return doubloons :: IntValue, totalDoubloons :: IntValue
end

local function resolveChestTier(chestIdentifier)
	if typeof(chestIdentifier) ~= "string" or chestIdentifier == "" then
		return nil
	end

	for tierName in pairs(Economy.Chests.Tiers) do
		if string.lower(tierName) == string.lower(chestIdentifier) then
			return tierName
		end

		if string.lower(tierName .. " chest") == string.lower(chestIdentifier) then
			return tierName
		end
	end

	return nil
end

local function getChestItemId(tierName: string): string
	return tierName
end

local function getCrewRewardForTier(_tierName: string)
	if Economy.Rules.ChestsCanDropCrew ~= true then
		return nil
	end

	local rarity = Economy.VerticalSlice.StarterCrew.Rarity or "Common"
	return {
		DisplayName = CrewCatalog.GetRandomNameForRarity(rarity, randomObject),
		Rarity = rarity,
	}
end

local function grantFoodRewards(player: Player, foodRewards)
	for foodKey, amount in pairs(foodRewards) do
		local quantity = math.max(0, math.floor(tonumber(amount) or 0))
		if quantity > 0 then
			InventoryService.AddItem(player, ItemTypes.Consumable, foodKey, quantity)
		end
	end
end

local function grantMaterialRewards(player: Player, materialRewards)
	for materialKey, amount in pairs(materialRewards) do
		local quantity = math.max(0, math.floor(tonumber(amount) or 0))
		if quantity > 0 then
			local itemId = MATERIAL_DISPLAY_NAMES[materialKey] or materialKey
			InventoryService.AddItem(player, ItemTypes.Material, itemId, quantity)
		end
	end
end

local function grantCurrencyReward(player: Player, amount)
	local quantity = math.max(0, math.floor(tonumber(amount) or 0))
	if quantity <= 0 then
		return
	end

	local doubloons, totalDoubloons = ensureLeaderstats(player)
	doubloons.Value += quantity
	totalDoubloons.Value += quantity
end

local function maybeGrantDevilFruitReward(player: Player, devilFruitChance)
	local chance = tonumber(devilFruitChance) or 0
	if chance <= 0 or randomObject:NextNumber() > chance then
		return nil
	end

	local fruits = DevilFruitConfig.GetAllFruits()
	if #fruits == 0 then
		return nil
	end

	local fruit = fruits[randomObject:NextInteger(1, #fruits)]
	DevilFruitInventoryService.GrantFruit(player, fruit.FruitKey, 1)
	return fruit.DisplayName
end

local function openChestInternal(player: Player, chestTier: string)
	local tierConfig = Economy.Chests.Tiers[chestTier]
	if not tierConfig then
		return false, "invalid_chest_tier"
	end

	local rewards = tierConfig.Rewards or {}
	grantFoodRewards(player, rewards.Food or {})
	grantMaterialRewards(player, rewards.Materials or {})
	grantCurrencyReward(player, rewards.Doubloons)

	local grantedFruitName = maybeGrantDevilFruitReward(player, rewards.DevilFruitChance)
	local grantedCrew = getCrewRewardForTier(chestTier)
	if grantedCrew then
		CrewService.GrantCrew(player, grantedCrew.DisplayName, grantedCrew.Rarity, "Chest")
	end

	return true, {
		GrantedFruitName = grantedFruitName,
		GrantedCrewName = grantedCrew and grantedCrew.DisplayName or nil,
	}
end

function GrandLineRushChestService.GrantChest(player: Player, chestTier: string, amount: number?)
	local resolvedTier = resolveChestTier(chestTier)
	if not resolvedTier then
		return false, "invalid_chest_tier"
	end

	local quantity = math.max(1, math.floor(tonumber(amount) or 1))
	return InventoryService.AddItem(player, ItemTypes.Chest, getChestItemId(resolvedTier), quantity), nil
end

function GrandLineRushChestService.OpenChest(player: Player, chestTier: string)
	local resolvedTier = resolveChestTier(chestTier)
	if not resolvedTier then
		return false, "invalid_chest_tier"
	end

	local itemId = getChestItemId(resolvedTier)
	if InventoryService.GetQuantity(player, ItemTypes.Chest, itemId) <= 0 then
		return false, "not_owned"
	end

	local removed = InventoryService.RemoveItem(player, ItemTypes.Chest, itemId, 1)
	if not removed then
		return false, "remove_failed"
	end

	local opened, result = openChestInternal(player, resolvedTier)
	if not opened then
		InventoryService.AddItem(player, ItemTypes.Chest, itemId, 1)
		return false, result
	end

	return true, result
end

local function onChestConsumeRequest(player: Player, chestTier: string)
	if typeof(chestTier) ~= "string" then
		return
	end

	GrandLineRushChestService.OpenChest(player, chestTier)
end

local function hookPlayer(player: Player)
	ensureLeaderstats(player)
end

function GrandLineRushChestService.Start()
	if started then
		return
	end

	started = true

	local remotesFolder = getOrCreateRemotesFolder()
	chestConsumeRequestRemote =
		getOrCreateRemote(remotesFolder, "RemoteEvent", CHEST_CONSUME_REQUEST_REMOTE_NAME)

	for _, player in ipairs(Players:GetPlayers()) do
		hookPlayer(player)
	end

	Players.PlayerAdded:Connect(hookPlayer)
	chestConsumeRequestRemote.OnServerEvent:Connect(onChestConsumeRequest)
end

return GrandLineRushChestService
