local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevilFruitService = {}

local REQUEST_REMOTE_NAME = "DevilFruitAbilityRequest"
local STATE_REMOTE_NAME = "DevilFruitAbilityState"
local EFFECT_REMOTE_NAME = "DevilFruitAbilityEffect"
local COOLDOWN_BYPASS_ATTRIBUTE = "DevilFruitCooldownBypass"

local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))

local cooldownsByPlayer = {}
local fruitHandlerCache = {}
local started = false

local FruitHandlersFolder = script.Parent:FindFirstChild("DevilFruits") or script.Parent:WaitForChild("DevilFruits")

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

local function getOrCreateRemote(parent, name)
	local remote = parent:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end

	if remote then
		remote:Destroy()
	end

	remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function getRemoteBundle()
	local remotes = getOrCreateRemotesFolder()
	return {
		Request = getOrCreateRemote(remotes, REQUEST_REMOTE_NAME),
		State = getOrCreateRemote(remotes, STATE_REMOTE_NAME),
		Effect = getOrCreateRemote(remotes, EFFECT_REMOTE_NAME),
	}
end

local RemoteBundle = getRemoteBundle()

local function normalizeFruitName(fruitIdentifier)
	if fruitIdentifier == DevilFruitConfig.None then
		return DevilFruitConfig.None
	end

	local resolved = DevilFruitConfig.ResolveFruitName(fruitIdentifier)
	if resolved then
		return resolved
	end

	return nil
end

local function getFruitHandler(fruitName)
	local fruitConfig = DevilFruitConfig.GetFruit(fruitName)
	if not fruitConfig then
		return nil
	end

	local moduleName = fruitConfig.AbilityModule or fruitConfig.HandlerModule or fruitConfig.FruitKey or fruitConfig.Id
	if typeof(moduleName) ~= "string" or moduleName == "" then
		return nil
	end

	local cached = fruitHandlerCache[moduleName]
	if cached ~= nil then
		return cached or nil
	end

	local moduleScript = FruitHandlersFolder:FindFirstChild(moduleName)
	if not moduleScript then
		fruitHandlerCache[moduleName] = false
		warn(string.format("[DevilFruitService] Missing fruit handler '%s'", moduleName))
		return nil
	end

	local ok, handler = pcall(require, moduleScript)
	if not ok then
		fruitHandlerCache[moduleName] = false
		warn(string.format("[DevilFruitService] Failed to require '%s': %s", moduleName, tostring(handler)))
		return nil
	end

	fruitHandlerCache[moduleName] = handler
	return handler
end

local function getPlayerFruitFolder(player)
	return player:FindFirstChild("DevilFruit")
end

local function ensurePlayerFruitInstances(player)
	local fruitFolder = getPlayerFruitFolder(player)
	if not fruitFolder then
		fruitFolder = Instance.new("Folder")
		fruitFolder.Name = "DevilFruit"
		fruitFolder.Parent = player
	end

	local equippedValue = fruitFolder:FindFirstChild("Equipped")
	if equippedValue and not equippedValue:IsA("StringValue") then
		equippedValue:Destroy()
		equippedValue = nil
	end

	if not equippedValue then
		equippedValue = Instance.new("StringValue")
		equippedValue.Name = "Equipped"
		equippedValue.Value = DevilFruitConfig.None
		equippedValue.Parent = fruitFolder
	end

	return fruitFolder, equippedValue
end

local function getPlayerFruitValue(player)
	local _, equippedValue = ensurePlayerFruitInstances(player)
	return equippedValue
end

local function getCooldownTable(player)
	local cooldowns = cooldownsByPlayer[player]
	if cooldowns then
		return cooldowns
	end

	cooldowns = {}
	cooldownsByPlayer[player] = cooldowns
	return cooldowns
end

local function isCooldownBypassEnabled(player)
	return player:GetAttribute(COOLDOWN_BYPASS_ATTRIBUTE) == true
end

