local ServerScriptService = game:GetService("ServerScriptService")

local CrewmateGameplayService =
	require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewmateGameplayService"))

CrewmateGameplayService.Start()
