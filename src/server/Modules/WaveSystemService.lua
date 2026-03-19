local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WaveSystemService = {}

local REMOTES_FOLDER_NAME = "Remotes"
local KILL_REMOTE_NAME = "WaveKillRequest"
local PROGRESS_REMOTE_NAME = "WaveProgressSync"
local MAP_FOLDER_NAME = "Map"
local WAVE_FOLDER_NAME = "WaveFolder"
local CLIENT_WAVES_FOLDER_NAME = "ClientWaves"
local PAUSE_VALUE_NAME = "NoDisastersTimer"
local WAVES_FOLDER_NAME = "Waves"
local BIOMES_FOLDER_NAME = "Biomes"
local WAVE_RUNTIME_FOLDER_NAME = "WaveRuntime"
local DEBUG_ENABLED = true
local BIOME_BOUNDARIES = {
	{ Index = 1, Label = "Biome 1", Start = Vector3.new(-739.931, 25.693, -28.6) },
	{ Index = 2, Label = "Biome 2", Start = Vector3.new(-323.731, 25.693, -28.6) },
	{ Index = 3, Label = "Biome 3", Start = Vector3.new(210.069, 25.693, -28.6) },
	{ Index = 4, Label = "Biome 4", Start = Vector3.new(726.169, 25.693, -28.6) },
	{ Index = 5, Label = "Biome 5", Start = Vector3.new(1117.669, 25.693, -28.6) },
	{ Index = 6, Label = "Biome 6", Start = Vector3.new(1578.069, 25.693, -28.6) },
	{ Index = 7, Label = "Biome 7", Start = Vector3.new(2071.969, 25.693, -28.6) },
	{ Index = 8, Label = "Biome 8", Start = Vector3.new(2600.069, 25.693, -28.6), End = Vector3.new(3161.969, 25.693, -28.6) },
}

local joinOrder = {}
local started = false
local progressRemote: RemoteEvent
local killRemote: RemoteEvent
local activeWaveFolder: Instance?

local function debugLog(message: string)
	if DEBUG_ENABLED then
		print("[WaveSystemService] " .. message)
	end
end