local function clearFruitRuntimeState(player, fruitName)
	if fruitName == DevilFruitConfig.None then
		return
	end

	local fruitConfig = DevilFruitConfig.GetFruit(fruitName)
	if fruitConfig and fruitConfig.Abilities then
		local cooldowns = getCooldownTable(player)
		for abilityName in pairs(fruitConfig.Abilities) do
			cooldowns[abilityName] = nil
		end
	end

	if fruitName == "Mera Mera no Mi" then
		player:SetAttribute("MeraFireBurstUntil", nil)
	end

	if fruitName == "Hie Hie no Mi" then
		player:SetAttribute("HieIceBoostUntil", nil)
		player:SetAttribute("HieIceBoostSpeedMultiplier", nil)
		player:SetAttribute("HieIceBoostSpeedBonus", nil)
	end
end

local function syncFruitAttribute(player, fruitName)
	player:SetAttribute("EquippedDevilFruit", fruitName)
end

local function applyEquippedFruitRuntimeState(player, fruitName)
	local fruitValue = getPlayerFruitValue(player)
	fruitValue.Value = fruitName
	syncFruitAttribute(player, fruitName)
end

local function getEquippedFruit(player)
	local fruitAttribute = player:GetAttribute("EquippedDevilFruit")
	if typeof(fruitAttribute) == "string" then
		local normalized = normalizeFruitName(fruitAttribute)
		if normalized ~= nil then
			return normalized
		end
	end

	local fruitValue = getPlayerFruitValue(player)
	local normalized = normalizeFruitName(fruitValue.Value)
	if normalized ~= nil then
		return normalized
	end

	return DevilFruitConfig.None
end

local function cleanupPlayerState(player)
	cooldownsByPlayer[player] = nil
end

local function getCharacterContext(player, fruitName, abilityName, requestPayload)
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return nil
	end

	local fruitConfig = DevilFruitConfig.GetFruit(fruitName)
	local abilityConfig = DevilFruitConfig.GetAbility(fruitName, abilityName)
	local fruitHandler = getFruitHandler(fruitName)
	if not fruitConfig or not abilityConfig or not fruitHandler then
		return nil
	end

	return {
		Player = player,
		Character = character,
		Humanoid = humanoid,
		RootPart = rootPart,
		FruitKey = fruitConfig.FruitKey,
		FruitName = fruitName,
		FruitConfig = fruitConfig,
		AbilityName = abilityName,
		AbilityConfig = abilityConfig,
		FruitHandler = fruitHandler,
		RequestPayload = requestPayload,
	}
end

local function isAbilityReady(player, abilityName)
	if isCooldownBypassEnabled(player) then
		return true, 0
	end

	local cooldowns = getCooldownTable(player)
	local readyAt = cooldowns[abilityName]
	if not readyAt then
		return true, 0
	end

	if os.clock() >= readyAt then
		return true, 0
	end

	return false, readyAt
end

local function setAbilityCooldown(player, abilityName, duration)
	if isCooldownBypassEnabled(player) then
		getCooldownTable(player)[abilityName] = nil
		return 0
	end

	local readyAt = os.clock() + (tonumber(duration) or 0)
	getCooldownTable(player)[abilityName] = readyAt
	return readyAt
end

local function clearAbilityCooldown(player, abilityName)
	getCooldownTable(player)[abilityName] = nil
end

local function fireAbilityDenied(player, fruitName, abilityName, reason, readyAt)
	RemoteBundle.State:FireClient(player, "Denied", fruitName or DevilFruitConfig.None, abilityName, reason, readyAt or 0)
end

local function fireAbilityActivated(player, fruitName, abilityName, readyAt, payload)
	if fruitName == "Mera Mera no Mi" and abilityName == "FireBurst" then
		player:SetAttribute("MeraFireBurstUntil", os.clock() + ((payload and payload.Duration) or 0))
	end

	RemoteBundle.State:FireClient(player, "Activated", fruitName, abilityName, readyAt, payload or {})
	RemoteBundle.Effect:FireAllClients(player, fruitName, abilityName, payload or {})
end

