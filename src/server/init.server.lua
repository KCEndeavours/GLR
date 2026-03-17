local ServerScriptService = game:GetService("ServerScriptService")

local ServerFolder = ServerScriptService:WaitForChild("Server")
local InventoryService = require(ServerFolder:WaitForChild("InventoryService"))

InventoryService.Start()
