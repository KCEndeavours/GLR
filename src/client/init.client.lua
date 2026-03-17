local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Inventory = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Inventory"))
local Constants = Inventory.Constants
local Registry = Inventory.Registry

type ItemState = {
	ItemType: string,
	ItemId: string,
	Quantity: number,
	Equipped: boolean,
}

type InventorySnapshot = {
	[string]: {
		[string]: ItemState,
	},
}

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local inventoryRoot = localPlayer:WaitForChild(Constants.RootFolderName)

local remotesFolder = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
local commandRemote: RemoteEvent = remotesFolder:WaitForChild(Constants.CommandRemoteName)

local inventory: InventorySnapshot = {}
local isOpen = false

local ITEM_TYPE_ORDER = {
	"Crewmates",
	"DevilFruit",
	"Material",
	"Consumable",
}

local ITEM_TYPE_LABELS = {
	Crewmates = "Crewmates",
	DevilFruit = "Devil Fruit",
	Material = "Materials",
	Consumable = "Consumables",
}

local ITEM_TYPE_COLORS = {
	Crewmates = Color3.fromRGB(84, 171, 255),
	DevilFruit = Color3.fromRGB(255, 110, 110),
	Material = Color3.fromRGB(255, 193, 87),
	Consumable = Color3.fromRGB(97, 206, 112),
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

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "InventoryGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 20
screenGui.Enabled = true
screenGui.Parent = playerGui

local openButton = Instance.new("TextButton")
openButton.Name = "OpenInventoryButton"
openButton.AnchorPoint = Vector2.new(0, 1)
openButton.Position = UDim2.new(0, 20, 1, -20)
openButton.Size = UDim2.fromOffset(170, 48)
openButton.AutoButtonColor = false
openButton.BackgroundColor3 = THEME.Accent
openButton.BorderSizePixel = 0
openButton.Font = Enum.Font.GothamBold
openButton.Text = "Inventory [F]"
openButton.TextColor3 = THEME.Text
openButton.TextSize = 16
openButton.Parent = screenGui

local openButtonCorner = Instance.new("UICorner")
openButtonCorner.CornerRadius = UDim.new(0, 14)
openButtonCorner.Parent = openButton

local openButtonStroke = Instance.new("UIStroke")
openButtonStroke.Color = THEME.AccentSoft
openButtonStroke.Thickness = 1.25
openButtonStroke.Transparency = 0.2
openButtonStroke.Parent = openButton

local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.BackgroundColor3 = THEME.Background
overlay.BackgroundTransparency = 0.2
overlay.BorderSizePixel = 0
overlay.Size = UDim2.fromScale(1, 1)
overlay.Parent = screenGui

local shell = Instance.new("Frame")
shell.Name = "Shell"
shell.AnchorPoint = Vector2.new(0.5, 0.5)
shell.Position = UDim2.fromScale(0.5, 0.5)
shell.Size = UDim2.fromScale(0.72, 0.74)
shell.BackgroundColor3 = THEME.Panel
shell.BorderSizePixel = 0
shell.Parent = overlay

local shellCorner = Instance.new("UICorner")
shellCorner.CornerRadius = UDim.new(0, 18)
shellCorner.Parent = shell

local shellStroke = Instance.new("UIStroke")
shellStroke.Color = THEME.Stroke
shellStroke.Thickness = 1.5
shellStroke.Transparency = 0.15
shellStroke.Parent = shell

local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 35, 57)),
	ColorSequenceKeypoint.new(1, THEME.Panel),
})
gradient.Rotation = 90
gradient.Parent = shell

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 20)
padding.PaddingBottom = UDim.new(0, 20)
padding.PaddingLeft = UDim.new(0, 20)
padding.PaddingRight = UDim.new(0, 20)
padding.Parent = shell