local function executeAbility(player, abilityName, requestPayload)
	local fruitName = getEquippedFruit(player)
	local context = getCharacterContext(player, fruitName, abilityName, requestPayload)
	if not context then
		fireAbilityDenied(player, fruitName, abilityName, "InvalidContext")
		return
	end

	local handler = context.FruitHandler[abilityName]
	if typeof(handler) ~= "function" then
		fireAbilityDenied(player, fruitName, abilityName, "MissingHandler")
		return
	end

	local isReady, readyAt = isAbilityReady(player, abilityName)
	if not isReady then
		fireAbilityDenied(player, fruitName, abilityName, "Cooldown", readyAt)
		return
	end

	local nextReadyAt = setAbilityCooldown(player, abilityName, context.AbilityConfig.Cooldown)
	local ok, payload = pcall(handler, context)
	if not ok then
		clearAbilityCooldown(player, abilityName)
		warn("[DevilFruitService] Failed to execute " .. fruitName .. " / " .. abilityName .. ": " .. tostring(payload))
		fireAbilityDenied(player, fruitName, abilityName, "ExecutionFailed")
		return
	end

	fireAbilityActivated(player, fruitName, abilityName, nextReadyAt, payload)
end

local function hookPlayer(player)
	task.defer(function()
		ensurePlayerFruitInstances(player)
		if player:GetAttribute(COOLDOWN_BYPASS_ATTRIBUTE) == nil then
			player:SetAttribute(COOLDOWN_BYPASS_ATTRIBUTE, false)
		end
		applyEquippedFruitRuntimeState(player, getEquippedFruit(player))
	end)
end

function DevilFruitService.GetEquippedFruit(player)
	return getEquippedFruit(player)
end

function DevilFruitService.GetEquippedFruitKey(player)
	return DevilFruitConfig.GetFruitKey(getEquippedFruit(player))
end

function DevilFruitService.SetEquippedFruit(player, fruitIdentifier)
	if not player or not player:IsA("Player") then
		return false
	end

	if typeof(fruitIdentifier) ~= "string" then
		return false
	end

	local resolvedFruitName = normalizeFruitName(fruitIdentifier)
	if resolvedFruitName == nil then
		return false
	end

	local currentFruitName = getEquippedFruit(player)

	if currentFruitName ~= resolvedFruitName then
		clearFruitRuntimeState(player, currentFruitName)
	end

	applyEquippedFruitRuntimeState(player, resolvedFruitName)
	return true, true
end

function DevilFruitService.SetCooldownBypass(player, isEnabled)
	if not player or not player:IsA("Player") then
		return false
	end

	player:SetAttribute(COOLDOWN_BYPASS_ATTRIBUTE, isEnabled == true)
	if isEnabled == true then
		cooldownsByPlayer[player] = {}
	end

	return true
end

function DevilFruitService.GetCooldownBypass(player)
	if not player or not player:IsA("Player") then
		return false
	end

	return isCooldownBypassEnabled(player)
end

function DevilFruitService.IsHazardSuppressedForPlayer(player)
	local untilTime = player:GetAttribute("MeraFireBurstUntil")
	if typeof(untilTime) ~= "number" then
		return false
	end

	return untilTime > os.clock()
end

function DevilFruitService.Start()
	if started then
		return
	end

	started = true

	for _, player in ipairs(Players:GetPlayers()) do
		hookPlayer(player)
	end

	Players.PlayerAdded:Connect(hookPlayer)
	Players.PlayerRemoving:Connect(cleanupPlayerState)

	RemoteBundle.Request.OnServerEvent:Connect(function(player, abilityName, requestPayload)
		if typeof(abilityName) ~= "string" then
			return
		end

		local equippedFruit = getEquippedFruit(player)
		if equippedFruit == DevilFruitConfig.None then
			fireAbilityDenied(player, equippedFruit, abilityName, "NoFruit")
			return
		end

		local abilityConfig = DevilFruitConfig.GetAbility(equippedFruit, abilityName)
		if not abilityConfig then
			fireAbilityDenied(player, equippedFruit, abilityName, "UnknownAbility")
			return
		end

		executeAbility(player, abilityName, typeof(requestPayload) == "table" and requestPayload or nil)
	end)
end

return DevilFruitService
