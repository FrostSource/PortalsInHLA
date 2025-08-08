if thisEntity then
    inherit(GetScriptFile())
end

---Max field of view in degrees when updating catapult's target with direction check.
local SET_TARGET_BY_DIRECTION_FOV = 50
local SET_TARGET_BY_DIRECTION_MIN_DOT = math.cos(SET_TARGET_BY_DIRECTION_FOV / 180 * math.pi)
local DEBUG = false

---@class TriggerCatapult : EntityClass
local base = entity("TriggerCatapult")
_G.TriggerCatapult = base

base.m_flPlayerVelocity = 900 --Player Speed
base.m_flPhysicsVelocity = 900 --Physics Object Speed
base.m_bApplyAngularImpulse = true --Apply angular impulse
base.m_ExactVelocityChoice = 0 --Exact Solution Method
base.m_bUseExactVelocity = true --Use Exact Velocity
base.m_strLaunchTarget = nil
base.m_vecLaunchAngles = QAngle(0,0,0)
base.m_bLaunchAnglesIsLocal = true

---@type EntityHandle
base.targetHandle = nil

base.resetTargetOnCapture = false

-- ---Creates a physics entity for the player, and launches it with the specified velocity.
-- ---@param origin Vector Spawn origin for the phys entity. You'd probably want this to be the player's current origin.
-- ---@param velocity Vector Launch velocity.
-- local function CreatePlayerPhysEntity(origin, velocity)
-- 	local physEnt = SpawnEntityFromTableSynchronous("prop_dynamic_override", {
-- 		origin = origin + Vector(0,0,4),
-- 		targetname = "catapult_player_physics",
-- 		vscripts = "fstop/entity/trigger_catapult_playerphys",
-- 		velocity_x = tostring(velocity.x),
-- 		velocity_y = tostring(velocity.y),
-- 		velocity_z = tostring(velocity.z),
-- 		model = "models/props/choreo/ghost_speaker.vmdl",
-- 		solid = "0",
-- 		ScriptedMovement = "1",
-- 	})
-- end

---Called automatically on spawn
---@param spawnkeys CScriptKeyValues
function base:OnSpawn(spawnkeys)
	self.m_flPlayerVelocity = tonumber(spawnkeys:GetValue("playerSpeed")) --Player Speed
	self.m_flPhysicsVelocity = tonumber(spawnkeys:GetValue("physicsSpeed")) --Physics Object Speed
	self.m_bApplyAngularImpulse = truthy(spawnkeys:GetValue("applyAngularImpulse")) --Apply angular impulse
	self.m_ExactVelocityChoice = tonumber(spawnkeys:GetValue("exactVelocityChoiceType")) --Exact Solution Method
	self.m_bUseExactVelocity = truthy(spawnkeys:GetValue("useExactVelocity")) --Use Exact Velocity
	self.m_strLaunchTarget = spawnkeys:GetValue("launchTarget") or ""
	self.m_vecLaunchAngles = VectorToAngles(Util.VectorFromString(spawnkeys:GetValue("launchDirection"))) -- [0 0 0] gets converted to [90 0 0]
	self.m_bLaunchAnglesIsLocal = truthy(spawnkeys:GetValue("launchDirection_isLocal"))

    self.m_bUseThresholdCheck = truthy(spawnkeys:GetValue("useThresholdCheck"))
    self.m_flLowerThreshold = tonumber(spawnkeys:GetValue("lowerThreshold"))
    self.m_flUpperThreshold = tonumber(spawnkeys:GetValue("upperThreshold"))
    self.m_flEntryAngleTolerance = tonumber(spawnkeys:GetValue("entryAngleTolerance"))
    self.m_bOnlyVelocityCheck = truthy(spawnkeys:GetValue("onlyVelocityCheck"))

    -- print all the values with their display name
    print("Printing spawn values for trigger_catapult", self:GetName())
    print("playerSpeed", self.m_flPlayerVelocity)
    print("physicsSpeed", self.m_flPhysicsVelocity)
    print("applyAngularImpulse", self.m_bApplyAngularImpulse)
    print("exactVelocityChoiceType", self.m_ExactVelocityChoice)
    print("useExactVelocity", self.m_bUseExactVelocity)
    print("launchTarget", self.m_strLaunchTarget)
    print("launchDirection", self.m_vecLaunchAngles)
    print("launchDirection_isLocal", self.m_bLaunchAnglesIsLocal)
    print("useThresholdCheck", self.m_bUseThresholdCheck)
    print("lowerThreshold", self.m_flLowerThreshold)
    print("upperThreshold", self.m_flUpperThreshold)
    print("entryAngleTolerance", self.m_flEntryAngleTolerance)
    print("onlyVelocityCheck", self.m_bOnlyVelocityCheck)
    print()

	if self.m_strLaunchTarget ~= "" and self.m_strLaunchTarget ~= nil then
		self:SetLaunchTargetByHandle(Entities:FindByName(nil, self.m_strLaunchTarget))
	end
	---@TODO: Make sure this doesn't stack on game loads
	self:RedirectOutput("OnStartTouch", "StartTouch", self)
