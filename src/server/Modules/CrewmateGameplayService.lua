local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Configs = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs")
local SpawnSettings = require(Configs:WaitForChild("CrewmateSpawnSettings"))
local Inventory = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Inventory"))

local CrewmateWorldService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewmateWorldService"))
local CrewService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewService"))
local InventoryService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("InventoryService"))

local CrewmateGameplayService = {}

type SpawnSelection = {
	Id: string,
	BaseId: string,
	DisplayName: string,
	Rarity: string,
	Variant: string,
	IncomePerTick: number,
	Render: string?,
}

type ActiveCrewmate = {
	Model: Instance,
	Selection: SpawnSelection,
	SpawnPosition: Vector3,
}

local BIOME_STARTS = {
	Vector3.new(-739.931, 25.693, -28.6),
	Vector3.new(-323.731, 25.693, -28.6),
	Vector3.new(210.069, 25.693, -28.6),
	Vector3.new(726.169, 25.693, -28.6),
	Vector3.new(1117.669, 25.693, -28.6),
	Vector3.new(1578.069, 25.693, -28.6),
	Vector3.new(2071.969, 25.693, -28.6),
	Vector3.new(2600.069, 25.693, -28.6),
}

local BIOME_8_END = Vector3.new(3161.969, 25.693, -28.6)

local SPAWN_Y_OFFSET = 2.2
local SPAWN_Z_JITTER = 220
local BASE_SLOT_SPACING = 38
local BASE_OFFSET_FROM_IMPACT = Vector3.new(-120, 0, 0)
local BASE_DELIVERY_DISTANCE = 12
local INCOME_TICK_SECONDS = 1
local SPAWN_INTERVAL_MIN = 2
local SPAWN_INTERVAL_MAX = 4
local MAX_SPAWNS_PER_CYCLE = 2
local INITIAL_SPAWN_BURST_COUNT = 6
local EARLY_BIOME_BIAS_DURATION_SECONDS = 120
local EARLY_BIOME_MAX_ALPHA = 0.45

local started = false
local randomObject = Random.new()
local startedAt = 0

local activeCrewmates: { [Instance]: ActiveCrewmate } = {}
local carriedByPlayer: { [Player]: SpawnSelection } = {}
local baseByPlayer: { [Player]: BasePart } = {}
local slotByPlayer: { [Player]: number } = {}
local deliveredIncomePerTickByPlayer: { [Player]: number } = {}
local incomeFractionCarry: { [Player]: number } = {}
local ItemTypes = Inventory.ItemTypes

local function getMap(): Instance?
	local map = workspace:FindFirstChild("Map")
	if map then
		return map
	end

	return nil
end

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local folder = parent:FindFirstChild(name)
	if folder and folder:IsA("Folder") then
		return folder
	end

	if folder then
		folder:Destroy()
	end

	folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
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
		totalDoubloons.Value = doubloons.Value
		totalDoubloons.Parent = totalStats
	end

	return doubloons, totalDoubloons
end

local function getFirstAvailableSlot(): number
	local occupied = {}
	for _, slot in pairs(slotByPlayer) do
		occupied[slot] = true
	end

	local slot = 1
	while occupied[slot] do
		slot += 1
	end

	return slot
end

local function setPlayerCarryState(player: Player, selection: SpawnSelection?)
	carriedByPlayer[player] = selection
	player:SetAttribute("CarryingCrewmate", selection ~= nil)
	player:SetAttribute("CarryingCrewmateName", selection and selection.DisplayName or "")
end

local function getOrCreateValue(parent: Instance, className: string, name: string, defaultValue)
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

local function getOrCreateCaptainLogFolder(player: Player): Folder
	local captainLog = player:FindFirstChild("CaptainLog")
	if captainLog and captainLog:IsA("Folder") then
		return captainLog
	end

	if captainLog then
		captainLog:Destroy()
	end

	captainLog = Instance.new("Folder")
	captainLog.Name = "CaptainLog"
	captainLog.Parent = player
	return captainLog
end

local function syncCaptainLogEntry(
	player: Player,
	instanceId: string,
	displayName: string,
	rarity: string,
	incomePerTick: number
)
	local captainLog = getOrCreateCaptainLogFolder(player)
	local entry = captainLog:FindFirstChild(instanceId)
	if not entry or not entry:IsA("Folder") then
		if entry then
			entry:Destroy()
		end
		entry = Instance.new("Folder")
		entry.Name = instanceId
		entry.Parent = captainLog
	end

	getOrCreateValue(entry, "StringValue", "DisplayName", displayName).Value = displayName
	getOrCreateValue(entry, "StringValue", "Rarity", rarity).Value = rarity
	getOrCreateValue(entry, "NumberValue", "Level", 1).Value = 1
	getOrCreateValue(entry, "NumberValue", "CurrentXP", 0).Value = 0
	getOrCreateValue(entry, "NumberValue", "NextLevelXP", 0).Value = 0
	getOrCreateValue(entry, "NumberValue", "ShipIncomePerHour", incomePerTick).Value = incomePerTick
	getOrCreateValue(entry, "NumberValue", "IncomePerTick", incomePerTick).Value = incomePerTick
