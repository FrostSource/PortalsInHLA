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
---@type table<string, PortalColor> # Name -> PortalColor
PortalManager.colors = {
    blue = defPortalColor("blue", "orange", Color(0, 0.4, 1)),
    orange = defPortalColor("orange", "blue", Color(1, 0.4, 0)),
}

---@type PortalGun
PortalManager.portalGun = nil

---Only allow portals to be opened on entities whose name starts with `PortalManager.PortalableSurfaceNamePrefix`
PortalManager.AllowPortalsOnlyOnPrefixedEntities = true -- default for The Courtesy Call

---The prefix part that must be on portalable surface entities.
PortalManager.PortalableSurfaceNamePrefix = "@PortalableSurfaces" -- default for The Courtesy Call

---List of targetnames the portalgun cannot pickup
---@type string[]
PortalManager.disabledPickupNames = {}

local function checkDebugScope(scope)
    if not Convars:GetBool(scope) then
        debugoverlay:RemoveAllInScope(scope)
    end
end

local startAllDebugOn = "1"

EasyConvars:RegisterConvar("portal_debug_portals", startAllDebugOn, "Shows debugging visuals for portals", 0, function() checkDebugScope("portal_debug_portals") end)
EasyConvars:RegisterConvar("portal_debug_portalgun", startAllDebugOn, "Shows debugging visuals for the portalgun", 0, function() checkDebugScope("portal_debug_portalgun") end)
EasyConvars:RegisterConvar("portal_debug_portal_rendering", startAllDebugOn, "Shows debugging visuals for portal rendering", 0, function() checkDebugScope("portal_debug_portal_rendering") end)
EasyConvars:RegisterConvar("portal_debug_flings", startAllDebugOn, "Shows debugging visuals for flinging mechanics", 0, function() checkDebugScope("portal_debug_flings") end)

Convars:RegisterCommand("portal_debug_clear", function()
    Convars:SetInt("portal_debug_portal_rendering", 0)

    debugoverlay:RemoveAllInScope("portal_debug_portals")
    debugoverlay:RemoveAllInScope("portal_debug_portalgun")
    debugoverlay:RemoveAllInScope("portal_debug_portal_rendering")
    debugoverlay:RemoveAllInScope("portal_debug_flings")

    ---@TODO Create function for looping portals
    for name in pairs(PortalManager.colors) do
        local portal = PortalManager:GetPortal(name)
        if portal then
            portal:ClearDebug()
        end
    end
end, "Clears all debugging visuals (only needed for portal_debug_portal_rendering)", 0)

Convars:RegisterConvar("portal_sample_steps", "2", "Number of edge samples checked when placing a portal", 0)

---@diagnostic disable-next-line: lowercase-global
function debugprint_portalgun(...)
    if Convars:GetInt("portal_debug_portalgun") > 0 then
        print(...)
    end
end

---@diagnostic disable-next-line: lowercase-global
function debugprint_portals(...)
    if Convars:GetInt("portal_debug_portals") > 0 then
        print(...)
    end
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

---@param convar string
---@param scope string
---@param min number
---@param func fun()
---@overload fun(convar, scope, func)
---@overload fun(convar, func)
function DebugIf(convar, scope, min, func)
    if type(scope) == "function" then
        func = scope
        scope = convar
        min = 1
    elseif type(min) == "function" then
        func = min
        min = 1
    end

    if Convars:GetInt(convar) >= min then
        debugoverlay:PushDebugOverlayScope(scope)
        func()
        debugoverlay:PopDebugOverlayScope()
        -- debugoverlay:PushDebugOverlayScope("")
    end
end

