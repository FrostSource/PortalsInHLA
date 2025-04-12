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
PortalManager.AllowPortalsOnlyOnPrefixedEntities = false

---The prefix part that must be on portalable surface entities.
PortalManager.PortalableSurfaceNamePrefix = ""

---List of targetnames the portalgun cannot pickup
---@type string[]
PortalManager.disabledPickupNames = {}


Convars:RegisterConvar("portal_debug_portals", "0", "Shows debugging visuals for portals", 0)
Convars:RegisterConvar("portal_debug_portalgun", "0", "Shows debugging visuals for the portalgun", 0)
Convars:RegisterConvar("portal_debug_portal_rendering", "0", "Shows debugging visuals for portal rendering", 0)
Convars:RegisterCommand("portal_debug_clear", function()
    Convars:SetInt("portal_debug_portal_rendering", 0)
    debugoverlay:RemoveAllInScope("portaldebug")
    ---@TODO Create function for looping portals
    for name in pairs(PortalManager.colors) do
        local portal = PortalManager:GetPortal(name)
        if portal then
            portal:ClearDebug()
        end
    end
end, "Clears all debugging visuals (only needed for portal_debug_portal_rendering)", 0)

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
    TraceLine(traceTable)

    local timeout = 0

    while traceTable.hit
    -- ignore physics objects
    and (IsPortalIgnorableEntity(traceTable.enthit)
    -- ignore the original ignored entity
    or (ignore ~= nil and traceTable.enthit == ignore)) do
        traceTable.hit = false
        traceTable.ignore = traceTable.enthit
        traceTable.startpos = traceTable.pos
        TraceLine(traceTable)


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

---@param position Vector
---@param normalAngles QAngle
---@param maxAttempts number
---@return Vector|nil # Adjusted position or nil if failed
function PortalManager:TestPortalPositionAdjust(position, normalAngles, maxAttempts)

    local startingPosition = position
    position = position + normalAngles:Forward() * 1

    local stepSize = 1

    local hitUp, hitDown, hitLeft, hitRight

    ---Trace in a direction
    ---@param direction Vector # Direction and distance
    ---@return boolean # If the trace hit or empty space behind
    local function trace(direction)
        local tr = self:TraceDirection(position, direction)
        if tr.hit then return true end
        tr = self:TraceDirection(position + direction, -normalAngles:Forward() * 30)
        if not tr.hit then return true end
        return false
    end

    for i = 1, maxAttempts do
        hitUp = trace(normalAngles:Up() * PORTAL_SIZE_Z / 2)
        hitDown = trace((-normalAngles:Up()) * PORTAL_SIZE_Z / 2)
        hitLeft = trace(normalAngles:Left() * PORTAL_SIZE_Y / 2)
        hitRight = trace((-normalAngles:Left()) * PORTAL_SIZE_Y / 2)
        -- local UpTrace = self:TraceDirection(position, normalAngles:Up())
        -- if not UpTrace.hit then
        --     UpTrace = self:TraceDirection(position + normalAngles:Up() * PORTAL_SIZE_Z / 2, -normalAngles:Forward() * 30)
        --     if not UpTrace.hit then hitUp = true end
        -- else hitUp = true end

        -- local DownTrace = self:TraceDirection(position, (-normalAngles:Up()) * PORTAL_SIZE_Z / 2)
        -- local hitDown = DownTrace.hit
        -- local LeftTrace = self:TraceDirection(position, normalAngles:Left() * PORTAL_SIZE_Y / 2)
        -- local hitLeft = LeftTrace.hit
        -- local RightTrace = self:TraceDirection(position, (-normalAngles:Left()) * PORTAL_SIZE_Y / 2)
        -- local hitRight = RightTrace.hit

        if not hitUp and not hitDown and not hitLeft and not hitRight then
            if Convars:GetInt("portal_debug_portals") >= 1 then
                debugoverlay:Sphere(startingPosition, 0.75, 255, 0, 0, 255, true, 5)
                debugoverlay:HorzArrow(startingPosition, position, 1.5, 255, 0, 0, 255, true, 5)
                debugoverlay:VertArrow(startingPosition, position, 1.5, 255, 0, 0, 255, true, 5)
            end
            return position - normalAngles:Forward() * 1
        end

        local moveX = 0
        local moveY = 0

        if hitUp then moveY = -stepSize end
        if hitDown then moveY = stepSize end
        if hitLeft then moveX = -stepSize end
        if hitRight then moveX = stepSize end

        local newPosition = position + (normalAngles:Left() * moveX) + (normalAngles:Up() * moveY)

        position = newPosition
    end

    if Convars:GetInt("portal_debug_portalgun") >= 1 then
        debugoverlay:Text(startingPosition, 0, "Failed to find position for portal", 0, 255, 0, 0, 255, 5)
    end

    return nil
end

---Try to open a portal at a given `position`, checking to make sure it can fit.
---@param position Vector # World position to open the portal at.
---@param normal Vector # Normalized direction the portal should face.
---@param color PortalColor|string # Color of the portal, must be an existing color.
---@return boolean # Returns true if the portal successfully opened, false otherwise.
function PortalManager:TryCreatePortalAt(position, normal, color)
    color = resolveColor(color)
    local normalAngles = self:ReorientPortalPerpendicular(normal, Player:GetWorldForward())

    -- local UpTrace = self:TraceDirection(position + normalAngles:Forward() * 10, normalAngles:Up() * PORTAL_SIZE_Z / 2)
    -- if not UpTrace.hit then
    --     UpTrace = self:TraceDirection(UpTrace.endpos, -normalAngles:Forward() * 30)
    --     if not UpTrace.hit then
    --         return false
    --     end
    -- else
    --     return false
    -- end
    -- local DownTrace = self:TraceDirection(position+normalAngles:Forward() * 10, (-normalAngles:Up()) * PORTAL_SIZE_Z / 2)
    -- if not DownTrace.hit then
    --     DownTrace = self:TraceDirection(DownTrace.endpos, -normalAngles:Forward() * 30)
    --     if not DownTrace.hit then
    --         return false
    --     end
    -- else
    --     return false
    -- end
    -- local LeftTrace = self:TraceDirection(position + normalAngles:Forward() * 10, normalAngles:Left() * PORTAL_SIZE_Y / 2)
    -- if not LeftTrace.hit then
    --     LeftTrace = self:TraceDirection(LeftTrace.endpos, -normalAngles:Forward() * 30)
    --     if not LeftTrace.hit then
    --         return false
    --     end
    -- else
    --     return false
    -- end
    -- local RightTrace = self:TraceDirection(position+normalAngles:Forward() * 10, (-normalAngles:Left()) * PORTAL_SIZE_Y / 2)
    -- if not RightTrace.hit then
    --     RightTrace = self:TraceDirection(RightTrace.endpos, -normalAngles:Forward() * 30)
    --     if not RightTrace.hit then
    --         return false
    --     end
    -- else
    --     return false
    -- end

    position = self:TestPortalPositionAdjust(position, normalAngles, PORTAL_SIZE_Y)

    if position == nil then
        return false
    end

    ---@TODO This only checks the connected portal, it should check all portals
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

    -- For color changing particle (broken)
    -- local pindex = ParticleManager:CreateParticle("particles/portal_projectile/portal_badsurface.vpcf", 0, Player)
    -- ParticleManager:SetParticleControl(pindex, 0, pos + dir)
    -- ParticleManager:SetParticleControl(pindex, 2, color)
    SendToConsole("cl_particles_dumplist")
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
