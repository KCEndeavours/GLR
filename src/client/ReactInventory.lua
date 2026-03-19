local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ReactInventory = {}

local HOTBAR_FOLDER_NAME = "InventoryHotbar"
local HOTBAR_SLOT_COUNT = 5
local TOGGLE_ICON_ID = "rbxassetid://129583821766521"
local SHOP_ICON_ID = ""

local TOGGLE_LAYOUT = {
	anchorPoint = Vector2.new(0, 0.5),
	position = UDim2.new(0, 18, 0.5, 0),
	size = UDim2.fromOffset(70, 70),
	compact = true,
	dock = "hotbarLeft",
}

local SHOP_LAYOUT = {
	anchorPoint = Vector2.new(0, 0.5),
	position = UDim2.new(0, 100, 0.5, 0),
	size = UDim2.fromOffset(70, 70),
	compact = true,
	dock = "hotbarLeft",
}

local CATEGORY_DEFS = {
	Crewmates = {
		label = "Crewmates",
		accentColor = Color3.fromRGB(93, 203, 200),
	},
	DevilFruits = {
		label = "Devil Fruits",
		accentColor = Color3.fromRGB(239, 129, 156),
	},
	Resources = {
		label = "Resources",
		accentColor = Color3.fromRGB(241, 184, 86),
	},
}

local RARITY_ORDER = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythical = 6,
	Mythic = 6,
	Godly = 7,
	Secret = 8,
}

local RARITY_COLORS = {
	Common = Color3.fromRGB(188, 197, 211),
	Uncommon = Color3.fromRGB(112, 220, 140),
	Rare = Color3.fromRGB(91, 170, 255),
	Epic = Color3.fromRGB(200, 120, 255),
	Legendary = Color3.fromRGB(255, 187, 74),
	Mythical = Color3.fromRGB(255, 101, 134),
	Mythic = Color3.fromRGB(255, 101, 134),
	Godly = Color3.fromRGB(255, 84, 84),
	Secret = Color3.fromRGB(255, 240, 110),
}

local CREW_VALUE_NAMES = {
	DisplayName = "DisplayName",
	Rarity = "Rarity",
	Level = "Level",
	CurrentXP = "CurrentXP",
	NextLevelXP = "NextLevelXP",
	ShipIncomePerHour = "ShipIncomePerHour",
}

local KEY_TO_SLOT = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
}

local started = false

local function trim(text)
	return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function matchesQuery(entry, query)
	if query == "" then
		return true
	end

	local haystack = string.lower(table.concat({
		tostring(entry.displayName or ""),
		tostring(entry.subtitle or ""),
		tostring(entry.footer or ""),
	}, " "))

	return string.find(haystack, string.lower(query), 1, true) ~= nil
end

local function countEntries(map)
	local count = 0
	for _ in pairs(map or {}) do
		count += 1
	end
	return count
end