end

local function buildFallbackModel(selection: SpawnSelection, position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = selection.DisplayName

	local part = Instance.new("Part")
	part.Name = "Root"
	part.Size = Vector3.new(4, 4, 4)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(98, 182, 255)
	part.Position = position
	part.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Nameplate"
	billboard.Size = UDim2.fromOffset(220, 48)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.35
	label.Text = selection.DisplayName
	label.Parent = billboard

	model.PrimaryPart = part
	return model
end

local function tryFindTemplate(selection: SpawnSelection): Model?
	local foldersToCheck = {
		ReplicatedStorage:FindFirstChild("CrewmateFolder"),
		ReplicatedStorage:FindFirstChild("BrainrotFolder"),
		ReplicatedStorage:FindFirstChild("Assets"),
	}

	local namesToCheck = {
		selection.DisplayName,
		selection.BaseId,
		selection.Id,
	}

	for _, candidate in ipairs(foldersToCheck) do
		if candidate and candidate:IsA("Folder") then
			for _, name in ipairs(namesToCheck) do
				local direct = candidate:FindFirstChild(name)
				if direct and direct:IsA("Model") then
					return direct
				end
			end

			local variantFolder = candidate:FindFirstChild(selection.Variant)
			if variantFolder and variantFolder:IsA("Folder") then
				local byBase = variantFolder:FindFirstChild(selection.BaseId)
				if byBase and byBase:IsA("Model") then
					return byBase
				end
			end

			local crewmatesSubfolder = candidate:FindFirstChild("Crewmates")
			if crewmatesSubfolder and crewmatesSubfolder:IsA("Folder") then
				local byBase = crewmatesSubfolder:FindFirstChild(selection.BaseId)
				if byBase and byBase:IsA("Model") then
					return byBase
				end
			end
		end
	end

	return nil
end

local function cloneForWorld(selection: SpawnSelection, position: Vector3): Model
	local template = tryFindTemplate(selection)
	local model: Model
	if template then
		model = template:Clone()
		model.Name = selection.DisplayName
	else
		model = buildFallbackModel(selection, position)
		return model
	end

	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if primary and primary:IsA("BasePart") then
		model.PrimaryPart = primary
	end

	if model.PrimaryPart then
		model:PivotTo(CFrame.new(position))
	else
		local fallback = buildFallbackModel(selection, position)
		model:Destroy()
		return fallback
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end

	return model
end

local function getSpawnRanges()
	local ranges = {}
	local laneMinX = math.min(BIOME_STARTS[1].X, BIOME_8_END.X)
	local laneMaxX = math.max(BIOME_STARTS[1].X, BIOME_8_END.X)
	local laneWidth = math.max(1, laneMaxX - laneMinX)

	for index = 1, #BIOME_STARTS do
		local startPoint = BIOME_STARTS[index]
		local endPoint = BIOME_STARTS[index + 1] or BIOME_8_END
		local minX = math.min(startPoint.X, endPoint.X)
		local maxX = math.max(startPoint.X, endPoint.X)
		table.insert(ranges, {
			Index = index,
			MinX = minX,
			MaxX = maxX,
			MinAlpha = math.clamp((minX - laneMinX) / laneWidth, 0, 1),
			MaxAlpha = math.clamp((maxX - laneMinX) / laneWidth, 0, 1),
		})
	end

	return ranges
end

local SPAWN_RANGES = getSpawnRanges()

local function rollSpawnPosition(maxDepthAlpha: number?): (Vector3, number)
	local cappedDepthAlpha = math.clamp(tonumber(maxDepthAlpha) or 1, 0, 1)
	local eligibleRanges = {}
	local totalWeight = 0

	for _, range in ipairs(SPAWN_RANGES) do
		if range.MinAlpha <= cappedDepthAlpha then
			local baseWeight = 1 / math.pow(range.Index, 1.35)
			local biomeOneBonus = if range.Index == 1 then 4 else 1
			local weight = baseWeight * biomeOneBonus
			totalWeight += weight
			table.insert(eligibleRanges, {
				Range = range,
				Weight = weight,
			})
		end
	end

	local selectedRange = SPAWN_RANGES[1]
	if #eligibleRanges > 0 and totalWeight > 0 then
		local pick = randomObject:NextNumber(0, totalWeight)
		local cursor = 0
		for _, entry in ipairs(eligibleRanges) do
			cursor += entry.Weight
			if pick <= cursor then
				selectedRange = entry.Range
				break
			end
		end
	end

	local range = selectedRange
	local x = randomObject:NextNumber(range.MinX, range.MaxX)
	local z = BIOME_STARTS[1].Z + randomObject:NextNumber(-SPAWN_Z_JITTER, SPAWN_Z_JITTER)
	local y = BIOME_STARTS[1].Y + SPAWN_Y_OFFSET
	local laneMinX = math.min(BIOME_STARTS[1].X, BIOME_8_END.X)
	local laneMaxX = math.max(BIOME_STARTS[1].X, BIOME_8_END.X)
	local depthAlpha = math.clamp((x - laneMinX) / math.max(1, laneMaxX - laneMinX), 0, 1)

	if depthAlpha > cappedDepthAlpha then
		local depthX = laneMinX + ((laneMaxX - laneMinX) * cappedDepthAlpha)
		x = depthX
		depthAlpha = cappedDepthAlpha
	end

	return Vector3.new(x, y, z), depthAlpha
end

local function getMaxActiveCrewmates(): number
	local perPart = math.max(1, tonumber(SpawnSettings.MaxPerPart) or 7)
	return math.max(10, perPart * 3)
end

local function removeActiveCrewmate(instance: Instance)
	activeCrewmates[instance] = nil
	if instance.Parent then
		instance:Destroy()
	end
end

local function addIncome(player: Player, amount: number)
	if amount <= 0 then
		return
	end

	local doubloons, totalDoubloons = ensureLeaderstats(player)
	doubloons.Value += amount
	totalDoubloons.Value += amount
end

local function deliverCrewmate(player: Player)
	local carried = carriedByPlayer[player]
	if not carried then
		return
	end

	local granted, instanceId = CrewService.GrantCrew(player, carried.DisplayName, carried.Rarity, "WorldPickup")
	if granted then
		deliveredIncomePerTickByPlayer[player] = (deliveredIncomePerTickByPlayer[player] or 0) + carried.IncomePerTick

		if instanceId then
			syncCaptainLogEntry(player, instanceId, carried.DisplayName, carried.Rarity, carried.IncomePerTick)
			InventoryService.RemoveItem(player, ItemTypes.Crewmates, instanceId, 1)
			player:SetAttribute("LastDeliveredCrewmateId", instanceId)
		end
	end

	setPlayerCarryState(player, nil)
end

local function createBasePart(player: Player, basesFolder: Folder)
	local slot = getFirstAvailableSlot()
	slotByPlayer[player] = slot

	local position = BIOME_STARTS[1] + BASE_OFFSET_FROM_IMPACT + Vector3.new(0, 0, (slot - 1) * BASE_SLOT_SPACING)

	local basePart = Instance.new("Part")
	basePart.Name = player.Name .. "_CrewmateBase"
	basePart.Size = Vector3.new(24, 1, 24)
	basePart.Anchored = true
	basePart.CanCollide = true
	basePart.Material = Enum.Material.SmoothPlastic
	basePart.Transparency = 0.2
	basePart.Color = Color3.fromRGB(70, 110, 190)
	basePart.Position = position
	basePart.Parent = basesFolder

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(240, 36)
	billboard.StudsOffset = Vector3.new(0, 4.5, 0)
	billboard.Parent = basePart

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(230, 245, 255)
	label.TextStrokeTransparency = 0.45
	label.Text = player.DisplayName .. "'s Base"
	label.Parent = billboard

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DeliverCrewmatePrompt"
	prompt.ActionText = "Deliver Crewmate"
	prompt.ObjectText = "Base"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = BASE_DELIVERY_DISTANCE
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.RequiresLineOfSight = false
	prompt.Parent = basePart

	prompt.Triggered:Connect(function(triggeringPlayer)
		if triggeringPlayer ~= player then
			return
		end

		deliverCrewmate(player)
	end)

	baseByPlayer[player] = basePart
end

local function spawnOne(worldFolder: Folder, maxDepthAlpha: number?): boolean
	local spawnPosition, depthAlpha = rollSpawnPosition(maxDepthAlpha)
	local selection = CrewmateWorldService.RollSpawn(randomObject, nil, depthAlpha)
	if not selection then
		return false
	end

	local model = cloneForWorld(selection, spawnPosition)
	model.Parent = worldFolder

	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not root or not root:IsA("BasePart") then
		model:Destroy()
		return false
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickupPrompt"
	prompt.ActionText = "Pick Up"
	prompt.ObjectText = selection.DisplayName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.RequiresLineOfSight = false
	prompt.Parent = root

	local activeEntry: ActiveCrewmate = {
		Model = model,
		Selection = selection,
		SpawnPosition = spawnPosition,
	}

	model:SetAttribute("SpawnDepthAlpha", depthAlpha)
	model:SetAttribute("SpawnBiomeApprox", math.clamp(1 + math.floor(depthAlpha * 8), 1, 8))
	model:SetAttribute("SpawnRarity", selection.Rarity)
	model:SetAttribute("SpawnVariant", selection.Variant)
	model:SetAttribute("SpawnCrewmateId", selection.Id)

	activeCrewmates[model] = activeEntry

	prompt.Triggered:Connect(function(player)
		if carriedByPlayer[player] then
			return
		end

		if not activeCrewmates[model] then
			return
		end

		setPlayerCarryState(player, selection)
		removeActiveCrewmate(model)
	end)

	return true
end

local function runSpawnLoop(worldFolder: Folder)
	task.spawn(function()
		while started do
			local playerCount = #Players:GetPlayers()
			if playerCount > 0 then
				local activeCount = 0
				for _ in pairs(activeCrewmates) do
					activeCount += 1
				end

				local maxActiveCrewmates = getMaxActiveCrewmates()
				if activeCount < maxActiveCrewmates then
					local elapsed = os.clock() - startedAt
					local maxDepthAlpha = if elapsed <= EARLY_BIOME_BIAS_DURATION_SECONDS then EARLY_BIOME_MAX_ALPHA else 1
					local attempts = math.min(MAX_SPAWNS_PER_CYCLE, maxActiveCrewmates - activeCount)

					for _ = 1, attempts do
						if activeCount >= maxActiveCrewmates then
							break
						end

						if spawnOne(worldFolder, maxDepthAlpha) then
							activeCount += 1
						end
					end
				end
			end

			task.wait(randomObject:NextNumber(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_MAX))
		end
	end)
end

local function runIncomeLoop()
	task.spawn(function()
		while started do
			for _, player in ipairs(Players:GetPlayers()) do
				local incomePerTick = deliveredIncomePerTickByPlayer[player] or 0
				if incomePerTick > 0 then
					local rolling = (incomeFractionCarry[player] or 0) + incomePerTick
					local whole = math.floor(rolling)
					incomeFractionCarry[player] = rolling - whole

					if whole > 0 then
						addIncome(player, whole)
					end
				end
			end

			task.wait(INCOME_TICK_SECONDS)
		end
	end)
end

function CrewmateGameplayService.Start()
	if started then
		return
	end

	started = true
	startedAt = os.clock()

	CrewService.Start()

	local map = getMap()
	if not map then
		warn("[CrewmateGameplay] workspace.Map was not found; crewmate gameplay did not start.")
		return
	end

	local worldFolder = getOrCreateFolder(map, "CrewmatesWorld")
	local activeFolder = getOrCreateFolder(worldFolder, "Active")
	local baseFolder = getOrCreateFolder(map, "CrewmateBases")

	for _, player in ipairs(Players:GetPlayers()) do
		setPlayerCarryState(player, nil)
		getOrCreateCaptainLogFolder(player)
		createBasePart(player, baseFolder)
	end

	Players.PlayerAdded:Connect(function(player)
		setPlayerCarryState(player, nil)
		deliveredIncomePerTickByPlayer[player] = 0
		incomeFractionCarry[player] = 0
		getOrCreateCaptainLogFolder(player)
		createBasePart(player, baseFolder)
	end)

	Players.PlayerRemoving:Connect(function(player)
		setPlayerCarryState(player, nil)
		deliveredIncomePerTickByPlayer[player] = nil
		incomeFractionCarry[player] = nil
		slotByPlayer[player] = nil

		local basePart = baseByPlayer[player]
		baseByPlayer[player] = nil
		if basePart and basePart.Parent then
			basePart:Destroy()
		end
	end)

	for _ = 1, INITIAL_SPAWN_BURST_COUNT do
		local maxActiveCrewmates = getMaxActiveCrewmates()
		local activeCount = 0
		for _entry in pairs(activeCrewmates) do
			activeCount += 1
		end

		if activeCount >= maxActiveCrewmates then
			break
		end

		spawnOne(activeFolder, EARLY_BIOME_MAX_ALPHA)
	end

	runSpawnLoop(activeFolder)
	runIncomeLoop()
end

return CrewmateGameplayService