local function describeChildren(parent: Instance): string
	local names = {}
	for _, child in ipairs(parent:GetChildren()) do
		names[#names + 1] = child.Name
	end
	table.sort(names)
	return table.concat(names, ", ")
end

local function ensureFolder(parent: Instance, name: string, className: string?): Instance
	local existing = parent:FindFirstChild(name)
	local expectedClass = className or "Folder"
	if existing and existing.ClassName == expectedClass then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local folder = Instance.new(expectedClass)
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensureRemote(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function ensurePart(parent: Instance, name: string, position: Vector3): BasePart
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("BasePart") then
		existing.Anchored = true
		existing.CanCollide = false
		existing.CanTouch = false
		existing.CanQuery = false
		existing.Transparency = 1
		existing.Size = Vector3.new(12, 1, 12)
		existing.Position = position
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(12, 1, 12)
	part.Position = position
	part.Parent = parent
	return part
end

local function ensureNumberValue(parent: Instance, name: string): NumberValue
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("NumberValue") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local value = Instance.new("NumberValue")
	value.Name = name
	value.Value = 0
	value.Parent = parent
	return value
end

local function ensureVector3Value(parent: Instance, name: string, value: Vector3): Vector3Value
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Vector3Value") then
		existing.Value = value
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local vectorValue = Instance.new("Vector3Value")
	vectorValue.Name = name
	vectorValue.Value = value
	vectorValue.Parent = parent
	return vectorValue
end

local function ensureStringValue(parent: Instance, name: string, value: string): StringValue
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("StringValue") then
		existing.Value = value
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local stringValue = Instance.new("StringValue")
	stringValue.Name = name
	stringValue.Value = value
	stringValue.Parent = parent
	return stringValue
end

local function ensureIntValue(parent: Instance, name: string, value: number): IntValue
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("IntValue") then
		existing.Value = value
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local intValue = Instance.new("IntValue")
	intValue.Name = name
	intValue.Value = value
	intValue.Parent = parent
	return intValue
end

local function extractNumericSuffix(name: string): number
	local digits = string.match(name, "(%d+)$")
	return tonumber(digits) or math.huge
end

local function getPartBounds(instance: Instance)
	local minVector: Vector3? = nil
	local maxVector: Vector3? = nil

	local function includePart(part: BasePart)
		local halfSize = part.Size * 0.5
		local corners = {
			part.CFrame * CFrame.new(-halfSize.X, -halfSize.Y, -halfSize.Z),
			part.CFrame * CFrame.new(-halfSize.X, -halfSize.Y, halfSize.Z),
			part.CFrame * CFrame.new(-halfSize.X, halfSize.Y, -halfSize.Z),
			part.CFrame * CFrame.new(-halfSize.X, halfSize.Y, halfSize.Z),
			part.CFrame * CFrame.new(halfSize.X, -halfSize.Y, -halfSize.Z),
			part.CFrame * CFrame.new(halfSize.X, -halfSize.Y, halfSize.Z),
			part.CFrame * CFrame.new(halfSize.X, halfSize.Y, -halfSize.Z),
			part.CFrame * CFrame.new(halfSize.X, halfSize.Y, halfSize.Z),
		}

		for _, corner in ipairs(corners) do
			local position = corner.Position
			if not minVector then
				minVector = position
				maxVector = position
			else
				minVector = Vector3.new(
					math.min(minVector.X, position.X),
					math.min(minVector.Y, position.Y),
					math.min(minVector.Z, position.Z)
				)
				maxVector = Vector3.new(
					math.max(maxVector.X, position.X),
					math.max(maxVector.Y, position.Y),
					math.max(maxVector.Z, position.Z)
				)
			end
		end
	end

	if instance:IsA("BasePart") then
		includePart(instance)
	else
		for _, descendant in ipairs(instance:GetDescendants()) do
			if descendant:IsA("BasePart") then
				includePart(descendant)
			end
		end
	end

	if minVector and maxVector then
		return minVector, maxVector
	end

	return nil
end

local function getInstanceCenter(instance: Instance): Vector3?
	local minVector, maxVector = getPartBounds(instance)
	if minVector and maxVector then
		return (minVector + maxVector) * 0.5
	end

	if instance:IsA("BasePart") then
		return instance.Position
	end

	if instance:IsA("Model") then
		local cf = instance:GetPivot()
		return cf.Position
	end

	local boxPart = instance:FindFirstChildWhichIsA("BasePart", true)
	if boxPart then
		return boxPart.Position
	end

	local model = instance:FindFirstChildWhichIsA("Model", true)
	if model then
		return model:GetPivot().Position
	end

	return nil
end

type BiomeData = {
	Name: string,
	Index: number,
	Center: Vector3,
	Min: Vector3,
	Max: Vector3,
}

local function getBiomeData(): { BiomeData }
	if #BIOME_BOUNDARIES >= 2 then
		local overriddenBiomeData = {}
		for index, boundary in ipairs(BIOME_BOUNDARIES) do
			local nextBoundary = BIOME_BOUNDARIES[index + 1]
			local startVector = boundary.Start
			local endVector = if boundary.End then boundary.End else (nextBoundary and nextBoundary.Start or boundary.Start)
			local minVector = Vector3.new(
				math.min(startVector.X, endVector.X),
				math.min(startVector.Y, endVector.Y),
				math.min(startVector.Z, endVector.Z)
			)
			local maxVector = Vector3.new(
				math.max(startVector.X, endVector.X),
				math.max(startVector.Y, endVector.Y),
				math.max(startVector.Z, endVector.Z)
			)
			overriddenBiomeData[#overriddenBiomeData + 1] = {
				Name = boundary.Label,
				Index = boundary.Index,
				Center = (startVector + endVector) * 0.5,
				Min = minVector,
				Max = maxVector,
			}
		end

		debugLog("Resolved " .. tostring(#overriddenBiomeData) .. " biome(s) from explicit boundary overrides")
		return overriddenBiomeData
	end

	local mapFolder = Workspace:FindFirstChild(MAP_FOLDER_NAME)
	if not mapFolder or not mapFolder:IsA("Folder") then
		debugLog("Map/Biomes folder missing; falling back to generic endpoints")
		return {}
	end

	local biomesFolder = mapFolder:FindFirstChild(BIOMES_FOLDER_NAME)
	if not biomesFolder or not biomesFolder:IsA("Folder") then
		debugLog("Biomes folder missing under Map; falling back to generic endpoints")
		return {}
	end

	local biomeChildren = biomesFolder:GetChildren()
	table.sort(biomeChildren, function(a, b)
		local aIndex = extractNumericSuffix(a.Name)
		local bIndex = extractNumericSuffix(b.Name)
		if aIndex == bIndex then
			return a.Name < b.Name
		end
		return aIndex < bIndex
	end)

	local biomeData = {}
	for _, biome in ipairs(biomeChildren) do
		local center = getInstanceCenter(biome)
		local minVector, maxVector = getPartBounds(biome)
		if center and minVector and maxVector then
			biomeData[#biomeData + 1] = {
				Name = biome.Name,
				Index = extractNumericSuffix(biome.Name),
				Center = center,
				Min = minVector,
				Max = maxVector,
			}
		end
	end

	debugLog("Resolved " .. tostring(#biomeData) .. " biome(s) for wave endpoints")

	return biomeData
end

local function getDefaultWaveEndpoints(): (Vector3, Vector3)
	if #BIOME_BOUNDARIES >= 2 then
		local firstBoundary = BIOME_BOUNDARIES[1]
		local lastBoundary = BIOME_BOUNDARIES[#BIOME_BOUNDARIES]
		local startVector = lastBoundary.End or lastBoundary.Start
		local endVector = firstBoundary.Start

		debugLog(
			("Using explicit centerline endpoints. Start=(%.1f, %.1f, %.1f) End=(%.1f, %.1f, %.1f)"):format(
				startVector.X,
				startVector.Y,
				startVector.Z,
				endVector.X,
				endVector.Y,
				endVector.Z
			)
		)

		return startVector, endVector
	end

	local biomeData = getBiomeData()
	if #biomeData >= 2 then
		local firstBiome = biomeData[1]
		local lastBiome = biomeData[#biomeData]
		local startVector = lastBiome.Center
		local endVector = firstBiome.Center

		debugLog(
			("Using biome center endpoints. Start=(%.1f, %.1f, %.1f) End=(%.1f, %.1f, %.1f)"):format(
				startVector.X,
				startVector.Y,
				startVector.Z,
				endVector.X,
				endVector.Y,
				endVector.Z
			)
		)

		return startVector, endVector
	end

	debugLog("Using fallback generic endpoints")
	return Vector3.new(0, 3, -140), Vector3.new(0, 3, 140)
end

local function resolveWaveFolder(): Instance
	local mapFolder = ensureFolder(Workspace, MAP_FOLDER_NAME, "Folder")
	return ensureFolder(mapFolder, WAVE_FOLDER_NAME, "Folder")
end

local function removeFromJoinOrder(userId: number)
	for index = #joinOrder, 1, -1 do
		if joinOrder[index] == userId then
			table.remove(joinOrder, index)
		end
	end
end

local function buildPayload()
	local payload = {}
	for _, userId in ipairs(joinOrder) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			payload[#payload + 1] = {
				UserId = player.UserId,
				Name = player.Name,
			}
		end
	end
	return payload
end

local function broadcastProgress()
	local payload = buildPayload()
	progressRemote:FireAllClients(#payload, payload)
end

local function sendProgress(player: Player)
	local payload = buildPayload()
	progressRemote:FireClient(player, #payload, payload)
end

local function ensureWaveFolderContents(waveFolder: Instance)
	local defaultStart, defaultEnd = getDefaultWaveEndpoints()
	ensurePart(waveFolder, "Start", defaultStart)
	ensurePart(waveFolder, "End", defaultEnd)
	ensureFolder(waveFolder, CLIENT_WAVES_FOLDER_NAME, "Folder")
	ensureFolder(waveFolder, "GrandLineRush", "Folder")
	debugLog("Ensured WaveFolder contents at " .. waveFolder:GetFullName())
	debugLog("WaveFolder children now: " .. describeChildren(waveFolder))
end

local function ensureWaveRuntimeData()
	local runtimeFolder = ensureFolder(ReplicatedStorage, WAVE_RUNTIME_FOLDER_NAME, "Folder")
	local defaultStart, defaultEnd = getDefaultWaveEndpoints()
	ensureVector3Value(runtimeFolder, "StartPosition", defaultStart)
	ensureVector3Value(runtimeFolder, "EndPosition", defaultEnd)

	local biomePointsFolder = ensureFolder(runtimeFolder, "BiomePoints", "Folder")
	local biomeDataFolder = ensureFolder(runtimeFolder, "BiomeData", "Folder")
	local biomeData = getBiomeData()
	for index, biome in ipairs(biomeData) do
		ensureVector3Value(biomePointsFolder, "Biome" .. tostring(index), biome.Center)

		local biomeFolder = ensureFolder(biomeDataFolder, "Biome" .. tostring(index), "Folder")
		ensureIntValue(biomeFolder, "Index", biome.Index)
		ensureStringValue(biomeFolder, "Label", biome.Name)
		ensureVector3Value(biomeFolder, "Center", biome.Center)
		ensureVector3Value(biomeFolder, "Min", biome.Min)
		ensureVector3Value(biomeFolder, "Max", biome.Max)
	end

	for _, child in ipairs(biomePointsFolder:GetChildren()) do
		local numericSuffix = string.match(child.Name, "(%d+)$")
		local numericIndex = tonumber(numericSuffix)
		if not numericIndex or numericIndex > #biomeData then
			child:Destroy()
		end
	end

	for _, child in ipairs(biomeDataFolder:GetChildren()) do
		local numericSuffix = string.match(child.Name, "(%d+)$")
		local numericIndex = tonumber(numericSuffix)
		if not numericIndex or numericIndex > #biomeData then
			child:Destroy()
		end
	end

	debugLog("Updated replicated WaveRuntime data")
end

local function ensureRuntimeFolders()
	local remotesFolder = ensureFolder(ReplicatedStorage, REMOTES_FOLDER_NAME, "Folder")
	progressRemote = ensureRemote(remotesFolder, PROGRESS_REMOTE_NAME)
	killRemote = ensureRemote(remotesFolder, KILL_REMOTE_NAME)

	ensureFolder(ReplicatedStorage, WAVES_FOLDER_NAME, "Folder")

	local waveFolder = resolveWaveFolder()
	activeWaveFolder = waveFolder
	ensureWaveFolderContents(waveFolder)
	ensureWaveRuntimeData()

	ensureNumberValue(Workspace, PAUSE_VALUE_NAME)
	debugLog("Runtime folders and remotes are ready")
end

local function onKillRequest(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
	end
end

function WaveSystemService.Start()
	if started then
		debugLog("Start() ignored because service is already running")
		return
	end

	started = true
	debugLog("Starting wave system service")
	ensureRuntimeFolders()

	if activeWaveFolder then
		activeWaveFolder.ChildAdded:Connect(function(child)
			debugLog("WaveFolder child added: " .. child.Name)
		end)
		activeWaveFolder.ChildRemoved:Connect(function(child)
			debugLog("WaveFolder child removed: " .. child.Name)
			if child.Name == "Start" or child.Name == "End" or child.Name == CLIENT_WAVES_FOLDER_NAME or child.Name == "GrandLineRush" then
				task.defer(function()
					if activeWaveFolder and activeWaveFolder.Parent then
						ensureWaveFolderContents(activeWaveFolder)
					end
				end)
			end
		end)
	end

	progressRemote.OnServerEvent:Connect(function(player, action)
		if action == "Request" then
			debugLog("Received progress sync request from " .. player.Name)
			sendProgress(player)
		end
	end)

	killRemote.OnServerEvent:Connect(onKillRequest)

	for _, player in ipairs(Players:GetPlayers()) do
		joinOrder[#joinOrder + 1] = player.UserId
	end

	Players.PlayerAdded:Connect(function(player)
		joinOrder[#joinOrder + 1] = player.UserId
		task.defer(broadcastProgress)
		task.delay(1, function()
			if player.Parent then
				sendProgress(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		removeFromJoinOrder(player.UserId)
		task.defer(broadcastProgress)
	end)

	broadcastProgress()
end

return WaveSystemService