end

---Called automatically on activate.
---Any self values set here are automatically saved
---@param loaded boolean
function base:OnReady(loaded)
end

---Main entity think function. Think state is saved between loads
function base:Think()
	return 0
end

---Calculates a launch velocity vector for an entity towards a target entity. Applies additional vertical velocity to compensate for gravity.
---@param pVictim EntityHandle Entity to calculate launch vector for.
---@param pTarget EntityHandle Entity to launch towards.
---@return Vector velocity Launch velocity vector
function base:CalculateLaunchVector(pVictim, pTarget)
	-- Find where we're going
	local vecSourcePos = pVictim:GetAbsOrigin()
	local vecTargetPos = pTarget:GetAbsOrigin()

	--debugoverlay:Sphere(vecSourcePos, 32, 255, 0, 0, 255, false, 10)
	--debugoverlay:Sphere(vecTargetPos, 32, 0, 255, 0, 255, false, 10)

	-- If victim is player, adjust target position so player's center will hit the target
	if pVictim:IsPlayer() then
		vecTargetPos = Vector(vecTargetPos.x, vecTargetPos.y, vecTargetPos.z - 32)
	end

	local flSpeed = (pVictim:IsPlayer()) and self.m_flPlayerVelocity or self.m_flPhysicsVelocity	-- u/sec
	local flGravity = -Convars:GetFloat("sv_gravity")

	local vecVelocity = (vecTargetPos - vecSourcePos)

	-- throw at a constant time
	local time = vecVelocity:Length( ) / flSpeed
	vecVelocity = vecVelocity * (1.0 / time) -- CatapultLaunchVelocityMultiplier

	-- adjust upward toss to compensate for gravity loss
	vecVelocity = Vector(vecVelocity.x, vecVelocity.y, vecVelocity.z - flGravity * time * 0.5)

	--debugoverlay:HorzArrow(vecSourcePos, vecSourcePos + vecVelocity * 1, 4, 255, 0, 0, 255, false, 10)
	--debugoverlay:HorzArrow(vecSourcePos, vecSourcePos + (vecTargetPos - vecSourcePos) * 128, 4, 255, 0, 0, 255, false, 10)
	return vecVelocity
end

