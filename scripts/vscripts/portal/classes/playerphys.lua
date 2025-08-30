if thisEntity then
    -- Inherit this script if attached to entity
    -- Will also load the script at the same time if needed
    inherit(GetScriptFile())
    return
end

local PLAYER_MASS = 65 -- in kg

local PORTAL_FUNNEL_AMOUNT = 6.0
Convars:RegisterConvar("portal_funnel_amount", tostring(PORTAL_FUNNEL_AMOUNT), "Amount of portals to funnel into", 0)

EasyConvars:RegisterConvar("portal_funnel_sensitivity", "2", "Overall sensitivity of portal funneling", FCVAR_NONE, function (newVal, oldVal)
    if newVal == "0" then
        Convars:SetBool("player_funnel_into_portals", false)
        Convars:SetFloat("portal_funnel_amount", 0.0)
    elseif newVal == "1" then
        Convars:SetBool("player_funnel_into_portals", true)
        Convars:SetFloat("portal_funnel_amount", 3.0)
    elseif newVal == "2" then
        Convars:SetBool("player_funnel_into_portals", true)
        Convars:SetFloat("portal_funnel_amount", 6.0)
    elseif newVal == "3" then
        Convars:SetBool("player_funnel_into_portals", true)
        Convars:SetFloat("portal_funnel_amount", 12.0)
    end
end)
EasyConvars:SetPersistent("portal_funnel_sensitivity", true)

local PORTAL_HALF_WIDTH = 28
local PORTAL_HALF_HEIGHT = 49.5

-- EasyConvars:RegisterConvar("portal_attract_distance", "128", "Distance at which the player is attracted to a portal when falling")
Convars:RegisterConvar("player_funnel_into_portals", "1", "Player will move towards portals they are falling into", 0)

EasyConvars:RegisterConvar("portal_max_fling_speed", "1200", "Maximum speed at which the player can move while flinging")
EasyConvars:SetPersistent("portal_max_fling_speed", true)

local DEBUG = true

---@class PortalPlayerPhys : EntityClass
local base, _, super = entity("PortalPlayerPhys")
_G.PortalPlayerPhys = base

base.__expectingPortal = false

---Called automatically on spawn
---@param spawnkeys CScriptKeyValues
function base:OnSpawn(spawnkeys)
	local xVelocity = tonumber(spawnkeys:GetValue("velocity_x"))
	local yVelocity = tonumber(spawnkeys:GetValue("velocity_y"))
	local zVelocity = tonumber(spawnkeys:GetValue("velocity_z"))

	self.velocity = Vector(xVelocity, yVelocity, zVelocity)
    print("VELOCITY NUMS", xVelocity, yVelocity, zVelocity)
    -- -- if xVelocity == 0 and zVelocity == 0 then
    -- -- print("VECLOTIY", self.velocity)
    -- debugoverlay:Line(self:GetOrigin(), self:GetOrigin() + self.velocity*10, 255, 0, 255, 255, true, 100)
    -- debugoverlay:Sphere(self:GetOrigin(), 8, 255, 0, 255, 255, true, 100)
    -- -- end


    self:DrawTrajectory()

    -- self:RemoveOthers()
    -- self:SetEntityName(ENT_NAME)
	self:SetPlayerAnchorParent(self:GetName())
	self:DisablePlayerTeleport()

	-- super.OnSpawn(self)
end

function base:Precache(context)
    PrecacheModel("models/props/choreo/ghost_speaker.vmdl", context)
end

