if thisEntity then
    -- Inherit this script if attached to entity
    -- Will also load the script at the same time if needed
    inherit(GetScriptFile())
    return
end

EasyConvars:RegisterConvar("portal_use_outlines", "1", "Show portal outlines through walls", nil,
    function(newValue, oldValue)
        local visible = Convars:GetBool("portal_use_outlines")
        for _, portal in ipairs(PortalManager:GetAllPortals()) do
            portal:SetOutlineVisible(visible)
        end
    end)
EasyConvars:SetPersistent("portal_use_outlines", true)

EasyConvars:RegisterConvar("portal_orient_to_gun", "1", "Orients portals to the portalgun instead of the player", FCVAR_NONE)
EasyConvars:SetPersistent("portal_orient_to_gun", true)

EasyConvars:RegisterConvar("portal_add_missing_speed_to_props", "0", "Add missing physical speed to props when they are teleported", FCVAR_NONE)
EasyConvars:SetPersistent("portal_add_missing_speed_to_props", true)
EasyConvars:RegisterConvar("portal_add_missing_speed_to_player", "0", "Add missing physical speed to player when they are teleported", FCVAR_NONE)
EasyConvars:SetPersistent("portal_add_missing_speed_to_player", true)

EasyConvars:RegisterConvar("portal_recenter_phys_objects", "1", "Objects exiting a portal are have their velocity recentered to the exit direction", FCVAR_NONE)
EasyConvars:RegisterConvar("portal_recenter_speed", "50", "Speed at which objects are recentered if recentering is enabled", FCVAR_NONE)

EasyConvars:RegisterConvar("portal_open_anim_speed", "0.25", "Animation speed of portal opening", FCVAR_NONE)

local PTX_PORTAL_EFFECT = "particles/portal_effect_parent.vpcf"

local SND_CLOSE = "Portal.Close"
local SND_CLOSE_BLUE = "Portal.Close.Blue"
local SND_CLOSE_ORANGE = "Portal.Close.Orange"
local SND_TELEPORT_ENTER = "PortalPlayer.Enter"

local PORTAL_HALF_WIDTH = 28
local PORTAL_HALF_HEIGHT = 49.5

---These are classes which are allowed to be teleported through a portal.
local PORTAL_CLASS_WHITELIST = {
    "player",

    "prop_physics",
    "prop_physics_override",
    "prop_physics_interactive",
    "func_physbox",
    "shatterglass_shard",
    "npc_manhack",
    "item_hlvr_grenade_frag",
    "item_hlvr_grenade_xen",
    "item_hlvr_prop_battery",
    "prop_ragdoll",
    "generic_actor",
    "hlvr_weapon_energygun",
    "item_healthvial",
    "item_item_crate",
    "item_hlvr_crafting_currency_large",
    "item_hlvr_crafting_currency_small",
    "item_hlvr_clip_energygun",
    "item_hlvr_clip_energygun_multiple",
    "item_hlvr_clip_rapidfire",
    "item_hlvr_clip_shotgun_single",
    "item_hlvr_clip_shotgun_multiple",
    "item_hlvr_clip_generic_pistol",
    "item_hlvr_clip_generic_pistol_multiple",
}

GlobalPrecache("model", "models/vrportal/portal_outline.vmdl")
GlobalPrecache("model", "models/vrportal/portal_collision.vmdl")


local TICKRATE = 0.05

---@class Portal : EntityClass
local base = entity("Portal")

base.glowLight = nil
base.aimat = nil
base.particleSystem = nil
base.__ptxEffect = -1
base.teleportTrigger = nil
base.portalModel = nil

base.camera = nil
base.monitor = nil
base.trigger = nil
---The trigger_teleport
---Weird bug where `teleport` gets saved as `Teleport` so name was changed
---@type PortalTeleport
base.teleportTrigger = nil
---@type EntityHandle?
base.outline = nil

---@type string
base.colorName = ""

---@type EntityHandle
base.debugCamera = nil

---Called automatically on spawn
---@param spawnkeys CScriptKeyValues
function base:OnSpawn(spawnkeys)
end

---Called automatically on activate.
---Any self values set here are automatically saved
---@param loaded boolean
function base:OnReady(loaded)
    if loaded then
        self:Delay(function()
            self:UpdateEffects()
        end, 0)
    end
end

function base:CleanupAndDestroy()
    self:PauseThink()
    devprints2("Destroying portal", self:GetName())
    if self.glowLight then self.glowLight:Kill() end
    if self.aimat then self.aimat:Kill() end
    if self.particleSystem then self.particleSystem:Kill() end
    -- if self.teleport then self.teleport:Kill() end
    if self.portalModel then self.portalModel:Kill() end
    if self.__ptxEffect ~= -1 then
        ParticleManager:DestroyParticle(self.__ptxEffect, true)
    end
    self.trigger:DisconnectRedirectedOutput("OnStartTouch", "OnTriggerTouch", self)
    self:ClearDebug()

    self:Kill()
end

function base:UpdateEffects()
    if self.__ptxEffect ~= -1 then
        ParticleManager:DestroyParticle(self.__ptxEffect, false)
    end
    self.__ptxEffect = ParticleManager:CreateParticleForPlayer(PTX_PORTAL_EFFECT, 1, self.particleSystem, Player)
    ParticleManager:SetParticleControl(self.__ptxEffect, 5, PortalManager.colors[self.colorName].color:ToDecimalVector())
