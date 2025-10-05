if thisEntity then
    -- Inherit this script if attached to entity
    -- Will also load the script at the same time if needed
    inherit(GetScriptFile())
    return
end

local PLAYER_MASS = 65 -- in kg

local PORTAL_FUNNEL_AMOUNT = 6.0
Convars:RegisterConvar("portal_funnel_amount", tostring(PORTAL_FUNNEL_AMOUNT), "Amount of portals to funnel into", 0)

Convars:RegisterConvar("portal_playerphys_wallbounce_multiplier", "0.05", "Multiplier for wall bounces", 0)

-- EasyConvars:RegisterConvar("portal_funnel_sensitivity", "2", "Overall sensitivity of portal funneling", FCVAR_NONE, function (newVal, oldVal)
--     if newVal == "0" then
--         Convars:SetBool("player_funnel_into_portals", false)
--         Convars:SetFloat("portal_funnel_amount", 0.0)
--     elseif newVal == "1" then
--         Convars:SetBool("player_funnel_into_portals", true)
--         Convars:SetFloat("portal_funnel_amount", 3.0)
--     elseif newVal == "2" then
--         Convars:SetBool("player_funnel_into_portals", true)
--         Convars:SetFloat("portal_funnel_amount", 6.0)
--     elseif newVal == "3" then
--         Convars:SetBool("player_funnel_into_portals", true)
--         Convars:SetFloat("portal_funnel_amount", 12.0)
--     end
-- end)
-- EasyConvars:SetPersistent("portal_funnel_sensitivity", true)

EasyConvars:RegisterConvar("portal_funnelling", "1", "If player portal funnelling is enabled", FCVAR_NONE)
EasyConvars:SetPersistent("portal_funnelling", true)

local PORTAL_HALF_WIDTH = 28
local PORTAL_HALF_HEIGHT = 49.5

PORTAL_OBBDATA = GetBoundingOBBData(PORTAL_MINS, PORTAL_MAXS)

-- EasyConvars:RegisterConvar("portal_attract_distance", "128", "Distance at which the player is attracted to a portal when falling")
Convars:RegisterConvar("player_funnel_into_portals", "1", "Player will move towards portals they are falling into", 0)

EasyConvars:RegisterConvar("portal_max_fling_speed", "800", "Maximum speed at which the player can move while flinging")
EasyConvars:SetPersistent("portal_max_fling_speed", true)

EasyConvars:RegisterConvar("portal_use_fling_vignette",
function()
    -- Default on for teleport movement
    local mt = Convars:GetInt("hlvr_movetype_default")
    return mt == 0 or mt == 1
end,
"If a vision vignette should be used when flinging", FCVAR_NONE,
function (newVal, oldVal)
    if IsValidEntity(PortalPlayerController.currentPlayerPhys) then
        if Convars:GetBool("portal_use_fling_vignette") then
            PortalPlayerController.currentPlayerPhys:CreateVignette()
        else
            PortalPlayerController.currentPlayerPhys:RemoveVignette()
        end
    end
end)
EasyConvars:SetPersistent("portal_use_fling_vignette", true)

---@class PortalPlayerPhys : EntityClass
local base = entity("PortalPlayerPhys")
_G.PortalPlayerPhys = base

base.__expectingPortal = false

base.__vignettePtfxIndex = -1

---Called automatically on spawn
---@param spawnkeys CScriptKeyValues
function base:OnSpawn(spawnkeys)
	local xVelocity = tonumber(spawnkeys:GetValue("velocity_x"))
	local yVelocity = tonumber(spawnkeys:GetValue("velocity_y"))
	local zVelocity = tonumber(spawnkeys:GetValue("velocity_z"))

	self.velocity = Vector(xVelocity, yVelocity, zVelocity)
    -- print("VELOCITY NUMS", xVelocity, yVelocity, zVelocity)

    -- Debug check is in function
    self:DrawTrajectory()

    -- self:RemoveOthers()
    -- self:SetEntityName(ENT_NAME)
	self:SetPlayerAnchorParent(self:GetName())
	self:DisablePlayerTeleport()

	-- super.OnSpawn(self)