function base:OnReady()
    self:ResumeThink()
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
        -- This is handled by the portal
        -- -- We're too close the the portal to continue correcting, but zero the velocity so our fling velocity is nice
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

        -- local funnelStrength = 1--PORTAL_FUNNEL_AMOUNT * FrameTime()
        -- self.velocity.x = self.velocity.x + fFunnelX*funnelStrength
        -- self.velocity.y = self.velocity.y + fFunnelY*funnelStrength
        -- self.velocity.x = Lerp(0.9, self.velocity.x, self.velocity.x + fFunnelX*funnelStrength)
        -- self.velocity.y = Lerp(0.9, self.velocity.y, self.velocity.y + fFunnelY*funnelStrength)

        -- local lerpFactor = 0.25 * FrameTime()
        -- -- print(lerpFactor, 0.025, FrameTime())

        -- local desiredVX = self.velocity.x + vPlayerToPortal.x * PORTAL_FUNNEL_AMOUNT
        -- local desiredVY = self.velocity.y + vPlayerToPortal.y * PORTAL_FUNNEL_AMOUNT

        -- self.velocity.x = Lerp(lerpFactor, self.velocity.x, desiredVX)
        -- self.velocity.y = Lerp(lerpFactor, self.velocity.y, desiredVY)



        --- THIS IS WORKING BUT TOO STRONG
        -- local newHorizontalVel = CalculatePortalVelocity(self:GetAbsOrigin(), portal:GetAbsOrigin(), self.velocity, Convars:GetFloat("sv_gravity"))
        -- self.velocity = LerpVectors(self.velocity, newHorizontalVel, 0.025)



        -- -- Funnel toward the portal in portal-local space
        -- local toPortal = portal:GetAbsOrigin() - self:GetAbsOrigin()

        -- -- Position offsets in portal space
        -- local localX = toPortal:Dot(vPortalRight)
        -- local localY = toPortal:Dot(vPortalUp)

        -- -- Velocity components in portal space
        -- local velX = self.velocity:Dot(vPortalRight)
        -- local velY = self.velocity:Dot(vPortalUp)

        -- -- Calculate corrections
        -- local fFunnelX = localX * PORTAL_FUNNEL_AMOUNT - velX
        -- local fFunnelY = localY * PORTAL_FUNNEL_AMOUNT - velY

        -- local funnelStrength = PORTAL_FUNNEL_AMOUNT * FrameTime()
        -- self.velocity = self.velocity
        --     + vPortalRight * (fFunnelX * funnelStrength)
        --     + vPortalUp * (fFunnelY * funnelStrength)
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
	--local deltaTime = time - lastTime
	local frameTime = FrameTime()

    local gravitySpeed = Convars:GetFloat("sv_gravity") -- default is 386
    -- gravitySpeed = gravitySpeed / 10 -- test

    self.__expectingPortal = false

    local wishdir = self:GetThumbstickVector()
    wishdir.z = 0
    wishdir = wishdir * 400

    -- local portalDownTrace = self:TraceSpace(Vector(0, 0, -2048))
    -- if portalDownTrace.hit then

    --     local attractDist = Convars:GetFloat("portal_attract_distance")
    --     -- local portal = PortalManager:GetNearestPortal(portalDownTrace.pos, 128)
    --     local portal = PortalManager:GetNearestPortalInBounds(portalDownTrace.pos,
    --         Vector(-attractDist, -attractDist, -16),
    --         Vector(attractDist, attractDist, 16),
    --     attractDist)
    --     debugoverlay:Box(
    --         portalDownTrace.pos + Vector(-attractDist, -attractDist, -16),
    --         portalDownTrace.pos + Vector(attractDist, attractDist, 16), 0, 255, 0, 255, false, 0)

    --     if portal then
    --         ---@TODO Move player towards all portals in their direction, not just upwards portals
    --         if portal:GetForwardVector().z > 0.5 -- portal must be facing up
    --         and self.velocity:Normalized():Dot(portal:GetForwardVector()) < -0.8 -- player must be moving towards portal
    --         and portal:GetConnectedPortal() then
    --             self.__expectingPortal = true
    --             -- local tFall = estimateFallTime(self:GetAbsOrigin().z, self.velocity.z, portal:GetAbsOrigin().z, gravitySpeed)
    --             -- if tFall then
    --             --     print("Attracting to portal")
    --                 debugoverlay:Sphere(self:GetAbsOrigin(), 2, 255, 0, 0, 255, false, 0)
    --                 -- local targetVal = computeTargetHorizontalVelocity(self:GetAbsOrigin(), portal:GetAbsOrigin(), tFall)
    --                 -- local currentHorizontalVel = Vector(self.velocity.x, self.velocity.y, 0)
    --                 -- local lerpFactor = 0.5
    --                 -- local newHorizontalVel = LerpVectors(currentHorizontalVel, targetVal, lerpFactor)
    --                 local newHorizontalVel = CalculatePortalVelocity(self:GetAbsOrigin(), portal:GetAbsOrigin(), self.velocity, gravitySpeed)
    --                 -- self.velocity = Vector(newHorizontalVel.x, newHorizontalVel.y, self.velocity.z)
    --                 -- self.velocity = newHorizontalVel
    --                 self.velocity = LerpVectors(self.velocity, newHorizontalVel, 0.025)
    --             -- end
    --         end
    --     end
    -- end

    for _, portal in ipairs(PortalManager:GetAllPortals()) do
        if portal:GetConnectedPortal() then
            local outdir = self:FunnelIntoPortal(portal, wishdir)
            if outdir ~= nil then
                wishdir = outdir
            end
            -- portal:FunnelIntoPortal(self, self.velocity)
        end
    end

    -- Cap thumbstick movement speed (NOT max velocity)
    if wishdir:Length() > 120 then
        wishdir = wishdir:Normalized() * 120
    end
    self.velocity = self.velocity + wishdir * frameTime

    -- -- testing accel
    -- local wishspeed = wishdir:Length()
    -- if wishspeed ~= 0 and (wishspeed > 100) then
    --     wishspeed = 100
    -- end
    -- local wishspd = wishspeed
    -- if wishspd > 60 then wishspd = 60 end
    -- local currentspeed = self.velocity:Dot(wishdir)
    -- local addspeed = wishspd - currentspeed
    -- -- if addspeed > 0 then
    --     local accelspeed = 15 * wishspeed * frameTime * 0.25
    --     if accelspeed > addspeed then
    --         accelspeed = addspeed
    --     end
    --     -- print(Debug.SimpleVector(wishdir), accelspeed)
    --     self.velocity = self.velocity + accelspeed * wishdir
    -- -- end

    local gravity = Vector()
    -- if not self:TraceSpace(Vector(0, 0, -5)).hit then
	    gravity = Vector(0,0,-gravitySpeed * frameTime)
    -- end

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
    -- print(origin.z, offset.z, self.velocity.z*frameTime, newOrigin.z, frameTime)

    -- if self.velocity:Length() < 0.1 then
    --     PortalPlayerController:PlayerLandedOnGround()
	-- 	self:Remove()
    --     return
    -- end

    if Player:IsNoclipping() or Convars:GetBool("noclip_vr_enabled") then
        PortalPlayerController:PlayerLandedOnGround()
		self:Remove()
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

        -- local dot = self.velocity:Dot(traceTable.normal)
        -- print("cancel out")
        -- print(Debug.SimpleVector(self.velocity))
        -- print(Debug.SimpleVector(traceTable.normal))
        -- if dot < 0 then
        --     print("Canceling out")
        --     self.velocity = self.velocity - traceTable.normal * dot
        -- end
        -- debugoverlay:Line(self:GetAbsOrigin(), self:GetAbsOrigin()+self.velocity*50, 255, 0, 128, 255, false, 10)

        -- if not self:TraceSpace(self.velocity * frameTime).hit then
        --     self:SetVelocity(self.velocity)
        --     PortalPlayerController:CacheVelocity(self.velocity)
        --     return 0
        -- end

        for _, portal in ipairs(PortalManager:GetAllPortals()) do
            if portal:GetConnectedPortal() then
                if portal:WillEntityTouchPortal(Player, traceTable.endpos) then
                    print("\nTouch portal on fall doing instance portal!!\n")
                    -- debugoverlay:Sphere(traceTable.endpos, 8, 0, 0, 255, 255, true, 10)
                    -- debugoverlay:Sphere(traceTable.endpos, 6, 0, 255, 0, 255, true, 10)
                    -- debugoverlay:Sphere(traceTable.endpos, 7, 255, 0, 0, 255, true, 10)
                    portal:Teleport(Player)
                    return 0
                end
            end
        end

        -- If there is nothing below the player they probably hit a wall
        if not self:TraceSpace(Vector(0, 0, -10)).hit then
            local impactVolume = Clamp(self.velocity:Length() / maxSpeed, 0, 1)
            Player:EmitSoundParams("JumpLand.HighVelocityImpact", 0, impactVolume, 0)
        end

        -- -- Move player against the collision to allow entering portals
        -- -- high speeds would cause the player to stop before hitting the portal
        -- self:SetOrigin(traceTable.endpos)

        -- This is a hack to keep the player away from the wall
        local reflected = self.velocity - 2 * self.velocity:Dot(traceTable.normal) * traceTable.normal
        PortalPlayerController:CacheBounceVelocity(reflected * 0.05)

        print("Phys hit world", traceTable.enthit:GetClassname(), traceTable.enthit:GetName(), traceTable.enthit:GetModelName())
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
	--thisEntity:SetAbsOrigin(newOrigin)
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
        local angles = Player.HMDAnchor:GetAngles()
        local amount = 0

        if Convars:GetBool("vr_quick_turn_continuous_enable") then
            local speed = Convars:GetFloat("vr_quick_turn_continuous_speed") or 0
            amount = speed * FrameTime() * turnSign
        elseif Convars:GetBool("vr_teleport_quick_turn_enable") and not quickTurnFlag then
            local speed = Convars:GetFloat("vr_teleport_quick_turn_angle") or 0
            amount = speed * turnSign
            quickTurnFlag = true
        end

        Player.HMDAnchor:SetAngles(angles.x, angles.y + amount, angles.z)
    end

	self.lastTime = time

	-- if DEBUG then
	-- 	debugoverlay:Sphere(newOrigin, 8, 255, 0, 0, 255, true, 0)
	-- end
	--print("deltaTime: "..tostring(deltaTime))
	--print("frameTime: "..tostring(frameTime))
	return 0
