local ServerScriptService = game:GetService("ServerScriptService")

local WaveSystemService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("WaveSystemService"))

WaveSystemService.Start()
