if thisEntity then
    -- Inherit this script if attached to entity
    -- Will also load the script at the same time if needed
    inherit(GetScriptFile())
    return
end

local PLAYER_MASS = 65 -- in kg

EasyConvars:RegisterConvar("portal_attract_distance", "128", "Distance at which the player is attracted to a portal when falling")


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
    if xVelocity == 0 and zVelocity == 0 then
    print("VECLOTIY", self.velocity)
    debugoverlay:Line(self:GetOrigin(), self:GetOrigin() + self.velocity*100, 255, 0, 255, 255, true, 100)
    debugoverlay:Sphere(self:GetOrigin(), 8, 255, 0, 255, 255, true, 100)
    end

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

local function estimateFallTime(playerZ, velocityZ, groundZ, gravity)
    local distance = playerZ - groundZ
    local discriminant = velocityZ * velocityZ + 2 * gravity * distance
    if discriminant < 0 then
        return nil
    end
    -- return (math.sqrt(discriminant) - velocityZ) / gravity
    return (-velocityZ + math.sqrt(discriminant)) / gravity
end

local function computeTargetHorizontalVelocity(playerPos, portalPos, t)
    if t <= 0 then return Vector(0, 0, 0) end
    local dx = portalPos.x - playerPos.x
    local dy = portalPos.y - playerPos.y
    return Vector(dx/t, dy/t, 0)
end

function CalculatePortalVelocity(playerPos, portalPos, currentVel, gravity)
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

---Main entity think function. Think state is saved between loads
function base:Think()
	local time = Time()
	--local deltaTime = time - lastTime
	local frameTime = FrameTime()

    local gravitySpeed = Convars:GetFloat("sv_gravity") -- default is 386
    -- gravitySpeed = gravitySpeed / 10 -- test

    self.__expectingPortal = false

    local portalDownTrace = self:TraceSpace(Vector(0, 0, -2048))
    if portalDownTrace.hit then

        local attractDist = Convars:GetFloat("portal_attract_distance")
        -- local portal = PortalManager:GetNearestPortal(portalDownTrace.pos, 128)
        local portal = PortalManager:GetNearestPortalInBounds(portalDownTrace.pos,
            Vector(-attractDist, -attractDist, -16),
            Vector(attractDist, attractDist, 16),
        attractDist)
        debugoverlay:Box(
            portalDownTrace.pos + Vector(-attractDist, -attractDist, -16),
            portalDownTrace.pos + Vector(attractDist, attractDist, 16), 0, 255, 0, 255, false, 0)

        if portal then
            ---@TODO Move player towards all portals in their direction, not just upwards portals
            if portal:GetForwardVector().z > 0.5 -- portal must be facing up
            and self.velocity:Normalized():Dot(portal:GetForwardVector()) < -0.8 -- player must be moving towards portal
            and portal:GetConnectedPortal() then
                self.__expectingPortal = true
                -- local tFall = estimateFallTime(self:GetAbsOrigin().z, self.velocity.z, portal:GetAbsOrigin().z, gravitySpeed)
                -- if tFall then
                --     print("Attracting to portal")
                    debugoverlay:Sphere(self:GetAbsOrigin(), 2, 255, 0, 0, 255, false, 0)
                    -- local targetVal = computeTargetHorizontalVelocity(self:GetAbsOrigin(), portal:GetAbsOrigin(), tFall)
                    -- local currentHorizontalVel = Vector(self.velocity.x, self.velocity.y, 0)
                    -- local lerpFactor = 0.5
                    -- local newHorizontalVel = LerpVectors(currentHorizontalVel, targetVal, lerpFactor)
                    local newHorizontalVel = CalculatePortalVelocity(self:GetAbsOrigin(), portal:GetAbsOrigin(), self.velocity, gravitySpeed)
                    -- self.velocity = Vector(newHorizontalVel.x, newHorizontalVel.y, self.velocity.z)
                    -- self.velocity = newHorizontalVel
                    self.velocity = LerpVectors(self.velocity, newHorizontalVel, 0.025)
                -- end
            end
        end
    end

	local gravity = Vector(0,0,-gravitySpeed * frameTime)
	self.velocity = self.velocity + gravity

	local origin = self:GetAbsOrigin()
	local offset = self.velocity * frameTime
	local newOrigin = origin + offset
    -- print(origin.z, offset.z, self.velocity.z*frameTime, newOrigin.z, frameTime)

	local traceTable = self:TraceSpace(offset)
	if traceTable.hit or Player:IsNoclipping() or Convars:GetBool("noclip_vr_enabled") then -- we hit something or noclip was enabled
		local enthit = traceTable.enthit
		-- if we hit a physics entity, apply a force to it
		if enthit and enthit.ApplyAbsVelocityImpulse and enthit.GetMass then
			local mass = enthit:GetMass()
			if mass ~= 0 then
				enthit:ApplyAbsVelocityImpulse(self.velocity / enthit:GetMass() * PLAYER_MASS)
			end
		end
        -- self:SetAbsOrigin(traceTable.pos)
        print("Phys hit ground", traceTable.enthit:GetClassname())
        Debug.ShowEntity(traceTable.enthit, 10)
        debugoverlay:Sphere(self:GetOrigin(), 5, 255, 0, 0, 255, false, 10)
        local hull = PortalPlayerController:GetPlayerHull()
        debugoverlay:Box(Player:GetOrigin() + hull.mins, Player:GetOrigin() + hull.maxs, 255, 0, 0, 255, false, 10)
        debugoverlay:Box(traceTable.pos + hull.mins, traceTable.pos + hull.maxs, 255, 0, 0, 255, false, 10)
        debugoverlay:Line(self:GetOrigin(), self:GetOrigin() + self.velocity, 255, 0, 0, 255, false, 10)
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

	self.lastTime = time

	if DEBUG then
		debugoverlay:Sphere(newOrigin, 8, 255, 0, 0, 255, true, 0)
	end
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
	self:EnablePlayerTeleport()
	-- self:RemoveVignette()
	-- self:SetEntityName("old_"..ENT_NAME)
    PortalPlayerController.currentPlayerPhys = nil
    print('killing')
	DoEntFireByInstanceHandle(self, "Kill", "", 0.1, self, self)
end

--Used for classes not attached directly to entities
return base