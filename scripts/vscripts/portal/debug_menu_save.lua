
local fileio = require("alyxlib.io.file")
local kvstore = require("alyxlib.io.kvstore")

local convars = {
    "portal2_approach_effect",
    "portal2_vr_body",
    "portal2_custom_hints",
    "portal_funnel_amount",
    "portal_max_fling_speed",
    "portal_physical_flings",
    "portal_player_speed_multiplier",
    "portal_use_outlines",
    "portal_woosh_always",
}

local function SaveConvars()
    print("Saving "..#convars.." convars")
    for _,v in pairs(convars) do

        local val
        if EasyConvars:Exists(v) then
            val = EasyConvars:GetStr(v)
        else
            val = Convars:GetStr(v)
        end

        if val ~= nil then
            print("Saving", v, val)
            kvstore.set(v, val)
        else
            print("Convar not found:", v)
        end
    end

    fileio.mkdir("portal")
    local success, err = kvstore.save("portal/kvstoretest.txt")
    if not success then
        warn("Failed to save", err)
        return
    end
    print("Done saving")
end

local function SaveConvarsWithDelay(delay)
    delay = delay or 0.05

    if not Player then
        warn("Cannot save convars without player")
        return
    end

    Player:Delay(function()
        SaveConvars()
    end, delay)
end

local function LoadConvars()
    print("Loading convars")
    local success, err = kvstore.load("portal/kvstoretest.txt")
    if not success then
        warn("Failed to load", err)
        return
    end

    for _,v in pairs(convars) do
        local val = kvstore.get(v)
        if val ~= nil then
            print("Loading", v, val)

            if EasyConvars:Exists(v) then
                if EasyConvars:GetStr(v) ~= val then
                    EasyConvars:SetStr(v, val)
                end
            else
                if Convars:GetStr(v) ~= val then
                    Convars:SetStr(v, val)
                end
            end
        else
            print("Convar not found in load:", v)
        end
    end
end

Convars:RegisterCommand("portal_test_save", SaveConvars, "", 0)
Convars:RegisterCommand("portal_test_load", LoadConvars, "", 0)

return {
    SaveConvars = SaveConvars,
    SaveConvarsWithDelay = SaveConvarsWithDelay,
    LoadConvars = LoadConvars,
}