end

function base:Precache(context)
    PrecacheModel(self:GetModelName(), context)
end

function base:OnReady()
    self:ResumeThink()

    if Convars:GetBool("portal_use_fling_vignette") then
        self:CreateVignette()
    end
end

---Sets the velocity for this player phys.
---@param velocity Vector
function base:SetVelocity(velocity)
    self.velocity = velocity
    CBaseEntity.SetVelocity(self, velocity)
end

function CalculatePortalVelocity(playerPos, portalPos, currentVel)
    local fallHeight = playerPos.z - portalPos.z

    -- Only adjust if above target
    if fallHeight <= 0 then
        return currentVel
    end

    -- Simple time calculation: how long at current Z velocity to reach target
    local fallTime = fallHeight / math.abs(currentVel.z)

    -- Calculate required horizontal velocity to hit target
    local targetVelX = (portalPos.x - playerPos.x) / fallTime
    local targetVelY = (portalPos.y - playerPos.y) / fallTime

    return Vector(targetVelX, targetVelY, currentVel.z)
end

---Funnel the player into the portal
---@param portal Portal
---@param wishdir Vector
function base:FunnelIntoPortal(portal, wishdir)
    if not IsValidEntity(portal) then return end

    local vPortalForward = portal:GetForwardVector()
    local vPortalRight = portal:GetRightVector()
    local vPortalUp = portal:GetUpVector()

    -- Make sure it's a floor portal
    if vPortalForward.z < 0.8 then return end

    vPortalRight.z = 0
    vPortalUp.z = 0
    vPortalRight = vPortalRight:Normalized()
    vPortalUp = vPortalUp:Normalized()

    -- Make sure the player is looking down
    if Player:EyeAngles():Forward().z > -0.5 then return end

    local vPlayerToPortal = portal:GetAbsOrigin() - self:GetAbsOrigin()
    local velocity = self.velocity

    -- Make sure the player isn't trying to air control, they're falling downward and they are vertically close to the portal
    --0.1422
    if abs(wishdir.x) > 40 or abs(wishdir.y) > 40 or velocity.z > -165 or vPlayerToPortal.z < -512 then
    -- if velocity.z > -165 or vPlayerToPortal.z < -512 then
        return
    end

    -- Make sure player is moving towards the portal
    -- if portal:GetForwardVector():Dot(velocity) > -0.5 then return end

    -- Make sure we're in the 2D portal rectangle
    if (vPlayerToPortal:Dot(vPortalRight) * vPortalRight):Length() > PORTAL_HALF_WIDTH * 1.5 then
        return
    end
    if (vPlayerToPortal:Dot(vPortalUp) * vPortalUp):Length() > PORTAL_HALF_HEIGHT * 1.5 then
        return
    end

    -- print("Funneling into portal", portal:GetName())

    if vPlayerToPortal.z > -8.0 then
        -- We're too close the the portal to continue correcting, but zero the velocity so our fling velocity is nice
        wishdir.x = 0
        wishdir.y = 0
        return wishdir
    else
        DebugIf("portal_debug_portals", function()
            debugoverlay:Sphere(self:GetAbsOrigin(), 1.5, 255, 0, 128, 255, true, 0.02)
        end)
        -- Funnel toward the portal
        local funnelAmount = Convars:GetFloat("portal_funnel_amount")
        local fFunnelX = vPlayerToPortal.x * funnelAmount - velocity.x
        local fFunnelY = vPlayerToPortal.y * funnelAmount - velocity.y

        wishdir.x = wishdir.x + fFunnelX
        wishdir.y = wishdir.y + fFunnelY
        return wishdir
    end
end