---Calculates a launch velocity vector for an entity towards a target entity, in a way that the entity's speed after launch will be the same as the one specified by the level designer (no additional vertical velocity is applied).
---Used for the 'Use Exact Velocity' launch mode.
---@param vecInitialVelocity Vector Initial velocity of the launched entity.
---@param pVictim EntityHandle Entity to calculate launch vector for.
---@param pTarget EntityHandle Entity to launch towards.
---@param bForcePlayer? boolean If true, player launch speed (set by level designer) will be applied on the entity no matter what.
---@return Vector velocity Launch velocity vector
function base:CalculateLaunchVectorPreserve(vecInitialVelocity, pVictim, pTarget, bForcePlayer)
	-- Find where we're going
	local vecSourcePos = pVictim:GetAbsOrigin()
	local vecTargetPos = pTarget:GetAbsOrigin()

	--debugoverlay:Sphere(vecSourcePos, 32, 255, 0, 0, 255, false, 10)
	--debugoverlay:Sphere(vecTargetPos, 32, 0, 255, 0, 255, false, 10)

	-- If victim is player, adjust target position so player's center will hit the target
	if pVictim:IsPlayer() then
		vecTargetPos = Vector(vecTargetPos.x, vecTargetPos.y, vecTargetPos.z - 32)
	end

	local vecDiff = (vecTargetPos - vecSourcePos)

	local flHeight = vecDiff.z
	local flDist = vecDiff:Length2D()
	local flVelocity = (pVictim:IsPlayer() or bForcePlayer ) and self.m_flPlayerVelocity or self.m_flPhysicsVelocity
	local flGravity = Convars:GetFloat("sv_gravity")


	if flDist == 0 then
		warn( "Bad location input for catapult!" )
		return self:CalculateLaunchVector(pVictim, pTarget)
	end

	local flRadical = flVelocity*flVelocity*flVelocity*flVelocity - flGravity*(flGravity*flDist*flDist - 2*flHeight*flVelocity*flVelocity)

	if flRadical <= 0 then
		warn( "Catapult can't hit target! Add more speed!" )
		return self:CalculateLaunchVector(pVictim, pTarget)
	end

	flRadical = math.sqrt( flRadical )

	local flTestAngle1 = flVelocity*flVelocity
	local flTestAngle2 = flTestAngle1

	flTestAngle1 = -math.atan( (flTestAngle1 + flRadical) / (flGravity*flDist) )
	flTestAngle2 = -math.atan( (flTestAngle2 - flRadical) / (flGravity*flDist) )

	local vecTestVelocity1 = Vector(vecDiff.x, vecDiff.y, 0):Normalized()

	local vecTestVelocity2 = vecTestVelocity1

	vecTestVelocity1 = vecTestVelocity1 * flVelocity*math.cos(flTestAngle1)
	vecTestVelocity1 = Vector(vecTestVelocity1.x, vecTestVelocity1.y, flVelocity*math.sin(flTestAngle1))

	vecTestVelocity2 = vecTestVelocity2 * flVelocity*math.cos(flTestAngle2)
	vecTestVelocity2 = Vector(vecTestVelocity2.x, vecTestVelocity2.y, flVelocity*math.sin(flTestAngle2))

	vecInitialVelocity = vecInitialVelocity:Normalized()

	--debugoverlay:HorzArrow(vecSourcePos, vecSourcePos + vecTestVelocity1 * 128, 4, 255, 0, 0, 255, false, 10)
	--debugoverlay:HorzArrow(vecSourcePos, vecSourcePos + vecTestVelocity2 * 128, 4, 0, 255, 0, 255, false, 10)

	if self.m_ExactVelocityChoice == 1 then
		return vecTestVelocity1
	elseif self.m_ExactVelocityChoice == 2 then
		return vecTestVelocity2
	end

	if vecInitialVelocity:Dot( vecTestVelocity1 ) > vecInitialVelocity:Dot( vecTestVelocity2 ) then
		return vecTestVelocity1
	end
	return vecTestVelocity2
end

---Launches an entity towards a target entity.
---@param pVictim EntityHandle Entity to launch
---@param pTarget EntityHandle Target entity to launch victim towards
function base:LaunchByTarget(pVictim, pTarget)
	local vecVictim = GetPhysVelocity(pVictim)
	-- get the launch vector
	local vecVelocity = self.m_bUseExactVelocity and
		self:CalculateLaunchVectorPreserve( vecVictim, pVictim, pTarget ) or
		self:CalculateLaunchVector( pVictim, pTarget )

	self:Launch(pVictim, vecVelocity)
