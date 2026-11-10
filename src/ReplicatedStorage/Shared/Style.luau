-- The game's look: natural, muted colours with real materials and soft, detailed lighting.
-- Every builder (world, scenery, models, grass) passes its colours and materials through
-- here, and WorldBuilder and the client read the lighting numbers, so the whole style is
-- tuned in this one file.
local Style = {}

---------------------------------------------------------------- colours
Style.SATURATION = 0.9 -- multiplies each colour's saturation (1 = as written in the configs)
Style.SATURATION_ADD = 0 -- then adds this much
Style.BRIGHTNESS = 1 -- multiplies each colour's brightness
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
	brightness = 2.6,
	exposure = 0,
	shadowSoftness = 0.15, -- crisp, slightly soft shadow edges
	sunTint = Color3.fromRGB(255, 240, 222), -- warm sunlight
	-- colour grading
	saturation = 0.06,
	contrast = 0.06,
	gradeBrightness = 0,
	-- glow around bright and neon things
	bloomIntensity = 0.22,
	bloomSize = 28,
	bloomThreshold = 1.6,
	sunRays = 0.07,
	-- a touch of blur on the far distance
	farBlur = 0.07,
	focusDistance = 90,
	inFocusRadius = 320,
}

---------------------------------------------------------------- sky and air (read by the client)
-- Each area sets its own ambient light and fog colour; these scale them.
Style.AMBIENT = 0.55 -- ambient light in shade: lower = deeper, more defined shadows
Style.OUTDOOR_AMBIENT = 0.8 -- fill light in open air
Style.FOG = 0.55 -- multiplies each area's fog density
Style.HAZE = 1.4 -- soft haze towards the horizon
Style.GLARE = 0.25 -- glow of the air around the sun
Style.AIR_OFFSET = 0.15 -- how far the haze sits from the camera

---------------------------------------------------------------- water (read by WorldBuilder)
Style.Water = {
	color = Color3.fromRGB(46, 138, 178),
	transparency = 0.45,
	reflectance = 0.55,
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
