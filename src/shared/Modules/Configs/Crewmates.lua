local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs")
local CrewCatalog = require(Configs:WaitForChild("GrandLineRushCrewCatalog"))
local Economy = require(Configs:WaitForChild("GrandLineRushEconomy"))

local Crewmates = {}

local VARIANTS = {
	Normal = {
		DisplayNamePrefix = "",
		IncomeMultiplier = 1,
	},
	Golden = {
		DisplayNamePrefix = "Golden ",
		IncomeMultiplier = 2.5,
	},
	Diamond = {
		DisplayNamePrefix = "Diamond ",
		IncomeMultiplier = 4,
	},
}

local RARITY_WEIGHTS = {
	Common = 90,
	Uncommon = 45,
	Rare = 18,
	Epic = 7,
	Legendary = 2,
	Mythical = 0.75,
	Celestial = 0.2,
	Godly = 0.05,
	Secret = 0.01,
}

local BASE_DEFINITIONS = {}
local SORTED_BASE_IDS = {}
local SORTED_VARIANT_KEYS = { "Normal", "Golden", "Diamond" }

local function getIncomePerTick(rarity: string, variantKey: string): number
	local baseIncomePerHour = Economy.Crew.ShipIncomePerHourByRarity[rarity] or 0
	local baseIncomePerTick = math.max(1, math.floor((baseIncomePerHour / 120) + 0.5))
	local multiplier = (VARIANTS[variantKey] and VARIANTS[variantKey].IncomeMultiplier) or 1

	return math.max(1, math.floor((baseIncomePerTick * multiplier) + 0.5))
end

for rarity, names in pairs(CrewCatalog.ByRarity) do
	for _, displayName in ipairs(names) do
		local id = string.gsub(displayName, "%s+", "")
		local definition = {
			Id = id,
			DisplayName = displayName,
			Rarity = rarity,
			SpawnWeight = RARITY_WEIGHTS[rarity] or 0,
			IncomePerTick = getIncomePerTick(rarity, "Normal"),
			Source = "CrewCatalog",
		}

		BASE_DEFINITIONS[id] = definition
		table.insert(SORTED_BASE_IDS, id)
	end
end

table.sort(SORTED_BASE_IDS)

local function shallowCopy(source)
	return table.clone(source)
end

function Crewmates.GetVariantInfo(variantKey: string)
	return VARIANTS[variantKey] or VARIANTS.Normal
end

function Crewmates.GetVariantKeys()
	return table.clone(SORTED_VARIANT_KEYS)
end

function Crewmates.GetBaseDefinitions()
	local definitions = {}
	for _, id in ipairs(SORTED_BASE_IDS) do
		definitions[id] = shallowCopy(BASE_DEFINITIONS[id])
	end

	return definitions
end

function Crewmates.GetBaseDefinition(id: string)
	local definition = BASE_DEFINITIONS[id]
	if not definition then
		return nil
	end

	return shallowCopy(definition)
end

function Crewmates.GetDefinition(id: string, variantKey: string?)
	local baseDefinition = BASE_DEFINITIONS[id]
	if not baseDefinition then
		return nil
	end

	local resolvedVariantKey = variantKey or "Normal"
	local variantInfo = Crewmates.GetVariantInfo(resolvedVariantKey)
	local definition = shallowCopy(baseDefinition)

	definition.BaseId = id
	definition.Variant = resolvedVariantKey
	definition.DisplayName = string.format("%s%s", variantInfo.DisplayNamePrefix, baseDefinition.DisplayName)
	definition.IncomePerTick = getIncomePerTick(baseDefinition.Rarity, resolvedVariantKey)

	return definition
end

function Crewmates.GetWeightedBaseEntries()
	local entries = {}
	for _, id in ipairs(SORTED_BASE_IDS) do
		local definition = BASE_DEFINITIONS[id]
		table.insert(entries, {
			Id = id,
			DisplayName = definition.DisplayName,
			Rarity = definition.Rarity,
			Weight = definition.SpawnWeight,
		})
	end

	return entries
end

return Crewmates
