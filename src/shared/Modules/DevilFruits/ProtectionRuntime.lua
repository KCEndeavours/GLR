local ProtectionRuntime = {}

local evaluators = {}

local function normalizeEvaluatorResult(result)
	if typeof(result) == "table" then
		local isProtected = result.IsProtected == true or result.Protected == true
		local consume = if typeof(result.Consume) == "function" then result.Consume else nil
		return isProtected, consume
	end

	return result == true, nil
end

local function evaluateProtection(targetPlayer, position, context, shouldConsume)
	for _, evaluator in pairs(evaluators) do
		local ok, result = pcall(evaluator, targetPlayer, position, context, {
			Consume = shouldConsume == true,
		})
		if ok then
			local isProtected, consume = normalizeEvaluatorResult(result)
			if isProtected then
				return true, consume
			end
		end
	end

	return false, nil
end

function ProtectionRuntime.Register(name, evaluator)
	if typeof(name) ~= "string" or name == "" then
		return false
	end

	if typeof(evaluator) ~= "function" then
		return false
	end

	evaluators[name] = evaluator
	return true
end

function ProtectionRuntime.Unregister(name)
	if typeof(name) ~= "string" then
		return
	end

	evaluators[name] = nil
end

function ProtectionRuntime.IsProtected(targetPlayer, position, context)
	local isProtected = evaluateProtection(targetPlayer, position, context, false)
	return isProtected
end

function ProtectionRuntime.TryConsume(targetPlayer, position, context)
	local isProtected, consume = evaluateProtection(targetPlayer, position, context, true)
	if not isProtected then
		return false
	end

	if consume then
		pcall(consume)
	end

	return true
end

return ProtectionRuntime
