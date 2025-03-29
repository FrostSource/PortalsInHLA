--[[
    This script requires the folder "panorama/localization/" to exist in the addon "game" folder
    either as a copy or symlink.
    The hlvr_*.txt files are used to override the hint text, see bottom of files.
]]

local this = thisEntity

---
---Show the hint for firing the blue portal.
---
function this:ShowBluePortalHint()

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
    SendToConsole("gameinstructor_teach_lesson \"Lesson - Teach Chamber Round\"")
end

---
---Show the hint for picking up items with the portal gun.
---
function this:ShowPortalGunPickupHint()
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
    this:SetContextThink("keephint", nil, 0)
end

---
---Enable all instructor hints.
---
function this:EnableHints()
    Convars:SetBool("gameinstructor_enable", true)
end

---
---Hide all hints
---
function this:HideHints()
    if Convars:GetBool("gameinstructor_enable") then
        Convars:SetBool("gameinstructor_enable", false)
        Convars:SetBool("gameinstructor_enable", true)
    end
    this:SetContextThink("keephint", nil, 0)
end