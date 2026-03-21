local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(packages:WaitForChild("React"))
local ReactRoblox = require(packages:WaitForChild("ReactRoblox"))
local e = React.createElement

local modules = ReplicatedStorage:WaitForChild("Modules")
local WavesConfig = require(modules:WaitForChild("Configs"):WaitForChild("LavaWaves"))
local HazardRuntime = require(modules:WaitForChild("DevilFruits"):WaitForChild("HazardRuntime"))
local ProtectionRuntime = require(modules:WaitForChild("DevilFruits"):WaitForChild("ProtectionRuntime"))
local WaveProgressBar = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("WaveProgressBar"))
local DEBUG_ENABLED = true

local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local progressRemote = remotes:WaitForChild("WaveProgressSync")
local killRemote = remotes:WaitForChild("WaveKillRequest")
local wavesFolder = ReplicatedStorage:WaitForChild("Waves")
local waveRuntimeFolder = ReplicatedStorage:WaitForChild("WaveRuntime")
local startPositionValue = waveRuntimeFolder:WaitForChild("StartPosition")
local endPositionValue = waveRuntimeFolder:WaitForChild("EndPosition")
local biomeDataFolder = waveRuntimeFolder:WaitForChild("BiomeData")

local function resolveWaveFolder(): Instance
	local waitedMap = Workspace:WaitForChild("Map")
	return waitedMap:WaitForChild("WaveFolder")
end

local waveFolder = resolveWaveFolder()
local clientWavesFolder = waveFolder:WaitForChild("ClientWaves")
local pauseValue = Workspace:WaitForChild("NoDisastersTimer")

local rootContainer = Instance.new("Folder")
rootContainer.Name = "WaveProgressRoot"
local root = ReactRoblox.createRoot(rootContainer)

local rng = Random.new()
local destroyed = false
local renderQueued = false
local orderedPlayers = {}
local waveEntries = {}
local cleanupConnections = {}
local biomeSections = {}
local pathAxis = -Vector3.xAxis
local pathLength = 1

local function debugLog(message)
	if DEBUG_ENABLED then
		print("[SpawnWaves] " .. message)
	end
end

