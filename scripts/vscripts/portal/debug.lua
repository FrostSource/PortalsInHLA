--[[
    General PortalsInHLA debugging logic
]]

local function listenForNoClipVrActivation()
    local buttonPressesToActivate = 3
    local buttonPresses = 0
    local timeToResetBetweenPresses = 0.6
    local buttonPressed = false
    local timeSinceLastButtonPress = 0

    -- Debug noclip vr activation
    Player:SetContextThink("debug_noclip_activate", function()
        if Convars:GetInt("developer") < 2 then return 5 end

        if Time() - timeSinceLastButtonPress > timeToResetBetweenPresses then
            buttonPresses = 0
            timeSinceLastButtonPress = math.huge
        end

        local hand = Player.SecondaryHand

        if Player:IsDigitalActionOnForHand(hand.Literal, DIGITAL_INPUT_ARM_GRENADE) then
            if not buttonPressed then
                buttonPressed = true
                timeSinceLastButtonPress = Time()
                buttonPresses = buttonPresses + 1

                if buttonPresses >= buttonPressesToActivate then
                    buttonPresses = 0
                    SendToConsole("noclip_vr")
                end
            end
        else
            if buttonPressed then
                buttonPressed = false
            end
        end

        return 0
    end, 0)
end

ListenToPlayerEvent("vr_player_ready", function()
    if IsVREnabled() then
        listenForNoClipVrActivation()
    end
end)