-- The game's look: bright, saturated cartoon colours with real materials and warm, soft lighting.
-- Every builder (world, scenery, models, grass) passes its colours and materials through
-- here, and WorldBuilder and the client read the lighting numbers, so the whole style is
-- tuned in this one file.
local Style = {}

---------------------------------------------------------------- colours
Style.SATURATION = 1.06 -- multiplies each colour's saturation (1 = as written in the configs)
Style.SATURATION_ADD = 0 -- then adds this much
Style.BRIGHTNESS = 1.02 -- multiplies each colour's brightness
Style.GREY_BELOW = 0.1 -- colours less saturated than this are left alone

---------------------------------------------------------------- materials
-- false: parts keep the material they were built with (slate, cobblestone, wood, metal...).
-- true: everything except KEEP_MATERIAL becomes flat SmoothPlastic, for a toy-like look.
Style.FLAT_MATERIALS = false
Style.KEEP_MATERIAL = { Neon = true, Glass = true, ForceField = true }

---------------------------------------------------------------- lighting (read by WorldBuilder)
-- The lighting technology itself (Future) is set in default.project.json, because scripts
-- are not allowed to change it.
Style.Lighting = {
	brightness = 2.9,
	exposure = 0.08,
	shadowSoftness = 0.2, -- crisp, slightly soft shadow edges
	sunTint = Color3.fromRGB(255, 236, 212), -- warm sunlight
	-- colour grading
	saturation = 0.14,
	contrast = 0.1,
	gradeBrightness = 0.01,
	-- glow around bright and neon things
	bloomIntensity = 0.3,
	bloomSize = 26,
	bloomThreshold = 1.4,
	sunRays = 0.09,
	-- a touch of blur on the far distance
	farBlur = 0.1,
	focusDistance = 80,
	inFocusRadius = 300,
}

---------------------------------------------------------------- sky and air (read by the client)
-- Each area sets its own ambient light and fog colour; these scale them.
Style.AMBIENT = 0.6 -- ambient light in shade: lower = deeper, more defined shadows
Style.OUTDOOR_AMBIENT = 0.85 -- fill light in open air
Style.FOG = 0.55 -- multiplies each area's fog density
Style.HAZE = 1.1 -- soft haze towards the horizon
Style.GLARE = 0.25 -- glow of the air around the sun
Style.AIR_OFFSET = 0.15 -- how far the haze sits from the camera

---------------------------------------------------------------- water (read by WorldBuilder)
Style.Water = {
	color = Color3.fromRGB(34, 168, 196), -- clear turquoise
	transparency = 0.38,
	reflectance = 0.5,
	waveSize = 0.14,
	waveSpeed = 8,
}

function Style.color(c: Color3): Color3
	local h, s, v = c:ToHSV()
	if s >= Style.GREY_BELOW then
		s = math.clamp(s * Style.SATURATION + Style.SATURATION_ADD, 0, 1)
	end
	return Color3.fromHSV(h, s, math.min(1, v * Style.BRIGHTNESS))
end

function Style.material(m: Enum.Material): Enum.Material
	if not Style.FLAT_MATERIALS or Style.KEEP_MATERIAL[m.Name] then
		return m
	end
	return Enum.Material.SmoothPlastic
end

return Style
