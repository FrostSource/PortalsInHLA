if thisEntity then
    -- Inherit this script if attached to entity
    -- Will also load the script at the same time if needed
    inherit(GetScriptFile())
    return
end

---@class PortalTeleport : EntityClass
local base = entity("PortalTeleport")

---@type EntityHandle
base.target = nil
---@type EntityHandle
base.landmark = nil

---Called automatically on spawn
---@param spawnkeys CScriptKeyValues
function base:OnSpawn(spawnkeys)
    local targetName = spawnkeys:GetValue("target")
    local landmarkName = spawnkeys:GetValue("landmark")

    self.target = Entities:FindByName(nil, targetName)
    self.landmark = Entities:FindByName(nil, landmarkName)
    print(self.target, self.landmark)
end

---Called automatically after OnActivate, when EasyConvars and Player have initialized.
---@param readyType OnReadyType
function base:OnReady(readyType)
end

---@param offset number
function base:Teleport(offset)
    local ent = self.landmark
    ent:SetLocalAngles(0, 180, 0)
    ent:SetLocalOrigin(Vector(10 + offset,0,0))
    self:Enable()
    -- self:EntFire("Enable")
    self:Delay(function()
        self:Disable()
        ent:ResetLocal()
    end, 0.1)
end

---Main entity think function. Think state is saved between loads
function base:Think()
    return 0
end

--Used for classes not attached directly to entities
return base