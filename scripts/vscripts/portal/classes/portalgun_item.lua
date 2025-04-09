--[[
    This script is required for physical portal gun to work.
    It attaches the portalgun class script to the gun entity created when this item is picked up.
]]

if thisEntity then
    -- Inherit this script if attached to entity
    -- Will also load the script at the same time if needed
    inherit(GetScriptFile())
    return
end

---@class PortalGunItem : EntityClass
local base = entity("PortalGunItem")

-- Yoink from portalgun class
base.Precache = PortalGunClass.Precache

---@param params GameEventItemPickup
base:GameEvent("item_pickup", function (self, params)
    ---@cast self PortalGunItem
    if params.item == "hlvr_weapon_generic_pistol" then
        local weapon = Player.PrimaryHand:GetHandAttachment()
        -- Current check to make sure this is the right weapon is using the name
        -- Name might change so script needs to be updated too
        -- Could use name of item as name of weapon
        -- Could check for model name
        if weapon:GetName() == "@PortalGun" then
            ---@cast weapon PortalGun
            AttachClassToEntity(weapon, "portal.classes.portalgun")

            ---@TODO Send useful spawnkeys from this item
            -- weapon:OnSpawn({})
        end
    end
end)

-- ---Called automatically on spawn
-- ---@param spawnkeys CScriptKeyValues
-- function base:OnSpawn(spawnkeys)
-- end

-- ---Called automatically after OnActivate, when EasyConvars and Player have initialized.
-- ---@param readyType OnReadyType
-- function base:OnReady(readyType)
-- end

-- ---Main entity think function. Think state is saved between loads
-- function base:Think()
--     return 0
-- end

--Used for classes not attached directly to entities
return base