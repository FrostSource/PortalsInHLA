
function Precache(context)
    print("Main portal precache")
    PrecacheResource("particle", "particles/portal_effect_parent.vpcf", context)
    PrecacheResource("model", "models/vrportal/portalshape.vmdl", context)
end


function Spawn(spawnkeys)
    local prefix = spawnkeys:GetValue("Group00")
    if prefix == nil then
        return
    end
    PortalManager.PortalableSurfaceNamePrefix = string.gsub(prefix,".*_","",0)
    devprints("PortalableSurfaceNamePrefix:", PortalManager.PortalableSurfaceNamePrefix)
end

---Open the blue portal at the caller.
---@param params IOParams
local function OpenBluePortal(params)
    PortalManager:TryCreatePortalAt(params.caller:GetOrigin(), params.caller:GetForwardVector(), "blue")
end
Expose(OpenBluePortal, "OpenBluePortal")

---Open the orange portal at the caller.
---@param params IOParams
local function OpenOrangePortal(params)
    PortalManager:TryCreatePortalAt(params.caller:GetOrigin(), params.caller:GetForwardVector(), "orange")
end
Expose(OpenOrangePortal, "OpenOrangePortal")

---Close the blue portal.
---@param params IOParams
local function CloseBluePortal(params)
    PortalManager:ClosePortal("blue")
end
Expose(CloseBluePortal, "CloseBluePortal")

---Open the orange portal at the caller.
---@param params IOParams
local function CloseOrangePortal(params)
    PortalManager:ClosePortal("orange")
end
Expose(CloseOrangePortal, "CloseOrangePortal")

---Allow portals to only be placed on prefixed entities.
---@param params IOParams
local function AllowPortalsOnlyOnPrefixedSurfaces(params)
    PortalManager:SetAllowPortalsOnlyOnPrefixedEntities(true)
end
Expose(AllowPortalsOnlyOnPrefixedSurfaces, "AllowPortalsOnlyOnPrefixedSurfaces")

---Allow portals to be placed on any surface.
---@param params IOParams
local function AllowPortalsOnAnySurface(params)
    PortalManager:SetAllowPortalsOnlyOnPrefixedEntities(false)
end
Expose(AllowPortalsOnAnySurface, "AllowPortalsOnAnySurface")

---Close all open portals, anywhere.
---@param params IOParams
local function CloseAllPortals(params)
    PortalManager:CloseAllPortals()
end
Expose(CloseAllPortals, "CloseAllPortals")

print("Main portal entity initiated")
