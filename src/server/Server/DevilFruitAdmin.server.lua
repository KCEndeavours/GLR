local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TextChatService = game:GetService("TextChatService")

local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local Inventory = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Inventory"))
local InventoryService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("InventoryService"))
local DevilFruitInventoryService =
	require(ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruitInventoryService"))
local DevilFruitService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruitService"))

local ItemTypes = Inventory.ItemTypes

local COMMAND_PREFIX = "/"

local function canUseAdminCommands(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end

	return player.UserId == game.CreatorId
end

local function splitWords(message: string): { string }
	local words = {}

	for word in string.gmatch(message, "%S+") do
		table.insert(words, word)
	end

	return words
end

local function joinWords(words: { string }, firstIndex: number, lastIndex: number): string
	local parts = {}

	for index = firstIndex, lastIndex do
		table.insert(parts, words[index])
	end

	return table.concat(parts, " ")
end

local function getFruitIdentifier(words: { string }): (string?, number)
	if #words < 2 then
		return nil, 1
	end

	local amount = tonumber(words[#words])
	local fruitLastIndex = if amount ~= nil then #words - 1 else #words
	if fruitLastIndex < 2 then
		return nil, 1
	end

	return joinWords(words, 2, fruitLastIndex), math.max(1, math.floor(amount or 1))
end

local function sendSystemMessage(_player: Player, _message: string)
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

local function handleFruitGrant(player: Player, words: { string })
	if words[2] == "nocd" then
		local requestedState = words[3]
		local currentState = DevilFruitService.GetCooldownBypass(player)
		local nextState = currentState

		if requestedState == nil or requestedState == "toggle" then
			nextState = not currentState
		elseif requestedState == "on" or requestedState == "true" then
			nextState = true
		elseif requestedState == "off" or requestedState == "false" then
			nextState = false
		else
			sendSystemMessage(player, "Usage: /fruit nocd [on|off|toggle]")
			return
		end

		DevilFruitService.SetCooldownBypass(player, nextState)
		sendSystemMessage(player, string.format("Devil Fruit cooldown bypass %s.", nextState and "enabled" or "disabled"))
		return
	end

	local fruitIdentifier, amount = getFruitIdentifier(words)
	if not fruitIdentifier then
		sendSystemMessage(player, "Usage: /fruit <mera|hie|fruit name> [amount] or /fruit nocd [on|off|toggle]")
		return
	end

	local fruit = DevilFruitConfig.GetFruit(fruitIdentifier)
	if not fruit then
		sendSystemMessage(player, string.format("Unknown fruit '%s'.", fruitIdentifier))
		return
	end

	local ok, reason = DevilFruitInventoryService.GrantFruit(player, fruitIdentifier, amount)
	if not ok then
		sendSystemMessage(player, string.format("Failed to grant %s: %s", fruit.DisplayName, tostring(reason)))
		return
	end

	sendSystemMessage(player, string.format("Granted %dx %s.", amount, fruit.DisplayName))
end

local function handleFruitRemove(player: Player, words: { string })
	local fruitIdentifier, amount = getFruitIdentifier(words)
	if not fruitIdentifier then
		sendSystemMessage(player, "Usage: /removefruit <mera|hie|fruit name> [amount]")
		return
	end

	local fruit = DevilFruitConfig.GetFruit(fruitIdentifier)
	if not fruit then
		sendSystemMessage(player, string.format("Unknown fruit '%s'.", fruitIdentifier))
		return
	end

	local ok, reason = DevilFruitInventoryService.ConsumeFruit(player, fruitIdentifier, amount)
	if not ok then
		sendSystemMessage(player, string.format("Failed to remove %s: %s", fruit.DisplayName, tostring(reason)))
		return
	end

	sendSystemMessage(player, string.format("Removed %dx %s.", amount, fruit.DisplayName))
end

local function handleClearFruitInventory(player: Player)
	removeAllDevilFruits(player)
	sendSystemMessage(player, "Cleared all Devil Fruit items from inventory.")
end

local function handleUnequipFruit(player: Player)
	DevilFruitService.SetEquippedFruit(player, DevilFruitConfig.None)
	sendSystemMessage(player, "Cleared equipped Devil Fruit.")
end

local function onCommandMessage(player: Player, message: string)
	if not canUseAdminCommands(player) then
		return
	end

	if string.sub(message, 1, #COMMAND_PREFIX) ~= COMMAND_PREFIX then
		return
	end

	local words = splitWords(string.lower(message))
	local commandName = words[1]
	if not commandName then
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
	command.Parent = TextChatService

	command.Triggered:Connect(function(textSource, unfilteredText)
		local player = getPlayerFromTextSource(textSource)
		if not player then
			return
		end

		onCommandMessage(player, unfilteredText)
	end)
end

createChatCommand("/fruit")
createChatCommand("/removefruit")
createChatCommand("/clearfruitinventory")
createChatCommand("/unequipfruit")