end

---Sets if the portal outline is visible.
---@param visible boolean # If true, the outline will be visible
function base:SetOutlineVisible(visible)
    if IsValidEntity(self.outline) then
        self.outline:SetRenderingEnabled(visible)
    end
end

---Open this portal with new properties.
---@param position Vector
---@param normal Vector
---@param color PortalColor
---@param reorientToPlayer? boolean # If true, the portal will be reoriented to be perpendicular to the player when placed on the ground or ceiling.
---@overload fun()
function base:Open(position, normal, color, reorientToPlayer)
    if Convars:GetInt("portal_debug_portals") >= 1 then
        devprints("Opening portal", Debug.SimpleVector(position), Debug.SimpleVector(normal), color.name, Debug.SimpleVector(color.color:ToVector()))
    end

    self.colorName = color.name
    local normalAngles = VectorToAngles(normal)

    if reorientToPlayer then
        -- if Convars:GetBool("portal_orient_to_gun") then
        --     local forward = CurrentPortalGun:GetForwardVector()
        --     forward.z = 0
        --     normalAngles = PortalManager:ReorientPortalPerpendicular(normal, forward)
        -- else
        --     normalAngles = PortalManager:ReorientPortalPerpendicular(normal, Player:GetWorldForward())
        -- end
        normalAngles = PortalManager:GetOrientedPortalAngles(normal)
    end

    self.aimat = SpawnEntityFromTableSynchronous("point_aimat", {
        targetname = color.name .. "Portal_aimat",
        origin = position,
        angles = normalAngles
    })
    self.aimat:SetForwardVector(AnglesToVector(normalAngles))--(normal)
    -- debugoverlay:VertArrow(self.aimat:GetOrigin(), self.aimat:GetOrigin() + self.aimat:GetForwardVector() * 64, 8, 255, 0, 0, 255, false, 900)

    -- Update self to aimat transform
    self:SetOrigin(self.aimat:GetOrigin())
    self:SetQAngle(self.aimat:GetAngles())

    -- local aimdebug = SpawnEntityFromTableSynchronous("prop_dynamic", {model="models/editor/point_aimat.vmdl"})
    -- aimdebug:SetParent(self.aimat, "")
    -- aimdebug:SetLocalOrigin(Vector())
    -- aimdebug:SetLocalAngles(0,0,0)

    local normalRotated = RotateOrientation(normalAngles, QAngle(90, 0, 0))

    ---This exists simply as a parent entity for particles created in base:UpdateEffects
    self.particleSystem = SpawnEntityFromTableSynchronous("info_particle_target", {
        -- effect_name = PTX_PORTAL_EFFECT,
        targetname = color.name .. "Portal_particles",
        -- cpoint5 = PortalManager:GetColorEntityName(color),
        origin = position + (normal / 2),
        angles = normalRotated,
    })

    -- local particles = ParticleManager:CreateParticleForPlayer(PTX_PORTAL_EFFECT, 1, self.particleSystem, Player)
    -- ParticleManager:SetParticleControl(particles, 5, color.color)

    self.portalModel = SpawnEntityFromTableSynchronous("prop_dynamic", {
        targetname = color.name .. "Portalview",
        angles = normalRotated,
        ---@TODO Update material to use dynamic expressions (2023-11-10 don't remember why expressions were wanted)
        skin = color.name,
        model = "models/vrportal/portalshape.vmdl",
    })
    ---@TODO Can move this into construction?
    self.portalModel:SetOrigin(position)

    -- self.teleport = SpawnEntityFromTableSynchronous("point_teleport", {
    --     targetname = color.name .. "Portal_teleport",
    --     origin = self.aimat:GetOrigin() + normal * 50,
    --     target = "!player",
    --     teleport_parented_entities = "1",
    --     spawnflags = "4",
    -- })

    self.outline = SpawnEntityFromTableSynchronous("prop_dynamic", {
        model = "models/vrportal/portal_outline.vmdl",
        origin = self:GetOrigin() + normal * 1,
        angles = self:GetAngles(),
        targetname = color.name .. "Portal_outline",
        disableshadows = "1", -- trying to fix black outline
        disablereceiveshadows = "1", -- ditto
    })
    self.outline:SetParent(self, "")
    -- local c = color.color:ToDecimalVector()
    -- DoEntFireByInstanceHandle(self.outline, "SetRenderAttribute", "tintColor="..c.x..","..c.y..","..c.z, 0, nil, nil)
    if color.name == "blue" then
        DoEntFireByInstanceHandle(self.outline, "SetRenderAttribute", "blueStrength=100", 0, nil, nil)
    end

    self:SetOutlineVisible(Convars:GetBool("portal_use_outlines"))

    self.camera = PortalManager:GetPortalCamera(color)
    self.monitor = PortalManager:GetPortalMonitor(color)
    self.trigger = PortalManager:GetPortalTrigger(color)
    self.trigger:RedirectOutput("OnStartTouch", "OnTriggerTouch", self)

    self.debugCamera = PortalManager:GetPortalDebugCamera(color)
    self.debugCamera:SetRenderingEnabled(false)

    self.teleportTrigger = PortalManager:GetPortalTeleport(color)

    -- Triggers are no longer parented, need to be moved manually
    self.trigger:SetOrigin(self.aimat:GetOrigin())
    self.trigger:SetQAngle(self.aimat:GetAngles())
    self.teleportTrigger:SetOrigin(self.aimat:GetOrigin())
    self.teleportTrigger:SetQAngle(self.aimat:GetAngles())

    self:UpdateEffects()

    if self:GetConnectedPortal() then
        self:UpdateConnection()
    end

    -- Animate portals opening by scaling up
    local animSpeed = Convars:GetFloat("portal_open_anim_speed")
    if animSpeed > 0 then
        self.portalModel:SetAbsScale(0.01)
        Animation:Animate(self.portalModel, self.portalModel.GetAbsScale, self.portalModel.SetAbsScale, 1, Animation.Curves.linear, animSpeed)
        self.monitor:SetAbsScale(0.01)
        Animation:Animate(self.monitor, self.monitor.GetAbsScale, self.monitor.SetAbsScale, 1, Animation.Curves.linear, animSpeed)
    else
        self.portalModel:SetAbsScale(1)
        self.monitor:SetAbsScale(1)
    end

end

---Get the portal connected to this one if it exists.
---@return Portal?
function base:GetConnectedPortal()
    if self.colorName == "" then
        return nil
    end
    local connectedPortal = PortalManager:GetConnectedPortal(self.colorName)
    return connectedPortal
end

function base:Close()
    ---@TODO Notify connected portal that it has closed
    EntFire(self.camera, self.camera:GetName(), "Disable")
    EntFire(self.monitor, self.monitor:GetName(), "Disable")
    self.monitor:SetRenderAlpha(0)
    local sndevnt = SND_CLOSE
    if self.colorName == PortalManager.colors.blue.name then
        sndevnt = SND_CLOSE_BLUE
    elseif self.colorName == PortalManager.colors.orange.name then
        sndevnt = SND_CLOSE_ORANGE
    end
    StartSoundEventFromPositionReliable(sndevnt, self:GetOrigin())

    local target = SpawnEntityFromTableSynchronous("info_particle_target", {
        origin = self:GetOrigin(),
        angles = RotateOrientation(self:GetAngles(), QAngle(0, 0, 90)),
    })
    local closePt = ParticleManager:CreateParticleForPlayer("particles/portals/portal_close.vpcf", 1, target, Player)
    ParticleManager:SetParticleControl(closePt, 2, PortalManager:GetPortalColor(self.colorName).color:ToVector())
    target:EntFire("Kill", nil, 2)

    self:CleanupAndDestroy()

    if self:GetConnectedPortal() then
        self:GetConnectedPortal():UpdateConnection()
    end
end

function base:UpdateConnection()
    local connectedPortal = self:GetConnectedPortal()
    if connectedPortal then
        local ents = {self, connectedPortal}

        for _, portal in ipairs(ents) do
            ---@TODO Monitor was pushed out 2 units, was there a specific reason for this?
            portal.monitor:SetOrigin(portal.aimat:GetOrigin() + portal.aimat:GetForwardVector() * 0.1)
            local angles = VectorToAngles(portal.aimat:GetForwardVector())
            portal.monitor:SetAngles(angles.x, angles.y, angles.z)

            portal.monitor:SetRenderAlpha(255)
            -- EntFire(portal.camera, portal.camera:GetName(), "Enable")
            EntFire(portal.monitor, portal.monitor:GetName(), "Enable")

            -- Toggle trigger to force it to re-evaluate touching entities
            portal.trigger:Disable()
            portal.trigger:Enable()
        end

        self:ResumeThink()

    else
        -- EntFire(self.camera, self.camera:GetName(), "Enable")
        EntFire(self.monitor, self.monitor:GetName(), "Disable")
        self.monitor:SetRenderAlpha(0)
        self:PauseThink()
    end
end

local portalVerticalThreshold = 0.6

---Checks if the portal is facing up
---@return boolean
function base:IsFloorPortal()
    return self:GetForwardVector().z > portalVerticalThreshold
end

---Checks if the portal is facing up
---@return boolean
function base:IsCeilingPortal()
    return self:GetForwardVector().z < -portalVerticalThreshold
end

---Checks if the portal is not facing up or down
---@return boolean
function base:IsWallPortal()
    return abs(self:GetForwardVector().z) <= portalVerticalThreshold
end

---Get if an entity can teleport to connected portal.
---@TODO Determine exactly how this works
---@param ent EntityHandle
---@return boolean
function base:CanTeleport(ent)
    local connectedPortal = self:GetConnectedPortal()
    if not connectedPortal then
        return false
    end
    ---@TODO Check free space at connected portal

    if ent.portalTravelDisabled then
        return false
    end

    return true

end

---Called
---@param params IOParams
function base:OnTriggerTouch(params)
    local ent = params.activator
    print("Trigger touched", self:GetName(), Debug.EntStr(ent))

    -- Disallow entities owned by player
    if ent:GetOwner() then
        local ownerClass = ent:GetOwner():GetClassname()
        print("Owner class", ownerClass)
        if ownerClass == "player" or ownerClass == "hl_prop_vr_hand" or ownerClass == "prop_hmd_avatar" or ownerClass == "hl_vr_teleport_controller" then
            print("Cancelling")
            return
        end
    end

    if not vlua.find(PORTAL_CLASS_WHITELIST, ent:GetClassname()) then
        print("Entity is not whitelisted")
        return
    end

    if ent:HasAttribute("DoNotPortal") then
        print("Entity has DoNotPortal")
        return
    end

    self:Teleport(ent)
end

---
---Test if an entity will touch this portal at a given origin and optional angles.
---
---@param ent EntityHandle
---@param origin Vector
---@param angles? QAngle
---@return boolean
function base:WillEntityTouchPortal(ent, origin, angles)
    local portalCollision = SpawnEntityFromTableSynchronous("prop_dynamic_override", {
        origin = self:GetOrigin(),
        angles = self:GetAngles(),
        model = "models/vrportal/portal_collision.vmdl",
    })

    -- ---@type TraceTableHull
    -- local trace = {
    --     startpos = origin,
    --     endpos = origin,
    --     min = ent:GetBoundingMins(),
    --     max = ent:GetBoundingMaxs(),
    --     ignore = GetWorld()
    -- }
    -- TraceHull(trace)

    -- debugoverlay:Sphere(CalcClosestPointOnEntityOBB(ent, origin), 1, 255, 0, 0, 255, false, 100)
    -- debugoverlay:Sphere(CalcClosestPointOnEntityOBB(ent, origin), 2, 0, 255, 0, 255, false, 100)
    -- debugoverlay:Sphere(CalcClosestPointOnEntityOBB(ent, origin), 3, 0, 0, 255, 255, false, 100)
    -- debugoverlay:Line(CalcClosestPointOnEntityOBB(ent, origin), origin, 0, 255, 0, 255, false, 100)
    -- debugoverlay:Box(ent:GetOrigin()+ent:GetBoundingMins(), ent:GetOrigin()+ent:GetBoundingMaxs(), 0, 255, 0, 255, false, 100)
    -- debugoverlay:Box(origin+ent:GetBoundingMins(), origin+ent:GetBoundingMaxs(), 0, 0, 255, 255, false, 100)

    ---@type TraceTableCollideable
    local trace = {
        startpos = CalcClosestPointOnEntityOBB(ent, origin),
        endpos = origin,
        ent = portalCollision,

        -- docs say this is local to ent,
        -- but testing seems like it's a swept box?
        mins = ent:GetBoundingMins(),
        maxs = ent:GetBoundingMaxs(),
    }
    TraceCollideable(trace)

    -- debugoverlay:PushDebugOverlayScope("asdf")
    -- debugoverlay:Line(trace.startpos, trace.endpos, 0, 255, 0, 255, true, 100)
    -- debugoverlay:Line(trace.startpos+Vector(0,0,-1), trace.endpos+Vector(0,0,-1), 255, 255, 0, 255, true, 100)
    -- debugoverlay:Line(trace.startpos+Vector(0,0,-2), trace.endpos+Vector(0,0,-2), 0, 0, 255, 255, true, 100)

    -- print("Results??", trace.hit)
    local touch = trace.hit

    -- print("Results??", trace.hit, Debug.EntStr(trace.enthit))
    -- local touch = trace.hit and trace.enthit == portalCollision

    portalCollision:Kill()
    return touch
end


---This should be fine to be a local to this class script
local lastPlayerTeleport = 0

---Teleports an entity from this portal to its connected portal (if one exists).
---@param ent EntityHandle
function base:Teleport(ent)
    if self:CanTeleport(ent) then

        if ent:GetModelName() == "models/props/camera_phys.vmdl" then
            if not ent.firstPortalTouch then
                ent.firstPortalTouch = true
                return
            end
        end

        local connectedPortal = self:GetConnectedPortal()--[[@as Portal]]

            self:TeleportPhysicalEntity(ent, connectedPortal)

            if not ent:IsPlayer() then
                if PortalManager.portalGun and PortalManager.portalGun.pickupEntity == ent then
                    PortalManager.portalGun:DropEntity()
                else
                    -- drop from player hand
                    ent:Drop()
                end
            end

    end
end

local function matrixVectorMultiply(mat, vec)
    local result = {}
    for i = 1, 4 do
        result[i] = 0
        for j = 1, 4 do
            result[i] = result[i] + mat[i][j] * vec[j]
        end
    end
    return result
end

function CBaseEntity:transformToLocal(vec)
	local R = self:GetRightVector()	
	local U = self:GetUpVector()	
	local F = self:GetForwardVector()

	local invertRotationMatrix =
	{
		{R.x, R.y, R.z, 0,};
		{U.x, U.y, U.z, 0,};
		{F.x, F.y, F.z, 0,};
		{0,   0,   0,   1,};
	}
	
	vec = {vec.x, vec.y, vec.z, 1}
	local result = matrixVectorMultiply(invertRotationMatrix, vec)

	return Vector(result[1], result[2], result[3])
end

function CBaseEntity:transformToWorld(vec)
	local R = -self:GetRightVector()	
	local U = self:GetUpVector()	
	local F = -self:GetForwardVector()

	local rotationMatrix =
	{
		{R.x; U.x; F.x; 0;};
		{R.y; U.y; F.y; 0;};
		{R.z; U.z; F.z; 0;};
		{0;   0;   0;   1;};
	}

	vec = {vec.x; vec.y; vec.z; 1;}
	local result = matrixVectorMultiply(rotationMatrix, vec)

	return Vector(result[1], result[2], result[3])
end

local function transformDirection(entFrom, entTo, vec)
	return entTo:transformToWorld(entFrom:transformToLocal(vec))
end

local function transformVector(entFrom, entTo, vec)
	local _vec = entFrom:TransformPointWorldToEntity(vec)
	return entTo:TransformPointEntityToWorld(Vector(_vec.x, -_vec.y, _vec.z))
end

local function transformAngles(entFrom, entTo, entAng)
	local F = transformDirection(entFrom, entTo, entAng:GetForwardVector())
	local R = transformDirection(entFrom, entTo, entAng:GetRightVector())
	local U = transformDirection(entFrom, entTo, entAng:GetUpVector())

	return RotateOrientation(VectorToAngles(F), QAngle(0,0, -Rad2Deg(math.atan2(R.z, U.z))) )
end

local function gravityDeltaVelocity(startPos, endPos, currentVel, gravity)
    gravity = gravity or Vector(0,0,-Convars:GetFloat("sv_gravity"))
    local gravityMag = gravity:Length()
    local gravityDir = gravity:Normalized()

    local displacement = endPos - startPos
    local dropDistance = displacement:Dot(gravityDir)

    if dropDistance <= 0 then
        return Vector()
    end

    local u = currentVel:Dot(gravityDir)
    -- print(startPos, endPos, currentVel, gravity, displacement, dropDistance, u)
    local v = math.sqrt(u*u + 2 * gravityMag * dropDistance)
    local deltaV = v - u

    return gravityDir * deltaV
end

function base:EstimateMissedVelocity(ent, entryPos, exitPos, connectedPortal)
    local prePortalVel = GetPhysVelocity(ent)
    connectedPortal = connectedPortal or self:GetConnectedPortal()
    local entryDelta = gravityDeltaVelocity(entryPos, self:GetOrigin(), prePortalVel)
    local preSpeed = prePortalVel:Length()
    local exitVelDir = transformDirection(self, connectedPortal, prePortalVel:Normalized())
    local exitVelBeforeGravity = exitVelDir * preSpeed
    
    ---@TODO use nearest point on portal plane instead of portal origin (origin causes sideways motion if ent is off-center)
    ---@TODO Add exit delta too

    local exitDelta = gravityDeltaVelocity(connectedPortal:GetOrigin(), exitPos, exitVelBeforeGravity)
    return exitVelDir * entryDelta:Length()
end




---@param ent EntityHandle
---@param connectedPortal Portal
function base:TeleportPhysicalEntity(ent, connectedPortal)

    -- Prevent double-teleporting
    local timeDiff = Time() - ent:Attribute_GetFloatValue("ent_teleport_time", 0)

    local MAX_TIME = 0.25
	if timeDiff < MAX_TIME and timeDiff >= 0 then return end

    devprints(self:GetName(), "teleporting", ent:GetClassname(), "to", connectedPortal.colorName)

	local offset = Vector(0,0,0)
	local entryVelocity = GetPhysVelocity(ent)
	local entryAngularVelocity = GetPhysAngularVelocity(ent)
	ent:Attribute_SetFloatValue("ent_teleport_time", Time())

	local dirOffset = transformDirection(self, connectedPortal, offset)
	local dirPosition = transformVector(self, connectedPortal, ent:GetOrigin()+offset)
	local dirAngle = transformAngles(self, connectedPortal, ent)
	local dirVelocity = transformDirection(self, connectedPortal, entryVelocity:Normalized())
	local dirAngVelocity = transformDirection(self, connectedPortal, entryAngularVelocity:Normalized())

    local exitPos
    local entryPos = ent:GetOrigin()

    DebugIf("portal_debug_portals", function()
        debugoverlay:Sphere(entryPos, 2, 255, 255, 0, 255, false, 6)
        debugoverlay:Box(entryPos+ent:GetBoundingMins(), entryPos+ent:GetBoundingMaxs(), 255, 255, 0, 255, false, 6)
    end)

    -- Physics objects
	if not ent:IsPlayer() then
        exitPos = dirPosition-dirOffset

        local exitVelocity = transformDirection(self, connectedPortal, entryVelocity)

        if Convars:GetBool("portal_add_missing_speed_to_props") then
            print("current vel", entryVelocity:Length(), Debug.SimpleVector(entryVelocity))
            local missedVelocity = self:EstimateMissedVelocity(ent, entryPos, exitPos, connectedPortal)
            print("Estimated missing speed:", missedVelocity:Length(), Debug.SimpleVector(missedVelocity))
            exitVelocity = exitVelocity + missedVelocity
        end

        if Convars:GetBool("portal_recenter_phys_objects") and entryVelocity:Length() >= Convars:GetFloat("portal_recenter_speed") then
            ---@TODO move ent to the center of the portal
            exitVelocity = connectedPortal:GetForwardVector() * exitVelocity:Length()
        end

        print('final vel', exitVelocity:Length(), exitVelocity)

        ent:SetOrigin(exitPos)
        ent:SetAngles(dirAngle.x, dirAngle.y, dirAngle.z)

        -- cancel current velocity first
		ent:ApplyAbsVelocityImpulse(-entryVelocity)

		ent:ApplyAbsVelocityImpulse(exitVelocity)
		SetPhysAngularVelocity(ent, dirAngVelocity*entryAngularVelocity:Length())

        DebugIf("portal_debug_portals", function()
            DebugDrawTrajectory(ent, PortalManager.colors[self.colorName].color:ToVector(), nil)
        end)
	else
		-- Player
        exitPos = (dirPosition-dirOffset) + AnglesToVector(dirAngle) * 4

        -- Start player away from exit portal
        exitPos = exitPos + connectedPortal:GetForwardVector() * 16

        -- Adjust player's feet to be at the bottom of the portal
        -- so they don't clip through the ceiling
        if connectedPortal:IsWallPortal() then
            -- print("adjusting player to bottom of wall portal")
            exitPos.z = connectedPortal:GetOrigin().z - PORTAL_HALF_HEIGHT
        elseif connectedPortal:IsFloorPortal() then
            -- Adjust exit pos to rest at the floor
            -- print("adjusting player to floor of portal")
            exitPos = connectedPortal:GetOrigin() + connectedPortal:GetForwardVector() * 2
        else
            -- print('adjusting for ceiling')
            -- print(exitPos)
            local playerHeight = (Player:EyePosition() - Player:GetOrigin()):Length()+64
            -- print(playerHeight)
            local newHeadPos = exitPos + Vector(0, 0, playerHeight)
            -- print(newHeadPos)
            -- debugoverlay:Sphere(Player:EyePosition(), 10, 255, 255, 255, 255, true, 100)
            local dist = connectedPortal:GetForwardVector():Dot(newHeadPos - connectedPortal:GetOrigin())
            -- print(dist)
            if dist < 0 then
                -- physEnt:SetOrigin(physEnt:GetOrigin() + connectedPortal:GetForwardVector() * dist)
                exitPos = exitPos - connectedPortal:GetForwardVector() * dist
            end
        end

        if IsVREnabled() or IsFakeVREnabled() then
            local playerVelocity = PortalPlayerController:GetPlayerVelocity()
            -- print("got velocity", playerVelocity, playerVelocity:Length())
            if PortalPlayerController:IsTeleporting() then
                -- print("player do be teleporting into portal!!")
                playerVelocity = playerVelocity/10
                -- print('shrunk tp velocity', playerVelocity, playerVelocity:Length())
            end

            local exitVelocity = connectedPortal:GetForwardVector() * playerVelocity:Length() -- safest transform
            -- local exitVelocity = transformDirection(self, connectedPortal, plrvelocity) -- this is more accurate but might cause direction bugs for floor portals

            if Convars:GetBool("portal_add_missing_speed_to_player") then
                local missedVelocity = self:EstimateMissedVelocity(ent, ent:GetCenter(), exitPos, connectedPortal)
                print("Estimated missing speed:", missedVelocity :Length(), Debug.SimpleVector(missedVelocity))
                exitVelocity = exitVelocity + missedVelocity
            end

            if PortalPlayerController.currentPlayerPhys ~= nil then
                -- Immediately set the playerphys velocity instead of killing it
                -- Hopefully it won't hit anything while teleporting
                PortalPlayerController.currentPlayerPhys:SetVelocity(exitVelocity)

                PortalPlayerController.currentPlayerPhys:DrawTrajectory(PortalManager.colors[connectedPortal.colorName].color:ToVector(), "portal_debug_portals")

                -- The playerphys does not get teleported with the player/anchor
                -- so it needs to be manually updated sometimes.
                PortalPlayerController.currentPlayerPhys:Delay(function()
                    PortalPlayerController.currentPlayerPhys:SnapToPlayer()
                end, 0.05)

            end

            local exitAngles = Player:EyeAngles()

            -- Teleporting out of a floor portal in vr makes it hard to judge expected angles
            ---@TODO make a cvar for this
            if not (self:IsFloorPortal() and connectedPortal:IsCeilingPortal()) then
                exitAngles = transformAngles(self, connectedPortal, Player.HMDAvatar)
            end
            -- zero out components that can't change in vr
            exitAngles = QAngle(0, exitAngles.y, 0)

            print('velocity before ExitPlayer', exitVelocity)

            PortalPlayerController:CacheVelocity(exitVelocity)
            self.teleportTrigger:TeleportTo(exitPos, exitAngles)

            local mt = Player:GetMoveType()
            if mt == PlayerMoveType.TeleportBlink or mt == PlayerMoveType.TeleportShift then
                local startTime = Time()
                local timeToFade = 2
                Player:QuickThink(function()
                    if Time() > startTime + timeToFade then
                        return nil
                    end

                    DoEntFire("@FadeFix", "Fade", "", 0, nil, nil)
                    return 0.01
                end, 0.1)
            end
        else
            -- Handle novr player
            ent:SetOrigin(exitPos)
            ent:ApplyAbsVelocityImpulse(-entryVelocity)
            -- ent:SetAngles(dirAngle.x, dirAngle.y, dirAngle.z)
            ent:SetForwardVector(dirAngle:Forward())
            ent:ApplyAbsVelocityImpulse(dirVelocity*entryVelocity:Length())
            SetPhysAngularVelocity(ent, dirAngVelocity*entryAngularVelocity:Length())
        end

        StartSoundEvent(SND_TELEPORT_ENTER, Player)
	end

    -- if Convars:GetInt("portal_debug_portals") >= 1 then
    --     debugoverlay:PushDebugOverlayScope("portaldebug")
    --     debugoverlay:Sphere(newPos, 2, 0, 0, 255, 255, false, 10)
    --     debugoverlay:Box(newPos+ent:GetBoundingMins(), newPos+ent:GetBoundingMaxs(), 0, 0, 255, 255, false, 10)
    --     debugoverlay:Line(oldPos, newPos, 0, 0, 255, 255, false, 10)
    -- end

    DebugIf("portal_debug_portals", function()
        debugoverlay:Sphere(exitPos, 2, 0, 0, 255, 255, false, 10)
        debugoverlay:Box(exitPos+ent:GetBoundingMins(), exitPos+ent:GetBoundingMaxs(), 0, 0, 255, 255, false, 10)
        debugoverlay:Line(entryPos, exitPos, 0, 0, 255, 255, false, 10)
    end)
end

-- Unused in newer portal code, delete on cleanup

-- function base:ExitPlayer(velocity, exitOrigin, zeroZ, dontMovePlayer)
--     local connectedPortal = self:GetConnectedPortal()
--     if not connectedPortal then return end

--     velocity = velocity or PortalPlayerController:GetPlayerVelocity()

--     if zeroZ or PortalPlayerController:IsPlayerOnGround() then
--         velocity.z = 0
--     end

--     print("portal velocity", velocity)

--     local desiredVelocity = connectedPortal:GetForwardVector() * velocity:Length()
--     local physEnt = PortalPlayerController:GetOrCreatePlayerPhys(desiredVelocity)

--     assert(physEnt ~= nil, "PortalPlayerController:GetOrCreatePlayerPhys failed")

--     if not dontMovePlayer then

--         -- debugoverlay:Line(newPos, newPos + cachedVelocity, 0, 255, 0, 255, false, 6)
--         exitOrigin = exitOrigin or (connectedPortal:GetOrigin() + connectedPortal:GetForwardVector() * 32)

--         -- -- Adjust player away from portal a bit
--         -- exitOrigin = exitOrigin + connectedPortal:GetForwardVector() * 16

--         -- Player's feet need to be at the bottom of the portal to avoid ceiling clipping
--         -- local adjustedZ = exitOrigin - connectedPortal:GetUpVector() * 32
--         print('adjusting for ceiling')
--         print(exitOrigin)
--         local playerHeight = (Player:EyePosition() - Player:GetOrigin()):Length()+16
--         print(playerHeight)
--         local exitHeadPos = exitOrigin + Vector(0, 0, playerHeight)
--         print(exitHeadPos)
--         -- debugoverlay:Sphere(Player:EyePosition(), 10, 255, 255, 255, 255, true, 100)
--         -- for k,v in ipairs(PortalManager:GetAllPortals()) do v:Kill() end
--         local dist = connectedPortal:GetForwardVector():Dot(exitHeadPos - connectedPortal:GetOrigin())
--         print(dist)
--         if dist < 0 then
--             -- physEnt:SetOrigin(physEnt:GetOrigin() + connectedPortal:GetForwardVector() * dist)
--             exitOrigin = exitOrigin - connectedPortal:GetForwardVector() * dist
--         end
--         physEnt:SetAbsOrigin(exitOrigin)
--     end

--     if Convars:GetInt("portal_debug_portals") >= 1 then
--         -- print(PortalManager.colors[self.colorName].color:ToVector(), "portaldebug")
--         -- debugoverlay:PushDebugOverlayScope("portaldebug")
--         physEnt:DrawTrajectory(PortalManager.colors[connectedPortal.colorName].color:ToVector(), "portal_debug_portals")
--     end

--     if not dontMovePlayer then
--         local newang = transformAngles(self, connectedPortal, Player.HMDAvatar)
--         local diff = AngleDiff(connectedPortal:GetAngles().y, Player.HMDAvatar:GetAngles().y)
--         local currentAngle = physEnt:GetAngles()
--         newang = QAngle(currentAngle.x, currentAngle.y + diff, currentAngle.z)
--         physEnt:SetQAngle(newang)
--     end

--     PortalPlayerController:ClearCache()
--     -- physEnt:Remove()
--     -- SendToConsole("noclip_vr")
-- end

---Funnel entity into the portal.
---@param entity EntityHandle
function base:FunnelIntoPortal(entity)

    local vPortalForward = self:GetForwardVector()
    local vPortalRight = self:GetRightVector()
    local vPortalUp = self:GetUpVector()

    -- Make sure it's a floor portal
    if vPortalForward.z < 0.8 then return end

    vPortalRight.z = 0
    vPortalUp.z = 0
    vPortalRight = vPortalRight:Normalized()
    vPortalUp = vPortalUp:Normalized()

    local vEntityToPortal = self:GetAbsOrigin() - entity:GetAbsOrigin()
    local velocity = GetPhysVelocity(entity)

    -- Make sure the player isn't trying to air control, they're falling downward and they are vertically close to the portal
    if abs(velocity.x) > 64 or abs(velocity.y) > 64 or velocity.z > -165 or vEntityToPortal.z < -512 then
        return
    end

    -- Make sure we're in the 2D portal rectangle
    if (vEntityToPortal:Dot(vPortalRight) * vPortalRight):Length() > PORTAL_HALF_WIDTH * 1.5 then
        return
    end
    if (vEntityToPortal:Dot(vPortalUp) * vPortalUp):Length() > PORTAL_HALF_HEIGHT * 1.5 then
        return
    end

    DebugIf("portal_debug_portals", function()
        debugoverlay:Sphere(entity:GetAbsOrigin(), 2, 255, 0, 128, 255, true, 0.1)
    end)

    if vEntityToPortal.z > -8.0 then
        -- We're too close the the portal to continue correcting, but zero the velocity so our fling velocity is nice
        velocity.x = 0
        velocity.y = 0
    else
        -- Funnel toward the portal

        entity:ApplyAbsVelocityImpulse(-velocity)

        local newHorizontalVel = CalculatePortalVelocity(entity:GetAbsOrigin(), self:GetAbsOrigin(), velocity)
        local newVelocity = LerpVectors(velocity, newHorizontalVel, 0.025)

        velocity.x = newVelocity.x
        velocity.y = newVelocity.y
        velocity.z = newVelocity.z

        entity:ApplyAbsVelocityImpulse(velocity)
    end
end





CAMERA_KEYVALUES =
	{
		targetname = "portal_camera_unknown",
		spawnflags = "0",
		FOV = tostring(DEFAULT_CAMERA_FOV),
		ZNear = "0.1",
		ZFar = "3000",
		UseScreenAspectRatio = "1",
		aspectRatio = "1",
		fogEnable = "0",
		rendercolor = "255 255 255 255",
	}

DEFAULT_CAMERA_FOV = 90
CAMERA_NEARZ_OFFSET = 1

local function GetPlayerRelativeOrigin(ent)
    local plr = Entities:GetLocalPlayer()
    local result = ent:TransformPointWorldToEntity(plr:EyePosition())

    return Vector(-result.x, -result.y, result.z)
end

local function GetOriginRelativeTo(ent, offset)
	return (ent:GetAbsOrigin()+RotatePosition(Vector(0,0,0), ent:GetAngles(), offset))
end

function base:CreateCamera()
	if IsValidEntity(self.camera) then self.camera:Kill() end

	local keyvals = CAMERA_KEYVALUES
	local relOrigin = GetPlayerRelativeOrigin(self)

    local connectedPortal = self:GetConnectedPortal()

    if not connectedPortal then
        return nil
    end

	keyvals.origin = GetOriginRelativeTo(connectedPortal, relOrigin)
	keyvals.angles = connectedPortal:GetAngles()
	keyvals.targetname = self.monitor:GetName():gsub("monitor", "camera")
	keyvals.ZNear = math.max(math.abs(relOrigin.x) - CAMERA_NEARZ_OFFSET, 0.001)
	keyvals.FOV = self.camera.Fov or DEFAULT_CAMERA_FOV

	self.camera = SpawnEntityFromTableSynchronous("point_camera", keyvals)
	self.camera.Fov = keyvals.FOV

	DoEntFireByInstanceHandle(self.monitor, "SetCamera", keyvals.targetname, 0, self.camera, self.camera)

    if Convars:GetInt("portal_debug_portal_rendering") > 0 then
        self.debugCamera:SetOrigin(self.camera:GetOrigin())
        self.debugCamera:SetQAngle(self.camera:GetAngles())
        self.debugCamera:SetRenderingEnabled(true)
    end

	return self.camera
end

function base:ClearDebug()
    self.debugCamera:SetRenderingEnabled(false)
end

local function CorrectFov(dist,size)
	return 2*Rad2Deg(math.atan((0.5*size.x + Vector(0,dist.y, dist.z):Length())/dist.x))
end

function CBaseEntity:SetFOV(fov)
	DoEntFireByInstanceHandle(self, "ChangeFOV", tostring(fov .. " 0"), 0, self, self)
end

function base:ModifyTexture()
	local plrLocal = self.monitor:TransformPointWorldToEntity(Entities:GetLocalPlayer():EyePosition())

    local p_size = Vector(99,99,99)

	local plrDist = 2*Vector(plrLocal.x/p_size.x, plrLocal.y/p_size.y, plrLocal.z/p_size.z)

	local _base = (1/math.tan(Deg2Rad(self.camera.Fov/2)))/plrDist.x

	self.camera.Fov = CorrectFov(plrLocal, p_size)
	self.camera:SetFOV(self.camera.Fov)

	local tex_offset = Vector(0, 0.5-_base*((plrLocal.y/p_size.y)+0.5), 0.5+_base*((plrLocal.z/p_size.z)-0.5))

	DoEntFireByInstanceHandle(self.monitor, "setrenderattribute", tostring("all=" .. _base .. "," .. _base .. "," .. tex_offset.y .. "," .. tex_offset.z), 0, self.monitor, self.monitor)
end

---Main entity think function. Think state is saved between loads
function base:Think()

    if self:CreateCamera() == nil then
        -- stop think, will be turned back on when connected portal is created
        return nil
    end

    self:ModifyTexture()

    -- Funnel physics objects into this portal
    -- Only cubes get funneled for now, for performance reasons
    -- local model = "models/props_junk/wood_crate001a.vmdl"
    local model = "models/props/metal_box_dirty.vmdl"
    for _, ent in ipairs(Entities:FindAllByModelWithin(model, self:GetAbsOrigin(), 1000)) do
        self:FunnelIntoPortal(ent)
    end

    return 0
end


function CEntityInstance:DisablePortalTravel()
    self.portalTravelDisabled = true
end

function CEntityInstance:EnablePortalTravel()
    self.portalTravelDisabled = false
end

--Used for classes not attached directly to entities
return base