---Draws the expected trajectory path for this phys object based on its current velocity.
---@param entity EntityHandle
---@param color? Vector
---@param scope? string
function DebugDrawTrajectory(entity, color, scope)
    local step = 0.05
    local maxSteps = 100

    if scope then
        debugoverlay:PushAndClearDebugOverlayScope(scope)
    end

    local simPos = entity:GetOrigin()
    local simVel = GetPhysVelocity(entity)

    local gravity = Vector(0,0,-Convars:GetFloat("sv_gravity"))
    local lastPos = simPos
    for i = 1, maxSteps do
        -- Apply gravity
        simVel = simVel + gravity * step

        -- Move forward
        simPos = simPos + simVel * step

        -- Draw line from lastPos → simPos
        DebugDrawLine(lastPos, simPos, 255, 255, 255, true, 30)

        -- Check if it hits something
        ---@type TraceTableHull
        local trace = {
            startpos = lastPos,
            endpos = simPos,
            ignore = entity,
            min = entity:GetBoundingMins(),
            max = entity:GetBoundingMaxs(),
        }
        TraceHull(trace)
        if trace.hit then
            DebugDrawCircle(simPos, color or Vector(), 255, 4, true, 30)
            break
        end

        lastPos = simPos
    end
end


local function HidePortalGunBlockers()
    for _, blocker in ipairs(Entities:FindAllByName("@PortalBlocker")) do
        blocker:SetOrigin(Vector(15000,15000,15000))
    end
end

local function ShowPortalGunBlockers()
    for _, blocker in ipairs(Entities:FindAllByName("@PortalBlocker")) do
        if blocker.startPos ~= nil then
            blocker:SetOrigin(blocker.startPos)
        end
    end
end

local function InitPortalGunBlockers()
    for _, blocker in ipairs(Entities:FindAllByName("@PortalBlocker")) do
        blocker.startPos = blocker:LoadVector("startpos", blocker:GetOrigin())
        blocker:SaveVector("startpos", blocker.startPos)
        blocker:SetOrigin(Vector(15000,15000,15000))
    end
end


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

---@return PortalColor
function PortalManager:GetPortalColor(name)
    return resolveColor(name)
end

---Sets a targetname as being allowed to be picked up by the portalgun or not.
---@param name string
---@param enabled boolean
function PortalManager:SetPickupNameEnabled(name, enabled)
    if enabled then
        ArrayRemoveVal(self.disabledPickupNames, name)
    else
        if not vlua.find(self.disabledPickupNames, name) then
            table.insert(self.disabledPickupNames, name)
        end
    end

    if not Player then
        warn("PortalManager cannot save disabledPickupNames because player doesn't exist")
    else
        Storage.SaveTable(Player, "PortalManager.disabledPickupNames", self.disabledPickupNames)
    end
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
    TraceLineIgnorePhysics(traceTable)
    -- if self:Debugging() then
    --     if traceTable.hit then
    --         DebugDrawLine(traceTable.startpos, traceTable.endpos, 255, 0, 0, true, 3)
    --     else
    --         DebugDrawLine(traceTable.startpos, traceTable.endpos, 0, 255, 0, true, 3)
    --     end
    -- end
    return traceTable
end

---@class TraceLinePortalable : TraceTableLine
---@field surfaceIsPortalable boolean

---@param entity EntityHandle
function IsPortalIgnorableEntity(entity)
    return
        entity == Player
        or entity:GetOwner() == Player
        or entity == PortalManager.portalGun
        or IsPhysicsObject(entity)
end

---Trace line while ignoring physics objects
---@param traceTable TraceTableLine
function TraceLineIgnorePhysics(traceTable)
    local ignore = traceTable.ignore

    local timeout = 0

    while TraceLine(traceTable) and traceTable.hit
    -- ignore physics objects
    and (IsPortalIgnorableEntity(traceTable.enthit)
    -- ignore the original ignored entity
    or (ignore ~= nil and traceTable.enthit == ignore)) do

        traceTable.hit = false
        traceTable.ignore = traceTable.enthit
        traceTable.enthit = nil
        traceTable.startpos = traceTable.pos

        timeout = timeout + 1
        if timeout > 10 then
            warn("PortalManager: TraceLineIgnorePhysics timed out")
            break
        end
    end

