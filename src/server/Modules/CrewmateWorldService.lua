local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs")
local CrewmateVariants = require(Configs:WaitForChild("CrewmateVariants"))
local CrewmatesData = require(Configs:WaitForChild("CrewmatesData"))

local CrewmateWorldService = {}

type WeightedEntry = {
	Id: string,
	DisplayName: string,
	Rarity: string,
	Weight: number,
}

type SpawnSelection = {
	Id: string,
	BaseId: string,
	DisplayName: string,
	Rarity: string,
	Variant: string,
	IncomePerTick: number,
	Render: string?,
}

local baseEntries: { WeightedEntry }? = nil
local variantEntries: { { Key: string, Weight: number } }? = nil
local rarityRank = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythical = 6,
	Mythic = 6,
	Godly = 7,
	Secret = 8,
	Omega = 9,
}

local function getBaseEntries()
	if baseEntries then
		return baseEntries
	end

	baseEntries = {}
	for id, info in pairs(CrewmatesData) do
		if type(info) == "table" and info.IsVariant ~= true then
			table.insert(baseEntries, {
				Id = id,
				DisplayName = info.DisplayName or id,
				Rarity = tostring(info.Rarity or "Common"),
				Weight = math.max(0, tonumber(info.Chance) or 0),
			})
		end
	end

	table.sort(baseEntries, function(a, b)
		if a.Weight == b.Weight then
			return a.DisplayName < b.DisplayName
		end

		return a.Weight > b.Weight
	end)

	return baseEntries
end

local function getVariantEntries()
	if variantEntries then
		return variantEntries
	end

	variantEntries = {}
	for _, key in ipairs(CrewmateVariants.Order or { "Normal" }) do
		local info = CrewmateVariants.Versions[key]
		table.insert(variantEntries, {
			Key = key,
			Weight = math.max(0, tonumber(info and info.Chance) or 0),
		})
	end

	return variantEntries
end

local function rollWeighted(entries, rng: Random, weightFn)
	local totalWeight = 0
	for _, entry in ipairs(entries) do
		local computedWeight = weightFn and weightFn(entry) or (tonumber(entry.Weight) or 0)
		totalWeight += math.max(0, computedWeight)
	end

	if totalWeight <= 0 then
		return nil
	end

	local target = rng:NextNumber(0, totalWeight)
	local cursor = 0

	for _, entry in ipairs(entries) do
		local computedWeight = weightFn and weightFn(entry) or (tonumber(entry.Weight) or 0)
		cursor += math.max(0, computedWeight)
		if target <= cursor then
			return entry
		end
	end

	return entries[#entries]
end

local function getVariantDisplayName(baseId: string, variantKey: string): string
	if variantKey == "Normal" then
		return baseId
	end

	local variantInfo = CrewmateVariants.Versions[variantKey]
	local prefix = tostring((variantInfo and variantInfo.Prefix) or (variantKey .. " "))
	return prefix .. baseId
end

local function getDefinition(baseId: string, variantKey: string): SpawnSelection?
	local variantDisplayName = getVariantDisplayName(baseId, variantKey)
	local variantDefinition = CrewmatesData[variantDisplayName]
	local baseDefinition = CrewmatesData[baseId]
	local resolved = variantDefinition or baseDefinition

	if type(resolved) ~= "table" then
		return nil
	end

	return {
		Id = variantDisplayName,
		BaseId = baseId,
		DisplayName = variantDisplayName,
		Rarity = tostring(resolved.Rarity or "Common"),
		Variant = variantKey,
		IncomePerTick = math.max(1, math.floor(tonumber(resolved.Income) or 1)),
		Render = tostring(resolved.Render or ""),
	}
end

function CrewmateWorldService.GetSpawnTable(): { WeightedEntry }
	return table.clone(getBaseEntries())
end

function CrewmateWorldService.RollBaseCrewmate(randomObject: Random?, depthAlpha: number?): string?
	local rng = randomObject or Random.new()
	local normalizedDepth = math.clamp(tonumber(depthAlpha) or 0, 0, 1)
	local maxRarityRank = 9
	local entry = rollWeighted(getBaseEntries(), rng, function(candidate)
		local baseWeight = math.max(0, tonumber(candidate.Weight) or 0)
		if baseWeight <= 0 then
			return 0
		end

		local rank = rarityRank[tostring(candidate.Rarity or "Common")] or 1
		local rarityBias = math.clamp((rank - 1) / math.max(1, maxRarityRank - 1), 0, 1)
		local boost = 1 + (normalizedDepth * rarityBias * 6)
		local dampen = 1 - (normalizedDepth * (1 - rarityBias) * 0.85)
		local combined = boost * math.max(0.15, dampen)
		return baseWeight * combined
	end)
	return entry and entry.Id or nil
end

function CrewmateWorldService.RollVariant(randomObject: Random?): string
	local rng = randomObject or Random.new()
	local entry = rollWeighted(getVariantEntries(), rng)
	if not entry then
		return "Normal"
	end

	return entry.Key
end

function CrewmateWorldService.RollSpawn(
	randomObject: Random?,
	forcedVariantKey: string?,
	depthAlpha: number?
): SpawnSelection?
	local rng = randomObject or Random.new()
	local baseId = CrewmateWorldService.RollBaseCrewmate(rng, depthAlpha)
	if not baseId then
		return nil
	end

	local variantKey = forcedVariantKey or CrewmateWorldService.RollVariant(rng)
	local selection = getDefinition(baseId, variantKey)
	if selection then
		return selection
	end

	return getDefinition(baseId, "Normal")
end

return CrewmateWorldService
