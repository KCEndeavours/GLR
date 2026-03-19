local LavaWaves = {
	Wave = {
		Speed = 60,
		Chance = 100,
		RotX = 0,
		RotY = 0,
		RotZ = 0,
		Image = "rbxassetid://96345846540605",
		Fallback = {
			ClassName = "Part",
			Color = Color3.fromRGB(236, 107, 55),
			Material = Enum.Material.Neon,
			Size = Vector3.new(28, 14, 6),
			Shape = Enum.PartType.Block,
			HazardClass = "major",
			HazardType = "lava_wave",
			CanFreeze = true,
			FreezeBehavior = "pause",
		},
	},
}

return LavaWaves
