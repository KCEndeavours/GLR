local ItemTypes = require(script.Parent.ItemTypes)

export type ItemTypeDefinition = {
	Name: string,
	Stackable: boolean,
	Equippable: boolean,
	MaxStack: number?,
	MaxEquipped: number?,
}

local Registry = {}

local definitions: { [string]: ItemTypeDefinition } = {}

local function copyDefinition(definition: ItemTypeDefinition): ItemTypeDefinition
	return {
		Name = definition.Name,
		Stackable = definition.Stackable,
		Equippable = definition.Equippable,
		MaxStack = definition.MaxStack,
		MaxEquipped = definition.MaxEquipped,
	}
end

function Registry.RegisterItemType(definition: ItemTypeDefinition): ItemTypeDefinition
	assert(typeof(definition) == "table", "definition must be a table")
	assert(typeof(definition.Name) == "string" and definition.Name ~= "", "definition.Name must be a non-empty string")

	local normalized = copyDefinition(definition)
	if normalized.MaxEquipped == nil then
		normalized.MaxEquipped = normalized.Equippable and 1 or 0
	end
	if normalized.Stackable == false then
		normalized.MaxStack = 1
	end

	definitions[normalized.Name] = normalized
	return copyDefinition(normalized)
end

function Registry.GetItemType(itemType: string): ItemTypeDefinition?
	local definition = definitions[itemType]
	if not definition then
		return nil
	end

	return copyDefinition(definition)
end

function Registry.GetAll(): { [string]: ItemTypeDefinition }
	local result = {}
	for itemType, definition in pairs(definitions) do
		result[itemType] = copyDefinition(definition)
	end
	return result
end

function Registry.IsRegistered(itemType: string): boolean
	return definitions[itemType] ~= nil
end

Registry.RegisterItemType({
	Name = ItemTypes.Crewmates,
	Stackable = true,
	Equippable = true,
	MaxEquipped = 1,
})

Registry.RegisterItemType({
	Name = ItemTypes.DevilFruit,
	Stackable = true,
	Equippable = true,
	MaxStack = 1,
	MaxEquipped = 1,
})

Registry.RegisterItemType({
	Name = ItemTypes.Material,
	Stackable = true,
	Equippable = false,
})

Registry.RegisterItemType({
	Name = ItemTypes.Consumable,
	Stackable = true,
	Equippable = false,
})

return Registry
