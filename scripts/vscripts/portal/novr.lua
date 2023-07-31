
local pressedUse = false
---@type PortalColor
local currentPortalColor = nil

local function novrPortalThink()
    local player = Player
    if player:IsUsePressed() then
        if not pressedUse then
            devprint("Firing portal from novr player...")
            pressedUse = true
            local portalIsBlue = currentPortalColor == PortalManager.colors.blue and true or false

            local result = PortalManager:TracePortalableSurface(player:EyePosition(), player:EyeAngles():Forward(), Player)
            if result.hit then
                -- FireUser1 for blue, FireUser2 or orange
                if not IsWorld(result.enthit) then
                    EntFireByHandle(player, result.enthit, portalIsBlue and "FireUser1" or "FireUser2")
                end

                if not result.surfaceIsPortalable then
                    -- createFailedPortalEffect(result.pos, result.normal, color.color)
                    return 0
                end

                if PortalManager:TryCreatePortalAt(result.pos, result.normal, currentPortalColor) then
                    StartSoundEventFromPositionReliable("Portal.Open", result.pos)
                    if portalIsBlue then
                        StartSoundEventFromPositionReliable("Portal.Open.Blue", result.pos)
                    else
                        StartSoundEventFromPositionReliable("Portal.Open.Orange", result.pos)
                    end
                end

                if currentPortalColor == PortalManager.colors.blue then
                    currentPortalColor = PortalManager.colors.orange
                else
                    currentPortalColor = PortalManager.colors.blue
                end
            end

        end
    -- Use is unpressed
    elseif pressedUse then
        pressedUse = false
    end

    return 0
end

RegisterPlayerEventCallback("novr_player", function(params)
    currentPortalColor = PortalManager.colors.blue
    Player:SetContextThink("novr_portal_testing", novrPortalThink, 0.1)
end)
