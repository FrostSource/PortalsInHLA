
local pressedUse = false
---@type PortalColor
local currentPortalColor = nil

local __pickupEntity = nil
local __timeSinceLastUsed = 0
local pickupRange = 100

local SND_EQUIP = "PortalGun.Equipped"
local SND_USE = "PortalGun.Use"
local SND_USE_LOOP = "PortalGun.UseLoop"
local SND_USE_FAILED = "PortalGun.UseFailed"
local SND_USE_FINISHED = "PortalGun.UseStop"

local PTX_PROJECTILE_BLUE = "particles/portal_projectile/portal_1_projectile_stream.vpcf"
local PTX_PROJECTILE_ORANGE = "particles/portal_projectile/portal_2_projectile_stream.vpcf"

---List of classnames that can be picked up by the gun
local PICKUP_CLASS_WHITELIST = {
    "prop_physics",
    "func_physbox",
    "prop_physics_override",
    "prop_physics_interactive",
}

local function HandlePickupAbility()
    if __pickupEntity ~= nil then
        -- Manipulate current pickup entity
        if not IsValidEntity(__pickupEntity) then
            __pickupEntity = nil
            return
        end
        local ent = __pickupEntity

        local desiredPosition = Player:EyePosition() + Player:EyeAngles():Forward() * Convars:GetFloat("portalgun_pickup_distance")
        if Convars:GetBool("portalgun_use_old_pickup_method") then
            local amountBy = VectorDistance(Player:GetOrigin(), ent:GetOrigin()) / 50
            local amount = min(amountBy, 2)
            if VectorDistance(desiredPosition, ent:GetOrigin()) < 25 then
                ent:ApplyAbsVelocityImpulse( (-GetPhysVelocity(ent) / 2) )
            else
                ent:ApplyAbsVelocityImpulse( (((desiredPosition - ent:GetOrigin()) * amount) - (GetPhysVelocity(ent) / 2)) )
            end
        else
            local velocity = (desiredPosition - ent:GetOrigin()) / Convars:GetFloat("portalgun_pickup_attenuation")
            velocity = velocity - GetPhysVelocity(ent)
            ent:ApplyAbsVelocityImpulse(velocity * Convars:GetFloat("portalgun_pickup_damping"))

            local aimAt = nil
            -- Example of special rotation entities
            if ent:GetName() == "@Wheatly" then
                aimAt = (Player:EyePosition() - ent:GetOrigin()):Normalized()
            else
                -- Default face portalgun
                ---@TODO Capture angles when picked up to maintain original angle
                aimAt = (Player:GetOrigin() - ent:GetOrigin()):Normalized()
            end
            local newAim = ent:GetForwardVector():Slerp(aimAt, Convars:GetFloat("portalgun_pickup_rotate_scale")--[[@as number]])
            ent:SetForwardVector(newAim)
        end
    else
        -- Find new pickup entity
        local muzzleOrigin = Player:EyePosition()
        local muzzleForward = Player:EyeAngles():Forward()
        ---@type TraceTableLine
        local traceTable = {
            startpos = muzzleOrigin,
            endpos = muzzleOrigin + muzzleForward * pickupRange,
            ignore = Player,
        }
        TraceLine(traceTable)
        if traceTable.hit and vlua.find(PICKUP_CLASS_WHITELIST, traceTable.enthit:GetClassname()) then
            StartSoundEventFromPositionReliable(SND_USE, Player:GetAbsOrigin())
            StartSoundEvent(SND_USE_LOOP, Player)
            print("New pickup entity: " .. Debug.EntStr(traceTable.enthit))
            __pickupEntity = traceTable.enthit

            -- if Player:IsHolding(traceTable.enthit) then
            --     traceTable.enthit:Drop()
            -- end

            -- Delay between fail sounds
            if __timeSinceLastUsed < 0.2 then
                __timeSinceLastUsed = __timeSinceLastUsed + 0.1
            else
                StartSoundEventFromPositionReliable(SND_USE_FAILED, Player:GetAbsOrigin())
                __timeSinceLastUsed = 0
            end

            ---@TODO Modulate hover distance based on object size
        end
    end
end

local function novrPortalThink()
    local player = Player
    -- 5 e
    -- 13 r
    -- 0 left mouse
    if Convars:GetBool("portal_novr_e_fires_portalgun") then

        if player:IsVRControllerButtonPressed(0) then
            HandlePickupAbility()
        elseif __pickupEntity ~= nil then
            __pickupEntity = nil
            StopSoundEvent(SND_USE_LOOP, Player)
            StartSoundEventFromPositionReliable(SND_USE_FINISHED, Player:GetAbsOrigin())
        end

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
Convars:RegisterConvar("portal_novr_mouse_grabs_objects", "1", "", 0)

ListenToPlayerEvent("novr_player", function(params)
    print("Player is in novr mode...")
    Player:SetContextThink("novr_portal_testing", novrPortalThink, 0.1)
end)
