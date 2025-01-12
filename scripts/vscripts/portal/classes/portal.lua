if thisEntity then
    -- Inherit this script if attached to entity
    -- Will also load the script at the same time if needed
    inherit(GetScriptFile())
    return
end

local PTX_PORTAL_EFFECT = "particles/portal_effect_parent.vpcf"

local SND_CLOSE = "Portal.Close"
local SND_CLOSE_BLUE = "Portal.Close.Blue"
local SND_CLOSE_ORANGE = "Portal.Close.Orange"
local SND_TELEPORT_ENTER = "PortalPlayer.Enter"

---These are classes which are allowed to be teleported through a portal.
local PORTAL_CLASS_WHITELIST = {
    "player",

    "prop_physics",
    "func_physbox",
    "npc_manhack",
    "item_hlvr_grenade_frag",
    "item_hlvr_grenade_xen",
    "item_hlvr_prop_battery",
    "prop_physics_interactive",
    "prop_physics_override",
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


local TICKRATE = 0.05

---@class Portal : EntityClass
local base = entity("Portal")

base.glowLight = nil
base.aimat = nil
base.particleSystem = nil
base.__ptxEffect = -1
base.teleport = nil
base.portalModel = nil

base.camera = nil
base.monitor = nil
base.trigger = nil

---@type string
base.colorName = ""

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
    devprints2("Destroying portal", self:GetName())
    if self.glowLight then self.glowLight:Kill() end
    if self.aimat then self.aimat:Kill() end
    if self.particleSystem then self.particleSystem:Kill() end
    if self.teleport then self.teleport:Kill() end
    if self.portalModel then self.portalModel:Kill() end
    if self.__ptxEffect ~= -1 then
        ParticleManager:DestroyParticle(self.__ptxEffect, true)
    end
    self.trigger:DisconnectRedirectedOutput("OnStartTouch", "OnTriggerTouch", self)

    self:Kill()
end

function base:UpdateEffects()
    if self.__ptxEffect ~= -1 then
        ParticleManager:DestroyParticle(self.__ptxEffect, false)
    end
    self.__ptxEffect = ParticleManager:CreateParticleForPlayer(PTX_PORTAL_EFFECT, 1, self.particleSystem, Player)
    ParticleManager:SetParticleControl(self.__ptxEffect, 5, PortalManager.colors[self.colorName].color:ToDecimalVector())
end

---Open this portal with new properties.
---@param position Vector
---@param normal Vector
---@param color PortalColor
---@overload fun()
function base:Open(position, normal, color)
    devprints("Opening portal", Debug.SimpleVector(position), Debug.SimpleVector(normal), color.name, Debug.SimpleVector(color.color:ToVector()))

    self.colorName = color.name
    local normalAngles = PortalManager:ReorientPortalPerpendicular(normal, Player:GetWorldForward())

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

    ---@TODO Why is this created in two different ways?
    self.particleSystem = SpawnEntityFromTableSynchronous("info_particle_target", {
        -- effect_name = PTX_PORTAL_EFFECT,
        targetname = color.name .. "Portal_particles",
        -- cpoint5 = PortalManager:GetColorEntityName(color),
        origin = position + normal * 2.25,
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
    self.portalModel:SetOrigin(position + normal)

    self.teleport = SpawnEntityFromTableSynchronous("point_teleport", {
        targetname = color.name .. "Portal_teleport",
        origin = self.aimat:GetOrigin() + normal * 50,
        target = "!player",
        teleport_parented_entities = "1",
        spawnflags = "4",
    })

    self.camera = PortalManager:GetPortalCamera(color)
    self.monitor = PortalManager:GetPortalMonitor(color)
    self.trigger = PortalManager:GetPortalTrigger(color)
    self.trigger:RedirectOutput("OnStartTouch", "OnTriggerTouch", self)

    self:UpdateEffects()

    if self:GetConnectedPortal() then
        self:UpdateConnection()
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

    self:CleanupAndDestroy()
end

function base:UpdateConnection()
    local connectedPortal = self:GetConnectedPortal()
    if connectedPortal then
        local ents = {self, connectedPortal}

        for _, portal in ipairs(ents) do
            portal.monitor:SetOrigin(portal.aimat:GetOrigin() + portal.aimat:GetForwardVector() * 2)
            local angles = VectorToAngles(portal.aimat:GetForwardVector())
            portal.monitor:SetAngles(angles.x, angles.y, angles.z)

            -- portal.camera:SetOrigin(portal.aimat:GetOrigin() + portal.aimat:GetForwardVector() * -40)

            -- angles = VectorToAngles(portal.aimat:GetForwardVector())
            -- portal.camera:SetAngles(angles.x, angles.y, angles.z)

            portal.monitor:SetRenderAlpha(255)
            -- EntFire(portal.camera, portal.camera:GetName(), "Enable")
            EntFire(portal.monitor, portal.monitor:GetName(), "Enable")
        end

        self:ResumeThink()

    else
        -- EntFire(self.camera, self.camera:GetName(), "Enable")
        EntFire(self.monitor, self.monitor:GetName(), "Enable")
        self:PauseThink()
    end
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
    return true

end

---Called
---@param params IOParams
function base:OnTriggerTouch(params, test)
    local ent = params.activator

    -- Disallow entities owned by player
    if ent:GetOwner() then
        local ownerClass = ent:GetOwner():GetClassname()
        if ownerClass == "player" or ownerClass == "hl_prop_vr_hand" or ownerClass == "prop_hmd_avatar" or ownerClass == "hl_vr_teleport_controller" then
            return
        end
    end

    if not vlua.find(PORTAL_CLASS_WHITELIST, ent:GetClassname()) then
        return
    end

    self:Teleport(ent)
end

---This should be fine to be a local to this class script
local lastPlayerTeleport = 0

---Teleports an entity from this portal to its connected portal (if one exists).
---@param ent EntityHandle
function base:Teleport(ent)
    if self:CanTeleport(ent) then

        local connectedPortal = self:GetConnectedPortal()--[[@as Portal]]

        devprints(self:GetName(), "teleporting", ent:GetClassname(), "to", connectedPortal.colorName)

        -- if ent:IsPlayer() then
        --     -- Teleport player
        --     if lastPlayerTeleport - GetFrameCount() < 0 and self:CanTeleport(Player) then
        --         -- In VR
        --         if Player.HMDAvatar ~= nil then

        --             local pos = connectedPortal:GetAbsOrigin() + connectedPortal:GetForwardVector() * 30

        --             local dir = connectedPortal:GetForwardVector()
        --             local forward = Player.HMDAnchor:GetForwardVector()
        --             local newForward = dir * forward:Length()
        --             newForward = -forward + newForward - dir
        --             newForward.z = 0

        --             Player.HMDAvatar:SetAbsOrigin(pos)
        --             Player:SetAnchorForwardAroundPlayer(newForward)

        --             lastPlayerTeleport = GetFrameCount() + 50
        --         -- In NOVR
        --         else
        --             self:TeleportPhysicalEntity(Player, connectedPortal)
        --             local dir = connectedPortal:GetForwardVector()
        --             local forward = Player:GetForwardVector()
        --             local newForward = dir * forward:Length()
        --             Player:SetForwardVector(-forward + newForward - dir)
        --         end
        --         StartSoundEvent(SND_TELEPORT_ENTER, Player)
        --     end
        -- else

            self:TeleportPhysicalEntity(ent, connectedPortal)

            if not ent:IsPlayer() then
                if PortalManager.portalGun and PortalManager.portalGun.__pickupEntity == ent then
                    PortalManager.portalGun:DropItem()
                else
                    -- drop from player hand
                    ent:Drop()
                end
            end
        -- end

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

function base:TeleportPhysicalEntity(ent, connectedPortal)
    -- local localPositionOnPortal = self:TransformPointWorldToEntity(ent:GetAbsOrigin())
    -- local dir = connectedPortal:GetForwardVector()
    -- -- Teleport from OriginalPortal to Portal but keep velocity and rotation of the entity with offset to keep it from constantly teleporting back and forth
    -- local newPos = connectedPortal:TransformPointEntityToWorld(localPositionOnPortal + Vector(PORTAL_MAXS.x, 0, 0))
    -- ent:SetOrigin(newPos)
    
    -- DebugDrawSphere(newPos, Vector(0,255,0), 255, 32, true, 100)
    -- ent:EntFire("DisableMotion")

    -- local dirAngle = transformAngles(self.aimat, connectedPortal.aimat, ent)
    -- ent:SetQAngle(dirAngle)

    -- -- Rotate Velocity to match the new direction
    -- local vel = GetPhysVelocity(ent)
    -- local newVel = dir * vel:Length() * 0.95

    -- ent:ApplyAbsVelocityImpulse(-vel + newVel - dir)

    -- if PortalManager:Debugging() then
    --     DebugDrawLine(self:GetOrigin(), self:GetOrigin() + vel, 255, 0, 0, true, 10)
    --     DebugDrawLine(connectedPortal:GetOrigin(), connectedPortal:GetOrigin() + newVel, 0, 255, 0, true, 10)
    --     print(Debug.SimpleVector(vel))
    --     print(Debug.SimpleVector(newVel))
    --     print("___________")
    -- end






    local timeDiff = Time() - ent:Attribute_GetFloatValue("ent_teleport_time", 0)

    print(timeDiff)
	if timeDiff < 0.25 and timeDiff >= 0 then return end

	local offset = Vector(0,0,0)
	local velocity = GetPhysVelocity(ent)
	local angularVelocity = GetPhysAngularVelocity(ent)
	ent:Attribute_SetFloatValue("ent_teleport_time", Time())

	local dirOffset = transformDirection(self, connectedPortal, offset)
	local dirPosition = transformVector(self, connectedPortal, ent:GetOrigin()+offset)
	local dirAngle = transformAngles(self, connectedPortal, ent)
	local dirVelocity = transformDirection(self, connectedPortal, velocity:Normalized())
	local dirAngVelocity = transformDirection(self, connectedPortal, angularVelocity:Normalized())

	-- ent:SetOrigin(dirPosition-dirOffset)
    -- DebugDrawSphere(dirPosition-dirOffset, Vector(0,255,0), 255, 16, true, 100)
    -- ent:EntFire("DisableMotion")
	--self:SetForwardVector(dirForward)
	
	if not ent:IsPlayer() then
		-- Not Player
        ent:SetOrigin(dirPosition-dirOffset)
		ent:ApplyAbsVelocityImpulse(-velocity)

		ent:SetAngles(dirAngle.x, dirAngle.y, dirAngle.z)

		ent:ApplyAbsVelocityImpulse(dirVelocity*velocity:Length())
		SetPhysAngularVelocity(ent, dirAngVelocity*angularVelocity:Length())
	else
		-- Player
        self.teleport:SetOrigin((dirPosition-dirOffset)+ AnglesToVector(dirAngle)*4)
        self.teleport:SetQAngle(dirAngle)
        -- DebugDrawSphere(self.teleport:GetOrigin(), Vector(255,255,0), 255, 16, true, 8)
        -- print(self.teleport:GetName())
        Player:SetMovementEnabled(false)
        self:Delay(function()
            self.teleport:EntFire("TeleportToCurrentPos")
            -- Player:SetMovementEnabled(true)
            Player:EntFire("EnableTeleport", "1", 0.01)
        end, 0)

        -- ent:SetAnchorOriginAroundPlayer(dirPosition-dirOffset)
        -- ent.HMDAnchor:SetOrigin((dirPosition-dirOffset)+ AnglesToVector(dirAngle)*4)
        -- DebugDrawSphere(ent.HMDAnchor:GetOrigin(), Vector(255,255,255), 255, 16, true, 100)
		-- ent:SetAngles(dirAngle.x, dirAngle.y, 0)
        -- Player:SetAnchorForwardAroundPlayer(dirAngle:Forward())
        -- Player:SetAnchorAngleAroundPlayer(dirAngle)
        -- ent:SetAnchorOriginAroundPlayer(ent:GetOrigin() + AnglesToVector(dirAngle)*4)
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
	
	keyvals.origin = GetOriginRelativeTo(connectedPortal, relOrigin)
	keyvals.angles = connectedPortal:GetAngles()
	keyvals.targetname = self.monitor:GetName():gsub("monitor", "camera")
	keyvals.ZNear = math.max(math.abs(relOrigin.x) - CAMERA_NEARZ_OFFSET, 0.001)
	keyvals.FOV = self.camera.Fov or DEFAULT_CAMERA_FOV
	
	self.camera = SpawnEntityFromTableSynchronous("point_camera", keyvals)
	self.camera.Fov = keyvals.FOV
	--tbl.Camera:SetPortalID(thisEntity:GetPortalID())

	DoEntFireByInstanceHandle(self.monitor, "SetCamera", keyvals.targetname, 0, self.camera, self.camera)

	return self.camera
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

	local base = (1/math.tan(Deg2Rad(self.camera.Fov/2)))/plrDist.x

	self.camera.Fov = CorrectFov(plrLocal, p_size)
	self.camera:SetFOV(self.camera.Fov)
	--print("CAM: " .. tbl.Camera.Fov)

	local tex_offset = Vector(0, 0.5-base*((plrLocal.y/p_size.y)+0.5), 0.5+base*((plrLocal.z/p_size.z)-0.5))

	--print(0.5+base*((plrLocal.z/tbl.Monitor.Size.z)-0.5))
	--print("Player: " .. tostring(plrLocal))
	--print("Base: " .. base)
	--print("X: " .. tex_offset.y)
	--print("Y: " .. tex_offset.z)

	DoEntFireByInstanceHandle(self.monitor, "setrenderattribute", tostring("all=" .. base .. "," .. base .. "," .. tex_offset.y .. "," .. tex_offset.z), 0, self.monitor, self.monitor)
end

---Main entity think function. Think state is saved between loads
function base:Think()

    self:CreateCamera()

    -- if not IsVREnabled() and IsValidEntity(self.monitor:GetMoveParent()) then
	-- 	self.monitor:GetMoveParent():SetVelocity(GetPhysVelocity(Player.HMDAvatar or Player))
	-- 	self.monitor:SetOrigin(self.aimat:GetAbsOrigin())
	-- end

    self:ModifyTexture()

    return 0

    -- local connectedPortal = self:GetConnectedPortal()--[[@as Portal]]

    -- -- Update render camera
    -- local PlayerToConnectedPortal = connectedPortal.aimat:TransformPointWorldToEntity(Player:EyePosition())
    -- PlayerToConnectedPortal.z = PlayerToConnectedPortal.z * -1
    -- PlayerToConnectedPortal.x = Clamp(PlayerToConnectedPortal.x, 0, 40)
    -- PlayerToConnectedPortal.y = Clamp(PlayerToConnectedPortal.y / 10, -15, 15)
    -- PlayerToConnectedPortal.z = Clamp(PlayerToConnectedPortal.z / 10, -10, 10)

    -- local camPos = self.aimat:TransformPointEntityToWorld(-PlayerToConnectedPortal)
    -- self.camera:SetOrigin(camPos)

    -- local angles = VectorToAngles( self.aimat:TransformPointEntityToWorld(PlayerToConnectedPortal) - self.aimat:GetOrigin() )
    -- self.camera:SetQAngle(angles)

    -- return TICKRATE
end

--Used for classes not attached directly to entities
return base