local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Inventory = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Inventory"))
local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local DevilFruitAssets = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Assets"))

local Constants = Inventory.Constants
local Registry = Inventory.Registry

local HOTBAR_FOLDER_NAME = "InventoryHotbar"
local HOTBAR_SLOT_COUNT = 5

local ITEM_TYPE_ORDER = { "Chest", "Crewmates", "DevilFruit", "Material", "Consumable" }
local ITEM_TYPE_LABELS = {
	Chest = "Chests",
	Crewmates = "Crewmates",
	DevilFruit = "Devil Fruit",
	Material = "Materials",
	Consumable = "Consumables",
}
local ITEM_TYPE_COLORS = {
	Chest = Color3.fromRGB(181, 127, 62),
	Crewmates = Color3.fromRGB(84, 171, 255),
	DevilFruit = Color3.fromRGB(255, 110, 110),
	Material = Color3.fromRGB(255, 193, 87),
	Consumable = Color3.fromRGB(97, 206, 112),
}
local CREW_VALUE_NAMES = {
	DisplayName = "DisplayName",
	Rarity = "Rarity",
	Level = "Level",
	CurrentXP = "CurrentXP",
	NextLevelXP = "NextLevelXP",
	ShipIncomePerHour = "ShipIncomePerHour",
}
local HOTBAR_KEYCODES = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
}
local ITEM_IMAGE_IDS = {
	Zoro = "rbxassetid://1234567890",
	GomuGomu = "rbxassetid://2345678901",
	Wood = "rbxassetid://3456789012",
}
local THEME = {
	Background = Color3.fromRGB(12, 16, 26),
	Panel = Color3.fromRGB(20, 27, 43),
	PanelAlt = Color3.fromRGB(29, 38, 59),
	Stroke = Color3.fromRGB(88, 118, 166),
	Text = Color3.fromRGB(236, 242, 255),
	TextMuted = Color3.fromRGB(163, 176, 201),
	Accent = Color3.fromRGB(77, 168, 255),
	AccentSoft = Color3.fromRGB(38, 93, 153),
	Success = Color3.fromRGB(72, 196, 123),
}

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local inventoryRoot = localPlayer:WaitForChild(Constants.RootFolderName)
local hotbarRoot = localPlayer:WaitForChild(HOTBAR_FOLDER_NAME)

local remotesFolder = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
local commandRemote = remotesFolder:WaitForChild(Constants.CommandRemoteName)
local gameRemotes = ReplicatedStorage:WaitForChild("Remotes")
local devilFruitConsumeRequestRemote = gameRemotes:WaitForChild("DevilFruitConsumeRequest")
local chestConsumeRequestRemote = gameRemotes:WaitForChild("GrandLineRushChestConsumeRequest")
local hotbarRequestRemote = gameRemotes:WaitForChild("InventoryHotbarRequest")

local inventory = {}
local hotbar = {}
local isOpen = false
local selectedHotbarSlot = nil
local heldFruitVisual = nil
local heldFruitKey = nil

local function create(className, props)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		object[key] = value
	end
	return object
end

local screenGui = create("ScreenGui", {
	Name = "InventoryGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 20,
	Enabled = true,
	Parent = playerGui,
})

local openButton = create("TextButton", {
	Name = "OpenInventoryButton",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 20, 1, -20),
	Size = UDim2.fromOffset(170, 48),
	AutoButtonColor = false,
	BackgroundColor3 = THEME.Accent,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "Inventory [F]",
	TextColor3 = THEME.Text,
	TextSize = 16,
	Parent = screenGui,
})
create("UICorner", { CornerRadius = UDim.new(0, 14), Parent = openButton })
create("UIStroke", { Color = THEME.AccentSoft, Thickness = 1.25, Transparency = 0.2, Parent = openButton })

local hotbarFrame = create("Frame", {
	Name = "Hotbar",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18),
	Size = UDim2.fromOffset(560, 88),
	BackgroundTransparency = 1,
	Parent = screenGui,
})
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Padding = UDim.new(0, 10),
	Parent = hotbarFrame,
})

