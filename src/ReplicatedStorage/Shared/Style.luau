-- The game's look: bright, saturated and cartoony. Every builder (world, scenery, models,
-- grass) passes its colours and materials through here, so the style is tuned in one place.
local Style = {}

Style.SATURATION = 1.3 -- multiplies each colour's saturation
Style.SATURATION_ADD = 0.06 -- then adds a little more
Style.BRIGHTNESS = 1.1 -- multiplies each colour's brightness
Style.GREY_BELOW = 0.1 -- colours less saturated than this stay grey / white / black

-- Materials that keep their own look. Everything else becomes flat SmoothPlastic.
Style.KEEP_MATERIAL = { Neon = true, Glass = true, ForceField = true }

-- Lighting and post-processing, read by WorldBuilder.
Style.Lighting = {
	brightness = 2.9,
	exposure = 0.15,
	shadowSoftness = 0.45,
	saturation = 0.3,
	contrast = 0.12,
	gradeBrightness = 0.02,
}
Style.FOG = 0.7 -- multiplies each area's fog density (haze washes colours out)
Style.WATER = Color3.fromRGB(40, 190, 235)

function Style.color(c: Color3): Color3
	local h, s, v = c:ToHSV()
	if s >= Style.GREY_BELOW then
		s = math.min(1, s * Style.SATURATION + Style.SATURATION_ADD)
	end
	return Color3.fromHSV(h, s, math.min(1, v * Style.BRIGHTNESS))
end

function Style.material(m: Enum.Material): Enum.Material
	return Style.KEEP_MATERIAL[m.Name] and m or Enum.Material.SmoothPlastic
end

return Style
