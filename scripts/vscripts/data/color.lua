---Get the memory address part of a table.
---@param tbl table
---@return string
local function getaddress(tbl)
	return tostring(tbl):match("table: (%S+)")
end

local function hasDecimal(number)
	return number ~= nil and number ~= math.floor(number)
end

local function clamp(v, a, b)
	-- return Clamp(v, a, b)
	return math.min(math.max(v, a), b)
end

---Convert a value range into a valid range for the Color class.
---@param value number
---@param default? integer
---@return integer
local function resolveColorRange(value, default)
	if hasDecimal(value) then
		value = value * 255
	end
	return clamp(value or default or 0, 0, 255)
end

local function hueToRgb(p, q, t)
	if t < 0 then t = t + 1 end
	if t > 1 then t = t - 1 end
	if t < 1/6 then return p + (q - p) * 6 * t end
	if t < 1/2 then return q end
	if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
	return p
end

---Converts HSL color values to RGB.
---@param h number # Hue value range [0-1].
---@param s number # Saturation value range [0-1].
---@param l number # Lightness value range [0-1].
---@return integer r # Red color value in range [0-255].
---@return integer g # Green color value in range [0-255].
---@return integer b # Blue color value in range [0-255].
local function hslToRgb(h, s, l)
	local r, g, b

	if s == 0 then
		-- achromatic
		r = l
		g = l
		b = l
	else
		local q = l < 0.5 and l * (1 + s) or l + s - l * s
		local p = 2 * l - q
		r = hueToRgb(p, q, h + 1/3)
		g = hueToRgb(p, q, h)
		b = hueToRgb(p, q, h - 1/3)
	end

	-- Adjust ranges for floating precision errors
	return math.min(math.floor(r*256),255), math.min(math.floor(g*256),255), math.min(math.floor(b*256),255)
end

---Converts RGB color values to HSL.
---@param r number # Red value range [0-255].
---@param g number # Red value range [0-255].
---@param b number # Red value range [0-255].
---@return number h # Hue color value in range [0-1].
---@return number s # Saturation color value in range [0-1].
---@return number l # Lightness color value in range [0-1].
local function rgbToHsl(r, g, b)
	r = r / 255
	g = g / 255
	b = b / 255
	local vmax, vmin = math.max(r, g, b), math.min(r, g, b)
	local div = (vmax + vmin) / 2
	local h, s, l = div, div, div

	if vmax == vmin then
		return 0, 0, l
	end

	local d = vmax - vmin
	s = l > 0.5 and d / (2 - vmax - vmin) or d / (vmax + vmin)
	if vmax == r then h = (g - b) / d + (g < b and 6 or 0) end
	if vmax == g then h = (b - r) / d + 2 end
	if vmax == b then h = (r - g) / d + 4 end
	h = h / 6

	return h, s, l
end

---@class Color
---@field r integer # Red component.
---@field g integer # Green component.
---@field b integer # Blue component.
---@field a integer # Alpha component.
---@field hue integer # Hue component.
---@field saturation integer # Saturation component.
---@field lightness integer # Lightness component.
local ColorClass = {}

if pcall(require, "storage") then
    Storage.RegisterType("Color", ColorClass)

    ---
    ---**Static Function**
    ---
    ---Helper function for saving the `Color`.
    ---
    ---@param handle EntityHandle # The entity to save on.
    ---@param name string # The name to save as.
    ---@param color Color # The color to save.
    ---@return boolean # If the save was successful.
    ---@luadoc-ignore
    function ColorClass.__save(handle, name, color)
        return Storage.SaveTableCustom(handle, name, color, "Color")
    end

    ---
    ---**Static Function**
    ---
    ---Helper function for loading the `Color`.
    ---
    ---@param handle EntityHandle # Entity to load from.
    ---@param name string # Name to load.
    ---@return Color|nil
    ---@luadoc-ignore
    function ColorClass.__load(handle, name)
		print("CUSTOM COLOR LOAD")
        local color = Storage.LoadTableCustom(handle, name, "Color")
        if color == nil then return nil end
		color.__address = getaddress(color)
        return setmetatable(color, ColorClass)
    end

    Storage.SaveColor = ColorClass.__save
    CBaseEntity.SaveColor = Storage.SaveColor

    ---
    ---Load a `Color`.
    ---
    ---@generic T
    ---@param handle EntityHandle # Entity to load from.
    ---@param name string # Name the Color was saved as.
    ---@param default? T # Optional default value.
    ---@return Color|T
    ---@luadoc-ignore
    Storage.LoadColor = function(handle, name, default)
        local color = ColorClass.__load(handle, name)
        if color == nil then
            return default
        end
        return color
    end
    CBaseEntity.LoadColor = Storage.LoadColor
end

---Retrieve component value from named color key.
---@param color Color
function ColorClass.__index(color, key)
	if type(key) == "number" then
		return rawget(color, key)
	elseif key == "r" then
		return rawget(color, 1)
	elseif key == "g" then
		return rawget(color, 2)
	elseif key == "b" then
		return rawget(color, 3)
	elseif key == "a" then
		return rawget(color, 4)
	elseif key == "hue" then
		local h, _, _ = color:GetHSL()
		return h
	elseif key == "saturation" then
		local _, s, _ = color:GetHSL()
		return s
	elseif key == "lightness" then
		local _, _, l = color:GetHSL()
		return l
	else
		return rawget(ColorClass, key)
	end
