
local pressedUse = false
---@type PortalColor
local currentPortalColor = nil

local function novrPortalThink()
    local player = Player
    -- 5 e
    -- 13 r
    if Convars:GetBool("portal_novr_e_fires_portalgun") then

        if not pressedUse then
            local color = nil
            local portalIsBlue = false
            if player:IsVRControllerButtonPressed(5) then
                color = PortalManager.colors.blue
                portalIsBlue = true
            elseif player:IsVRControllerButtonPressed(13) then
                color = PortalManager.colors.orange
            end

            if color ~= nil then
                devprint("Firing " .. color.name .. " portal from novr player...")
                pressedUse = true
                -- local portalIsBlue = currentPortalColor == PortalManager.colors.blue and true or false

                local result = PortalManager:TracePortalableSurface(player:EyePosition(), player:EyeAngles():Forward(), Player)
                if result.hit then
                    -- FireUser1 for blue, FireUser2 or orange
                    if not IsWorld(result.enthit) then
                        EntFireByHandle(player, result.enthit, portalIsBlue and "FireUser1" or "FireUser2")
                    end

                    if not result.surfaceIsPortalable then
                        print("Novr bad portal surface")
                        -- PortalManager:CreateFailedPortalEffect(result.pos, result.normal, color.color:ToDecimalVector())
                        PortalManager:CreateFailedPortalEffect(result.pos, result.normal, portalIsBlue and "blue" or "orange")
                        return 0
                    end

                    if PortalManager:TryCreatePortalAt(result.pos, result.normal, color) then
                        StartSoundEventFromPositionReliable("Portal.Open", result.pos)
                        if portalIsBlue then
                            StartSoundEventFromPositionReliable("Portal.Open.Blue", result.pos)
                        else
                            StartSoundEventFromPositionReliable("Portal.Open.Orange", result.pos)
                        end
                    end

                    -- if currentPortalColor == PortalManager.colors.blue then
                    --     currentPortalColor = PortalManager.colors.orange
                    -- else
                    --     currentPortalColor = PortalManager.colors.blue
                    -- end
                end
            end
        else
            if not player:IsVRControllerButtonPressed(5) and not player:IsVRControllerButtonPressed(13) then
                pressedUse = false
            end
        end
        
    end

    return 0
end

Convars:RegisterConvar("portal_novr_e_fires_portalgun", "1", "", 0)

ListenToPlayerEvent("novr_player", function(params)
    print("Player is in novr mode...")
    Player:SetContextThink("novr_portal_testing", novrPortalThink, 0.1)
end)