end

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
        mask = 4096 -- for transparency (glass)
    }

    ShowPortalGunBlockers()

    -- TraceLine(traceTable)
    TraceLineIgnorePhysics(traceTable)

    HidePortalGunBlockers()

    if traceTable.hit then

        local surfaceIsPortalable = true

        if self.AllowPortalsOnlyOnPrefixedEntities then
            if not traceTable.enthit:GetName():startswith(self.PortalableSurfaceNamePrefix) then
                surfaceIsPortalable = false
            end
        end

        -- Try to push the portal up against the wall instead of the portalable func
        if surfaceIsPortalable then
            ---@type TraceTableLine
            local traceTableAlign = {
                startpos = traceTable.pos,
                endpos = traceTable.pos + (-traceTable.normal) * 10,
                ignore = traceTable.enthit,
            }

            if traceTableAlign.hit then
                traceTable.pos = traceTableAlign.pos
                traceTable.normal = traceTableAlign.normal
            end
        end

        if Convars:GetInt("portal_debug_portalgun") >= 2 then
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

function PortalManager:GetOrientedPortalAngles(normal)
    local forward
    if Convars:GetBool("portal_orient_to_gun") and IsValidEntity(CurrentPortalGun) then
        forward = CurrentPortalGun:GetForwardVector()
    else
        forward = Player:GetWorldForward()
    end
    forward.z = 0
    forward = forward:Normalized()

    local xaxis = 0
    if math.isclose(normal.z, -1, 1e-7) then
        xaxis = 90 -- floor
        return RotateOrientation(VectorToAngles(forward), QAngle(xaxis, 0, 0))
    elseif math.isclose(normal.z, 1, 1e-7) then
        xaxis = -90 -- ceiling
        return RotateOrientation(VectorToAngles(forward), QAngle(xaxis, 0, 0))
    end

    return VectorToAngles(normal)
end

function CleanNormal(normal, epsilon)
    epsilon = epsilon or 0.01

    local x = math.abs(normal.x) < epsilon and 0 or (math.abs(normal.x) > 1 - epsilon and math.sign(normal.x) or normal.x)
    local y = math.abs(normal.y) < epsilon and 0 or (math.abs(normal.y) > 1 - epsilon and math.sign(normal.y) or normal.y)
    local z = math.abs(normal.z) < epsilon and 0 or (math.abs(normal.z) > 1 - epsilon and math.sign(normal.z) or normal.z)

    local cleaned = Vector(x, y, z)
    return cleaned:Normalized()
end