local function initials(text)
	local letters = {}
	for token in string.gmatch(tostring(text or ""), "%S+") do
		letters[#letters + 1] = string.upper(string.sub(token, 1, 1))
		if #letters >= 2 then
			break
		end
	end

	if #letters == 0 then
		return "?"
	end

	return table.concat(letters)
end

local function getValue(parent, name, className)
	if not parent then
		return nil
	end

	local child = parent:FindFirstChild(name)
	if child and child.ClassName == className then
		return child.Value
	end

	return nil
end

function ReactInventory.Start()
	if started then
		return
	end

	started = true

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local inventoryRoot = player:WaitForChild("Inventory")
	local hotbarRoot = player:WaitForChild(HOTBAR_FOLDER_NAME)

	local packages = ReplicatedStorage:WaitForChild("Packages")
	local modules = ReplicatedStorage:WaitForChild("Modules")
	local uiFolder = ReplicatedStorage:WaitForChild("UI")

	local React = require(packages:WaitForChild("React"))
	local ReactRoblox = require(packages:WaitForChild("ReactRoblox"))
	local e = React.createElement
	local App = require(uiFolder:WaitForChild("App"))
	local ShopFolder = uiFolder:WaitForChild("Shop")
	local ShopShell = require(ShopFolder:WaitForChild("ShopShell"))
	local ShopCatalog = require(ShopFolder:WaitForChild("Catalog"))
	local PurchaseAdapter = require(ShopFolder:WaitForChild("PurchaseAdapter"))

	local Economy = require(modules:WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
	local CrewCatalog = require(modules:WaitForChild("Configs"):WaitForChild("GrandLineRushCrewCatalog"))
	local DevilFruitConfig = require(modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
	local DevilFruitAssets = require(modules:WaitForChild("DevilFruits"):WaitForChild("Assets"))

	local remotesFolder = ReplicatedStorage:WaitForChild("InventoryRemotes")
	local commandRemote = remotesFolder:WaitForChild("Command")
	local gameRemotes = ReplicatedStorage:WaitForChild("Remotes")
	local devilFruitConsumeRequestRemote = gameRemotes:WaitForChild("DevilFruitConsumeRequest")
	local chestConsumeRequestRemote = gameRemotes:WaitForChild("GrandLineRushChestConsumeRequest")
	local hotbarRequestRemote = gameRemotes:WaitForChild("InventoryHotbarRequest")

	local rootContainer = Instance.new("Folder")
	rootContainer.Name = "ReactInventoryRoot"
	local root = ReactRoblox.createRoot(rootContainer)

	local cleanupConnections = {}
	local inventory = {}
	local hotbar = {}
	local destroyed = false
	local renderQueued = false
	local scheduleRender
	local isOpen = false
	local isShopOpen = false
	local activeView = "Inventory"
	local activeCategory = "Crewmates"
	local query = ""
	local noticeText = nil
	local noticeToken = 0
	local selectedHotbarSlot = nil
	local heldFruitVisual = nil
	local heldFruitKey = nil
	local purchaseAdapter = PurchaseAdapter.new(player)

	local function disconnectAll()
		for _, connection in ipairs(cleanupConnections) do
			connection:Disconnect()
		end
		table.clear(cleanupConnections)
	end

	local function setNotice(text)
		noticeText = text
		noticeToken += 1
		local currentToken = noticeToken
		scheduleRender()

		if text then
			task.delay(2.8, function()
				if destroyed or noticeToken ~= currentToken then
					return
				end

				noticeText = nil
				scheduleRender()
			end)
		end
	end

	local function buildCatalogViewModel()
		local catalog = {
			title = ShopCatalog.title,
			subtitle = ShopCatalog.subtitle,
			heroEyebrow = ShopCatalog.heroEyebrow,
			heroHeadline = ShopCatalog.heroHeadline,
			heroCopy = ShopCatalog.heroCopy,
			codesPanel = ShopCatalog.codesPanel,
			featuredOffers = {},
			sections = {},
		}

		for index, item in ipairs(ShopCatalog.featuredOffers or {}) do
			catalog.featuredOffers[index] = purchaseAdapter:getViewModel(item)
		end

		for sectionIndex, section in ipairs(ShopCatalog.sections or {}) do
			local sectionModel = {
				key = section.key,
				title = section.title,
				eyebrow = section.eyebrow,
				description = section.description,
				themeKey = section.themeKey,
				items = {},
			}

			for itemIndex, item in ipairs(section.items or {}) do
				sectionModel.items[itemIndex] = purchaseAdapter:getViewModel(item)
			end

			catalog.sections[sectionIndex] = sectionModel
		end

		return catalog
	end

	local function track(signal, callback)
		local connection = signal:Connect(callback)
		cleanupConnections[#cleanupConnections + 1] = connection
		return connection
	end

	local function destroyHeldFruitVisual()
		if heldFruitVisual then
			heldFruitVisual:Destroy()
			heldFruitVisual = nil
		end
		heldFruitKey = nil
	end

	local function getCharacterHand(character)
		local rightHand = character:FindFirstChild("RightHand")
		if rightHand and rightHand:IsA("BasePart") then
			return rightHand
		end

		local rightArm = character:FindFirstChild("Right Arm")
		if rightArm and rightArm:IsA("BasePart") then
			return rightArm
		end

		return nil
	end

	local function findPrimaryPart(model)
		if model.PrimaryPart then
			return model.PrimaryPart
		end

		local handle = model:FindFirstChild("Handle", true)
		if handle and handle:IsA("BasePart") then
			return handle
		end

		return model:FindFirstChildWhichIsA("BasePart", true)
	end

	local function normalizeHeldModel(sourceModel)
		if sourceModel:IsA("Model") then
			return sourceModel
		end

		if sourceModel:IsA("WorldModel") then
			local model = Instance.new("Model")
			for _, child in ipairs(sourceModel:GetChildren()) do
				child.Parent = model
			end
			sourceModel:Destroy()
			return model
		end

		return nil
	end

	local function buildHeldFruitVisual(fruitKey)
		local fruit = DevilFruitConfig.GetFruit(fruitKey)
		local character = player.Character
		if not fruit or not character then
			return
		end

		local hand = getCharacterHand(character)
		if not hand then
			return
		end

		local clone = DevilFruitAssets.CloneWorldModel(fruitKey)
		if not clone then
			return
		end

		local model = normalizeHeldModel(clone)
		if not model then
			return
		end

		model.Name = "HeldFruitVisual"

		local primaryPart = findPrimaryPart(model)
		if not primaryPart then
			model:Destroy()
			return
		end

		pcall(function()
			model.PrimaryPart = primaryPart
		end)

		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = false
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
				descendant.Massless = true
				if descendant ~= primaryPart then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = primaryPart
					weld.Part1 = descendant
					weld.Parent = descendant
				end
			end
		end

		model.Parent = character
		local _, modelSize = model:GetBoundingBox()
		local holdOffset = Vector3.new(0, 0, -(hand.Size.Z * 0.5 + modelSize.Z * 0.32))
		model:PivotTo(hand.CFrame * CFrame.new(holdOffset))

		local handWeld = Instance.new("WeldConstraint")
		handWeld.Part0 = hand
		handWeld.Part1 = primaryPart
		handWeld.Parent = primaryPart

		heldFruitVisual = model
		heldFruitKey = fruitKey
	end

	local function refreshHeldFruitVisual()
		local slotState = selectedHotbarSlot and hotbar[selectedHotbarSlot] or nil
		if not slotState or slotState.ItemType ~= "DevilFruit" then
			destroyHeldFruitVisual()
			return
		end

		if heldFruitVisual and heldFruitKey == slotState.ItemId and heldFruitVisual.Parent == player.Character then
			return
		end

		destroyHeldFruitVisual()
		buildHeldFruitVisual(slotState.ItemId)
	end

	local function readInventoryMirror()
		local snapshot = {}

		for _, typeFolder in ipairs(inventoryRoot:GetChildren()) do
			if typeFolder:IsA("Folder") then
				snapshot[typeFolder.Name] = {}
				for _, itemFolder in ipairs(typeFolder:GetChildren()) do
					if itemFolder:IsA("Folder") then
						snapshot[typeFolder.Name][itemFolder.Name] = {
							ItemType = getValue(itemFolder, "ItemType", "StringValue") or typeFolder.Name,
							ItemId = getValue(itemFolder, "ItemId", "StringValue") or itemFolder.Name,
							Quantity = getValue(itemFolder, "Quantity", "NumberValue") or 0,
							Equipped = getValue(itemFolder, "Equipped", "BoolValue") == true,
							DisplayName = getValue(itemFolder, CREW_VALUE_NAMES.DisplayName, "StringValue"),
							Rarity = getValue(itemFolder, CREW_VALUE_NAMES.Rarity, "StringValue"),
							Level = getValue(itemFolder, CREW_VALUE_NAMES.Level, "NumberValue"),
							CurrentXP = getValue(itemFolder, CREW_VALUE_NAMES.CurrentXP, "NumberValue"),
							NextLevelXP = getValue(itemFolder, CREW_VALUE_NAMES.NextLevelXP, "NumberValue"),
							ShipIncomePerHour = getValue(itemFolder, CREW_VALUE_NAMES.ShipIncomePerHour, "NumberValue"),
						}
					end
				end
			end
		end

		return snapshot
	end

	local function readHotbarMirror()
		local snapshot = {}
		for slotIndex = 1, HOTBAR_SLOT_COUNT do
			local slotFolder = hotbarRoot:FindFirstChild(string.format("Slot%d", slotIndex))
			if slotFolder and slotFolder:IsA("Folder") then
				local itemType = getValue(slotFolder, "ItemType", "StringValue")
				local itemId = getValue(slotFolder, "ItemId", "StringValue")
				if itemType and itemId and itemType ~= "" and itemId ~= "" then
					snapshot[slotIndex] = {
						ItemType = itemType,
						ItemId = itemId,
					}
				end
			end
		end
		return snapshot
	end

	local function getAssignedSlot(itemType, itemId)
		for slotIndex = 1, HOTBAR_SLOT_COUNT do
			local slotState = hotbar[slotIndex]
			if slotState and slotState.ItemType == itemType and slotState.ItemId == itemId then
				return slotIndex
			end
		end
		return nil
	end

	local function getPreferredHotbarSlot()
		for slotIndex = 1, HOTBAR_SLOT_COUNT do
			if hotbar[slotIndex] == nil then
				return selectedHotbarSlot or slotIndex
			end
		end
		return selectedHotbarSlot or 1
	end

	local function requestSlotAssignment(itemType, itemId)
		hotbarRequestRemote:FireServer("AssignSlot", {
			SlotIndex = getPreferredHotbarSlot(),
			ItemType = itemType,
			ItemId = itemId,
		})
	end

	local function requestSlotClear(slotIndex)
		hotbarRequestRemote:FireServer("ClearSlot", {
			SlotIndex = slotIndex,
		})
	end

	local function buildCrewEntry(itemKey, state)
		local displayName = state.DisplayName or CrewCatalog.Starter.Name or state.ItemId
		local rarity = state.Rarity or "Common"
		local level = math.floor(tonumber(state.Level) or 1)
		local currentXP = math.floor(tonumber(state.CurrentXP) or 0)
		local nextLevelXP = math.floor(tonumber(state.NextLevelXP) or 0)

		return {
			key = itemKey,
			kind = "Crewmate",
			name = state.ItemId,
			displayName = displayName,
			subtitle = rarity,
			footer = nextLevelXP > 0
				and string.format("Level %d  |  XP %d/%d", level, currentXP, nextLevelXP)
				or string.format("Level %d", level),
			fallbackText = initials(displayName),
			accentColor = RARITY_COLORS[rarity] or CATEGORY_DEFS.Crewmates.accentColor,
			interactive = false,
			level = level,
			currentXP = currentXP,
			nextLevelXP = nextLevelXP,
			shipIncomePerHour = math.floor(tonumber(state.ShipIncomePerHour) or 0),
		}
	end

	local function buildDevilFruitEntry(itemKey, state, slotIndex)
		local fruit = DevilFruitConfig.GetFruit(state.ItemId)
		local displayName = fruit and fruit.DisplayName or state.ItemId
		local rarity = fruit and tostring(fruit.Rarity or "Devil Fruit") or "Devil Fruit"
		local slotText = slotIndex and string.format("Assigned to Slot %d", slotIndex) or "Click to quick-equip"

		return {
			key = itemKey,
			kind = "DevilFruit",
			name = state.ItemId,
			displayName = displayName,
			subtitle = rarity,
			footer = string.format("Quantity %d  |  %s", math.max(0, state.Quantity or 0), slotText),
			fallbackText = initials(displayName),
			accentColor = RARITY_COLORS[rarity] or CATEGORY_DEFS.DevilFruits.accentColor,
			interactive = true,
			previewKind = "DevilFruit",
			previewName = state.ItemId,
			isEquipped = slotIndex ~= nil and selectedHotbarSlot == slotIndex,
			slotIndex = slotIndex,
		}
	end

	local function buildResourceEntry(kind, itemKey, state)
		if kind == "Chest" then
			return {
				key = itemKey,
				kind = "Chest",
				name = state.ItemId,
				displayName = string.format("%s Chest", state.ItemId),
				subtitle = "Unopened Chest",
				footer = string.format("Quantity %d  |  Click to open", math.max(0, state.Quantity or 0)),
				fallbackText = initials(state.ItemId),
				accentColor = Color3.fromRGB(191, 143, 86),
				interactive = true,
				previewKind = "Chest",
				previewName = state.ItemId,
			}
		end

		if kind == "Consumable" then
			local food = Economy.Food[state.ItemId]
			local displayName = food and tostring(food.DisplayName or state.ItemId) or state.ItemId
			return {
				key = itemKey,
				kind = "Resource",
				name = state.ItemId,
				displayName = displayName,
				subtitle = "Food",
				footer = string.format("Quantity %d", math.max(0, state.Quantity or 0)),
				fallbackText = initials(displayName),
				accentColor = Color3.fromRGB(113, 216, 146),
				interactive = false,
				previewKind = "Resource",
				previewName = state.ItemId,
			}
		end

		return {
			key = itemKey,
			kind = "Resource",
			name = state.ItemId,
			displayName = state.ItemId,
			subtitle = "Material",
			footer = string.format("Quantity %d", math.max(0, state.Quantity or 0)),
			fallbackText = initials(state.ItemId),
			accentColor = Color3.fromRGB(191, 143, 86),
			interactive = false,
			previewKind = "Resource",
			previewName = state.ItemId,
		}
	end

	local function buildCaptainLogData(queryText)
		local entries = {}
		for itemId, state in pairs(inventory.Crewmates or {}) do
			local entry = buildCrewEntry(itemId, state)
			entry.standName = string.format("Level %d", entry.level or 1)
			entry.collectable = entry.currentXP or 0
			entry.incomePerTick = entry.shipIncomePerHour or 0
			if matchesQuery(entry, queryText) then
				entries[#entries + 1] = entry
			end
		end

		table.sort(entries, function(a, b)
			local aLevel = tonumber(a.level) or 0
			local bLevel = tonumber(b.level) or 0
			if aLevel == bLevel then
				return tostring(a.displayName) < tostring(b.displayName)
			end
			return aLevel > bLevel
		end)

		return {
			entries = entries,
			filteredCount = #entries,
			totalCount = countEntries(inventory.Crewmates),
			placedCount = countEntries(inventory.Crewmates),
			totalCollectable = 0,
		}
	end

	local function getCrewCount()
		local count = 0
		for _ in pairs(inventory.Crewmates or {}) do
			count += 1
		end
		return count
	end

	local function getDevilFruitCount()
		local count = 0
		for _, state in pairs(inventory.DevilFruit or {}) do
			if (state.Quantity or 0) > 0 then
				count += 1
			end
		end
		return count
	end

	local function getResourceCount()
		local count = 0
		for _, itemType in ipairs({ "Chest", "Consumable", "Material" }) do
			for _, state in pairs(inventory[itemType] or {}) do
				if (state.Quantity or 0) > 0 then
					count += 1
				end
			end
		end
		return count
	end

	local function buildItems(queryText)
		local entries = {}

		if activeCategory == "Crewmates" then
			for itemId, state in pairs(inventory.Crewmates or {}) do
				local entry = buildCrewEntry(itemId, state)
				if matchesQuery(entry, queryText) then
					entries[#entries + 1] = entry
				end
			end
			table.sort(entries, function(a, b)
				if a.level == b.level then
					return a.displayName < b.displayName
				end
				return a.level > b.level
			end)
		elseif activeCategory == "DevilFruits" then
			for itemId, state in pairs(inventory.DevilFruit or {}) do
				if (state.Quantity or 0) > 0 then
					local slotIndex = getAssignedSlot("DevilFruit", state.ItemId)
					local entry = buildDevilFruitEntry(itemId, state, slotIndex)
					if matchesQuery(entry, queryText) then
						entries[#entries + 1] = entry
					end
				end
			end
			table.sort(entries, function(a, b)
				local aRank = RARITY_ORDER[a.subtitle] or 0
				local bRank = RARITY_ORDER[b.subtitle] or 0
				if aRank == bRank then
					return a.displayName < b.displayName
				end
				return aRank > bRank
			end)
		else
			for _, itemType in ipairs({ "Chest", "Consumable", "Material" }) do
				for itemId, state in pairs(inventory[itemType] or {}) do
					if (state.Quantity or 0) > 0 then
						local entry = buildResourceEntry(itemType, itemId, state)
						if matchesQuery(entry, queryText) then
							entries[#entries + 1] = entry
						end
					end
				end
			end
			table.sort(entries, function(a, b)
				if a.kind == b.kind then
					return a.displayName < b.displayName
				end
				return a.kind < b.kind
			end)
		end

		return entries
	end

	local function buildHotbarSlots()
		local slots = {}
		for slotIndex = 1, HOTBAR_SLOT_COUNT do
			local slotState = hotbar[slotIndex]
			local item = nil
			if slotState and slotState.ItemType == "DevilFruit" then
				local state = inventory.DevilFruit and inventory.DevilFruit[slotState.ItemId]
				if state and (state.Quantity or 0) > 0 then
					item = buildDevilFruitEntry(slotState.ItemId, state, slotIndex)
				end
			end

			slots[#slots + 1] = {
				slotLabel = slotIndex,
				item = item,
			}
		end
		return slots
	end

	local function buildSummary()
		local leaderstats = player:FindFirstChild("leaderstats")
		local doubloons = tonumber(getValue(leaderstats, "Doubloons", "IntValue") or getValue(leaderstats, "Doubloons", "NumberValue") or 0)
		local chests = 0
		local timber = 0
		local iron = 0
		local ancientTimber = 0

		for _, state in pairs(inventory.Chest or {}) do
			chests += math.max(0, tonumber(state.Quantity) or 0)
		end
		for _, state in pairs(inventory.Material or {}) do
			local quantity = math.max(0, tonumber(state.Quantity) or 0)
			if state.ItemId == "Common Ship Material" or state.ItemId == "Timber" then
				timber += quantity
			elseif state.ItemId == "Rare Ship Material" or state.ItemId == "Iron" then
				iron += quantity
			elseif state.ItemId == "Ancient Timber" then
				ancientTimber += quantity
			end
		end

		return {
			doubloons = doubloons,
			chests = chests,
			timber = timber,
			iron = iron,
			ancientTimber = ancientTimber,
		}
	end

	local function handleEntryActivated(entry)
		if not entry then
			return
		end

		if entry.kind == "DevilFruit" then
			if entry.slotIndex then
				selectedHotbarSlot = if selectedHotbarSlot == entry.slotIndex then nil else entry.slotIndex
				refreshHeldFruitVisual()
			else
				local assignedSlot = getAssignedSlot("DevilFruit", entry.name)
				if assignedSlot then
					requestSlotClear(assignedSlot)
					if selectedHotbarSlot == assignedSlot then
						selectedHotbarSlot = nil
					end
				else
					requestSlotAssignment("DevilFruit", entry.name)
				end
			end
		elseif entry.kind == "Chest" then
			chestConsumeRequestRemote:FireServer(entry.name)
		end
	end

	local function render()
		local trimmedQuery = trim(query)
		local items = buildItems(trimmedQuery)
		local captainLog = buildCaptainLogData(trimmedQuery)
		local catalogView = buildCatalogViewModel()
		local categories = {
			{
				key = "Crewmates",
				label = CATEGORY_DEFS.Crewmates.label,
				count = getCrewCount(),
				accentColor = CATEGORY_DEFS.Crewmates.accentColor,
			},
			{
				key = "DevilFruits",
				label = CATEGORY_DEFS.DevilFruits.label,
				count = getDevilFruitCount(),
				accentColor = CATEGORY_DEFS.DevilFruits.accentColor,
			},
			{
				key = "Resources",
				label = CATEGORY_DEFS.Resources.label,
				count = getResourceCount(),
				accentColor = CATEGORY_DEFS.Resources.accentColor,
			},
		}

		root:render(ReactRoblox.createPortal(e(React.Fragment, nil,
			e(App, {
				isOpen = isOpen,
				activeView = activeView,
				activeCategory = activeCategory,
				activeCategoryLabel = CATEGORY_DEFS[activeCategory].label,
				categories = categories,
				items = items,
				captainLog = captainLog,
				hotbarSlots = buildHotbarSlots(),
				summary = buildSummary(),
				filteredCount = #items,
				totalCount = if activeCategory == "Crewmates"
					then getCrewCount()
					elseif activeCategory == "DevilFruits" then getDevilFruitCount() else getResourceCount(),
				query = query,
				toggleLayout = TOGGLE_LAYOUT,
				toggleIcon = {
					image = TOGGLE_ICON_ID,
					imageColor3 = Color3.new(1, 1, 1),
					scaleType = Enum.ScaleType.Fit,
				},
				toggleLabel = "Inventory",
				toggleKeyText = "F",
				shopLayout = SHOP_LAYOUT,
				shopIcon = {
					image = SHOP_ICON_ID,
					imageColor3 = Color3.new(1, 1, 1),
					scaleType = Enum.ScaleType.Fit,
				},
				shopLabel = "Shop",
				onToggle = function()
					isOpen = not isOpen
					if isOpen then
						isShopOpen = false
					end
					render()
				end,
				onShopToggle = function()
					isShopOpen = not isShopOpen
					if isShopOpen then
						isOpen = false
					end
					render()
				end,
				onSelectView = function(viewKey)
					activeView = viewKey
					query = ""
					render()
				end,
				onSelectCategory = function(categoryKey)
					activeCategory = categoryKey
					render()
				end,
				onQueryChanged = function(nextQuery)
					query = nextQuery
					render()
				end,
				onActivateItem = function(entry)
					handleEntryActivated(entry)
					render()
				end,
			}),
			isShopOpen and e("ScreenGui", {
				DisplayOrder = 25,
				IgnoreGuiInset = true,
				ResetOnSpawn = false,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			}, {
				Backdrop = e("TextButton", {
					AutoButtonColor = false,
					BackgroundColor3 = Color3.fromRGB(3, 8, 18),
					BackgroundTransparency = 0.42,
					BorderSizePixel = 0,
					Modal = true,
					Size = UDim2.fromScale(1, 1),
					Text = "",
					ZIndex = 80,
					[React.Event.Activated] = function()
						isShopOpen = false
						render()
					end,
				}),
				Host = e("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(0.9, 0.84),
					ZIndex = 120,
				}, {
					SizeConstraint = e("UISizeConstraint", {
						MinSize = Vector2.new(980, 680),
						MaxSize = Vector2.new(1340, 860),
					}),
					Shell = e(ShopShell, {
						catalog = catalogView,
						noticeText = noticeText,
						onClose = function()
							isShopOpen = false
							render()
						end,
						onPurchaseRequested = function(item)
							local success, message = purchaseAdapter:requestPurchase(item)
							if not success and message then
								setNotice(message)
							end
						end,
						onGiftRequested = function(item)
							local itemTitle = item and item.title or "This offer"
							setNotice(itemTitle .. " gifting is not available yet.")
						end,
						onRedeemRequested = function(codeText)
							local trimmedCode = trim(codeText)
							if trimmedCode == "" then
								setNotice("Enter a code before redeeming.")
								return
							end

							setNotice("Code redemption is not active right now. Watch for update and event drops.")
						end,
						onSectionSelected = function()
						end,
					}),
				}),
			}) or nil
		), playerGui))
	end

	scheduleRender = function()
		if destroyed or renderQueued then
			return
		end

		renderQueued = true
		task.defer(function()
			renderQueued = false
			if not destroyed then
				render()
			end
		end)
	end

	local function refreshState()
		inventory = readInventoryMirror()
		hotbar = readHotbarMirror()
		if selectedHotbarSlot and hotbar[selectedHotbarSlot] == nil then
			selectedHotbarSlot = nil
		end
		refreshHeldFruitVisual()
		scheduleRender()
	end

	local function tryConsumeSelectedFruit()
		if isOpen or not selectedHotbarSlot then
			return
		end

		local slotState = hotbar[selectedHotbarSlot]
		if slotState and slotState.ItemType == "DevilFruit" then
			devilFruitConsumeRequestRemote:FireServer(slotState.ItemId)
		end
	end

	track(UserInputService.InputBegan, function(input, gameProcessed)
		if gameProcessed or UserInputService:GetFocusedTextBox() then
			return
		end

		if input.KeyCode == Enum.KeyCode.F then
			isOpen = not isOpen
			scheduleRender()
			return
		end

		local slotIndex = KEY_TO_SLOT[input.KeyCode]
		if slotIndex then
			selectedHotbarSlot = if selectedHotbarSlot == slotIndex then nil else slotIndex
			refreshHeldFruitVisual()
			scheduleRender()
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			tryConsumeSelectedFruit()
		end
	end)

	track(inventoryRoot.DescendantAdded, function(descendant)
		if descendant:IsA("ValueBase") then
			track(descendant:GetPropertyChangedSignal("Value"), refreshState)
		end
		task.defer(refreshState)
	end)
	track(inventoryRoot.DescendantRemoving, function()
		task.defer(refreshState)
	end)
	track(hotbarRoot.DescendantAdded, function(descendant)
		if descendant:IsA("ValueBase") then
			track(descendant:GetPropertyChangedSignal("Value"), refreshState)
		end
		task.defer(refreshState)
	end)
	track(hotbarRoot.DescendantRemoving, function()
		task.defer(refreshState)
	end)

	for _, descendant in ipairs(inventoryRoot:GetDescendants()) do
		if descendant:IsA("ValueBase") then
			track(descendant:GetPropertyChangedSignal("Value"), refreshState)
		end
	end
	for _, descendant in ipairs(hotbarRoot:GetDescendants()) do
		if descendant:IsA("ValueBase") then
			track(descendant:GetPropertyChangedSignal("Value"), refreshState)
		end
	end

	track(player.ChildAdded, function(child)
		if child.Name == "leaderstats" then
			task.defer(refreshState)
		end
	end)

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		for _, child in ipairs(leaderstats:GetChildren()) do
			if child:IsA("ValueBase") then
				track(child:GetPropertyChangedSignal("Value"), scheduleRender)
			end
		end
		track(leaderstats.ChildAdded, function(child)
			if child:IsA("ValueBase") then
				track(child:GetPropertyChangedSignal("Value"), scheduleRender)
			end
			scheduleRender()
		end)
	end

	if player.Character then
		refreshHeldFruitVisual()
	end

	track(player.CharacterAdded, function()
		task.defer(refreshHeldFruitVisual)
	end)
	cleanupConnections[#cleanupConnections + 1] = purchaseAdapter:subscribe(scheduleRender)

	commandRemote:FireServer("RequestSnapshot")
	purchaseAdapter:primeCatalog(ShopCatalog)
	refreshState()
	render()

	script.Destroying:Connect(function()
		destroyed = true
		disconnectAll()
		destroyHeldFruitVisual()
		purchaseAdapter:destroy()
		root:unmount()
	end)
end

return ReactInventory