end

---Traces player hull aganist solids from phys object's current location to an offset.
---@param offset Vector Offset from current position to trace towards, defines end position of trace.
---@return TraceTableHull
function base:TraceSpace(offset)
	-- --local origin = Player:GetAbsOrigin()
	-- local origin = self:GetAbsOrigin()

	-- local startpos = origin
	-- local endpos = origin + offset * 1.2

	-- -- local justLaunched = false--Time() - self.launchTime < PLAYER_LAUNCH_BBOX_OFFSET_DURATION
	-- -- local minZ = justLaunched and PLAYER_LAUNCH_BBOX_HEIGHT_OFFSET or 0
    -- local minZ = 0

	-- local min = Vector(-PLAYER_GIRTH, -PLAYER_GIRTH, minZ)
	-- local max = Vector(PLAYER_GIRTH, PLAYER_GIRTH, PLAYER_HEIGHT)

	-- local traceTable =
	-- {
	-- 	startpos = startpos;
	-- 	endpos = endpos;
	-- 	ignore = Player;
	-- 	mask =  33636363; -- TRACE_MASK_PLAYER_SOLID from L4D2 script API, may not be correct for Source 2.
	-- 	min = min;
	-- 	max = max
	-- }
	-- TraceHull(traceTable)
	-- if DEBUG then
	-- 	local color = traceTable.hit and Vector(255, 0, 0) or Vector(0, 255, 0)
	-- 	debugoverlay:Box(startpos + traceTable.min, startpos + traceTable.max, color.x, color.y, color.z, 170, false, 0)
	-- 	debugoverlay:Box(endpos + traceTable.min, endpos + traceTable.max, color.x, color.y, color.z, 170, false, 0)
	-- 	--debugoverlay:SweptBox(startpos, endpos, min, max, {x = 0; y = 0; z = 0; w = 1;}, 0, 255, 0, 255, 10)
	-- end

	-- return traceTable
    return PortalPlayerController:TracePlayerSpace(self:GetAbsOrigin(), self:GetAbsOrigin() + offset * 1.2)
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
    -- yellow sphere at death point
    debugoverlay:Sphere(self:GetAbsOrigin(), 8, 255, 255, 0, 255, true, 8)
	self:ClearPlayerAnchorParent()
    if not Convars:GetBool("noclip_vr_enabled") then
    	self:EnablePlayerTeleport()
    end
    PortalPlayerController:UpdateWhooshSound(0)
	-- self:RemoveVignette()
	-- self:SetEntityName("old_"..ENT_NAME)
    PortalPlayerController.currentPlayerPhys = nil
    print('killing')
	DoEntFireByInstanceHandle(self, "Kill", "", 0.1, self, self)
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

    local simPos = self:GetOrigin()
    local simVel = self.velocity
    local graycol = Vector(255,255,255)

    local gravity = Vector(0,0,-Convars:GetFloat("sv_gravity"))
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