local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.BackgroundTransparency = 1
topBar.Size = UDim2.new(1, 0, 0, 48)
topBar.Parent = shell

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -64, 0, 28)
title.Font = Enum.Font.GothamBold
title.Text = "Inventory"
title.TextColor3 = THEME.Text
title.TextSize = 28
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = topBar

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.fromOffset(0, 28)
subtitle.Size = UDim2.new(1, -64, 0, 18)
subtitle.Font = Enum.Font.Gotham
subtitle.Text = "Press F to open or close"
subtitle.TextColor3 = THEME.TextMuted
subtitle.TextSize = 14
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = topBar

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.fromScale(1, 0)
closeButton.Size = UDim2.fromOffset(44, 44)
closeButton.AutoButtonColor = false
closeButton.BackgroundColor3 = THEME.PanelAlt
closeButton.Text = "X"
closeButton.Font = Enum.Font.GothamBold
closeButton.TextColor3 = THEME.Text
closeButton.TextSize = 18
closeButton.Parent = topBar

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 12)
closeCorner.Parent = closeButton

local closeStroke = Instance.new("UIStroke")
closeStroke.Color = THEME.Stroke
closeStroke.Transparency = 0.35
closeStroke.Parent = closeButton

local body = Instance.new("Frame")
body.Name = "Body"
body.BackgroundTransparency = 1
body.Position = UDim2.fromOffset(0, 62)
body.Size = UDim2.new(1, 0, 1, -62)
body.Parent = shell

local list = Instance.new("ScrollingFrame")
list.Name = "ItemList"
list.Active = true
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.CanvasSize = UDim2.new()
list.ScrollBarImageColor3 = THEME.Accent
list.ScrollBarThickness = 6
list.Size = UDim2.fromScale(1, 1)
list.Parent = body

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 12)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

local function deepCopySnapshot(snapshot): InventorySnapshot
	local result: InventorySnapshot = {}

	for itemType, entries in pairs(snapshot) do
		result[itemType] = {}
		for itemId, itemState in pairs(entries) do
			result[itemType][itemId] = {
				ItemType = itemState.ItemType,
				ItemId = itemState.ItemId,
				Quantity = itemState.Quantity,
				Equipped = itemState.Equipped,
			}
		end
	end

	return result
end

local function readInventoryMirror(): InventorySnapshot
	local snapshot: InventorySnapshot = {}

	for _, typeFolder in ipairs(inventoryRoot:GetChildren()) do
		if typeFolder:IsA("Folder") then
			snapshot[typeFolder.Name] = {}

			for _, itemFolder in ipairs(typeFolder:GetChildren()) do
				if itemFolder:IsA("Folder") then
					local quantity = itemFolder:FindFirstChild(Constants.ValueNames.Quantity)
					local equipped = itemFolder:FindFirstChild(Constants.ValueNames.Equipped)
					local itemType = itemFolder:FindFirstChild(Constants.ValueNames.ItemType)
					local itemId = itemFolder:FindFirstChild(Constants.ValueNames.ItemId)
					local resolvedItemType = if itemType and itemType:IsA("StringValue") then itemType.Value else typeFolder.Name
					local resolvedItemId = if itemId and itemId:IsA("StringValue") then itemId.Value else itemFolder.Name
					local resolvedQuantity = if quantity and quantity:IsA("NumberValue") then quantity.Value else 0
					local resolvedEquipped = if equipped and equipped:IsA("BoolValue") then equipped.Value else false

					snapshot[typeFolder.Name][itemFolder.Name] = {
						ItemType = resolvedItemType,
						ItemId = resolvedItemId,
						Quantity = resolvedQuantity,
						Equipped = resolvedEquipped,
					}
				end
			end
		end
	end

	return snapshot
end

local function setInventoryVisible(visible: boolean)
	isOpen = visible
	overlay.Visible = visible
	shell.Visible = visible
	openButton.Visible = not visible
end

local function getTypeColor(itemType: string): Color3
	return ITEM_TYPE_COLORS[itemType] or THEME.Accent
end

local function getItemImage(itemId: string): string?
	return ITEM_IMAGE_IDS[itemId]
end

local function getItemMonogram(itemId: string): string
	local compact = itemId:gsub("[^%w%s]", "")
	local letters = {}

	for word in compact:gmatch("%S+") do
		table.insert(letters, string.sub(word, 1, 1):upper())
		if #letters >= 2 then
			break
		end
	end

	if #letters == 0 then
		return string.sub(itemId, 1, 2):upper()
	end

	return table.concat(letters)
end

