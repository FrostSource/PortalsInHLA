--[[
    This script requires the folder "panorama/localization/" to exist in the addon "game" folder
    either as a copy or symlink.
    The hlvr_*.txt files are used to override the hint text, see bottom of files.
]]

local this = thisEntity

local userLanguage = Convars:GetStr("cl_language")

---
---Show the hint for firing the blue portal.
---
function this:ShowBluePortalHint()
    this:EnableHints()

    -- Reset because grenade hint only shows twice
    SendToConsole("gameinstructor_reset_counts")

    -- Trick the game into showing the hijacked grenade hint
    FireGameEvent("item_pickup", {
        item = "item_hlvr_grenade_frag",
        vr_tip_attachment = 1
    })

    -- Teach Grenade has 10s timeout
    -- SendToConsole("gameinstructor_teach_lesson \"Lesson - Teach Grenade\"")
    SendToConsole("gameinstructor_teach_lesson \"Lesson - Teach First Reload Single Controller\"")
    print('hint done')
end

---
---Show the hint for firing the orange portal.
---
function this:ShowOrangePortalHint()
    this:EnableHints()

    -- Vive is remapped to burst fire
    if Player:GetVRControllerType() == 2 then
        SendToConsole("gameinstructor_teach_lesson \"Lesson - Teach Toggle Burst Fire\"")
    else
        SendToConsole("gameinstructor_teach_lesson \"Lesson - Teach Chamber Round\"")
    end
end

---
---Show the hint for picking up items with the portal gun.
---
function this:ShowPortalGunPickupHint()
    this:EnableHints()

    -- Has a 5s timeout, unsure how to work around
    -- this:SetContextThink("keephint", function ()
        SendToConsole("gameinstructor_teach_lesson \"Lesson - Shotgun Upgrade Grenade Teach Fire\"")
        -- return 1
    -- end, 0)
end

---
---Disable all instructor hints.
---Useful for removing Alyx hints.
---
function this:DisableHints()
    Convars:SetBool("gameinstructor_enable", false)
end

---
---Enable all instructor hints.
---
function this:EnableHints()
    userLanguage = Convars:GetStr("cl_language")
    Convars:SetBool("gameinstructor_enable", true)
    -- This is required to show custom hint text
    SendToConsole("set_vgui_language " .. userLanguage)
end

---
---Hide all hints
---
function this:HideHints()
    if Convars:GetBool("gameinstructor_enable") then
        Convars:SetBool("gameinstructor_enable", false)
        Convars:SetBool("gameinstructor_enable", true)
    end
end