function base:GetThumbstickVector()
    -- Check offhand first because it's most common, then check primary hand movement
    local moveVector = Player:GetAnalogActionPositionForHand(Player.SecondaryHand.Literal, ANALOG_INPUT_TELEPORT_TURN)
    local hand = Player.SecondaryHand
    if #moveVector == 0 then
        moveVector = Player:GetAnalogActionPositionForHand(Player.PrimaryHand.Literal, ANALOG_INPUT_TELEPORT_TURN)
        hand = Player.PrimaryHand
    end

    local dir = Vector(0, 0, 0)

    if moveVector:Length() > 0 then
        local moveType = Player:GetMoveType()

        if moveType == PlayerMoveType.ContinuousHand then
            dir = (hand:GetAngles():Left() * moveVector.x) + (hand:GetAngles():Forward() * moveVector.y)
        else
            dir = (Player:EyeAngles():Left() * moveVector.x) + (Player:EyeAngles():Forward() * moveVector.y)
        end
    end

    return dir:Normalized()
end

local quickTurnFlag = false

---Main entity think function. Think state is saved between loads
function base:Think()
	local time = Time()
	local frameTime = FrameTime()

    local gravitySpeed = Convars:GetFloat("sv_gravity") -- default is 386
    -- gravitySpeed = gravitySpeed / 10 -- test

    self.__expectingPortal = false

    local wishdir = self:GetThumbstickVector()
    wishdir.z = 0
    wishdir = wishdir * 400

    if Convars:GetBool("portal_funnelling") and Convars:GetFloat("portal_funnel_amount") > 0 then
        for _, portal in ipairs(PortalManager:GetAllPortals()) do
            if portal:GetConnectedPortal() then
                local outdir = self:FunnelIntoPortal(portal, wishdir)
                if outdir ~= nil then
                    wishdir = outdir
                end
            end
        end
    end

    -- Cap thumbstick movement speed (NOT max velocity)
    if wishdir:Length() > 120 then
        wishdir = wishdir:Normalized() * 120
    end
    self.velocity = self.velocity + wishdir * frameTime

    local gravity = Vector()
    gravity = Vector(0,0,-gravitySpeed * frameTime)

    -- local friction = 6
    -- local decay = math.max(0, 1 - friction * frameTime)
    local decay = 1

    self.velocity = self.velocity * decay + gravity

    -- cap velocity
    local maxSpeed = Convars:GetInt("portal_max_fling_speed")
    if self.velocity:Length() > maxSpeed then
        self.velocity = self.velocity:Normalized() * maxSpeed
    end

	local origin = self:GetAbsOrigin()
	local offset = self.velocity * frameTime
	local newOrigin = origin + offset

    if Player:IsNoclipping() or Convars:GetBool("noclip_vr_enabled") then
        PortalPlayerController:PlayerLandedOnGround()
		self:Remove()
        return nil
    end

	local traceTable = self:TraceSpace(offset)
	if traceTable.hit then -- we hit something or noclip was enabled
		local enthit = traceTable.enthit
		-- if we hit a physics entity, apply a force to it
		if enthit and enthit.ApplyAbsVelocityImpulse and enthit.GetMass then
			local mass = enthit:GetMass()
			if mass ~= 0 then
				enthit:ApplyAbsVelocityImpulse(self.velocity / enthit:GetMass() * PLAYER_MASS)
			end
		end

        -- Check if we are about to hit a portal
        for _, portal in ipairs(PortalManager:GetAllPortals()) do
            if portal:GetConnectedPortal() then
                if self.velocity:Dot(portal:GetForwardVector()) < 0 -- moving towards portal
                and AABBvsOBB(
                    traceTable.endpos + Player:GetBoundingMins(), traceTable.endpos + Player:GetBoundingMaxs(),
                    PORTAL_OBBDATA, portal:GetOrigin(), portal:GetAngles()
                ) then
                    -- print("\nTouch portal on fall doing instant portal!!", portal.colorName,"\n")
                    portal:Teleport(Player)
                    return 0
                end
            end
        end

        -- If there is nothing below the player they probably hit a wall
        if not self:TraceSpace(Vector(0, 0, -10)).hit then
            local impactVolume = Clamp(self.velocity:Length() / maxSpeed, 0, 1)
            Player:EmitSoundParams("JumpLand.HighVelocityImpact", 0, impactVolume, 0)

            -- This is a hack to keep the player away from the wall
            if Convars:GetFloat("portal_playerphys_wallbounce_multiplier") > 0 then
                local reflected = self.velocity - 2 * self.velocity:Dot(traceTable.normal) * traceTable.normal
                PortalPlayerController:CacheBounceVelocity(reflected * Convars:GetFloat("portal_playerphys_wallbounce_multiplier"))
            end
        else
            -- Move player against the collision, hopefully triggering footstep sound
            self:SetOrigin(traceTable.endpos)
        end

        -- print("Phys hit world", traceTable.enthit:GetClassname(), traceTable.enthit:GetName(), traceTable.enthit:GetModelName())
        if traceTable.enthit:GetOwner() then print("Owner:", traceTable.enthit:GetOwner():GetClassname()) end

        DebugIf("portal_debug_flings", function()
            Debug.ShowEntity(traceTable.enthit, 10)
            debugoverlay:Sphere(self:GetOrigin(), 5, 255, 0, 0, 255, false, 10)
            local hull = PortalPlayerController:GetPlayerHull()
            debugoverlay:Box(Player:GetOrigin() + hull.mins, Player:GetOrigin() + hull.maxs, 255, 0, 0, 255, false, 10)
            debugoverlay:Box(traceTable.pos + hull.mins, traceTable.pos + hull.maxs, 255, 0, 0, 255, false, 10)
            debugoverlay:Line(self:GetOrigin(), self:GetOrigin() + self.velocity, 255, 0, 0, 255, false, 10)
        end)
        PortalPlayerController:PlayerLandedOnGround()
		self:Remove()
		return
	end

	self:SetVelocity(self.velocity)
    PortalPlayerController:CacheVelocity(self.velocity)
	if Player.PrimaryHand == nil then
		Player:SetAbsOrigin(newOrigin)
		Player:SetVelocity(self.velocity)
	end

    --- Custom turning

    local turnSign = 0
    if Player:IsDigitalActionOnForHand(0, DIGITAL_INPUT_TURN_LEFT) or Player:IsDigitalActionOnForHand(1, DIGITAL_INPUT_TURN_LEFT) then
        turnSign = 1
    elseif Player:IsDigitalActionOnForHand(0, DIGITAL_INPUT_TURN_RIGHT) or Player:IsDigitalActionOnForHand(1, DIGITAL_INPUT_TURN_RIGHT) then
        turnSign = -1
    else
        quickTurnFlag = false
    end

    if turnSign ~= 0 then
        local angles = self:GetAngles()
        local amount = 0

        if Convars:GetBool("vr_quick_turn_continuous_enable") then
            local speed = Convars:GetFloat("vr_quick_turn_continuous_speed") or 0
            amount = speed * FrameTime() * turnSign
            self:SetAngles(angles.x, angles.y + amount, angles.z)
        elseif Convars:GetBool("vr_teleport_quick_turn_enable") and not quickTurnFlag then
            local speed = Convars:GetFloat("vr_teleport_quick_turn_angle") or 0
            amount = speed * turnSign
            quickTurnFlag = true
            self:SetAngles(angles.x, angles.y + amount, angles.z)
        end

    end

	self.lastTime = time

	return 0
