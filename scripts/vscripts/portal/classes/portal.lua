local PTX_PORTAL_EFFECT = "particles/portal_effect_parent.vpcf"

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
    -- devprints("Destroying portal", self:GetName())
    if self.glowLight then self.glowLight:Kill() end
    if self.aimat then self.aimat:Kill() end
    if self.particleSystem then self.particleSystem:Kill() end
    if self.teleport then self.teleport:Kill() end
    if self.portalModel then self.portalModel:Kill() end

    self:Kill()
end

function base:UpdateEffects()
    if self.__ptxEffect ~= -1 then
        ParticleManager:DestroyParticle(self.__ptxEffect, false)
    end
    self.__ptxEffect = ParticleManager:CreateParticleForPlayer(PTX_PORTAL_EFFECT, 1, self.particleSystem, Player)
    ParticleManager:SetParticleControl(self.__ptxEffect, 5, PortalManager.colors[self.colorName].color)
end

---Open this portal with new properties.
---@param position Vector
---@param normal Vector
---@param color PortalColor
---@overload fun()
function base:Open(position, normal, color)
    devprints("Opening portal", Debug.SimpleVector(position), Debug.SimpleVector(normal), color.name, Debug.SimpleVector(color.color))

    self.colorName = color.name
    -- local normalAngles = VectorToAngles(normal)
    local normalAngles = PortalManager:ReorientPortalPerpendicular(normal, Player:GetWorldForward())
    -- if normal.x == 0 and normal.y == 0 and (normal.z > 0.999 or normal.z < -0.999) then
    --     local newnormal = Vector(Player:GetOrigin().x,Player:GetOrigin().y,0)-Vector(position.x,position.y,0)
    --     newnormal = newnormal:Normalized()
    --     normalAngles = VectorToAngles(newnormal)
    --     if normal.z > 0.999 then
    --         normalAngles = RotateOrientation(normalAngles, QAngle(-90, 0, 180))
    --     else
    --         normalAngles = RotateOrientation(normalAngles, QAngle(90, 0, 180))
    --     end
    -- end

    self.aimat = SpawnEntityFromTableSynchronous("point_aimat", {
        targetname = color.name .. "Portal_aimat",
        origin = position,
        angles = normalAngles
    })
    self.aimat:SetForwardVector(AnglesToVector(normalAngles))--(normal)

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
        ---@TODO Update material to use dynamic expressions
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

            EntFire(portal.camera, portal.camera:GetName(), "Enable")
        end

        -- self.monitor:SetOrigin(self.aimat:GetOrigin() + self.aimat:GetForwardVector() * 2)
        -- connectedPortal.monitor:SetOrigin(connectedPortal.aimat:GetOrigin() + connectedPortal.aimat:GetForwardVector() * 2)

    else

        EntFire(self.camera, self.camera:GetName(), "Enable")

    end
end

---Main entity think function. Think state is saved between loads
function base:Think()

    -- local connectedPortal = self:GetConnectedPortal()
    -- if connectedPortal then
    --     local playerToPortal = 
    -- end

    return 0
end

--Used for classes not attached directly to entities
return base