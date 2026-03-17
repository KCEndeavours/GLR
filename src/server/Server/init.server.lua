local ServerScriptService = game:GetService("ServerScriptService")

local ModulesFolder = ServerScriptService:WaitForChild("Modules")
local InventoryService = require(ModulesFolder:WaitForChild("InventoryService"))

InventoryService.Start()