end

---Traces player hull aganist solids from phys object's current location to an offset.
---@param offset Vector Offset from current position to trace towards, defines end position of trace.
---@return TraceTableHull
function base:TraceSpace(offset)
    return PortalPlayerController:TracePlayerSpace(Player:GetAbsOrigin(), Player:GetAbsOrigin() + offset * 1.2)
end

---Snaps this playerphys to the player's current position without moving the anchor.
---
---The playerphys does not get teleported with the player/anchor
---so it needs to be manually updated sometimes.
---
---@param origin? Vector # Optional origin to snap to instead of player position.
function base:SnapToPlayer(origin)
    if Player.HMDAnchor:GetMoveParent() == self then
        Player.HMDAnchor:SetParent(nil, nil)
        self:SetOrigin(origin or Player:GetOrigin())
        Player.HMDAnchor:SetParent(self, nil)
    end
end

---Creates the anti motion sickness screen effect, if it doesn't exist yet.
---Used for players with non-continuous movement types.
function base:CreateVignette()
	if self.__vignettePtfxIndex ~= -1 then return end
	self.__vignettePtfxIndex = ParticleManager:CreateParticle("particles/vrportal/motion_sickness_vignette.vpcf", 0, Player)
end

---Removes the anti motion sickness screen effect if it exist.
---Used for players with non-continuous movement types.
function base:RemoveVignette()
	if self.__vignettePtfxIndex == -1 then return end
	ParticleManager:DestroyParticle(self.__vignettePtfxIndex, false)
	self.__vignettePtfxIndex = -1
