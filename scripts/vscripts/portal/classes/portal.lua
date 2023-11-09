local PTX_PORTAL_EFFECT = "particles/portal_effect_parent.vpcf"

---These are classes which are allowed to be teleported through a portal.
local PORTAL_CLASS_WHITELIST = {
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
    self:CleanupAndDestroy()
end

function base:UpdateConnection()
    local connectedPortal = self:GetConnectedPortal()
    if connectedPortal then
        local ents = {self, connectedPortal}

        for _, portal in ipairs(ents) do
            portal.monitor:SetOrigin(portal.aimat:GetOrigin() + portal.aimat:GetForwardVector() * 2)
            local angles = VectorToAngles(-portal.aimat:GetForwardVector())
            portal.monitor:SetAngles(angles.x, angles.y, angles.z)

            portal.camera:SetOrigin(portal.aimat:GetOrigin() + portal.aimat:GetForwardVector() * -40)

            angles = VectorToAngles(portal.aimat:GetForwardVector())
            portal.camera:SetAngles(angles.x, angles.y, angles.z)

            portal.monitor:SetRenderAlpha(255)
            EntFire(portal.camera, portal.camera:GetName(), "Enable")
            EntFire(portal.monitor, portal.monitor:GetName(), "Enable")
        end

        self:ResumeThink()

    else
        EntFire(self.camera, self.camera:GetName(), "Enable")
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

        devprints(self:GetName(), "teleporting", ent:GetClassname())

        if ent:IsPlayer() then
            -- Teleport player
            if lastPlayerTeleport - GetFrameCount() < 0 and self:CanTeleport(Player) then
                -- In VR
                if Player.HMDAvatar ~= nil then
                    Player.HMDAvatar:SetAbsOrigin(
                        (connectedPortal:GetAbsOrigin() + connectedPortal:GetForwardVector() * 30) + (Player.HMDAnchor:GetOrigin() - Player.HMDAvatar:GetOrigin())
                    )
                    StartSoundEvent("PortalPlayer.Enter", Player)
                    lastPlayerTeleport = GetFrameCount() + 50
                -- In NOVR
                else
                    Player:SetOrigin(Player:GetOrigin() + Vector(0, 0, 10))
                    self:Teleport(Player)
                    lastPlayerTeleport = GetFrameCount() + 10
                end
            end
        else
            local localPositionOnPortal = self:TransformPointWorldToEntity(ent:GetOrigin())
            local dir = connectedPortal:GetForwardVector()
            -- Teleport from OriginalPortal to Portal but keep velocity and rotation of the entity with offset to keep it from constantly teleporting back and forth
            ent:SetOrigin(connectedPortal:TransformPointEntityToWorld(localPositionOnPortal + Vector(PORTAL_MAXS.x, 0, 0)))

            -- Rotate Velocity to match the new direction
            local vel = GetPhysVelocity(ent)
            local newVel = dir * vel:Length() * 0.95

            ent:ApplyAbsVelocityImpulse(-vel + newVel - dir)

            if PortalManager:Debugging() then
                DebugDrawLine(self:GetOrigin(), self:GetOrigin() + vel, 255, 0, 0, true, 10)
                DebugDrawLine(connectedPortal:GetOrigin(), connectedPortal:GetOrigin() + newVel, 0, 255, 0, true, 10)
                print(Debug.SimpleVector(vel))
                print(Debug.SimpleVector(newVel))
                print("___________")
            end

            if PortalManager.portalGun and PortalManager.portalGun.__pickupEntity == ent then
                PortalManager.portalGun:DropItem()
            end
        end

    end
end

---Main entity think function. Think state is saved between loads
function base:Think()

    local connectedPortal = self:GetConnectedPortal()--[[@as Portal]]

    -- Update render camera
    local PlayerToConnectedPortal = connectedPortal.aimat:TransformPointWorldToEntity(Player:EyePosition())
    PlayerToConnectedPortal.z = PlayerToConnectedPortal.z * -1
    PlayerToConnectedPortal.x = Clamp(PlayerToConnectedPortal.x, 0, 40)
    PlayerToConnectedPortal.y = Clamp(PlayerToConnectedPortal.y / 10, -15, 15)
    PlayerToConnectedPortal.z = Clamp(PlayerToConnectedPortal.z / 10, -10, 10)

    local camPos = self.aimat:TransformPointEntityToWorld(-PlayerToConnectedPortal)
    self.camera:SetOrigin(camPos)

    local angles = VectorToAngles( self.aimat:TransformPointEntityToWorld(PlayerToConnectedPortal) - self.aimat:GetOrigin() )
    self.camera:SetQAngle(angles)

    return TICKRATE
end

--Used for classes not attached directly to entities
return base