local function clearList()
	for _, child in ipairs(list:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function getOrderedTypes()
	local ordered = table.clone(ITEM_TYPE_ORDER)

	for itemType in pairs(inventory) do
		if not table.find(ordered, itemType) then
			table.insert(ordered, itemType)
		end
	end

	return ordered
end

local function getSortedItems(itemType: string)
	local items = {}

	for itemId, itemState in pairs(inventory[itemType] or {}) do
		table.insert(items, {
			ItemId = itemId,
			ItemState = itemState,
		})
	end

	table.sort(items, function(left, right)
		local leftEquipped = left.ItemState.Equipped == true
		local rightEquipped = right.ItemState.Equipped == true
		if leftEquipped ~= rightEquipped then
			return leftEquipped
		end

		return left.ItemId < right.ItemId
	end)

	return items
end

local function createEmptyState()
	local emptyCard = Instance.new("Frame")
	emptyCard.Name = "EmptyState"
	emptyCard.BackgroundColor3 = THEME.PanelAlt
	emptyCard.BorderSizePixel = 0
	emptyCard.Size = UDim2.new(1, -8, 0, 110)
	emptyCard.Parent = list

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = emptyCard

	local stroke = Instance.new("UIStroke")
	stroke.Color = THEME.Stroke
	stroke.Transparency = 0.35
	stroke.Parent = emptyCard

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -32, 1, -32)
	label.Position = UDim2.fromOffset(16, 16)
	label.Font = Enum.Font.GothamMedium
	label.Text = "Your inventory is empty.\nUse the server commands to add items and they will appear here."
	label.TextColor3 = THEME.TextMuted
	label.TextSize = 18
	label.TextWrapped = true
	label.Parent = emptyCard
end

local function createSectionHeader(text: string, order: number)
	local header = Instance.new("TextLabel")
	header.Name = text .. "Header"
	header.BackgroundTransparency = 1
	header.LayoutOrder = order
	header.Size = UDim2.new(1, -8, 0, 24)
	header.Font = Enum.Font.GothamBold
	header.Text = text
	header.TextColor3 = THEME.Text
	header.TextSize = 18
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Parent = list
end