end

---Anchors the player to an entity with the given name.
---@param targetname string Name of entity to anchor player to.
function base:SetPlayerAnchorParent(targetname)
	-- DoEntFireByInstanceHandle(Player, "SetAnchorParent", targetname, 0, self, self)
    Player.HMDAnchor:SetParent(self, "")
end
---Clears the player's current anchor.
function base:ClearPlayerAnchorParent()
	-- DoEntFireByInstanceHandle(Player, "ClearAnchorParent", "", 0, self, self)
    Player.HMDAnchor:SetParent(nil, "")
end
---Enables player movement.
function base:EnablePlayerTeleport()
	DoEntFireByInstanceHandle(Player, "EnableTeleport", "1", 0, self, self)
end
---Disables player movement.
function base:DisablePlayerTeleport()
	DoEntFireByInstanceHandle(Player, "EnableTeleport", "0", 0, self, self)
end

function base:Remove()
    self:PauseThink()
    PortalPlayerController:PlayerLandedOnGround()
	self:ClearPlayerAnchorParent()
    if not Convars:GetBool("noclip_vr_enabled") then
    	self:EnablePlayerTeleport()
    end
    PortalPlayerController:UpdateWhooshSound(0)
	self:RemoveVignette()
	-- self:SetEntityName("old_"..ENT_NAME)
    PortalPlayerController.currentPlayerPhys = nil
	DoEntFireByInstanceHandle(self, "Kill", "", 0.1, self, self)
end

---Destroy references on death
---Fallback for if entity is destroyed without calling Remove
function base:UpdateOnRemove()
	self:RemoveVignette()
end

---Draws the expected trajectory path for this phys object based on its current velocity.
---@param color? Vector
---@param scope? string
function base:DrawTrajectory(color, scope)
    if Convars:GetInt("portal_debug_flings") < 1 then return end

    local step = 0.05
    local maxSteps = 100

    scope = scope or "playerphys"
    if scope == "playerphys" then
        debugoverlay:PushAndClearDebugOverlayScope(scope)
    else
        debugoverlay:PushDebugOverlayScope(scope)
    end

    local simPos = Player:GetOrigin()
    local simVel = self.velocity
    local graycol = Vector(255,255,255)

    local gravity = Vector(0,0,-Convars:GetFloat("sv_gravity")) -- default is 386
    local lastPos = simPos
    for i = 1, maxSteps do
        -- Apply gravity
        simVel = simVel + gravity * step

        -- Move forward
        simPos = simPos + simVel * step

        -- Draw line from lastPos → simPos
        DebugDrawLine(lastPos, simPos, graycol.x, graycol.y, graycol.z, true, 60)
        -- make color get darker
        graycol = graycol * 0.9

        -- Check if it hits something
        local trace = PortalPlayerController:TracePlayerSpace(simPos, simPos + (simPos - lastPos) * 1)
        if trace.hit then
            DebugDrawCircle(simPos, color or Vector(0, 255, 0), 255, 4, true, 60)
            break
        end

        lastPos = simPos
    end
end

--Used for classes not attached directly to entities
return base