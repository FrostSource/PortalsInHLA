PORTAL_SIZE_X = 25
PORTAL_SIZE_Y = 55
PORTAL_SIZE_Z = 100
PORTAL_MINS = Vector(-(PORTAL_SIZE_X / 2), -(PORTAL_SIZE_Y / 2), -(PORTAL_SIZE_Z / 2))
PORTAL_MAXS = Vector(PORTAL_SIZE_X / 2, PORTAL_SIZE_Y / 2, PORTAL_SIZE_Z / 2)

---Max distance the gun can trace to look for a portal location.
local MAX_TRACE_DISTANCE = 10000

local PORTAL_NAME_TEMPLATE = "%s_Portal"

PortalManager = {}
PortalManager.__index = PortalManager

---@class PortalColor
---@field name string
---@field connection string
---@field color Color

---Create a portal color
---@param name string
---@param connection string
---@param color Color
---@return table
local function defPortalColor(name, connection, color)
    return {
        name = name,
        connection = connection,
        color = color
    }
end

---Resolve a value into a `PortalColor`.
---@param color string|PortalColor
---@return PortalColor
local function resolveColor(color)
    local _color = color
    if type(color) == "string" then
        color = PortalManager.colors[color]
    end
    if color == nil or not (type(color) == "table" and color.color) then
        error(tostring(_color) .. " is not a valid color")
    end

    return color
end

---@enum PortalColors
---@type table<string, PortalColor>
PortalManager.colors = {
    blue = defPortalColor("blue", "orange", Color(0, 0.4, 1)),
    orange = defPortalColor("orange", "blue", Color(1, 0.4, 0)),
}

---@type PortalGun
PortalManager.portalGun = nil

---Only allow portals to be opened on entities whose name starts with `PortalManager.PortalableSurfaceNamePrefix`
PortalManager.AllowPortalsOnlyOnPrefixedEntities = false

---The prefix part that must be on portalable surface entities.
PortalManager.PortalableSurfaceNamePrefix = ""

Convars:RegisterConvar("portal_debugging_is_on", _G.Debugging and "1" or "0", "", 0)
Convars:RegisterCommand("portal_debugging", function (_, on)
    if on == nil or on == "" then
        on = not _G.Debugging
    elseif on == false or on == "0" or on == "false" or on == "off" then
        on = false
    else
        on = true
    end
    _G.Debugging = on
end, "Toggle portal debugging", 0)

function PortalManager:Debugging()
    -- return Convars:GetInt("developer") > 0 or Convars:GetBool("portal_debugging_is_on")
    return Convars:GetBool("portal_debugging_is_on")
end

Convars:RegisterCommand("portal_disable_all_portals", function(_)
    for k, v in pairs(PortalManager.colors) do
        local portal = PortalManager:GetPortal(v)
        if portal then
            portal.trigger:Disable()
        end
    end
end, "", 0)

Convars:RegisterCommand("portal_close_all_portals", function (_, ...)
    PortalManager:CloseAllPortals()
end, "", 0)

---Add a portal color
---@param name string
---@param connection string
---@param color Color|Vector|string
function PortalManager:AddPortalColor(name, connection, color)
    if not IsColor(color) then
        color = Color(color)
    end
    self.colors[name] = defPortalColor(name, connection, color)
    if not Player then
        Warning("PortalManager cannot save colors because player doesn't exist\n")
        return
    end
    Player:SaveTable("PortalColors", self.colors)
end

---Utility function for tracing in a direction.
---@param position Vector
---@param dir Vector
---@return TraceTableLine
function PortalManager:TraceDirection(position, dir)
    local traceTable = {
        startpos = position,
        endpos = position + dir,
        ignore = Player,
    }
    TraceLine(traceTable)
    if self:Debugging() then
        if traceTable.hit then
            DebugDrawLine(traceTable.startpos, traceTable.endpos, 255, 0, 0, true, 3)
        else
            DebugDrawLine(traceTable.startpos, traceTable.endpos, 0, 255, 0, true, 3)
        end
    end
    return traceTable
end

---@class TraceLinePortalable : TraceTableLine
---@field surfaceIsPortalable boolean

