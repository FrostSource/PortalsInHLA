
local fileio = require("alyxlib.io.file")
local kvstore = require("alyxlib.io.kvstore")

local convars = {
    "portal2_approach_effect",
    "portal_funnel_amount",
    "portal_max_fling_speed",
    "portal_physical_flings",
    "portal_player_speed_multiplier",
    "portal_use_outlines",
    "portal_whoosh_always",
}

local function SaveConvars()
    print("Saving "..#convars.." convars")
    for _,v in pairs(convars) do
        local val = Convars:GetStr(v)
        if val ~= nil then
            print("Saving", v, Convars:GetStr(v))
            kvstore.set(v, Convars:GetStr(v))
        else
            print("Convar not found:", v)
        end
    end

    fileio.mkdir("portal")
    local success, err = kvstore.save("portal/kvstoretest.txt")
    if not success then
        print("Failed to save", err)
        return
    end
    print("Done saving")
end

local function LoadConvars()
    print("Loading convars (dummy load, convars won't be changed)")
    local success, err = kvstore.load("portal/kvstoretest.txt")
    if not success then
        print("Failed to load", err)
        return
    end

    for _,v in pairs(convars) do
        local val = kvstore.get(v)
        if val ~= nil then
            print("Loading", v, val)
            -- Convars:SetStr(v, val)
        else
            print("Convar not found in load:", v)
        end
    end
end

Convars:RegisterCommand("portal_test_save", SaveConvars, "", 0)
Convars:RegisterCommand("portal_test_load", LoadConvars, "", 0)