local overlay = create("Frame", {
	Name = "Overlay",
	BackgroundColor3 = THEME.Background,
	BackgroundTransparency = 0.2,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	Parent = screenGui,
})

local shell = create("Frame", {
	Name = "Shell",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.72, 0.74),
	BackgroundColor3 = THEME.Panel,
	BorderSizePixel = 0,
	Parent = overlay,
})
create("UICorner", { CornerRadius = UDim.new(0, 18), Parent = shell })
create("UIStroke", { Color = THEME.Stroke, Thickness = 1.5, Transparency = 0.15, Parent = shell })
create("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 35, 57)),
		ColorSequenceKeypoint.new(1, THEME.Panel),
	}),
	Rotation = 90,
	Parent = shell,
})
create("UIPadding", {
	PaddingTop = UDim.new(0, 20),
	PaddingBottom = UDim.new(0, 20),
	PaddingLeft = UDim.new(0, 20),
	PaddingRight = UDim.new(0, 20),
	Parent = shell,
})

local topBar = create("Frame", { Name = "TopBar", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 48), Parent = shell })
create("TextLabel", {
	Name = "Title",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, -64, 0, 28),
	Font = Enum.Font.GothamBold,
	Text = "Inventory",
	TextColor3 = THEME.Text,
	TextSize = 28,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = topBar,
})
create("TextLabel", {
	Name = "Subtitle",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 28),
	Size = UDim2.new(1, -64, 0, 18),
	Font = Enum.Font.Gotham,
	Text = "Press F to open or close",
	TextColor3 = THEME.TextMuted,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = topBar,
})
local closeButton = create("TextButton", {
	Name = "CloseButton",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromOffset(44, 44),
	AutoButtonColor = false,
	BackgroundColor3 = THEME.PanelAlt,
	Text = "X",
	Font = Enum.Font.GothamBold,
	TextColor3 = THEME.Text,
	TextSize = 18,
	Parent = topBar,
})
create("UICorner", { CornerRadius = UDim.new(0, 12), Parent = closeButton })
create("UIStroke", { Color = THEME.Stroke, Transparency = 0.35, Parent = closeButton })