local function track(signal, callback)
	local connection = signal:Connect(callback)
	cleanupConnections[#cleanupConnections + 1] = connection
	return connection
end

local function disconnectAll()
	for _, connection in ipairs(cleanupConnections) do
		connection:Disconnect()
	end
	table.clear(cleanupConnections)
end

local function clearClientWaves()
	for _, child in ipairs(clientWavesFolder:GetChildren()) do
		child:Destroy()
	end
	table.clear(waveEntries)
end

local function getWaveImage(config)
	return config.Image or config.IMAGE or ""
end

local function extractNumericSuffix(name)
	local digits = string.match(name, "(%d+)$")
	return tonumber(digits) or math.huge
end

local function rebuildBiomeSections()
	biomeSections = {}

	local startPosition = startPositionValue.Value
	local endPosition = endPositionValue.Value
	local travelVector = endPosition - startPosition
	pathLength = math.max(travelVector.Magnitude, 1)
	pathAxis = if travelVector.Magnitude > 1e-6 then travelVector.Unit else -Vector3.xAxis

	local runtimeBiomes = biomeDataFolder:GetChildren()
	table.sort(runtimeBiomes, function(a, b)
		local aIndexValue = a:FindFirstChild("Index")
		local bIndexValue = b:FindFirstChild("Index")
		local aIndex = aIndexValue and aIndexValue:IsA("IntValue") and aIndexValue.Value or extractNumericSuffix(a.Name)
		local bIndex = bIndexValue and bIndexValue:IsA("IntValue") and bIndexValue.Value or extractNumericSuffix(b.Name)
		return aIndex < bIndex
	end)

	local includedProjectionLength = 0
	for _, biomeFolder in ipairs(runtimeBiomes) do
		local indexValue = biomeFolder:FindFirstChild("Index")
		local labelValue = biomeFolder:FindFirstChild("Label")
		local minValue = biomeFolder:FindFirstChild("Min")
		local maxValue = biomeFolder:FindFirstChild("Max")
		local biomeIndex = indexValue and indexValue:IsA("IntValue") and indexValue.Value
			or extractNumericSuffix(biomeFolder.Name)
		if minValue and minValue:IsA("Vector3Value") and maxValue and maxValue:IsA("Vector3Value") then
			local minProjection = (minValue.Value - startPosition):Dot(pathAxis)
			local maxProjection = (maxValue.Value - startPosition):Dot(pathAxis)
			local sectionProjection = math.max(0, maxProjection - minProjection)
			if sectionProjection > 0 then
				includedProjectionLength += sectionProjection
				biomeSections[#biomeSections + 1] = {
					label = if biomeIndex == 1
						then "Impact Zone"
						else (
							labelValue and labelValue:IsA("StringValue") and labelValue.Value
							or ("Biome " .. tostring(biomeIndex))
						),
					index = biomeIndex,
					projectionLength = sectionProjection,
					isImpact = biomeIndex == 1,
				}
			end
		end
	end

	for _, section in ipairs(biomeSections) do
		section.widthScale = if includedProjectionLength > 0
			then section.projectionLength / includedProjectionLength
			else 1 / math.max(#biomeSections, 1)
	end

	debugLog("Rebuilt biome mapping with " .. tostring(#biomeSections) .. " visible section(s)")
end

local function getProgressOnPath(worldPosition)
	local projection = (worldPosition - startPositionValue.Value):Dot(pathAxis)
	return math.clamp(projection / math.max(pathLength, 1), 0, 1)
end

local function getDisplayAlpha(worldPosition)
	local progressAlpha = getProgressOnPath(worldPosition)
	return 0.97 - (progressAlpha * 0.94)
end

local function createFallbackWave(config)
	local fallback = config.Fallback or {}
	local part = Instance.new("Part")
	part.Name = "Wave"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = true
	part.CanQuery = false
	part.Material = fallback.Material or Enum.Material.Neon
	part.Color = fallback.Color or Color3.fromRGB(255, 119, 69)
	part.Size = fallback.Size or Vector3.new(28, 14, 6)
	part.Shape = fallback.Shape or Enum.PartType.Block
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("HazardClass", fallback.HazardClass or "major")
	part:SetAttribute("HazardType", fallback.HazardType or "wave")
	part:SetAttribute("CanFreeze", fallback.CanFreeze ~= false)
	part:SetAttribute("FreezeBehavior", fallback.FreezeBehavior or "pause")
	return part
end

local function cloneWaveTemplate(waveName, config)
	local template = wavesFolder:FindFirstChild(waveName)
	if template and (template:IsA("BasePart") or template:IsA("Model")) then
		debugLog("Using wave template " .. template:GetFullName())
		local clone = template:Clone()
		clone.Name = waveName
		return clone
	end

	debugLog("Wave template '" .. waveName .. "' missing; using fallback part")
	local fallback = createFallbackWave(config)
	fallback.Name = waveName
	return fallback
end

local function setPivot(instance, cf)
	if instance:IsA("Model") then
		instance:PivotTo(cf)
	else
		instance.CFrame = cf
	end
end

local function getPivot(instance)
	if instance:IsA("Model") then
		return instance:GetPivot()
	end
	return instance.CFrame
end

local function getBoundingBox(instance)
	if instance:IsA("Model") then
		return instance:GetBoundingBox()
	end
	return instance.CFrame, instance.Size
end

local function anchorInstance(instance)
	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanQuery = false
		return
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
		end
	end
end

local function getPrimaryPart(instance)
	if instance:IsA("BasePart") then
		return instance
	end

	if instance.PrimaryPart then
		return instance.PrimaryPart
	end

	local part = instance:FindFirstChildWhichIsA("BasePart", true)
	if part then
		pcall(function()
			instance.PrimaryPart = part
		end)
	end
	return part
end

local function getTopPivot(instance, refPart)
	local boxCf, boxSize = getBoundingBox(instance)
	local currentPivot = getPivot(instance)
	local pivotOffset = currentPivot:ToObjectSpace(boxCf)
	local surface = refPart.Position - (refPart.CFrame.UpVector * (refPart.Size.Y * 0.5))
	local authoredRotation = currentPivot - currentPivot.Position
	local desiredBoxCf = CFrame.new(surface + Vector3.new(0, boxSize.Y * 0.5, 0)) * authoredRotation
	return desiredBoxCf * pivotOffset:Inverse()
end

local function isLocalRoot(hit)
	local character = LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	return rootPart ~= nil and hit == rootPart
end

local function killLocalPlayer()
	local character = LocalPlayer.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not rootPart then
		return
	end

	if ProtectionRuntime.TryConsume(LocalPlayer, rootPart.Position, "WaveKill") then
		return
	end

	killRemote:FireServer()
end

local function hookKillOnTouch(instance)
	local function hookPart(part)
		part.CanTouch = true
		part.CanCollide = false
		part.CanQuery = false
		part.Touched:Connect(function(hit)
			if isLocalRoot(hit) then
				killLocalPlayer()
			end
		end)
	end

	if instance:IsA("BasePart") then
		hookPart(instance)
		return
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			hookPart(descendant)
		end
	end
end

local function createFreezeController(hazardRoot, tween)
	local controller = {
		HazardRoot = hazardRoot,
		Tween = tween,
		FrozenUntil = 0,
		Destroyed = false,
	}

	function controller:SetFrozen(isFrozen)
		if self.Destroyed then
			return
		end

		if isFrozen then
			if self.Tween.PlaybackState == Enum.PlaybackState.Playing then
				pcall(function()
					self.Tween:Pause()
				end)
			end
		elseif self.Tween.PlaybackState == Enum.PlaybackState.Paused then
			pcall(function()
				self.Tween:Play()
			end)
		end
	end

	function controller:Freeze(duration)
		if self.Destroyed or not self.HazardRoot.Parent then
			return false
		end

		local freezeDuration = math.max(0, tonumber(duration) or 0)
		if freezeDuration <= 0 then
			return false
		end

		self.FrozenUntil = math.max(self.FrozenUntil, os.clock() + freezeDuration)
		self:SetFrozen(true)

		task.spawn(function()
			while not self.Destroyed and self.HazardRoot.Parent and os.clock() < self.FrozenUntil do
				task.wait(0.05)
			end

			if self.Destroyed or not self.HazardRoot.Parent then
				return
			end

			self:SetFrozen(false)
		end)

		return true
	end

	function controller:Destroy()
		if self.Destroyed then
			return
		end

		self.Destroyed = true
		HazardRuntime.Unregister(self.HazardRoot)
	end

	HazardRuntime.Register(hazardRoot, controller)
	return controller
end

local function scheduleRender()
	if destroyed or renderQueued then
		return
	end

	renderQueued = true
	task.defer(function()
		renderQueued = false
		if destroyed then
			return
		end

		local playerMarkers = {}
		for _, info in ipairs(orderedPlayers) do
			local player = Players:GetPlayerByUserId(info.UserId)
			local character = player and player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local alpha = 0
			if rootPart then
				alpha = getDisplayAlpha(rootPart.Position)
			end

			playerMarkers[#playerMarkers + 1] = {
				alpha = alpha,
				userId = info.UserId,
				isDead = humanoid ~= nil and humanoid.Health <= 0,
			}
		end

		local activeWaves = {}
		for waveInstance, data in pairs(waveEntries) do
			if waveInstance.Parent then
				local worldPosition = if waveInstance:IsA("Model")
					then waveInstance:GetPivot().Position
					else waveInstance.Position
				activeWaves[#activeWaves + 1] = {
					alpha = getDisplayAlpha(worldPosition),
					image = data.Image,
				}
			else
				waveEntries[waveInstance] = nil
			end
		end

		root:render(ReactRoblox.createPortal(
			e(WaveProgressBar, {
				players = playerMarkers,
				waves = activeWaves,
				startLabel = "Impact",
				endLabel = "Spawn",
				sections = biomeSections,
			}),
			playerGui
		))
	end)
end

local function chooseWaveEntry()
	local entries = {}
	local totalChance = 0

	for waveName, config in pairs(WavesConfig) do
		local chance = math.max(0, tonumber(config.Chance) or 0)
		entries[#entries + 1] = {
			Name = waveName,
			Config = config,
			Chance = chance,
		}
		totalChance += chance
	end

	if #entries == 0 then
		return nil
	end

	if totalChance <= 0 then
		return entries[rng:NextInteger(1, #entries)]
	end

	local pick = rng:NextNumber(0, totalChance)
	local running = 0
	for _, entry in ipairs(entries) do
		running += entry.Chance
		if pick <= running then
			return entry
		end
	end

	return entries[#entries]
end

local function spawnWave()
	local entry = chooseWaveEntry()
	if not entry then
		debugLog("No wave entry available from LavaWaves config")
		return
	end

	debugLog("Attempting to spawn wave '" .. entry.Name .. "'")
	local wave = cloneWaveTemplate(entry.Name, entry.Config)
	wave.Parent = clientWavesFolder
	anchorInstance(wave)
	hookKillOnTouch(wave)

	local startGuidePart = Instance.new("Part")
	startGuidePart.Anchored = true
	startGuidePart.CanCollide = false
	startGuidePart.CanTouch = false
	startGuidePart.CanQuery = false
	startGuidePart.Transparency = 1
	startGuidePart.Size = Vector3.new(12, 1, 12)
	local travelDirection = (endPositionValue.Value - startPositionValue.Value)
	if travelDirection.Magnitude <= 1e-6 then
		travelDirection = -Vector3.xAxis
	else
		travelDirection = travelDirection.Unit
	end
	startGuidePart.CFrame = CFrame.lookAt(startPositionValue.Value, startPositionValue.Value + travelDirection)

	local endGuidePart = Instance.new("Part")
	endGuidePart.Anchored = true
	endGuidePart.CanCollide = false
	endGuidePart.CanTouch = false
	endGuidePart.CanQuery = false
	endGuidePart.Transparency = 1
	endGuidePart.Size = Vector3.new(12, 1, 12)
	endGuidePart.CFrame = CFrame.lookAt(endPositionValue.Value, endPositionValue.Value + travelDirection)

	local startCf = getTopPivot(wave, startGuidePart)
	local endCf = getTopPivot(wave, endGuidePart)
	setPivot(wave, startCf)

	local speed = math.max(1, tonumber(entry.Config.Speed) or 50)
	local distance = (startCf.Position - endCf.Position).Magnitude
	local duration = math.max(0.05, distance / speed)
	debugLog(
		("Spawned '%s' from (%.1f, %.1f, %.1f) to (%.1f, %.1f, %.1f) over %.2fs"):format(
			entry.Name,
			startCf.Position.X,
			startCf.Position.Y,
			startCf.Position.Z,
			endCf.Position.X,
			endCf.Position.Y,
			endCf.Position.Z,
			duration
		)
	)
	startGuidePart:Destroy()
	endGuidePart:Destroy()

	local targetPart = getPrimaryPart(wave)
	local tweenTarget = targetPart or wave
	local tweenProperty = if tweenTarget:IsA("BasePart") then { CFrame = endCf } else { Value = 1 }
	local alphaValue = nil
	local tween

	if tweenTarget:IsA("BasePart") then
		tween = TweenService:Create(
			tweenTarget,
			TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
			tweenProperty
		)
	else
		alphaValue = Instance.new("NumberValue")
		alphaValue.Value = 0
		alphaValue.Parent = wave
		alphaValue:GetPropertyChangedSignal("Value"):Connect(function()
			setPivot(wave, startCf:Lerp(endCf, alphaValue.Value))
		end)
		tween = TweenService:Create(
			alphaValue,
			TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
			tweenProperty
		)
	end

	local freezeController = createFreezeController(wave, tween)
	waveEntries[wave] = {
		Image = getWaveImage(entry.Config),
	}

	tween.Completed:Connect(function()
		freezeController:Destroy()
		waveEntries[wave] = nil
		if alphaValue then
			alphaValue:Destroy()
		end
		if wave.Parent then
			wave:Destroy()
		end
		scheduleRender()
	end)

	tween:Play()
	scheduleRender()
end

track(progressRemote.OnClientEvent, function(_, payload)
	orderedPlayers = payload or {}
	scheduleRender()
end)

track(Players.PlayerAdded, scheduleRender)
track(Players.PlayerRemoving, scheduleRender)
track(RunService.RenderStepped, function()
	scheduleRender()
end)

track(clientWavesFolder.ChildRemoved, scheduleRender)
track(pauseValue:GetPropertyChangedSignal("Value"), function()
	debugLog("Pause value changed to " .. tostring(pauseValue.Value))
	if pauseValue.Value > 0 then
		clearClientWaves()
		debugLog("Cleared client waves because the system is paused")
	end
	scheduleRender()
end)

debugLog("Client wave script started")
debugLog("WaveFolder resolved to " .. waveFolder:GetFullName())
debugLog("Start position is " .. tostring(startPositionValue.Value))
debugLog("End position is " .. tostring(endPositionValue.Value))
debugLog("Pause value is " .. tostring(pauseValue.Value))

progressRemote:FireServer("Request")
rebuildBiomeSections()
scheduleRender()

task.spawn(function()
	local firstSpawn = true
	while not destroyed do
		if pauseValue.Value <= 0 then
			spawnWave()
			if firstSpawn then
				firstSpawn = false
				debugLog("First wave spawned; waiting 0.5s before next loop")
				task.wait(0.5)
			else
				debugLog("Waiting 20-23 seconds for the next wave")
				task.wait(rng:NextInteger(20, 23))
			end
		else
			task.wait(0.2)
		end
	end
end)

script.Destroying:Connect(function()
	destroyed = true
	disconnectAll()
	clearClientWaves()
	root:unmount()
end)

if biomeDataFolder and biomeDataFolder:IsA("Folder") then
	track(biomeDataFolder.ChildAdded, function()
		rebuildBiomeSections()
		scheduleRender()
	end)
	track(biomeDataFolder.ChildRemoved, function()
		rebuildBiomeSections()
		scheduleRender()
	end)
end

track(startPositionValue:GetPropertyChangedSignal("Value"), function()
	rebuildBiomeSections()
	scheduleRender()
end)

track(endPositionValue:GetPropertyChangedSignal("Value"), function()
	rebuildBiomeSections()
	scheduleRender()
end)