end

---Launches an entity by the catapult's launch angles.
---@param pVictim EntityHandle Entity to launch.
function base:LaunchByDirection(pVictim)
	local vecForward = self:GetDirectionVector()

	local flVelocity = pVictim:IsPlayer() and self.m_flPlayerVelocity or self.m_flPhysicsVelocity
	local vecVelocity = vecForward * flVelocity

	if DEBUG then
		local origin = self:GetAbsOrigin()
		debugoverlay:HorzArrow(origin, origin + vecForward * 128, 24, 0, 255, 0, 255, false, 10)
	end

	self:Launch(pVictim, vecVelocity)
end

---Returns the absolute direction vector of the catapult (by rotating launch angles, which is local).
---Used when catapult launches by direction and not towards a target entity.
---@return Vector dir Direction vector of the catapult.
function base:GetDirectionVector()
	local angles = self.m_vecLaunchAngles

	if self.m_bLaunchAnglesIsLocal then
		angles = RotateOrientation(self:GetAngles(), angles)
	end

	return AnglesToVector(angles)
end

---Returns a vector with each component being a random value between specified min and max.
---@param min number Component min value.
---@param max number Component max value.
---@return Vector # 
local function RandomAngularImpulse(min, max)
	local delta = max - min
	return Vector(RandomFloat(min, max), RandomFloat(min, max), RandomFloat(min, max))
end

---Launches an entity with a given velocity vector.
---@param pVictim EntityHandle Entity to launch.
---@param vecVelocity Vector Velocity vector to apply on entity.
function base:Launch(pVictim, vecVelocity)
	local vecVictim = GetPhysVelocity(pVictim)
    print("Launchgin!")
	-- Handle a player
	if pVictim:IsPlayer() then
		-- Send us flying
		-- we're launching the player with the phys entity in both vr and novr, so that the player has no air control
		PortalPlayerController:SetPlayerVelocity(vecVelocity)
	else
		self:Drop(pVictim)

		local angImpulse = self.m_bApplyAngularImpulse and RandomAngularImpulse( -150.0, 150.0 ) or Vector(0,0,0)
		pVictim:ApplyAbsVelocityImpulse(vecVelocity - vecVictim)
		pVictim:ApplyLocalAngularVelocityImpulse(angImpulse)
	end
	--OnLaunchedVictim( pVictim )
    self:FireOutput("OnUser1", pVictim, self, nil, 0)
end

---Desc here
---@param target EntityHandle # 
function base:Drop(target)
	Player:DropByHandle(target)
	if not Player.HMDAvatar then
		-- drop anything that's being carried in novr mode - we're probably carrying the launched prop
		-- novr is for just testing anyways
		DoEntFireByInstanceHandle(Player, "ForceDropPhysObjects", "", 0, self, self)
	end
end