local body = create("Frame", {
	Name = "Body",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 62),
	Size = UDim2.new(1, 0, 1, -62),
	Parent = shell,
})
local list = create("ScrollingFrame", {
	Name = "ItemList",
	Active = true,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(),
	ScrollBarImageColor3 = THEME.Accent,
	ScrollBarThickness = 6,
	Size = UDim2.fromScale(1, 1),
	Parent = body,
})
create("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

local function getTypeColor(itemType)
	return ITEM_TYPE_COLORS[itemType] or THEME.Accent
end

local function getItemImage(itemId)
	return ITEM_IMAGE_IDS[itemId]
end

local function setInventoryVisible(visible)
	isOpen = visible
	overlay.Visible = visible
	shell.Visible = visible
	openButton.Visible = not visible
end

local function getDisplayItemName(itemState)
	if itemState.ItemType == "DevilFruit" then
		local fruit = DevilFruitConfig.GetFruit(itemState.ItemId)
		if fruit then
			return fruit.DisplayName
		end
	end
	if itemState.ItemType == "Consumable" then
		local foodConfig = Economy.Food[itemState.ItemId]
		if foodConfig and typeof(foodConfig.DisplayName) == "string" then
			return foodConfig.DisplayName
		end
	end
	if itemState.ItemType == "Chest" then
		return string.format("%s Chest", itemState.ItemId)
	end
	if itemState.ItemType == "Crewmates" and typeof(itemState.DisplayName) == "string" and itemState.DisplayName ~= "" then
		return itemState.DisplayName
	end
	return itemState.ItemId:gsub("(%l)(%u)", "%1 %2")
end

local function getItemDetailsText(itemState)
	if itemState.ItemType == "Crewmates" then
		local rarity = itemState.Rarity or "Common"
		local level = math.floor(tonumber(itemState.Level) or 1)
		local currentXP = math.floor(tonumber(itemState.CurrentXP) or 0)
		local nextLevelXP = math.floor(tonumber(itemState.NextLevelXP) or 0)
		if nextLevelXP > 0 then
			return string.format("Rarity: %s   Level: %d   XP: %d/%d", rarity, level, currentXP, nextLevelXP)
		end
		return string.format("Rarity: %s   Level: %d", rarity, level)
	end
	return string.format("Type: %s   Quantity: %d", ITEM_TYPE_LABELS[itemState.ItemType] or itemState.ItemType, itemState.Quantity)
end

local function getItemMonogram(text)
	local compact = tostring(text):gsub("[^%w%s]", "")
	local letters = {}
	for word in compact:gmatch("%S+") do
		letters[#letters + 1] = string.sub(word, 1, 1):upper()
		if #letters >= 2 then break end
	end
	if #letters == 0 then
		return string.sub(compact, 1, 2):upper()
	end
	return table.concat(letters)
end

local function clearChildrenExceptLayouts(parent)
	for _, child in ipairs(parent:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function readInventoryMirror()
	local snapshot = {}
	for _, typeFolder in ipairs(inventoryRoot:GetChildren()) do
		if typeFolder:IsA("Folder") then
			snapshot[typeFolder.Name] = {}
			for _, itemFolder in ipairs(typeFolder:GetChildren()) do
				if itemFolder:IsA("Folder") then
					local quantity = itemFolder:FindFirstChild(Constants.ValueNames.Quantity)
					local equipped = itemFolder:FindFirstChild(Constants.ValueNames.Equipped)
					local itemType = itemFolder:FindFirstChild(Constants.ValueNames.ItemType)
					local itemId = itemFolder:FindFirstChild(Constants.ValueNames.ItemId)
					local function numberValue(name)
						local value = itemFolder:FindFirstChild(name)
						return if value and value:IsA("NumberValue") then value.Value else nil
					end
					local function stringValue(name)
						local value = itemFolder:FindFirstChild(name)
						return if value and value:IsA("StringValue") then value.Value else nil
					end
					snapshot[typeFolder.Name][itemFolder.Name] = {
						ItemType = if itemType and itemType:IsA("StringValue") then itemType.Value else typeFolder.Name,
						ItemId = if itemId and itemId:IsA("StringValue") then itemId.Value else itemFolder.Name,
						Quantity = if quantity and quantity:IsA("NumberValue") then quantity.Value else 0,
						Equipped = if equipped and equipped:IsA("BoolValue") then equipped.Value else false,
						DisplayName = stringValue(CREW_VALUE_NAMES.DisplayName),
						Rarity = stringValue(CREW_VALUE_NAMES.Rarity),
						Level = numberValue(CREW_VALUE_NAMES.Level),
						CurrentXP = numberValue(CREW_VALUE_NAMES.CurrentXP),
						NextLevelXP = numberValue(CREW_VALUE_NAMES.NextLevelXP),
						ShipIncomePerHour = numberValue(CREW_VALUE_NAMES.ShipIncomePerHour),
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
			local itemType = slotFolder:FindFirstChild("ItemType")
			local itemId = slotFolder:FindFirstChild("ItemId")
			if itemType and itemType:IsA("StringValue") and itemId and itemId:IsA("StringValue") and itemType.Value ~= "" and itemId.Value ~= "" then
				snapshot[slotIndex] = { ItemType = itemType.Value, ItemId = itemId.Value }
			end
		end
	end
	return snapshot
end

local function getHotbarSlotWithItem(itemType, itemId)
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

local function requestSlotAssignment(itemState)
	hotbarRequestRemote:FireServer("AssignSlot", { SlotIndex = getPreferredHotbarSlot(), ItemType = itemState.ItemType, ItemId = itemState.ItemId })
end

local function requestSlotClear(slotIndex)
	hotbarRequestRemote:FireServer("ClearSlot", { SlotIndex = slotIndex })
end

local function renderInventory()
	clearChildrenExceptLayouts(list)
	local layoutOrder = 1
	local hasAnyItems = false
	local ordered = table.clone(ITEM_TYPE_ORDER)
	for itemType in pairs(inventory) do
		if not table.find(ordered, itemType) then
			ordered[#ordered + 1] = itemType
		end
	end
	for _, itemType in ipairs(ordered) do
		local entries = {}
		for itemId, itemState in pairs(inventory[itemType] or {}) do
			entries[#entries + 1] = { ItemId = itemId, ItemState = itemState }
		end
		table.sort(entries, function(a, b)
			return a.ItemId < b.ItemId
		end)
		if #entries > 0 then
			hasAnyItems = true
			create("TextLabel", {
				Name = (ITEM_TYPE_LABELS[itemType] or itemType) .. "Header",
				BackgroundTransparency = 1,
				LayoutOrder = layoutOrder,
				Size = UDim2.new(1, -8, 0, 24),
				Font = Enum.Font.GothamBold,
				Text = ITEM_TYPE_LABELS[itemType] or itemType,
				TextColor3 = THEME.Text,
				TextSize = 18,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = list,
			})
			layoutOrder += 1
			for _, entry in ipairs(entries) do
				local itemState = entry.ItemState
				local typeColor = getTypeColor(itemState.ItemType)
				local displayName = getDisplayItemName(itemState)
				local fruitHotbarSlot = if itemState.ItemType == "DevilFruit" then getHotbarSlotWithItem(itemState.ItemType, itemState.ItemId) else nil
				local card = create("Frame", {
					Name = itemState.ItemId,
					BackgroundColor3 = THEME.PanelAlt,
					BorderSizePixel = 0,
					LayoutOrder = layoutOrder,
					Size = UDim2.new(1, -8, 0, 84),
					Parent = list,
				})
				create("UICorner", { CornerRadius = UDim.new(0, 16), Parent = card })
				create("UIStroke", { Color = itemState.Equipped and THEME.Success or typeColor, Transparency = itemState.Equipped and 0 or 0.35, Parent = card })
				local icon = create("Frame", {
					BackgroundColor3 = typeColor,
					BorderSizePixel = 0,
					Position = UDim2.new(0, 16, 0.5, -26),
					Size = UDim2.fromOffset(52, 52),
					Parent = card,
				})
				create("UICorner", { CornerRadius = UDim.new(0, 14), Parent = icon })
				local imageId = getItemImage(itemState.ItemId)
				if imageId then
					create("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -10, 1, -10), Position = UDim2.fromOffset(5, 5), Image = imageId, Parent = icon })
				else
					create("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, Text = getItemMonogram(displayName), TextColor3 = THEME.Text, TextSize = 20, Parent = icon })
				end
				create("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(82, 12),
					Size = UDim2.new(1, -226, 0, 24),
					Font = Enum.Font.GothamBold,
					Text = displayName,
					TextColor3 = THEME.Text,
					TextSize = 20,
					TextXAlignment = Enum.TextXAlignment.Left,
					Parent = card,
				})
				create("TextLabel", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(82, 42),
					Size = UDim2.new(1, -246, 0, 18),
					Font = Enum.Font.Gotham,
					Text = getItemDetailsText(itemState),
					TextColor3 = THEME.TextMuted,
					TextSize = 14,
					TextXAlignment = Enum.TextXAlignment.Left,
					Parent = card,
				})
				if itemState.Equipped or fruitHotbarSlot then
					local badgeText = if itemState.Equipped then "Equipped" else string.format("Slot %d", fruitHotbarSlot)
					local badge = create("TextLabel", {
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, -16, 0, 12),
						Size = UDim2.fromOffset(110, 26),
						BackgroundColor3 = itemState.Equipped and THEME.Success or THEME.AccentSoft,
						BorderSizePixel = 0,
						Font = Enum.Font.GothamBold,
						Text = badgeText,
						TextColor3 = THEME.Text,
						TextSize = 13,
						Parent = card,
					})
					create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = badge })
				end
				local definition = Registry.GetItemType(itemState.ItemType)
				local buttonText = nil
				local buttonColor = typeColor
				local callback = nil
				if itemState.ItemType == "Chest" then
					buttonText = "Open"
					callback = function()
						chestConsumeRequestRemote:FireServer(itemState.ItemId)
					end
				elseif itemState.ItemType == "DevilFruit" then
					buttonText = fruitHotbarSlot and "Remove" or "To Hotbar"
					buttonColor = fruitHotbarSlot and THEME.Panel or typeColor
					callback = function()
						if fruitHotbarSlot then
							requestSlotClear(fruitHotbarSlot)
						else
							requestSlotAssignment(itemState)
						end
					end
				elseif definition and definition.Equippable then
					buttonText = itemState.Equipped and "Unequip" or "Equip"
					buttonColor = itemState.Equipped and THEME.Panel or typeColor
					callback = function()
						commandRemote:FireServer(Constants.Commands.ToggleEquip, { ItemType = itemState.ItemType, ItemId = itemState.ItemId })
					end
				end
				if buttonText then
					local actionButton = create("TextButton", {
						AnchorPoint = Vector2.new(1, 1),
						Position = UDim2.new(1, -16, 1, -14),
						Size = UDim2.fromOffset(itemState.ItemType == "DevilFruit" and 118 or 110, 32),
						AutoButtonColor = false,
						BackgroundColor3 = buttonColor,
						BorderSizePixel = 0,
						Font = Enum.Font.GothamBold,
						Text = buttonText,
						TextColor3 = THEME.Text,
						TextSize = 14,
						Parent = card,
					})
					create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = actionButton })
					create("UIStroke", { Color = buttonColor == THEME.Panel and THEME.Stroke or THEME.AccentSoft, Transparency = 0.2, Parent = actionButton })
					actionButton.MouseButton1Click:Connect(callback)
				end
				layoutOrder += 1
			end
		end
	end
	if not hasAnyItems then
		local emptyCard = create("Frame", { BackgroundColor3 = THEME.PanelAlt, BorderSizePixel = 0, Size = UDim2.new(1, -8, 0, 110), Parent = list })
		create("UICorner", { CornerRadius = UDim.new(0, 16), Parent = emptyCard })
		create("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -32, 1, -32),
			Position = UDim2.fromOffset(16, 16),
			Font = Enum.Font.GothamMedium,
			Text = "Your inventory is empty.\nUse the server commands to add items and they will appear here.",
			TextColor3 = THEME.TextMuted,
			TextSize = 18,
			TextWrapped = true,
			Parent = emptyCard,
		})
	end
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
	local character = localPlayer.Character
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
	primaryPart.CFrame = hand.CFrame * CFrame.new(fruit.ToolGripBias or Vector3.new(0.72, -0.12, 0.18))
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
	if heldFruitVisual and heldFruitKey == slotState.ItemId and heldFruitVisual.Parent == localPlayer.Character then
		return
	end
	destroyHeldFruitVisual()
	buildHeldFruitVisual(slotState.ItemId)
