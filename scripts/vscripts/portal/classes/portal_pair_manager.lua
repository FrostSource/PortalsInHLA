if thisEntity then
    -- Inherit this script if attached to entity
    -- Will also load the script at the same time if needed
    inherit(GetScriptFile())
    return
end

---@class PortalPairManager : EntityClass
local base = entity("PortalPairManager")

---@type string
base.portal1Name = ""
---@type Vector
base.portal1Color = Vector()
---@type string
base.portal2Name = ""
---@type Vector
base.portal2Color = Vector()

---Called automatically on spawn
---@param spawnkeys CScriptKeyValues
function base:OnSpawn(spawnkeys)
    self.portal1Name = spawnkeys:GetValue("Group00") or DoUniqueString("color1")
    self.portal1Color = Util.VectorFromString(spawnkeys:GetValue("Group01"))
    self.portal2Name = spawnkeys:GetValue("Group02") or DoUniqueString("color2")
    self.portal2Color = Util.VectorFromString(spawnkeys:GetValue("Group03"))

    debugprint_portals("Portal Pair Spawn:", self.portal1Name, Debug.SimpleVector(self.portal1Color), " - ", self.portal2Name, Debug.SimpleVector(self.portal2Color))
end

---Called automatically on activate.
---Any self values set here are automatically saved
---@param readyType OnReadyType
function base:OnReady(readyType)
    if readyType ~= READY_GAME_LOAD then
        -- Must wait until player exists to save color table
        -- ListenToPlayerEvent("player_activate", function (params)
            local portal1Camera = self:FindInPrefab("portal_1_camera")
            local portal2Camera = self:FindInPrefab("portal_2_camera")
            local portal1Monitor = self:FindInPrefab("portal_1_monitor")
            local portal2Monitor = self:FindInPrefab("portal_2_monitor")
            local portal1Trigger = self:FindInPrefab("portal_1_trigger")
            local portal2Trigger = self:FindInPrefab("portal_2_trigger")
            local portal1DebugCamera = self:FindInPrefab("portal_1_debug_camera")
            local portal2DebugCamera = self:FindInPrefab("portal_2_debug_camera")
            local portal1TeleportTrigger = self:FindInPrefab("portal_1_teleport")--[[@as PortalTeleport]]
            local portal2TeleportTrigger = self:FindInPrefab("portal_2_teleport")--[[@as PortalTeleport]]
            if not (portal1Camera and portal2Camera
            and portal1Monitor and portal2Monitor
            and portal1Trigger and portal2Trigger
            and portal1DebugCamera and portal2DebugCamera
            and portal1TeleportTrigger and portal2TeleportTrigger) then
                Warning("Missing entity in portal pair prefab " .. self:GetName())
                self:Kill()
                return
            end

            -- Rename prefab entities so they can be found by PortalManager
            portal1Camera:SetEntityName("_portalcamera" .. self.portal1Name:lower())
            portal2Camera:SetEntityName("_portalcamera" .. self.portal2Name:lower())
            portal1Monitor:SetEntityName("_portalmonitor" .. self.portal1Name:lower())
            portal2Monitor:SetEntityName("_portalmonitor" .. self.portal2Name:lower())
            portal1Trigger:SetEntityName("_portaltrigger" .. self.portal1Name:lower())
            portal2Trigger:SetEntityName("_portaltrigger" .. self.portal2Name:lower())

            portal1DebugCamera:SetEntityName("_portaldebugcamera" .. self.portal1Name:lower())
            portal2DebugCamera:SetEntityName("_portaldebugcamera" .. self.portal2Name:lower())
            portal1DebugCamera:SetRenderColor(self.portal1Color.x, self.portal1Color.y, self.portal1Color.z)
            portal2DebugCamera:SetRenderColor(self.portal2Color.x, self.portal2Color.y, self.portal2Color.z)

            -- test teleport
            portal1TeleportTrigger:SetEntityName("_portalteleport" .. self.portal1Name:lower())
            portal2TeleportTrigger:SetEntityName("_portalteleport" .. self.portal2Name:lower())

            --- Scaled teleport triggers cause bizarre behavior
            --- Unparent from animated monitor
            ---@NOTE positioning is handled in portal.lua:UpdateConnection
            portal1Trigger:SetParent(nil, nil)
            portal2Trigger:SetParent(nil, nil)
            portal1TeleportTrigger:SetParent(nil, nil)
            portal2TeleportTrigger:SetParent(nil, nil)
            portal1TeleportTrigger.targetEnt:SetParent(nil, nil)
            portal2TeleportTrigger.targetEnt:SetParent(nil, nil)

            ---@TODO Consider moving this to Spawn
            PortalManager:AddPortalColor(self.portal1Name, self.portal2Name, self.portal1Color)
            PortalManager:AddPortalColor(self.portal2Name, self.portal1Name, self.portal2Color)
        -- end)
    end
end

---Base function for opening one of the paired portals.
---@param origin Vector
---@param normal Vector
---@param color string
function base:OpenPortal(origin, normal, color)
    if not PortalManager:TryCreatePortalAt(origin, normal, color) then
        devprints("Failed to open portal", color, Debug.SimpleVector(origin), Debug.SimpleVector(normal))
    end
end

---Base function for opening one the paired portals at an entity.
---@param ent EntityHandle
---@param color string
function base:OpenPortalAtEntity(ent, color)
    if not IsEntity(ent, true) then
        devprints("Trying to open portal at invalid entity:", tostring(ent))
        return
    end
    self:OpenPortal(ent:GetOrigin(), ent:GetForwardVector(), color)
end

---Open portal 1.
---@param params IOParams
function base:OpenPortal1(params)
    self:OpenPortalAtEntity(params.caller, self.portal1Name)
end

---Open portal 2.
---@param params IOParams
function base:OpenPortal2(params)
    self:OpenPortalAtEntity(params.caller, self.portal2Name)
end

---Close portal 1.
---@param params IOParams
function base:ClosePortal1(params)
    PortalManager:ClosePortal(self.portal1Name)
end

---Close portal 2.
---@param params IOParams
function base:ClosePortal2(params)
    PortalManager:ClosePortal(self.portal2Name)
end

--Used for classes not attached directly to entities
return base