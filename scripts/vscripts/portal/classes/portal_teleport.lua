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

    debugprint_portals("Portal Teleport Spawn:", self.target, self.landmark)
end

---Called automatically after OnActivate, when EasyConvars and Player have initialized.
---@param readyType OnReadyType
function base:OnReady(readyType)
end

---@param offset number
function base:Teleport(offset)
    
    local landmark = self.landmark
    landmark:SetLocalAngles(0, 180, 0)

    -- if portal is straight up or down
    if math.isclose(abs(landmark:GetAngles().x), 90) then
        -- set player's angle to the same as the target portal
        local targang = self.target:GetAngles()
        landmark:SetAngles(targang.x, targang.y - AngleDiff(targang.y, Player:GetAngles().y), targang.z)
        -- push player out so they're not behind the wall
        self.target:SetLocalOrigin(Vector(64,0,0))
    end

    landmark:SetLocalOrigin(Vector(32 + offset,0,0))
    self:Enable()
    -- self:EntFire("Enable")
    self:Delay(function()
        self:Disable()
        landmark:ResetLocal()
        self.target:ResetLocal()
    end, 0.1)
end

---Main entity think function. Think state is saved between loads
function base:Think()
    return 0
end


--Used for classes not attached directly to entities
return base