---Desc here
---@param params IOParams
function base:StartTouch(params)
    print("Player hit catapult", self:GetName(), Debug.EntStr(params.activator))
    local victim = params.activator

    if IsValidEntity(victim) and victim:GetOwner() == Player and not victim:IsPlayer() then
        print("Ignoring player's own entity")
        return
    end

	if self.targetHandle then

        if not IsValidEntity(self.targetHandle) then
            print("Catapult has invalid target, clearing target")
			self.targetHandle = nil
			self:StartTouch(params)
			return
		end

        print("Catapult has target", self.targetHandle:GetName())

        if self.m_bUseThresholdCheck then
            print("Using threshold check")
            local vecVictim
            if victim:IsPlayer() then
                vecVictim = PortalPlayerController:GetPlayerVelocity()
            else
                vecVictim = GetPhysVelocity(victim)
            end

            local flVictimSpeed = vecVictim:Length()
            print("Victim speed", flVictimSpeed)

            -- get the speed needed to hit the target
            local vecVelocity
            if self.m_bUseExactVelocity then
                print("Using exact velocity")
                vecVelocity = self:CalculateLaunchVectorPreserve(vecVictim, victim, self.targetHandle)
            else
                print("Using normal velocity")
                vecVelocity = self:CalculateLaunchVector(victim, self.targetHandle)
            end
            local flLaunchSpeed = vecVelocity:Length()

            -- is the victim facing the target?
            local vecDirection = self.targetHandle:GetAbsOrigin() - victim:GetAbsOrigin()
            local necNormalizedVictim = vecVictim:Normalized()
            local vecNormalizedDirection = vecDirection:Normalized()

            local flDot = necNormalizedVictim:Dot(vecNormalizedDirection)
            print("Is the victim facing the target?", flDot >= self.m_flEntryAngleTolerance, flDot, self.m_flEntryAngleTolerance)
            if flDot >= self.m_flEntryAngleTolerance then
                -- Is the victim speed within the tolerance to launch them?
                if ( ( flLaunchSpeed - (flLaunchSpeed * self.m_flLowerThreshold ) ) < flVictimSpeed ) and ( ( flLaunchSpeed + (flLaunchSpeed * self.m_flUpperThreshold ) ) > flVictimSpeed ) then
                    if self.m_bOnlyVelocityCheck then
                        print("Only velocity check is enabled, sending output")
                        self:FireOutput("OnUser1", params.activator, self, nil, 0)
                    else
                        print("Launching by target")
                        self:LaunchByTarget(victim, self.targetHandle)
                    end
                end
            end
        else
            print("No threshold check, launching by target")
		    self:LaunchByTarget(params.activator, self.targetHandle)
        end
	else
        print("No target, launching by direction")
        local bShouldLaunch = true

        if self.m_bUseThresholdCheck then
            local vecVictim
            if victim:IsPlayer() then
                vecVictim = PortalPlayerController:GetPlayerVelocity()
            else
                vecVictim = GetPhysVelocity(victim)
            end

            local vecForward = AnglesToVector(self.m_vecLaunchAngles)

            local flDot = vecForward:Dot(vecVictim)
            -- why does valve only check player velocity?
            local flLower = self.m_flPlayerVelocity - (self.m_flPlayerVelocity * self.m_flLowerThreshold)
            local flUpper = self.m_flPlayerVelocity + (self.m_flPlayerVelocity * self.m_flUpperThreshold)
            if flDot < flLower or flDot > flUpper then
                bShouldLaunch = false
            end
        end

        if bShouldLaunch then
            if self.m_bOnlyVelocityCheck then
                self:FireOutput("OnUser1", params.activator, self, nil, 0)
            else
                self:LaunchByDirection(params.activator)
            end
        end
	end
end

-- ---Updates a flag on the catapult which handles reseting the catapult's target when it's captured.
-- ---@param value boolean true to clear the catapult's target when it's captured, false to keep current target
-- function base:SetResetTargetOnCapture(value)
-- 	self.resetTargetOnCapture = value
-- 	self:Save("resetTargetOnCapture")
-- end

-- ---Update the catapult's launch target if it's placed on an anchor that should change its target.
-- ---@param params IOParams
-- function base:OnPlacedOnAnchor(params)
-- 	---@TODO: Is this always an anchor?
-- 	local caller = params.caller--[[@as Anchor]]
-- 	if caller then
-- 		local catapultSetLaunchTarget = caller.catapultSetLaunchTarget
-- 		if not catapultSetLaunchTarget then return end

-- 		local catapultLaunchTarget = caller.catapultLaunchTarget
-- 		local catapultLaunchByDirection = caller.catapultLaunchTargetByDirection
-- 		self:SetLaunchTarget(catapultLaunchTarget, catapultLaunchByDirection)
-- 		self:SetResetTargetOnCapture(true)
-- 	end
-- end