---Trace in a direction and get the resulting surface properties to check if a surface is portalable.
---@param startpos Vector
---@param forward Vector
---@param ignore? EntityHandle
---@return TraceLinePortalable
function PortalManager:TracePortalableSurface(startpos, forward, ignore)
    ---@type TraceLinePortalable
    local traceTable = {
        startpos = startpos,
        endpos = startpos + forward * MAX_TRACE_DISTANCE,
        ignore = ignore,
        surfaceIsPortalable = false,
    }

    TraceLine(traceTable)
    if traceTable.hit then

        local surfaceIsPortalable = true

        if self.AllowPortalsOnlyOnPrefixedEntities then
            if not traceTable.enthit:GetName():startswith(self.PortalableSurfaceNamePrefix) then
                surfaceIsPortalable = false
            end
        end

        if self:Debugging() then
            DebugDrawLine(traceTable.startpos, traceTable.endpos, surfaceIsPortalable and 0 or 255, surfaceIsPortalable and 255 or 0, 0, false, 1)
            DebugDrawLine(traceTable.pos, traceTable.pos + traceTable.normal * 10, 0, 0, 255, false, 1)
        end

        traceTable.surfaceIsPortalable = surfaceIsPortalable
    end

    return traceTable
end

---Returns `QAngle` version of the `normal` vector.
---If `normal` is perpendicular to `forward` then it will reorient towards `forward`.
---@param normal Vector
---@param forward Vector
---@return QAngle # Final angle of the portal.
function PortalManager:ReorientPortalPerpendicular(normal, forward)
    local normalAngles = VectorToAngles(normal)

    if normal:IsPerpendicularTo(forward) then
        local xaxis = 0
        if math.isclose(normal.z, -1, 1e-7) then
            xaxis = 90
        else
            xaxis = -90
        end

        normalAngles = VectorToAngles(forward)
        normalAngles = RotateOrientation(normalAngles, QAngle(xaxis, 0, 0))
    end
    return normalAngles
end

---Try to open a portal at a given `position`, checking to make sure it can fit.
---@param position Vector # World position to open the portal at.
---@param normal Vector # Normalized direction the portal should face.
---@param color PortalColor|string # Color of the portal, must be an existing color.
---@return boolean # Returns true if the portal successfully opened, false otherwise.
function PortalManager:TryCreatePortalAt(position, normal, color)
    color = resolveColor(color)
    local normalAngles = self:ReorientPortalPerpendicular(normal, Player:GetWorldForward())

    local UpTrace = self:TraceDirection(position + normalAngles:Forward() * 10, normalAngles:Up() * PORTAL_SIZE_Z / 2)
    if not UpTrace.hit then
        UpTrace = self:TraceDirection(UpTrace.endpos, -normalAngles:Forward() * 30)
        if not UpTrace.hit then
            return false
        end
    else
        return false
    end
    local DownTrace = self:TraceDirection(position+normalAngles:Forward() * 10, (-normalAngles:Up()) * PORTAL_SIZE_Z / 2)
    if not DownTrace.hit then
        DownTrace = self:TraceDirection(DownTrace.endpos, -normalAngles:Forward() * 30)
        if not DownTrace.hit then
            return false
        end
    else
        return false
    end
    local LeftTrace = self:TraceDirection(position + normalAngles:Forward() * 10, normalAngles:Left() * PORTAL_SIZE_Y / 2)
    if not LeftTrace.hit then
        LeftTrace = self:TraceDirection(LeftTrace.endpos, -normalAngles:Forward() * 30)
        if not LeftTrace.hit then
            return false
        end
    else
        return false
    end
    local RightTrace = self:TraceDirection(position+normalAngles:Forward() * 10, (-normalAngles:Left()) * PORTAL_SIZE_Y / 2)
    if not RightTrace.hit then
        RightTrace = self:TraceDirection(RightTrace.endpos, -normalAngles:Forward() * 30)
        if not RightTrace.hit then
            return false
        end
    else
        return false
    end

    local otherPortal = PortalManager:GetConnectedPortal(color)
    if otherPortal ~= nil then
        local localPosition = otherPortal:TransformPointWorldToEntity(position)
        if abs(localPosition.y) < PORTAL_SIZE_Y  and abs(localPosition.z) < PORTAL_SIZE_Z and abs(localPosition.x) < 20 then
            return false
        end
    end

    PortalManager:CreatePortalAt(position, normal, color)
    return true
end

---Create a portal at a position with a direction.
---@param position Vector
---@param normal Vector
---@param color PortalColor|string
function PortalManager:CreatePortalAt(position, normal, color)
    color = resolveColor(color)
    if type(color) ~= "table" or not color.color then
        return
    end

    if self:IsPortalOpen(color) then
        self:ClosePortal(color)
    end

    local newPortal = SpawnEntityFromTableSynchronous("logic_script", {
        targetname = PORTAL_NAME_TEMPLATE:format(color.name),
        vscripts = "portal/classes/portal",
    })--[[@as Portal]]

    -- Portal handles its own opening/connection logic
    newPortal:Open(position, normal, color)

    local connectedPortal = self:GetConnectedPortal(color)
    if connectedPortal then
        connectedPortal:UpdateConnection()
    end
