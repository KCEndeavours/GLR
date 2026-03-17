local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DevilFruitInventoryService = {}

local PROMPT_TIMEOUT = 20
local TOOL_ATTR_KIND = "InventoryItemKind"

local Inventory = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Inventory"))
local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local InventoryService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("InventoryService"))
local DevilFruitService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruitService"))
local HotbarService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("HotbarService"))

local ItemTypes = Inventory.ItemTypes

local promptRemote: RemoteEvent
local responseRemote: RemoteEvent
local requestRemote: RemoteEvent
local pendingConsumeByPlayer = {}
local started = false

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

local function ensureRemotes()
	local remotesFolder = getOrCreateRemotesFolder()
	promptRemote = getOrCreateRemote(remotesFolder, "RemoteEvent", "DevilFruitConsumePrompt")
	responseRemote = getOrCreateRemote(remotesFolder, "RemoteEvent", "DevilFruitConsumeResponse")
	requestRemote = getOrCreateRemote(remotesFolder, "RemoteEvent", "DevilFruitConsumeRequest")
end

local function resolveFruit(fruitIdentifier)
	local fruit = DevilFruitConfig.GetFruit(fruitIdentifier)
	if not fruit then
		return nil, "unknown_fruit"
	end

	return fruit
end

local function clearPendingConsume(player: Player)
	pendingConsumeByPlayer[player] = nil
end

local function destroyLegacyFruitTools(container: Instance?)
	if not container then
		return
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute(TOOL_ATTR_KIND) == "DevilFruit" then
			child:Destroy()
		end
	end
end

local function cleanupLegacyFruitTools(player: Player)
	destroyLegacyFruitTools(player:FindFirstChildOfClass("Backpack"))
	destroyLegacyFruitTools(player.Character)
end

local function beginConsumePrompt(player: Player, fruitKey: string)
	if pendingConsumeByPlayer[player] ~= nil then
		return false, "consume_pending"
	end

	local fruit = DevilFruitConfig.GetFruit(fruitKey)
	if not fruit then
		return false, "unknown_fruit"
	end

	local quantity = InventoryService.GetQuantity(player, ItemTypes.DevilFruit, fruit.FruitKey)
	if quantity <= 0 then
		return false, "not_owned"
	end

	pendingConsumeByPlayer[player] = {
		FruitKey = fruit.FruitKey,
		RequestedAt = os.clock(),
	}

	promptRemote:FireClient(player, {
		FruitKey = fruit.FruitKey,
		FruitName = fruit.DisplayName,
		CurrentFruitName = DevilFruitService.GetEquippedFruit(player),
	})

	return true, nil
end

function DevilFruitInventoryService.GetFruitQuantity(player: Player, fruitIdentifier)
	local fruit, reason = resolveFruit(fruitIdentifier)
	if not fruit then
		return nil, reason
	end

	return InventoryService.GetQuantity(player, ItemTypes.DevilFruit, fruit.FruitKey)
end

function DevilFruitInventoryService.GrantFruit(player: Player, fruitIdentifier, amount)
	local fruit, reason = resolveFruit(fruitIdentifier)
	if not fruit then
		return false, reason
	end

	local increment = math.max(1, math.floor(tonumber(amount) or 1))
	return InventoryService.AddItem(player, ItemTypes.DevilFruit, fruit.FruitKey, increment), nil
end

function DevilFruitInventoryService.ConsumeFruit(player: Player, fruitIdentifier, amount)
	local fruit, reason = resolveFruit(fruitIdentifier)
	if not fruit then
		return false, reason
	end

	local decrement = math.max(1, math.floor(tonumber(amount) or 1))
	local currentQuantity = InventoryService.GetQuantity(player, ItemTypes.DevilFruit, fruit.FruitKey)
	if currentQuantity < decrement then
		return false, "not_enough_fruit"
	end

	return InventoryService.RemoveItem(player, ItemTypes.DevilFruit, fruit.FruitKey, decrement), nil
end

function DevilFruitInventoryService.RequestConsume(player: Player, fruitIdentifier)
	local fruit, reason = resolveFruit(fruitIdentifier)
	if not fruit then
		return false, reason
	end

	return beginConsumePrompt(player, fruit.FruitKey)
end

local function handleConsumeResponse(player: Player, accepted, fruitKey)
	local pending = pendingConsumeByPlayer[player]
	if not pending then
		return
	end

	clearPendingConsume(player)

	if accepted ~= true then
		return
	end

	if typeof(fruitKey) ~= "string" or fruitKey ~= pending.FruitKey then
		return
	end

	if os.clock() - pending.RequestedAt > PROMPT_TIMEOUT then
		return
	end

	local currentFruitName = DevilFruitService.GetEquippedFruit(player)
	local targetFruitName = DevilFruitConfig.ResolveFruitName(fruitKey)
	if currentFruitName ~= DevilFruitConfig.None and currentFruitName == targetFruitName then
		return
	end

	local consumed, reason = DevilFruitInventoryService.ConsumeFruit(player, fruitKey, 1)
	if not consumed then
		warn(
			string.format(
				"[DevilFruitInventoryService] Failed to consume %s for %s: %s",
				fruitKey,
				player.Name,
				tostring(reason)
			)
		)
		return
	end

	HotbarService.ClearItem(player, ItemTypes.DevilFruit, fruitKey)

	local equipped = DevilFruitService.SetEquippedFruit(player, fruitKey)
	if not equipped then
		DevilFruitInventoryService.GrantFruit(player, fruitKey, 1)
		warn(string.format("[DevilFruitInventoryService] Failed to equip %s for %s after consuming", fruitKey, player.Name))
		return
	end
end

local function handleConsumeRequest(player: Player, fruitIdentifier)
	if typeof(fruitIdentifier) ~= "string" then
		return
	end

	local requested, reason = DevilFruitInventoryService.RequestConsume(player, fruitIdentifier)
	if not requested and reason ~= "consume_pending" then
		warn(
			string.format(
				"[DevilFruitInventoryService] Failed to open consume prompt for %s (%s): %s",
				player.Name,
				fruitIdentifier,
				tostring(reason)
			)
		)
	end
end

local function hookPlayer(player: Player)
	cleanupLegacyFruitTools(player)

	player.CharacterAdded:Connect(function()
		task.defer(cleanupLegacyFruitTools, player)
	end)
end

function DevilFruitInventoryService.Start()
	if started then
		return
	end

	started = true
	ensureRemotes()

	for _, player in ipairs(Players:GetPlayers()) do
		hookPlayer(player)
	end

	Players.PlayerAdded:Connect(hookPlayer)
	Players.PlayerRemoving:Connect(clearPendingConsume)
	requestRemote.OnServerEvent:Connect(handleConsumeRequest)
	responseRemote.OnServerEvent:Connect(handleConsumeResponse)
end

return DevilFruitInventoryService