-- ---Desc here
-- function base:OnCaptured()
-- 	if self.resetTargetOnCapture then
-- 		self:SetLaunchTargetByHandle(nil)
-- 		self:SetResetTargetOnCapture(false)
-- 	end
-- end

-- ---Desc here
-- function base:OnPlaced()
-- 	if not CatapultModifiers then return end

-- 	for trigger, _ in pairs(CatapultModifiers) do
-- 		local dist = CalcDistanceBetweenEntityOBB(trigger, self)
-- 		if dist < 0.01 then
-- 			---@TODO: Replace load functions with direct member calls when trigger_catapult_target_modifier is redone
-- 			local catapultLaunchTarget = trigger:LoadString("CatapultLaunchTarget", "")
-- 			local catapultLaunchByDirection = trigger:LoadBoolean("CatapultLaunchByDirection", false)
-- 			self:SetLaunchTarget(catapultLaunchTarget, catapultLaunchByDirection)
-- 			self:SetResetTargetOnCapture(true)
-- 			return
-- 		end
-- 	end
-- end

---Updates the catapult's launch target, by targetname.
---@param targetname string Name of launch target. Invalid names will reset the catapult's target. Can be a group's name if checkDirection is true.
---@param checkDirection boolean If true, target will be selected from the named group by direction. If none of the entities in the group is in FOV, the catapult's target will be cleared, and it will launch by its' launch angles instead.
function base:SetLaunchTarget(targetname, checkDirection)
	if targetname == nil or targetname == "" then
		self:SetLaunchTargetByHandle(nil)
	else
		if checkDirection then
			self:SetLaunchTargetCheckDirection(targetname)
		else
			local target = Entities:FindByName(nil, self.m_strLaunchTarget)
			self:SetLaunchTargetByHandle(target)
		end
	end
end

---Updates the catapult's launch target, by entity handle.
---@param target EntityHandle|nil Handle of launch target.
function base:SetLaunchTargetByHandle(target)
	if target == nil then
		self.targetHandle = nil
		self:Save("m_strLaunchTarget", "")
		self:SetOwner(target)
	else
		self.targetHandle = target
		self:Save("m_strLaunchTarget", target:GetName())
		self:SetOwner(nil)
	end
end

---Updates the catapult's launch target, by group name.
---Target will be selected from the named group by direction.
---If none of the entities in the group is in FOV, the catapult's target will be cleared, and it will launch by its' launch angles instead.
---@param targetname string Group name of potential targets
function base:SetLaunchTargetCheckDirection(targetname)
	local origin = self:GetAbsOrigin()
	local direction = self:GetDirectionVector()

	local bestTarget = nil
	local bestDirection = SET_TARGET_BY_DIRECTION_MIN_DOT

	local target = Entities:FindByName(nil, targetname)
	while target do
		local direction_dot = (target:GetAbsOrigin() - origin):Dot(direction)
		if direction_dot >= bestDirection then
			bestTarget = target
			bestDirection = direction_dot
		end
		target = Entities:FindByName(target, targetname)
	end

	self:SetLaunchTargetByHandle(bestTarget)
end

---Updates the catapult's launch target, by entity handle.
---If target is not in FOV, the catapult's target will be cleared, and it will launch by its' launch angles instead.
---@param target EntityHandle Handle of launch target.
function base:SetLaunchTargetByHandleCheckDirection(target)
	local origin = self:GetAbsOrigin()
	local direction = self:GetDirectionVector()

	local direction_dot = (target:GetAbsOrigin() - origin):Dot(direction)
	if direction_dot >= SET_TARGET_BY_DIRECTION_MIN_DOT then
		self:SetLaunchTargetByHandle(target)
	else
		self:SetLaunchTargetByHandle(nil)
	end
end

--Used for classes not attached directly to entities
return base