local function createItemCard(itemState: ItemState, order: number)
	local definition = Registry.GetItemType(itemState.ItemType)
	local typeColor = getTypeColor(itemState.ItemType)

	local card = Instance.new("Frame")
	card.Name = itemState.ItemId
	card.BackgroundColor3 = THEME.PanelAlt
	card.BorderSizePixel = 0
	card.LayoutOrder = order
	card.Size = UDim2.new(1, -8, 0, 84)
	card.Parent = list

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 16)
	cardCorner.Parent = card

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = itemState.Equipped and THEME.Success or typeColor
	cardStroke.Transparency = itemState.Equipped and 0 or 0.35
	cardStroke.Parent = card

	local iconFrame = Instance.new("Frame")
	iconFrame.Name = "Icon"
	iconFrame.BackgroundColor3 = typeColor
	iconFrame.BorderSizePixel = 0
	iconFrame.Position = UDim2.new(0, 16, 0.5, -26)
	iconFrame.Size = UDim2.fromOffset(52, 52)
	iconFrame.Parent = card

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 14)
	iconCorner.Parent = iconFrame

	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = Color3.fromRGB(255, 255, 255)
	iconStroke.Transparency = 0.75
	iconStroke.Parent = iconFrame

	local iconImageId = getItemImage(itemState.ItemId)
	if iconImageId then
		local iconImage = Instance.new("ImageLabel")
		iconImage.BackgroundTransparency = 1
		iconImage.Size = UDim2.new(1, -10, 1, -10)
		iconImage.Position = UDim2.fromOffset(5, 5)
		iconImage.Image = iconImageId
		iconImage.Parent = iconFrame
	else
		local iconText = Instance.new("TextLabel")
		iconText.BackgroundTransparency = 1
		iconText.Size = UDim2.fromScale(1, 1)
		iconText.Font = Enum.Font.GothamBold
		iconText.Text = getItemMonogram(itemState.ItemId)
		iconText.TextColor3 = THEME.Text
		iconText.TextSize = 20
		iconText.Parent = iconFrame
	end

	local itemName = Instance.new("TextLabel")
	itemName.BackgroundTransparency = 1
	itemName.Position = UDim2.fromOffset(82, 12)
	itemName.Size = UDim2.new(1, -226, 0, 24)
	itemName.Font = Enum.Font.GothamBold
	itemName.Text = itemState.ItemId
	itemName.TextColor3 = THEME.Text
	itemName.TextSize = 20
	itemName.TextXAlignment = Enum.TextXAlignment.Left
	itemName.Parent = card

	local details = Instance.new("TextLabel")
	details.BackgroundTransparency = 1
	details.Position = UDim2.fromOffset(82, 42)
	details.Size = UDim2.new(1, -246, 0, 18)
	details.Font = Enum.Font.Gotham
	details.Text = string.format(
		"Type: %s   Quantity: %d",
		ITEM_TYPE_LABELS[itemState.ItemType] or itemState.ItemType,
		itemState.Quantity
	)
	details.TextColor3 = THEME.TextMuted
	details.TextSize = 14
	details.TextXAlignment = Enum.TextXAlignment.Left
	details.Parent = card

	local badge = Instance.new("TextLabel")
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, -16, 0, 12)
	badge.Size = UDim2.fromOffset(92, 26)
	badge.BackgroundColor3 = itemState.Equipped and THEME.Success or typeColor
	badge.BorderSizePixel = 0
	badge.Font = Enum.Font.GothamBold
	badge.Text = itemState.Equipped and "Equipped" or "Stored"
	badge.TextColor3 = THEME.Text
	badge.TextSize = 13
	badge.Parent = card

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(1, 0)
	badgeCorner.Parent = badge

	if definition and definition.Equippable then
		local actionButton = Instance.new("TextButton")
		actionButton.AnchorPoint = Vector2.new(1, 1)
		actionButton.Position = UDim2.new(1, -16, 1, -14)
		actionButton.Size = UDim2.fromOffset(110, 32)
		actionButton.AutoButtonColor = false
		actionButton.BackgroundColor3 = itemState.Equipped and THEME.Panel or typeColor
		actionButton.BorderSizePixel = 0
		actionButton.Font = Enum.Font.GothamBold
		actionButton.Text = itemState.Equipped and "Unequip" or "Equip"
		actionButton.TextColor3 = THEME.Text
		actionButton.TextSize = 14
		actionButton.Parent = card

		local actionCorner = Instance.new("UICorner")
		actionCorner.CornerRadius = UDim.new(0, 10)
		actionCorner.Parent = actionButton

		local actionStroke = Instance.new("UIStroke")
		actionStroke.Color = itemState.Equipped and THEME.Stroke or THEME.AccentSoft
		actionStroke.Transparency = 0.2
		actionStroke.Parent = actionButton

		actionButton.MouseButton1Click:Connect(function()
			commandRemote:FireServer(Constants.Commands.ToggleEquip, {
				ItemType = itemState.ItemType,
				ItemId = itemState.ItemId,
			})
		end)
	end
end

local function renderInventory()
	clearList()

	local hasAnyItems = false
	local layoutOrder = 1

	for _, itemType in ipairs(getOrderedTypes()) do
		local sortedItems = getSortedItems(itemType)
		if #sortedItems > 0 then
			hasAnyItems = true
			createSectionHeader(ITEM_TYPE_LABELS[itemType] or itemType, layoutOrder)
			layoutOrder += 1

			for _, item in ipairs(sortedItems) do
				createItemCard(item.ItemState, layoutOrder)
				layoutOrder += 1
			end
		end
	end

	if not hasAnyItems then
		createEmptyState()
	end
end

local function refreshInventory()
	inventory = deepCopySnapshot(readInventoryMirror())
	renderInventory()
end

local function toggleInventory()
	setInventoryVisible(not isOpen)
end

closeButton.MouseButton1Click:Connect(function()
	setInventoryVisible(false)
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end

	if input.KeyCode == Enum.KeyCode.F then
		toggleInventory()
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

for _, descendant in ipairs(inventoryRoot:GetDescendants()) do
	if descendant:IsA("ValueBase") then
		descendant.Changed:Connect(refreshInventory)
	end
end

refreshInventory()
setInventoryVisible(false)

openButton.MouseButton1Click:Connect(function()
	setInventoryVisible(true)
end)

commandRemote:FireServer(Constants.Commands.RequestSnapshot)
