local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TextChatService = game:GetService("TextChatService")

local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local CrewCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushCrewCatalog"))
local Inventory = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Inventory"))
local InventoryService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("InventoryService"))
local DevilFruitInventoryService =
	require(ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruitInventoryService"))
local DevilFruitService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruitService"))
local GrandLineRushChestService =
	require(ServerScriptService:WaitForChild("Modules"):WaitForChild("GrandLineRushChestService"))
local CrewService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewService"))

local ItemTypes = Inventory.ItemTypes
local COMMAND_PREFIX = "/"

local fruitAliases = {}
local chestTierAliases = {}

local function canUseAdminCommands(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end

	return player.UserId == game.CreatorId
end

local function normalizeText(text: string?): string
	return tostring(text or ""):lower():match("^%s*(.-)%s*$") or ""
end

local function splitWords(message: string): { string }
	local words = {}

	for word in string.gmatch(message, "%S+") do
		words[#words + 1] = word
	end

	return words
end

local function joinWords(words: { string }, firstIndex: number, lastIndex: number): string
	local parts = {}

	for index = firstIndex, lastIndex do
		parts[#parts + 1] = words[index]
	end

	return table.concat(parts, " ")
end

local function getIdentifierAndAmount(words: { string }, usageStartIndex: number): (string?, number)
	if #words < usageStartIndex then
		return nil, 1
	end

	local amount = tonumber(words[#words])
	local lastIndex = if amount ~= nil then #words - 1 else #words
	if lastIndex < usageStartIndex then
		return nil, 1
	end

	return joinWords(words, usageStartIndex, lastIndex), math.max(1, math.floor(amount or 1))
end

local function ensureLeaderstats(player: Player): (IntValue, IntValue)
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
		doubloons.Value = Economy.Tutorial.StartingDoubloons or 0
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
		totalDoubloons.Value = doubloons.Value
		totalDoubloons.Parent = totalStats
	end

	return doubloons, totalDoubloons
end

local function adjustDoubloons(player: Player, amount: number)
	local doubloons, totalDoubloons = ensureLeaderstats(player)
	local clampedAmount = math.floor(amount)
	local nextBalance = math.max(0, doubloons.Value + clampedAmount)
	local actualDelta = nextBalance - doubloons.Value

	doubloons.Value = nextBalance
	if actualDelta > 0 then
		totalDoubloons.Value += actualDelta
	end
end

local function sendSystemMessage(_player: Player, _message: string)
end

local function registerFruitAlias(alias: string, fruitKey: string)
	local normalizedAlias = normalizeText(alias)
	if normalizedAlias == "" then
		return
	end

	fruitAliases[normalizedAlias] = fruitKey
end

local function registerChestAlias(alias: string, tierName: string)
	local normalizedAlias = normalizeText(alias)
	if normalizedAlias == "" then
		return
	end

	chestTierAliases[normalizedAlias] = tierName
end

for _, fruit in ipairs(DevilFruitConfig.GetAllFruits()) do
	registerFruitAlias(fruit.FruitKey, fruit.FruitKey)
	registerFruitAlias(fruit.DisplayName, fruit.FruitKey)
	registerFruitAlias(fruit.Id, fruit.FruitKey)

	for _, alias in ipairs(fruit.Aliases or {}) do
		registerFruitAlias(alias, fruit.FruitKey)
	end
end

for tierName in pairs(Economy.Chests.Tiers or {}) do
	registerChestAlias(tierName, tierName)
	registerChestAlias(tierName .. " chest", tierName)
end

registerChestAlias("wood", "Wooden")
registerChestAlias("wooden", "Wooden")
registerChestAlias("iron", "Iron")
registerChestAlias("gold", "Gold")
registerChestAlias("legend", "Legendary")
registerChestAlias("legendary", "Legendary")

local function resolveFruitKey(identifier: string?): string?
	local normalized = normalizeText(identifier)
	if normalized == "" then
		return nil
	end

	return fruitAliases[normalized]
end

local function resolveChestTier(identifier: string?): string?
	local normalized = normalizeText(identifier)
	if normalized == "" then
		return nil
	end

	return chestTierAliases[normalized]
end

local function removeAllDevilFruits(player: Player)
	local snapshot = InventoryService.GetSnapshot(player)
	local devilFruitEntries = snapshot[ItemTypes.DevilFruit]
	if not devilFruitEntries then
		return
	end

	for itemId in pairs(devilFruitEntries) do
		InventoryService.SetQuantity(player, ItemTypes.DevilFruit, itemId, 0)
	end
end

local function grantAllFruits(player: Player)
	for _, fruit in ipairs(DevilFruitConfig.GetAllFruits()) do
		local quantity = InventoryService.GetQuantity(player, ItemTypes.DevilFruit, fruit.FruitKey)
		if quantity <= 0 then
			DevilFruitInventoryService.GrantFruit(player, fruit.FruitKey, 1)
		end
	end
end

local function handleFruitGrant(player: Player, words: { string })
	local argument = normalizeText(joinWords(words, 2, #words))
	if argument == "" then
		sendSystemMessage(player, "Usage: /fruit <fruit|all|equip|clear|nocd>")
		return
	end

	if argument == "all" then
		grantAllFruits(player)
		return
	end

	local cooldownArgument = argument:match("^nocd%s*(.*)$")
	if cooldownArgument ~= nil then
		local normalizedCooldownArgument = normalizeText(cooldownArgument)
		local currentState = DevilFruitService.GetCooldownBypass(player)
		local nextState = currentState

		if normalizedCooldownArgument == "" or normalizedCooldownArgument == "toggle" then
			nextState = not currentState
		elseif normalizedCooldownArgument == "on" or normalizedCooldownArgument == "true" then
			nextState = true
		elseif normalizedCooldownArgument == "off" or normalizedCooldownArgument == "false" then
			nextState = false
		else
			sendSystemMessage(player, "Usage: /fruit nocd [on|off|toggle]")
			return
		end

		DevilFruitService.SetCooldownBypass(player, nextState)
		return
	end

	local directEquipArgument = argument:match("^equip%s+(.+)$")
	if directEquipArgument then
		local fruitKey = resolveFruitKey(directEquipArgument)
		if not fruitKey then
			sendSystemMessage(player, "Unknown fruit.")
			return
		end

		DevilFruitService.SetEquippedFruit(player, fruitKey)
		return
	end

	if argument == "clear" or argument == "none" or argument == "remove" then
		DevilFruitService.SetEquippedFruit(player, DevilFruitConfig.None)
		return
	end

	local fruitIdentifier, amount = getIdentifierAndAmount(words, 2)
	if not fruitIdentifier then
		sendSystemMessage(player, "Usage: /fruit <fruit name> [amount]")
		return
	end

	local fruitKey = resolveFruitKey(fruitIdentifier)
	if not fruitKey then
		sendSystemMessage(player, "Unknown fruit.")
		return
	end

	DevilFruitInventoryService.GrantFruit(player, fruitKey, amount)
end

local function handleFruitRemove(player: Player, words: { string })
	local fruitIdentifier, amount = getIdentifierAndAmount(words, 2)
	if not fruitIdentifier then
		sendSystemMessage(player, "Usage: /removefruit <fruit name> [amount]")
		return
	end

	local fruitKey = resolveFruitKey(fruitIdentifier)
	if not fruitKey then
		sendSystemMessage(player, "Unknown fruit.")
		return
	end

	DevilFruitInventoryService.ConsumeFruit(player, fruitKey, amount)
end

local function handleClearFruitInventory(player: Player)
	removeAllDevilFruits(player)
end

local function handleUnequipFruit(player: Player)
	DevilFruitService.SetEquippedFruit(player, DevilFruitConfig.None)
end

local function handleChestGrant(player: Player, words: { string })
	local chestIdentifier, amount = getIdentifierAndAmount(words, 2)
	if not chestIdentifier then
		sendSystemMessage(player, "Usage: /chest <wooden|iron|gold|legendary> [amount]")
		return
	end

	local chestTier = resolveChestTier(chestIdentifier)
	if not chestTier then
		sendSystemMessage(player, "Unknown chest tier.")
		return
	end

	GrandLineRushChestService.GrantChest(player, chestTier, amount)
end

local function handleCrewGrant(player: Player, words: { string })
	local crewIdentifier, amount = getIdentifierAndAmount(words, 2)
	if not crewIdentifier then
		sendSystemMessage(player, "Usage: /crew <rarity|crew name> [amount]")
		return
	end

	local normalizedRarity = nil
	for _, rarity in ipairs(Economy.Crew.RarityOrder) do
		if string.lower(rarity) == normalizeText(crewIdentifier) then
			normalizedRarity = rarity
			break
		end
	end

	local crewName = crewIdentifier
	local rarity = "Common"
	if normalizedRarity then
		crewName = CrewCatalog.GetRandomNameForRarity(normalizedRarity)
		rarity = normalizedRarity
	end

	for _ = 1, amount do
		CrewService.GrantCrew(player, crewName, rarity, "AdminCommand")
	end
end

local function handleMoneyAdjust(player: Player, words: { string })
	local amountText = joinWords(words, 2, #words):gsub(",", "")
	local amount = tonumber(amountText)
	if typeof(amount) ~= "number" or amount ~= amount or amount == 0 then
		sendSystemMessage(player, "Usage: /money <signed amount>")
		return
	end

	adjustDoubloons(player, amount)
end

local function handleSpawnCommand(player: Player, words: { string })
	local spawnTarget = normalizeText(words[2])
	if spawnTarget == "" then
		sendSystemMessage(player, "Usage: /spawn <chest|crew>")
		return
	end

	if spawnTarget == "chest" then
		GrandLineRushChestService.GrantChest(player, "Wooden", 1)
		return
	end

	if spawnTarget == "crew" then
		local crewName = CrewCatalog.GetRandomNameForRarity(Economy.VerticalSlice.StarterCrew.Rarity or "Common")
		CrewService.GrantCrew(player, crewName, Economy.VerticalSlice.StarterCrew.Rarity or "Common", "SpawnCommand")
	end
end

local function onCommandMessage(player: Player, message: string)
	if not canUseAdminCommands(player) then
		return
	end

	if string.sub(message, 1, #COMMAND_PREFIX) ~= COMMAND_PREFIX then
		return
	end

	local words = splitWords(message)
	local commandName = normalizeText(words[1])
	if commandName == "" then
		return
	end

	if commandName == "/fruit" then
		handleFruitGrant(player, words)
		return
	end

	if commandName == "/removefruit" then
		handleFruitRemove(player, words)
		return
	end

	if commandName == "/clearfruitinventory" then
		handleClearFruitInventory(player)
		return
	end

	if commandName == "/unequipfruit" then
		handleUnequipFruit(player)
		return
	end

	if commandName == "/chest" then
		handleChestGrant(player, words)
		return
	end

	if commandName == "/crew" then
		handleCrewGrant(player, words)
		return
	end

	if commandName == "/money" then
		handleMoneyAdjust(player, words)
		return
	end

	if commandName == "/spawn" then
		handleSpawnCommand(player, words)
	end
end

local function getPlayerFromTextSource(textSource: TextSource?): Player?
	if not textSource then
		return nil
	end

	return Players:GetPlayerByUserId(textSource.UserId)
end

local function createChatCommand(alias: string)
	local command = Instance.new("TextChatCommand")
	command.Name = string.sub(alias, 2) .. "Command"
	command.PrimaryAlias = alias
	command.AutocompleteVisible = false
	command.Parent = TextChatService

	command.Triggered:Connect(function(textSource, unfilteredText)
		local player = getPlayerFromTextSource(textSource)
		if not player then
			return
		end

		local normalizedText = tostring(unfilteredText or "")
		if string.sub(normalizedText, 1, #alias) == alias then
			onCommandMessage(player, normalizedText)
			return
		end

		local suffix = tostring(unfilteredText or ""):match("^%s*(.-)%s*$") or ""
		local syntheticCommand = suffix ~= "" and (alias .. " " .. suffix) or alias
		onCommandMessage(player, syntheticCommand)
	end)
end

createChatCommand("/fruit")
createChatCommand("/removefruit")
createChatCommand("/clearfruitinventory")
createChatCommand("/unequipfruit")
createChatCommand("/chest")
createChatCommand("/crew")
createChatCommand("/money")
createChatCommand("/spawn")
