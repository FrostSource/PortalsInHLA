local PORTAL_SIZE_X = 25
local PORTAL_SIZE_Y = 55
local PORTAL_SIZE_Z = 100

---Max distance the gun can trace to look for a portal location.
local MAX_TRACE_DISTANCE = 10000

local PORTAL_NAME_TEMPLATE = "%s_Portal"

PortalManager = {}

---@class PortalColor
---@field name string
---@field connection string
---@field color Vector

---Create a portal color
---@param name string
---@param connection string
---@param color Vector
---@return table
local function defPortalColor(name, connection, color)
    return {
        name = name,
        connection = connection,
        color = color
    }
end

---@enum PortalColors
PortalManager.colors = {
    blue = defPortalColor("blue", "orange", Vector(0, 0.4, 1)),
    orange = defPortalColor("orange", "blue", Vector(1, 0.4, 0)),
}

-- ---@type table<string, Portal>
-- PortalManager.portals = {}

---@type PortalGun
PortalManager.portalGun = nil

---Only allow portals to be opened on entities whose name starts with `PortalManager.PortableNamePrefix`
PortalManager.AllowPortalsOnlyOnNamedEntities = false

---The prefix part that must be on portable entities.
PortalManager.PortableNamePrefix = ""

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
    return Convars:GetInt("developer") > 0 or Convars:GetBool("portal_debugging_is_on")
end

function PortalManager:GetColorRGB(color)
    return Vector(color.color.x * 255, color.color.y * 255, color.color.z * 255)
end

---Add a portal color
---@param name string
---@param connection string
---@param color Vector
function PortalManager:AddPortalColor(name, connection, color)
    self.colors[name] = defPortalColor(name, connection, color)
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

---Gets the entity whose origin vector dictates a color.
---Used for particle control points.
---@param color PortalColor
---@return EntityHandle?
function PortalManager:GetColorEntity(color)
    local ent = Entities:FindByName(nil, "PortalColor_" .. color.name)
    return ent
end

---Gets the name of the entity whose origin vector dictates a color.
---Used for particle control points.
---@param color PortalColor
---@return string # Name of the entity or blank string.
function PortalManager:GetColorEntityName(color)
    local ent = self:GetColorEntity(color)
    if ent then
        return ent:GetName()
    end
    return ""
end

---@class TraceLinePortable : TraceTableLine
---@field surfaceIsPortable boolean

---Trace in a direction and get the resulting surface properties to check if a surface is portable.
---@param startpos Vector
---@param forward Vector
---@param ignore? EntityHandle
---@return TraceLinePortable
function PortalManager:TracePortableSurface(startpos, forward, ignore)
    ---@type TraceLinePortable
    local traceTable = {
        startpos = startpos,
        endpos = startpos + forward * MAX_TRACE_DISTANCE,
        ignore = ignore,
        surfaceIsPortable = false,
    }

    TraceLine(traceTable)
    if traceTable.hit then

        local surfaceIsPortable = true

        if self.AllowPortalsOnlyOnNamedEntities then
            if not traceTable.enthit:GetName():startswith(self.PortableNamePrefix) then
                surfaceIsPortable = false
            end
        end

        if self:Debugging() then
            DebugDrawLine(traceTable.startpos, traceTable.endpos, surfaceIsPortable and 0 or 255, surfaceIsPortable and 255 or 0, 0, false, 1)
            DebugDrawLine(traceTable.pos, traceTable.pos + traceTable.normal * 10, 0, 0, 255, false, 1)
        end

        traceTable.surfaceIsPortable = surfaceIsPortable
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

function PortalManager:TryCreatePortalAt(position, normal, color)
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
---@param color PortalColor
function PortalManager:CreatePortalAt(position, normal, color)
    if type(color) ~= "table" or not color.color then
        return
    end

    if self:IsPortalOpen(color) then
        self:ClosePortal(color)
    end

    local newPortal = SpawnEntityFromTableSynchronous("logic_script", {
        targetname = PORTAL_NAME_TEMPLATE:format(color.name),
        vscripts = "portal/entities/portal",
    })--[[@as Portal]]

    -- Portal handles its own opening/connection logic
    newPortal:Open(position, normal, color)

    local connectedPortal = self:GetConnectedPortal(color)
    if connectedPortal then
        connectedPortal:UpdateConnection()
    end
end

---Close a portal color if it's open.
---@param color PortalColor
function PortalManager:ClosePortal(color)
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

---Get a portal entity by color.
---@param color PortalColor
---@return Portal?
function PortalManager:GetPortal(color)
    return Entities:FindByName(nil, PORTAL_NAME_TEMPLATE:format(color.name))--[[@as Portal]]
end

---Get if a portal color is open.
---@param color PortalColor
---@return boolean
function PortalManager:IsPortalOpen(color)
    return self:GetPortal(color) ~= nil
end

---Get the camera entity associated with a portal color.
---@param color PortalColor
---@return EntityHandle?
function PortalManager:GetPortalCamera(color)
    return Entities:FindByName(nil, "@" .. color.name .. "PointCamera")
end

---Get the monitor entity associated with a portal color.
---@param color PortalColor
---@return EntityHandle?
function PortalManager:GetPortalMonitor(color)
    return Entities:FindByName(nil, "@" .. color.name .. "FuncMonitor")
end

---Get the currently opened portal connected to a specified color.
---@param originalColor PortalColors|PortalColor|string # Color table or name of color.
---@return Portal?
function PortalManager:GetConnectedPortal(originalColor)
    if type(originalColor) == "string" then
        originalColor = self.colors[originalColor]
    end
    local connectedPortal = self:GetPortal(self.colors[originalColor.connection])
    if connectedPortal ~= nil then
        return connectedPortal
    end
    return nil
end