end

---Close a portal color if it's open.
---@param color PortalColor|string
function PortalManager:ClosePortal(color)
    color = resolveColor(color)
    if type(color) ~= "table" or not color.color then
        return
    end

    local portal = self:GetPortal(color)

    if portal then
        portal:CleanupAndDestroy()
        return true
    end

    return false
end

---Close all portals open in the map.
function PortalManager:CloseAllPortals()
    for index, value in ipairs(Entities:FindAllByClassname("logic_script")) do
        if isinstance(value, "Portal") then
            local portal = value--[[@as Portal]]
            portal:Close()
        end
    end
end

---Get a portal entity by color.
---@param color PortalColor|string
---@return Portal?
function PortalManager:GetPortal(color)
    color = resolveColor(color)
    return Entities:FindByName(nil, PORTAL_NAME_TEMPLATE:format(color.name))--[[@as Portal]]
end

---Get if a portal color is open.
---@param color PortalColor|string
---@return boolean
function PortalManager:IsPortalOpen(color)
    color = resolveColor(color)
    return self:GetPortal(color) ~= nil
end

---Get the camera entity associated with a portal color.
---@param color PortalColor|string
---@return EntityHandle?
function PortalManager:GetPortalCamera(color)
    color = resolveColor(color)
    return Entities:FindByName(nil, "_PortalCamera" .. color.name)
end

---Get the monitor entity associated with a portal color.
---@param color PortalColor|string
---@return EntityHandle?
function PortalManager:GetPortalMonitor(color)
    color = resolveColor(color)
    return Entities:FindByName(nil, "_PortalMonitor" .. color.name)
end

---Get the trigger_multiple associated with a portal color.
---@param color PortalColor|string
---@return EntityHandle?
function PortalManager:GetPortalTrigger(color)
    color = resolveColor(color)
    return Entities:FindByName(nil, "_PortalTrigger" .. color.name)
end

---Get the currently opened portal connected to a specified color.
---@param color PortalColors|PortalColor|string # Color table or name of color.
---@return Portal?
function PortalManager:GetConnectedPortal(color)
    color = resolveColor(color)
    local connectedPortal = self:GetPortal(self.colors[color.connection])
    if connectedPortal ~= nil then
        return connectedPortal
    end
    return nil
end

---Sets the prefix that must be on entity names that allow portals to be placed.
---@param prefix string
function PortalManager:SetPortalableSurfaceNamePrefix(prefix)
    self.PortalableSurfaceNamePrefix = prefix or ""
    if not Player then
        Warning("PortalManager cannot save PortalableSurfaceNamePrefix because player doesn't exist\n")
        return
    end
    Player:SaveString("PortalableSurfaceNamePrefix", self.PortalableSurfaceNamePrefix)
end

---Sets if portals can only be placed on name prefixed entities or if they can be placed anywhere.
---@param allow boolean
function PortalManager:SetAllowPortalsOnlyOnPrefixedEntities(allow)
    self.AllowPortalsOnlyOnPrefixedEntities = truthy(allow)
    if not Player then
        Warning("PortalManager cannot save AllowPortalsOnlyOnPrefixedEntities because player doesn't exist\n")
        return
    end
    Player:SaveBoolean("AllowPortalsOnlyOnPrefixedEntities", self.AllowPortalsOnlyOnPrefixedEntities)
end

-- Loading values
ListenToPlayerEvent("player_activate", function (params)
    PortalManager.PortalableSurfaceNamePrefix = Player:LoadString("PortalableSurfaceNamePrefix", PortalManager.PortalableSurfaceNamePrefix)
    PortalManager.AllowPortalsOnlyOnPrefixedEntities = Player:LoadBoolean("AllowPortalsOnlyOnPrefixedEntities", PortalManager.AllowPortalsOnlyOnPrefixedEntities)
    PortalManager.colors = Player:LoadTable("PortalColors", PortalManager.colors)
end)

Convars:RegisterCommand("portalgun_give", function (_, ...)
    local portalgun = Entities:FindByName(nil, "@PortalGun")--[[@as PortalGun]]
    if portalgun == nil then
        portalgun = SpawnEntityFromTableSynchronous("npc_furniture", {
            targetname = "@PortalGun",
            model = "models/vrportal/portalgun.vmdl",
            vscripts = "portal/entities/portalgun",
        })--[[@as PortalGun]]
    end
    portalgun:AttachToHand()
end, "", 0)

Convars:RegisterCommand("close_all_portals", function (_, ...)
    PortalManager:CloseAllPortals()
end, "", 0)