end

---Update the raw color values when selecting named color keys.
---@param color Color
---@param key any
---@param value any
function ColorClass.__newindex(color, key, value)
	---@TODO Does this actually fire if 1-4?
	if type(key) == "number" then
		if key == 1 or key == 2 or key == 3 or key == 4 then
			rawset(color, key, resolveColorRange(value, rawget(color, key)))
		else
			rawset(color, key, value)
		end
	elseif key == "r" then
		rawset(color, 1, resolveColorRange(value, rawget(color, 1)))
	elseif key == "g" then
		rawset(color, 2, resolveColorRange(value, rawget(color, 2)))
	elseif key == "b" then
		rawset(color, 3, resolveColorRange(value, rawget(color, 3)))
	elseif key == "a" then
		rawset(color, 4, resolveColorRange(value, rawget(color, 4)))
	elseif key == "hue" then
		color:SetHSL(value, nil, nil)
	elseif key == "saturation" then
		color:SetHSL(nil, value, nil)
	elseif key == "lightness" then
		color:SetHSL(nil, nil, value)
	else
		rawset(color, key, value)
	end
end

function ColorClass.__tostring(color)
	return string.format("Color %s [%d %d %d %d]", color.__address, color[1], color[2], color[3], color[4])
end

function ColorClass:ToHexString()
	local function toHex(val)
        return string.format("%02X", val)
    end

    return "#" .. toHex(self.r) .. toHex(self.g) .. toHex(self.b)
end

---Get a `Vector` from this `Color` in the form of [x=r, y=g, z=b].
---@return Vector # The color vector.
function ColorClass:ToVector()
	return Vector(self[1], self[2], self[3])
end

---Get a `Vector` from this `Color` in the form of [x=r, y=g, z=b] but with ranges [0-1].
---@return Vector # The color vector.
function ColorClass:ToDecimalVector()
	return Vector(self[1] / 255, self[2] / 255, self[3] / 255)
end

---Set the color and alpha values of this `Color`.
---@param r? number # Can be ranges [0-1] or [0-255].
---@param g? number # Can be ranges [0-1] or [0-255].
---@param b? number # Can be ranges [0-1] or [0-255].
---@param a? number # Can be ranges [0-1] or [0-255].
function ColorClass:SetRGB(r, g, b, a)
	if hasDecimal(r) or hasDecimal(g) or hasDecimal(b) or hasDecimal(a) then
		r = r and r * 255 or self.r
		g = g and g * 255 or self.g
		b = b and b * 255 or self.b
		a = a and a * 255 or self.a
	end

	self.r = r
	self.g = g
	self.b = b
	self.a = a
end

---Get the HSL color values from this `Color`.
---@return number? h # Hue color value in range [0-360]
---@return number? s # Saturation color value in range [0-100]
---@return number? l # Lightness color value in range [0-100]
function ColorClass:GetHSL()
	local h, s, l = rgbToHsl(self[1], self[2], self[3])
	return math.floor(h * 360), math.floor(s * 100), math.floor(l * 100)
end

function ColorClass:SetHSL(h, s, l)
	if hasDecimal(h) or hasDecimal(s) or hasDecimal(l) then
		h = h and h / 360 or nil
		s = s / 100 or nil
		l = l / 100 or nil
	end

	-- Allow for nil values being unchanged
	if h == nil or s == nil or l == nil then
		local _h, _s, _l = self:GetHSL()
		h = h or _h
		s = s or _s
		l = l or _l
	end

    self:SetRGB(hslToRgb(h, s, l))
end

---Create a new `Color` instance using range [0-1] or [0-255].
---@param r? number # Red color value.
---@param g? number # Green color value.
---@param b? number # Blue color value.
---@param a? number # Alpha value.
---@return Color
---@overload fun(rgb: Vector)
---@overload fun(rgb: string)
function Color(r, g, b, a)
	if type(r) == "string" then
		r, g, b, a = r:match("(%d+)[^%d]+(%d*)[^%d]+(%d*)[^%d]+(%d*)")
		return Color(tonumber(r), tonumber(g), tonumber(b), tonumber(a))
	elseif IsVector(r) then
		---@diagnostic disable-next-line: need-check-nil
		return Color(r.x, r.y, r.z, nil)
	end

	local self = {}

	-- Convert [0-1] ranges
	if hasDecimal(r) or hasDecimal(g) or hasDecimal(b) or hasDecimal(a) then
		r = r and r * 255 or nil
		g = g and g * 255 or nil
		b = b and b * 255 or nil
		a = a and a * 255 or nil
	end

	self[1] = clamp(r or 0, 0, 255)
	self[2] = clamp(g or 0, 0, 255)
	self[3] = clamp(b or 0, 0, 255)
	self[4] = clamp(a or 255, 0, 255)

	self.__address = getaddress(self)
	setmetatable(self, ColorClass)
	return self
end

---Get if a value is a `Color`.
---@param value any
---@return boolean
function IsColor(value)
	return type(value) == "table" and getmetatable(value) == ColorClass
end