---Attempts to adjust the position of the portal to the nearest valid position.
---@param position Vector
---@param normalAngles QAngle
---@param colorName string
---@param maxAttempts number
---@return Vector|nil # Adjusted position or nil if failed
function PortalManager:PortalPositionAdjust(position, normalAngles, colorName, maxAttempts)

    local startingPosition = position
    position = position + normalAngles:Forward() * 1

    local normal = normalAngles:Forward()

    local stepSize = 1

    local hitUp, hitDown, hitLeft, hitRight

    ---@type {ent:EntityHandle,reason:string,dot:number}[]
    local debugents = {}
    local debugpath = {position}
    local totaltraces = 0

    local failhappened = false

    ---Trace in a direction
    ---@param direction Vector # Direction and distance
    ---@return boolean # If the trace hit or empty space behind
    local function trace(direction)
        -- First check if there is space for the portal in this direction
        local tr = self:TraceDirection(position, direction)
        totaltraces = totaltraces + 1
        if tr.hit then
            table.insert(debugents, {ent=tr.enthit,reason="hit"})
            return true
        end -- no space, return to move
        -- Then check if the space behind is valid
        tr = self:TraceDirection(position + direction, -normalAngles:Forward() * 3)
        totaltraces = totaltraces + 1
        if not tr.hit then
            table.insert(debugents,{reason="overhang"})
            return true
        end -- empty space behind (overhang), return to move
        if self.AllowPortalsOnlyOnPrefixedEntities and tr.enthit and not tr.enthit:GetName():startswith(self.PortalableSurfaceNamePrefix) then
            table.insert(debugents,{ent=tr.enthit,reason="badsurface"})
            return true
        end -- not a portalable surface
        if normal:Dot(tr.normal) < 0.99 then
            table.insert(debugents,{ent=tr.enthit,reason="angle",dot=normal:Dot(tr.normal)})
            return true
        end -- surface is angled differently
        return false
    end

    local function printdebug()
        print("Total traces: ",totaltraces)
        print("Total adjusts:", #debugpath - 1)
        ---@type {str:string,count:number}[]
        local entsseen = {}
        for _,en in ipairs(debugents) do
            local id = tostring(en.ent)..tostring(en.reason)
            if entsseen[id] then
                entsseen[id].count = entsseen[id].count + 1
            else
                if en.reason == "overhang" then
                    entsseen[id] = {str="Overhang",count=1}
                elseif en.reason == "angle" then
                    entsseen[id] = {str=string.format("%s : %s [%s] (%d)",en.reason,Debug.EntStr(en.ent),en.ent:GetEntityIndex(),en.dot),count=1}
                else
                    entsseen[id] = {str=string.format("%s : %s [%s]",en.reason,Debug.EntStr(en.ent),en.ent:GetEntityIndex()),count=1}
                end
            end
        end
        for k,v in pairs(entsseen) do
            print(v.str, "Times: "..tostring(v.count))
        end
    end

    local stepsX = Convars:GetInt("portal_sample_steps")
    local stepsY = Convars:GetInt("portal_sample_steps")

    print("left", normalAngles:Left())
    print("up", normalAngles:Up())
    print("forward", normalAngles:Forward())

    local existingPortals = self:GetAllPortals()

    local anySuccess = false

    for i = 1, maxAttempts do
        -- hitUp = trace(normalAngles:Up() * PORTAL_SIZE_Z / 2)
        -- hitDown = trace((-normalAngles:Up()) * PORTAL_SIZE_Z / 2)
        -- hitLeft = trace(normalAngles:Left() * PORTAL_SIZE_Y / 2)
        -- hitRight = trace((-normalAngles:Left()) * PORTAL_SIZE_Y / 2)

        -- if not hitUp and not hitDown and not hitLeft and not hitRight then
        --     DebugIf("portal_debug_portals", function()
        --         debugoverlay:Sphere(startingPosition, 0.75, 0, 255, 0, 255, true, 5)
        --         debugoverlay:HorzArrow(startingPosition, position, 1.5, 0, 255, 0, 255, true, 5)
        --         debugoverlay:VertArrow(startingPosition, position, 1.5, 0, 255, 0, 255, true, 5)
        --     end)
        --     return position - normalAngles:Forward() * 1
        -- end

        -- local moveX = 0
        -- local moveY = 0

        -- if hitUp then moveY = -stepSize end
        -- if hitDown then moveY = stepSize end
        -- if hitLeft then moveX = -stepSize end
        -- if hitRight then moveX = stepSize end

        -- local newPosition = position + (normalAngles:Left() * moveX) + (normalAngles:Up() * moveY)

        -- position = newPosition

        -- VV NEW CODE VV

        anySuccess = false
        failhappened = false

        local push = Vector(0, 0, 0)
        for ix = -stepsX, stepsX do
            for iy = -stepsY, stepsY do
                -- only check outer edges
                if ix == -stepsX or ix == stepsX or iy == -stepsY or iy == stepsY then
                    local offset =
                        normalAngles:Left() * (ix/stepsX * PORTAL_SIZE_Y/2) +
                        normalAngles:Up() * (iy/stepsY * PORTAL_SIZE_Z/2)
                    if i == 1 then
                        DebugIf("portal_debug_portals", function()
                            debugoverlay:Line(position, position + offset, 255, 0, 0, 255, false, 5)
                            debugoverlay:Sphere(position + offset, 1, 0, 255, 0, 255, false, 5)
                            debugoverlay:Line(position + offset, position + offset + (-normalAngles:Forward() * 3), 0, 0, 255, 255, false, 5)
                        end)
                    end
                    if trace(offset) then
                        failhappened = true
                        push = push - offset -- push away from hit sample
                    else
                        -- check intersecting portals
                        local blocked = false
                        for _, portal in ipairs(existingPortals) do
                            if portal.colorName ~= colorName then
                                local localPosition = portal:TransformPointWorldToEntity(position + offset)
                                if abs(localPosition.x) < PORTAL_SIZE_X/2
                                and abs(localPosition.y) < PORTAL_SIZE_Y/2
                                and abs(localPosition.z) < PORTAL_SIZE_Z/2 then
                                    failhappened = true
                                    blocked = true
                                    table.insert(debugents,{ent=portal,reason="portal"})
                                    push = push - offset -- push away from hit sample
                                end
                            end
                        end

                        if not blocked then
                            anySuccess = true
                        end
                    end
                end
            end
        end

        push = CleanVector(push)

        if not anySuccess then
            print('breaking')
            break
        end

        -- print("push", Debug.SimpleVector(push))
        if push:Length() > 0 then
            push = push:Normalized()
            -- print("push normalized", Debug.SimpleVector(push))
            -- print("","Adjust portal",i,Debug.SimpleVector(position),Debug.SimpleVector(push),Debug.SimpleVector(position + push * stepSize))
            position = position + push * stepSize
            table.insert(debugpath, position)
            -- position = position + push * (PORTAL_SIZE_Y/2 + PORTAL_SIZE_Z/2)
        else
            if not failhappened then
                if #debugpath > 1 then
                    DebugIf("portal_debug_portals", function()
                        for j = 1, #debugpath - 1 do
                            debugoverlay:HorzArrow(debugpath[j], debugpath[j + 1], 1.5, 0, 255, 0, 255, true, 5)
                            debugoverlay:VertArrow(debugpath[j], debugpath[j + 1], 1.5, 0, 255, 0, 255, true, 5)
                        end
                        -- debugoverlay:Sphere(startingPosition, 0.75, 0, 255, 0, 255, true, 5)
                        -- debugoverlay:HorzArrow(startingPosition, position, 1.5, 0, 255, 0, 255, true, 5)
                        -- debugoverlay:VertArrow(startingPosition, position, 1.5, 0, 255, 0, 255, true, 5)
                    end)
                end
                print("Portal adjust found valid position")
                print("Success results:")
                printdebug()
                return position - normalAngles:Forward() * 1
            else
                -- nowhere to move, exit
                break
            end
        end

        if i == maxAttempts then
            print("Reached max attempts")
        end
    end

    -- if Convars:GetInt("portal_debug_portalgun") >= 1 then
    DebugIf("portal_debug_portals", function()
        debugoverlay:Text(startingPosition, 0, "Failed to find position for portal", 0, 255, 0, 0, 255, 5)
        if #debugpath > 1 then
            for j = 1, #debugpath - 1 do
                debugoverlay:HorzArrow(debugpath[j], debugpath[j + 1], 1.5, 255, 0, 0, 255, true, 5)
                debugoverlay:VertArrow(debugpath[j], debugpath[j + 1], 1.5, 255, 0, 0, 255, true, 5)
            end
        end
    end)

    print("Failed to find position for portal")
    print("Fail results:")
    printdebug()
    -- print("Total traces: ",totaltraces)
    -- print("Total adjusts:", #debugpath - 1)
    -- ---@type {str:string,count:number}[]
    -- local entsseen = {}
    -- for _,en in ipairs(debugents) do
    --     local id = tostring(en.ent)..tostring(en.reason)
    --     if entsseen[id] then
    --         entsseen[id].count = entsseen[id].count + 1
    --     else
    --         if en.reason == "overhang" then
    --             entsseen[id] = {str="Overhang",count=1}
    --         elseif en.reason == "angle" then
    --             entsseen[id] = {str=string.format("%s : %s [%s] (%n)",en.reason,Debug.EntStr(en.ent),en.ent:GetEntityIndex(),en.dot),count=1}
    --         else
    --             entsseen[id] = {str=string.format("%s : %s [%s]",en.reason,Debug.EntStr(en.ent),en.ent:GetEntityIndex()),count=1}
    --         end
    --     end
    -- end

    return nil
end

---Try to open a portal at a given `position`, checking to make sure it can fit.
---@param position Vector # World position to open the portal at.
---@param normal Vector # Normalized direction the portal should face.
---@param color PortalColor|string # Color of the portal, must be an existing color.
---@param reorientToPlayer? boolean # If true, the portal will be reoriented to be perpendicular to the player when placed on the ground or ceiling.
---@return boolean # Returns true if the portal successfully opened, false otherwise.
function PortalManager:TryCreatePortalAt(position, normal, color, reorientToPlayer)
    normal = CleanNormal(normal)
    print('\nNORMAL'..tostring(Debug.SimpleVector(normal))..'\n')
    color = resolveColor(color)

    local normalAngles = VectorToAngles(normal)

    if reorientToPlayer then
        -- if Convars:GetBool("portal_orient_to_gun") then
        --     local forward = CurrentPortalGun:GetForwardVector()
        --     forward.z = 0
        --     forward = forward:Normalized()
        --     local a= normalAngles
        --     normalAngles = self:ReorientPortalPerpendicular(normal, forward)
        --     print("orient by gun", Debug.SimpleVector(a), Debug.SimpleVector(normalAngles))
        -- else
        --     normalAngles = self:ReorientPortalPerpendicular(normal, Player:GetWorldForward())
        -- end

        -- local forward = Convars:GetBool("portal_orient_to_gun") and CurrentPortalGun:GetForwardVector() or Player:GetWorldForward()
        -- forward.z = 0
        -- forward = forward:Normalized()

        -- local xaxis = 0
        -- if math.isclose(normal.z, -1, 1e-7) then
        --     xaxis = 90 -- floor
        --     normalAngles = VectorToAngles(forward)
        --     normalAngles = RotateOrientation(normalAngles, QAngle(xaxis, 0, 0))
        -- elseif math.isclose(normal.z, 1, 1e-7) then
        --     xaxis = -90 -- ceiling
        --     normalAngles = VectorToAngles(forward)
        --     normalAngles = RotateOrientation(normalAngles, QAngle(xaxis, 0, 0))
        -- end
        normalAngles = self:GetOrientedPortalAngles(normal)
        
    end

    print("\nDoing portal adjustment, beware spam:\n")
    position = self:PortalPositionAdjust(position, normalAngles, color.name, PORTAL_SIZE_Y*2)
    print("\nFinished portal adjustment\n")

    if position == nil then
        return false
    end

    -- ---@TODO This only checks the connected portal, it should check all portals
    -- local otherPortal = PortalManager:GetConnectedPortal(color)
    -- if otherPortal ~= nil then
    --     local localPosition = otherPortal:TransformPointWorldToEntity(position)
    --     if abs(localPosition.y) < PORTAL_SIZE_Y  and abs(localPosition.z) < PORTAL_SIZE_Z and abs(localPosition.x) < 20 then
    --         return false
    --     end
    -- end

    PortalManager:CreatePortalAt(position, normal, color, reorientToPlayer)
    return true
end

---Create a portal at a position with a direction.
---@param position Vector
---@param normal Vector
---@param color PortalColor|string
---@param reorientToPlayer? boolean # If true, the portal will be reoriented to be perpendicular to the player when placed on the ground or ceiling.
function PortalManager:CreatePortalAt(position, normal, color, reorientToPlayer)
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
    newPortal:Open(position, normal, color, reorientToPlayer)

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
        portal:Close()
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

---Get if any portal is open.
function PortalManager:IsAnyPortalOpen()
    for index, value in ipairs(Entities:FindAllByClassname("logic_script")) do
        if isinstance(value, "Portal") then
            return true
        end
    end
end

---Gets the nearest `Portal` entity to a given position.
---@param origin Vector
---@param maxRadius number
---@return Portal?
function PortalManager:GetNearestPortal(origin, maxRadius)
    ---@NOTE logic_script can't be found with FindAllByClassnameWithin for some reason
    ---@TODO Provide built-in way to get all portals
    for _, script in ipairs(Entities:FindAllByClassname("logic_script")) do
        if isinstance(script, "Portal") and VectorDistance(script:GetAbsOrigin(), origin) <= maxRadius then
            return script--[[@as Portal]]
        end
    end
end

---Gets the nearest `Portal` entity to a given position within a bounding box.
---@param origin Vector
---@param mins Vector
---@param maxs Vector
---@param maxRadius number
---@return Portal?
function PortalManager:GetNearestPortalInBounds(origin, mins, maxs, maxRadius)
    local best, bestDistance = nil, math.huge
    for _, script in ipairs(Entities:FindAllByClassname("logic_script")) do
        if isinstance(script, "Portal") and script:IsWithinBounds(origin + mins, origin + maxs) then
            local distance = VectorDistance(script:GetAbsOrigin(), origin)
            if distance <= maxRadius and distance < bestDistance then
                best, bestDistance = script, distance
            end
        end
    end
    return best
end

---Gets a list of all `Portal` entities in the map.
---@return Portal[]
function PortalManager:GetAllPortals()
    local all = {}
    for _, script in ipairs(Entities:FindAllByClassname("logic_script")) do
        if isinstance(script, "Portal") then
            table.insert(all, script)
        end
    end
    return all
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

---Get the trigger_multiple associated with a portal color.
---@param color PortalColor|string
---@return PortalTeleport?
function PortalManager:GetPortalTeleport(color)
    color = resolveColor(color)
    return Entities:FindByName(nil, "_PortalTeleport" .. color.name)--[[@as PortalTeleport]]
end

---Get the debug camera entity associated with a portal color.
---@param color PortalColor|string
---@return EntityHandle?
function PortalManager:GetPortalDebugCamera(color)
    color = resolveColor(color)
    return Entities:FindByName(nil, "_PortalDebugCamera" .. color.name)
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
    if not Entities:GetLocalPlayer() then
        warn("PortalManager cannot save PortalableSurfaceNamePrefix because player doesn't exist")
        return
    end
    Entities:GetLocalPlayer():SaveString("PortalableSurfaceNamePrefix", self.PortalableSurfaceNamePrefix)
end

---Sets if portals can only be placed on name prefixed entities or if they can be placed anywhere.
---@param allow boolean
function PortalManager:SetAllowPortalsOnlyOnPrefixedEntities(allow)
    self.AllowPortalsOnlyOnPrefixedEntities = truthy(allow)
    if not Entities:GetLocalPlayer() then
        Warning("PortalManager cannot save AllowPortalsOnlyOnPrefixedEntities because player doesn't exist\n")
        return
    end
    Entities:GetLocalPlayer():SaveBoolean("AllowPortalsOnlyOnPrefixedEntities", self.AllowPortalsOnlyOnPrefixedEntities)
end

---Create a failed portal opening effect.
---@param pos Vector
---@param dir Vector
---@param color "blue"|"orange" # Must specify blue or orange until particle is fixed
-----@param color Vector
function PortalManager:CreateFailedPortalEffect(pos, dir, color)
    StartSoundEventFromPositionReliable("PortalGun.Shoot.Fail", pos)

    -- orange is used for other colors
    local ppath = "particles/portal_projectile/portal_2_badsurface.vpcf"

    if color == "blue" then
        ppath = "particles/portal_projectile/portal_1_badsurface.vpcf"
    elseif color == "orange" then
        ppath = "particles/portal_projectile/portal_2_badsurface.vpcf"
    end

    local pindex = ParticleManager:CreateParticle(ppath, 0, Player)
    ParticleManager:SetParticleControl(pindex, 0, pos + dir)

end

-- Loading values
ListenToPlayerEvent("player_activate", function (params)
    PortalManager.PortalableSurfaceNamePrefix = Player:LoadString("PortalableSurfaceNamePrefix", PortalManager.PortalableSurfaceNamePrefix)
    PortalManager.AllowPortalsOnlyOnPrefixedEntities = Player:LoadBoolean("AllowPortalsOnlyOnPrefixedEntities", PortalManager.AllowPortalsOnlyOnPrefixedEntities)
    PortalManager.colors = Player:LoadTable("PortalColors", PortalManager.colors)
    PortalManager.disabledPickupNames = Player:LoadTable("PortalManager.disabledPickupNames", PortalManager.disabledPickupNames)

    InitPortalGunBlockers()
end)

-- Hack to save portalable values
ListenToGameEvent("player_spawn", function()
    PortalManager:SetPortalableSurfaceNamePrefix(PortalManager.PortalableSurfaceNamePrefix)
    PortalManager:SetAllowPortalsOnlyOnPrefixedEntities(PortalManager.AllowPortalsOnlyOnPrefixedEntities)
end, nil)

Convars:RegisterCommand("portalgun_give", function (_, ...)
    local portalgun = Entities:FindByName(nil, "@PortalGun")--[[@as PortalGun]]

    if Convars:GetBool("portalgun_is_physical") then
        if portalgun == nil then
            -- portalgun = SpawnEntityFromTableAsynchronous("item_hlvr_weapon_generic_pistol", {
            --     targetname = "@PortalGun",

            --     -- Required to attach script to gun in hand
            --     vscripts = "portal/classes/portalgun_item",

            --     origin = Player:GetOrigin() + Vector(0, 0, 10),

            --     inventory_name = "portalgun",
            --     inventory_model = "models/vrportal/portalgun.vmdl",
            --     model = "models/vrportal/portalgun.vmdl",
            --     model_right_handed = "models/vrportal/portalgun.vmdl",
            --     model_left_handed = "models/vrportal/portalgun.vmdl",

            --     inventory_position = "1",

            --     set_spawn_ammo = "-1",
            --     ammo_per_clip = "0",
            --     damage = "0",
            --     attack_interval = "0.175",
            --     clip_grab_dist = "8.0",
            --     bullet_count_anim_rate = "1.0",
            --     slide_interact_min_dist = "6.0",
            --     slide_interact_max_dist = "6.0",
            --     bottom_grip_min_dist = "4.0",
            --     bottom_grip_max_dist = "4.5",
            --     bottom_grip_disengage_dist = "5.0",

            --     -- Unsure if these need null assets
            --     -- or can just be completely omitted
            --     slide_model_right_handed = "",
            --     slide_model_left_handed = "",
            --     clip_model_right_handed = "",
            --     clip_model_left_handed = "",
            --     single_bullet_model = "",
            --     eject_shell_model = "",
            --     shoot_sound = "",
            --     no_ammo_sound = "",
            --     last_shot_chambered = "",
            --     slide_lock_sound = "",
            --     slide_back_sound = "",
            --     slide_close_sound = "",
            --     clip_insert_sound = "",
            --     clip_release_sound = "",
            --     muzzle_flash_effect = "",
            --     tracer_effect = "",
            --     eject_shell_smoke_effect = "",
            --     glow_effect = "",
            --     barrel_smoke_effect = "",
            --     clip_glow_effect = "",
            -- }, function(gun)
            --     print("gun spawned")
            --     Player:SetWeapon("hand_use_controller")
            --     portalgun:Grab(Player.PrimaryHand)
            --     portalgun:EntFire("Use", "1", 0, Player, Player)
            -- end, {})
            warn("Could not find a portalgun item! Make sure the prefab was placed in the map!")
            return
        end
        Player:SetWeapon("hand_use_controller")
        portalgun:Grab(Player.PrimaryHand)
        -- portalgun:EntFire("Use", "1", 0, Player, Player)
    else
        if portalgun == nil then
            portalgun = SpawnEntityFromTableSynchronous("npc_furniture", {
                targetname = "@PortalGun",
                model = "models/vrportal/portalgun.vmdl",
                vscripts = "portal/entities/portalgun",
            })--[[@as PortalGun]]
        end
        portalgun:AttachToHand()
    end
end, "", 0)

Convars:RegisterCommand("close_all_portals", function (_, ...)
    PortalManager:CloseAllPortals()
end, "", 0)