end

local function renderHotbar()
	clearChildrenExceptLayouts(hotbarFrame)
	for slotIndex = 1, HOTBAR_SLOT_COUNT do
		local slotState = hotbar[slotIndex]
		local isSelected = selectedHotbarSlot == slotIndex
		local slotColor = slotState and getTypeColor(slotState.ItemType) or THEME.PanelAlt
		local slotButton = create("TextButton", {
			Name = string.format("Slot%d", slotIndex),
			AutoButtonColor = false,
			BackgroundColor3 = isSelected and THEME.AccentSoft or THEME.Panel,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(104, 84),
			Text = "",
			Parent = hotbarFrame,
		})
		create("UICorner", { CornerRadius = UDim.new(0, 14), Parent = slotButton })
		create("UIStroke", { Color = isSelected and THEME.Accent or slotColor, Transparency = slotState and 0.15 or 0.45, Thickness = isSelected and 2 or 1.25, Parent = slotButton })
		create("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(24, 16), Font = Enum.Font.GothamBold, Text = tostring(slotIndex), TextColor3 = THEME.TextMuted, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Parent = slotButton })
		if slotState then
			local displayName = inventory[slotState.ItemType] and inventory[slotState.ItemType][slotState.ItemId] and getDisplayItemName(inventory[slotState.ItemType][slotState.ItemId]) or slotState.ItemId
			local icon = create("Frame", { BackgroundColor3 = slotColor, BorderSizePixel = 0, Position = UDim2.fromOffset(10, 24), Size = UDim2.fromOffset(34, 34), Parent = slotButton })
			create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = icon })
			local imageId = getItemImage(slotState.ItemId)
			if imageId then
				create("ImageLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(26, 26), Image = imageId, Parent = icon })
			else
				create("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, Text = getItemMonogram(displayName), TextColor3 = THEME.Text, TextSize = 14, Parent = icon })
			end
			create("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(50, 22), Size = UDim2.fromOffset(44, 38), Font = Enum.Font.GothamBold, Text = displayName, TextColor3 = THEME.Text, TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, Parent = slotButton })
		else
			create("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 34), Size = UDim2.fromOffset(84, 18), Font = Enum.Font.Gotham, Text = "Empty", TextColor3 = THEME.TextMuted, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Parent = slotButton })
		end
		slotButton.MouseButton1Click:Connect(function()
			selectedHotbarSlot = if selectedHotbarSlot == slotIndex then nil else slotIndex
			renderHotbar()
			refreshHeldFruitVisual()
		end)
	end
end

local function refreshInventory()
	inventory = readInventoryMirror()
	renderInventory()
	renderHotbar()
end

local function refreshHotbar()
	hotbar = readHotbarMirror()
	if selectedHotbarSlot and hotbar[selectedHotbarSlot] == nil then
		selectedHotbarSlot = nil
	end
	renderHotbar()
	renderInventory()
	refreshHeldFruitVisual()
end

local function tryConsumeSelectedFruit()
	if isOpen or not selectedHotbarSlot then return end
	local slotState = hotbar[selectedHotbarSlot]
	if slotState and slotState.ItemType == "DevilFruit" then
		devilFruitConsumeRequestRemote:FireServer(slotState.ItemId)
	end
end

closeButton.MouseButton1Click:Connect(function()
	setInventoryVisible(false)
end)
openButton.MouseButton1Click:Connect(function()
	setInventoryVisible(true)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == Enum.KeyCode.F then
		setInventoryVisible(not isOpen)
		return
	end
	for slotIndex, keyCode in ipairs(HOTBAR_KEYCODES) do
		if input.KeyCode == keyCode then
			selectedHotbarSlot = if selectedHotbarSlot == slotIndex then nil else slotIndex
			renderHotbar()
			refreshHeldFruitVisual()
			return
		end
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		tryConsumeSelectedFruit()
	end
end)

inventoryRoot.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("ValueBase") then
		descendant.Changed:Connect(refreshInventory)
	end
	refreshInventory()
end)
inventoryRoot.DescendantRemoving:Connect(function()
	task.defer(refreshInventory)
end)
hotbarRoot.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("ValueBase") then
		descendant.Changed:Connect(refreshHotbar)
	end
	refreshHotbar()
end)
hotbarRoot.DescendantRemoving:Connect(function()
	task.defer(refreshHotbar)
end)
for _, descendant in ipairs(inventoryRoot:GetDescendants()) do
	if descendant:IsA("ValueBase") then
		descendant.Changed:Connect(refreshInventory)
	end
end
for _, descendant in ipairs(hotbarRoot:GetDescendants()) do
	if descendant:IsA("ValueBase") then
		descendant.Changed:Connect(refreshHotbar)
	end
end
localPlayer.CharacterAdded:Connect(function()
	task.defer(refreshHeldFruitVisual)
end)

refreshInventory()
refreshHotbar()
setInventoryVisible(false)
commandRemote:FireServer(Constants.Commands.RequestSnapshot)
