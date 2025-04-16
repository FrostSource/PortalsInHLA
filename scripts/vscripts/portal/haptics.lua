--[[
    Custom haptic feedback curves for Portal.
    Code driven haptics allow for quicker fine tuning without having to recompile a map.

    To test these in-game enter in the console `code "PortalHapticImpact2()"`
    Replace the name in quotes with any of the following:

    PortalHapticExplosion
    PortalHapticImpact1
    PortalHapticImpact2
    PortalHapticRumbleWaves
    PortalHapticRoomRumble

    To trigger haptics through I/O you can target any entity and fire:
    
    CallGlobalScriptFunction -> PortalHapticImpact2
]]

local ExplosionCurve = function(t)
    local decay = math.exp(-5 * t)
    return Clamp(decay * RandomFloat(0.85, 1.15), 0, 1)
end

local ImpactCurve1 = function(t)
    local decay = math.exp(-12 * t)        -- fades fast
    local wobble = RandomFloat(0.85, 1.15) -- adds some grit
    return Clamp(decay * wobble, 0, 1)
end

local ImpactCurve2 = function(t)
    if t < 0.05 then
        return 1.0 -- massive initial hit
    elseif t < 0.15 then
        return 0.5 + 0.2 * math.sin(60 * t) -- short, tight metal jitter
    elseif t < 0.4 then
        local echo = 0.3 * math.sin(20 * t - 1.5) * math.exp(-6 * (t - 0.15))
        local noise = RandomFloat(0.8, 1.2)
        return Clamp(echo * noise, 0, 1)
    else
        return 0
    end
end

-- local PortalGunPickupCurve = function(t)
--     -- Base constant hum
--     local base = 0.2

--     -- Subtle pulsing to feel like a hum (not too rhythmic)
--     local lowOsc = 0.05 * math.sin(2 * math.pi * t * 1.5)

--     -- Micro jitter to simulate flickering energy
--     local flicker = 0.02 * math.sin(60 * t + RandomFloat(-0.5, 0.5))

--     local combined = base + lowOsc + flicker
--     return Clamp(combined, 0, 1)
-- end

local RumbleWavesCurve = function(t)
    -- Base sine wave for low-frequency oscillation
    local base = math.abs(math.sin(4 * math.pi * t)) -- 2 full waves per second

    -- Add a wobble layer for chaos
    local wobble = 0.1 * math.sin(40 * t + RandomFloat(-0.5, 0.5))

    -- Add random micro-variation
    local noise = RandomFloat(0.9, 1.1)

    local combined = Clamp((base + wobble) * noise, 0, 1)
    return combined ^ 1.5 -- skew to emphasize stronger moments
end

local RoomRumbleCurve = function(t)
    -- Random-like variation based on time t
    local base = math.sin(3 * t + math.sin(7 * t))          -- Irregular motion as base
    local randomVariation = math.sin(13 * t + math.sin(2.5 * t))  -- Secondary layer
    local combined = base + 0.5 * randomVariation           -- Combine both layers

    -- Adding a subtle, time-varying jitter effect
    local jitter = math.sin(20 * t + math.sin(5 * t)) * 0.05

    -- Final combined value with sharp nonlinear scaling to exaggerate peaks
    local signal = math.abs(combined + jitter)

    -- Apply a power curve to make the motion more intense at certain points (no sine-like smoothness)
    return Clamp(signal ^ 1.7, 0, 1)
end

local function startPortalHaptic(curve, length, minVariance, maxVariance)
    local startTime = Time()
    minVariance = minVariance or 30
    maxVariance = maxVariance or 30
    local leftHandVariance = RandomInt(minVariance, maxVariance)
    local rightHandVariance = RandomInt(minVariance, maxVariance)

    Player:SetContextThink("PortalHaptics", function()
        local t = RemapValClamped(Time(), startTime, startTime + length, 0, 1)
        local x = curve(t)
        Player.LeftHand:FireHapticPulsePrecise(x * leftHandVariance)
        Player.RightHand:FireHapticPulsePrecise(x * rightHandVariance)

        if t >= 1.0 then
            return nil
        end

        return 0
    end, 0)
end

function PortalHapticExplosion()
    startPortalHaptic(ExplosionCurve, 2.0, 60, 80)
end
Expose(PortalHapticExplosion, "PortalHapticExplosion", _G)

function PortalHapticImpact1()
    startPortalHaptic(ImpactCurve1, 2.2)
end
Expose(PortalHapticImpact1, "PortalHapticImpact1", _G)

function PortalHapticImpact2()
    startPortalHaptic(ImpactCurve2, RandomFloat(2.3, 2.6), 30, 60)
end
Expose(PortalHapticImpact2, "PortalHapticImpact2", _G)

function PortalHapticRumbleWaves()
    startPortalHaptic(RumbleWavesCurve, RandomFloat(4, 5))
end
Expose(PortalHapticRumbleWaves, "PortalHapticRumbleWaves", _G)

function PortalHapticRoomRumble()
    startPortalHaptic(RoomRumbleCurve, RandomFloat(5, 7))
end
Expose(PortalHapticRoomRumble, "PortalHapticRoomRumble", _G)

-- Debug testing stuff, delete before ship

-- local index = 0
-- local inds = {
--     "PortalHapticExplosion",
--     "PortalHapticImpact1",
--     "PortalHapticImpact2",
--     "PortalHapticRumbleWaves",
--     "PortalHapticRoomRumble",
-- }

-- Input:ListenToButton("press", -1, DIGITAL_INPUT_FIRE, 1, function()
--     index = index + 1
--     if index > #inds then index = 1 end
--     local nam = inds[index]
--     local fun = _G[nam]
--     if fun then
--         print(nam)
--         fun()
--     end
-- end)
