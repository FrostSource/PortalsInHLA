

local MIN_STEP_NORMAL = 0.7 -- Minimum normal Z for walkable surface

local MIN_CHASM_HEIGHT = 64

local playerOnGround = true
local playerGroundNormal = Vector(0, 0, 1)
local currentPlayerOrigin = Vector()
local currentPlayerVelocity = Vector()

local PLAYER_GIRTH = 7
local PLAYER_HEIGHT = 96

local MIN_FLING_SPEED = 300

local currentWhooshVolume = 0

local playerIsTeleporting = false

EasyConvars:RegisterConvar("portal_woosh_always", "0", "Always adjust the woosh instead of just when flinging")
EasyConvars:SetPersistent("portal_woosh_always", true)

local mapFlingTriggers = {
    -- first area
    "fall_input_modifier",
    "fall_trigger",
    "fall_fade_out",
    "fall_fade_in",
    "fall_teleport1_destination",
    "fall_audio1",
    "fall_teleport1",
    "fall1_triggeronce",

    -- second area
    "fall2_trigger_spawn",
    "fall3_trigger_spawn",
    "fall4_trigger_spawn",
    "fall2_triggeronce",
    "fall3_triggeronce",
    "fall4_triggeronce",
    "fall_audio2",
    "fall_audio3",
    "fall_audio4",
    "fall2_trigger",
    "fall3_trigger",
    "fall4_trigger",
    "fall_teleport2_destination",
    "fall_teleport3_destination",
    "fall_teleport4_destination",
    "fall_teleport2",
    "fall_teleport3",
    "fall_teleport4",
    "fall3_trigger_spawn_RL",
    "fall4_trigger_spawn_RL",
    "EnableFall3Trigger",
}

---@param trigger EntityHandle
local function hideFlingTrigger(trigger, hide)
    if hide == nil then
        hide = true
    end

    if hide then
        if not trigger:HasAttribute("FlingTriggerHidden") then
            print("Hiding fling trigger", trigger:GetName())
            local startingZ = trigger:Attribute_GetFloatValue("StartingZ", trigger:GetAbsOrigin().z)
            trigger:Attribute_SetFloatValue("StartingZ", startingZ)
            trigger:SetIntAttr("FlingTriggerHidden", 1)
            -- move trigger high up so it doesn't hit the player
            trigger:SetAbsOrigin(trigger:GetAbsOrigin() + Vector(0, 0, 10000))
        end
    else
        if trigger:HasAttribute("FlingTriggerHidden") then
            print("Unhiding fling trigger", trigger:GetName())
            local startingZ = trigger:Attribute_GetFloatValue("StartingZ", trigger:GetAbsOrigin().z)
            trigger:DeleteAttribute("FlingTriggerHidden")
            -- move trigger back down
            local origin = trigger:GetAbsOrigin()
            trigger:SetAbsOrigin(Vector(origin.x, origin.y, startingZ))
        end
    end
end

EasyConvars:RegisterConvar("portal_physical_flings", "1", "Flings will use custom physics simulation", 0, function (newVal, oldVal)
    if truthy(newVal) == truthy(oldVal) then
        return
    end

    if Convars:GetBool("portal_physical_flings") then
        for _,triggerName in pairs(mapFlingTriggers) do
            local trigger = Entities:FindByName(nil, triggerName)
            if trigger then
                hideFlingTrigger(trigger, true)
            end
        end
    else
        for _,triggerName in pairs(mapFlingTriggers) do
            local trigger = Entities:FindByName(nil, triggerName)
            if trigger then
                hideFlingTrigger(trigger, false)
            end
        end
    end
end)
EasyConvars:SetPersistent("portal_physical_flings", true)

---Controls player falling into chasms.
PortalPlayerController = {}

---@type PortalPlayerPhys?
PortalPlayerController.currentPlayerPhys = nil

---@param params PlayerEventItemPickup
ListenToPlayerEvent("item_pickup", function (params)
    if params.item then
        if params.item.portalPrevOwner == nil then
            params.item.portalPrevOwner = params.item:GetOwner()
            params.item:SetOwner(Player)
        end
    end
end)

---@param params PlayerEventItemReleased
ListenToPlayerEvent("item_released", function (params)
    if params.item then
        -- Make sure item isn't being held by either hand for two handed pickups
        if not Player:IsHolding(params.item) then
            params.item:Delay(function()
                print("item released, resetting owner")
                params.item:SetOwner(params.item.portalPrevOwner)
                params.item.portalPrevOwner = nil
            end, 0)
        end
    end
end)

---@param params GameEventPlayerTeleportStart
ListenToGameEvent("player_teleport_start", function (params)
    playerIsTeleporting = true
end, nil)
---@param params GameEventPlayerTeleportFinish
ListenToGameEvent("player_teleport_finish", function (params)
    playerIsTeleporting = false
end, nil)

function PortalPlayerController:UpdateWhooshSound(override)
    local whooshVolume = self:GetPlayerVelocity():Length() - MIN_FLING_SPEED

    if override then
        whooshVolume = override
    else
        if whooshVolume < 0 then
            whooshVolume = 0
        else
            whooshVolume = whooshVolume / 2000
            if whooshVolume > 1 then
                whooshVolume = 1
            end

            whooshVolume = math.trunc(whooshVolume, 3)
        end
    end

    if whooshVolume ~= currentWhooshVolume then
        -- valve changes over time of 0.1, this would need a think to replicate
        DoEntFire("@FallWhooshParam", "SetFloatValue", tostring(whooshVolume), 0, nil, nil)
        currentWhooshVolume = whooshVolume
    end
end

function PortalPlayerController:GetPlayerHull()
    return
    {
        mins = Vector(-PLAYER_GIRTH, -PLAYER_GIRTH, 0);
        maxs = Vector(PLAYER_GIRTH, PLAYER_GIRTH, PLAYER_HEIGHT);
    }
end

---Traces player hull aganist solids from phys object's current location to an offset.
---@return TraceTableHull
function PortalPlayerController:TracePlayerSpace(startPos, endPos)

	local startpos = startPos
	local endpos = endPos

	-- local justLaunched = false--Time() - self.launchTime < PLAYER_LAUNCH_BBOX_OFFSET_DURATION
	-- local minZ = justLaunched and PLAYER_LAUNCH_BBOX_HEIGHT_OFFSET or 0
    local minZ = 0

	local min = Vector(-PLAYER_GIRTH, -PLAYER_GIRTH, minZ)
	local max = Vector(PLAYER_GIRTH, PLAYER_GIRTH, PLAYER_HEIGHT)

	local traceTable =
	{
		startpos = startpos;
		endpos = endpos;
		ignore = Player;
		mask =  33636363; -- TRACE_MASK_PLAYER_SOLID from L4D2 script API, may not be correct for Source 2.
		min = min;
		max = max
	}
	TraceHull(traceTable)
	-- if DEBUG then
	-- 	local color = traceTable.hit and Vector(255, 0, 0) or Vector(0, 255, 0)
	-- 	debugoverlay:Box(startpos + traceTable.min, startpos + traceTable.max, color.x, color.y, color.z, 170, false, 0)
	-- 	debugoverlay:Box(endpos + traceTable.min, endpos + traceTable.max, color.x, color.y, color.z, 170, false, 0)
	-- 	--debugoverlay:SweptBox(startpos, endpos, min, max, {x = 0; y = 0; z = 0; w = 1;}, 0, 255, 0, 255, 10)
	-- end

	return traceTable
end

local function CheckGround()
    -- ---@type TraceTableHull
    -- local trace = {
    --     startpos = Player:GetAbsOrigin(),
    --     endpos = Player:GetAbsOrigin() + Vector(0, 0, -2),
    --     min = Vector(-PLAYER_RADIUS, -PLAYER_RADIUS, 0),
    --     max = Vector(PLAYER_RADIUS, PLAYER_RADIUS, PLAYER_HEIGHT),
    --     ignore = Player
    -- }
    -- TraceHull(trace)
    local trace = PortalPlayerController:TracePlayerSpace(Player:GetAbsOrigin(), Player:GetAbsOrigin() + Vector(0, 0, -2))
    debugoverlay:Line(Player:GetAbsOrigin(), Player:GetAbsOrigin() + Vector(0, 0, -2), 255, 255, 255, 255, false, 0)
    debugoverlay:Sphere(Player:GetAbsOrigin(), 1, 255, 255, 0, 255, true, 0)
    debugoverlay:Sphere(Player:GetAbsOrigin() + Vector(0, 0, -2), 1, 0, 0, 255, 255, true, 0)

    -- print(trace.enthit:GetClassname())
    -- if trace.hit and trace.normal.z >= MIN_STEP_NORMAL then
    if trace.hit then
        -- print("Hit ground")
        -- playerOnGround = true
        playerGroundNormal = trace.normal
        
        -- -- Adjust position to stay on ground
        -- if trace.fraction < 1.0 then
        --     Player:SetAbsOrigin(trace.pos)
        -- end
        debugoverlay:Box(trace.startpos + trace.min, trace.startpos + trace.max, 255, 0, 0, 170, false, 0)
        return true
    else
        -- print("no git ground")
        -- playerOnGround = false
        playerGroundNormal = Vector(0, 0, 1)
        debugoverlay:Box(trace.startpos + trace.min, trace.startpos + trace.max, 0, 255, 0, 170, false, 0)
        return false
    end
end

local cacheVelocity = Vector(0, 0, 0)
local cacheTime = Time()

local cacheBounceVelocity = Vector(0, 0, 0)
local cacheBounceTime = Time()

function PortalPlayerController:CacheVelocity(velocity)
    cacheVelocity = velocity
    cacheTime = Time()
end
function PortalPlayerController:GetCachedVelocity()
    if Time() - cacheTime > 0.1 then
        return nil
    end
    return cacheVelocity
end
function PortalPlayerController:ClearCache()
    cacheVelocity = Vector(0, 0, 0)
    cacheTime = 0
end

function PortalPlayerController:CacheBounceVelocity(velocity)
    cacheBounceVelocity = velocity
    cacheBounceTime = Time()
end
function PortalPlayerController:GetCachedBounceVelocity()
    if Time() - cacheBounceTime > 0.1 then
        return nil
    end
    return cacheBounceVelocity
end
function PortalPlayerController:ClearBounceCache()
    cacheBounceVelocity = Vector(0, 0, 0)
    cacheBounceTime = 0
end

local function CleanVector(vec, threshold)
    threshold = threshold or 1e-6

    local x = math.abs(vec.x) < threshold and 0 or vec.x
    local y = math.abs(vec.y) < threshold and 0 or vec.y
    local z = math.abs(vec.z) < threshold and 0 or vec.z

    return Vector(x, y, z)
end

function PortalPlayerController:GetPlayerVelocity()
    local velocity = Vector()
    if IsValidEntity(self.currentPlayerPhys) then
        velocity = self.currentPlayerPhys.velocity
    else
        velocity = self:GetCachedVelocity()
        if not velocity then
            ---@TODO 100 seems too high, find good multiplier
            -- velocity = (Player:GetAbsOrigin() - currentPlayerOrigin) * 100
            velocity = currentPlayerVelocity
        end
    end

    return CleanVector(velocity)
end

function PortalPlayerController:SetPlayerVelocity(velocity)
    local playerPhys = self:GetOrCreatePlayerPhys(velocity)
    playerPhys:SetVelocity(velocity)
end

function PortalPlayerController:GetOrCreatePlayerPhys(initialVelocity)
    if IsValidEntity(self.currentPlayerPhys) then
        return self.currentPlayerPhys
    else
        playerOnGround = false
        local velocity = initialVelocity or self:GetPlayerVelocity()
        velocity = CleanVector(velocity)

        local physEnt = SpawnEntityFromTableSynchronous("prop_dynamic_override", {
            origin = Player:GetAbsOrigin(),-- + Vector(0,0,4),
            angles = Player.HMDAnchor:GetAngles(),
            targetname = "catapult_player_physics",
            vscripts = "portal/classes/playerphys",
            velocity_x = tostring(velocity.x),
            velocity_y = tostring(velocity.y),
            velocity_z = tostring(velocity.z),
            model = "models/props/choreo/ghost_speaker.vmdl",
            solid = "0",
            ScriptedMovement = "1",
        })
        self.currentPlayerPhys = physEnt
        return physEnt
    end
end

function PortalPlayerController:PlayerLandedOnGround()
    playerOnGround = true
end

function PortalPlayerController:IsPlayerOnGround()
    return playerOnGround
end

function PortalPlayerController:Enable()

    currentPlayerOrigin = Player:GetAbsOrigin()

    Player:SetContextThink("PortalFallThink", function()

        currentPlayerVelocity = (Player:GetAbsOrigin() - currentPlayerOrigin) * 100

        if Convars:GetBool("portal_woosh_always") or PortalPlayerController.currentPlayerPhys ~= nil then
            PortalPlayerController:UpdateWhooshSound()
        end

        if playerOnGround and not playerIsTeleporting and not (Player:IsNoclipping() or Convars:GetBool("noclip_vr_enabled")) then
            if not CheckGround() then
                -- Check if fall height is high enough
                local trace = PortalPlayerController:TracePlayerSpace(Player:GetAbsOrigin(), Player:GetAbsOrigin() + Vector(0, 0, -MIN_CHASM_HEIGHT))
                if not trace.hit then
                    print("Player falling")
                    local bounceVelocity = PortalPlayerController:GetCachedBounceVelocity()
                    if bounceVelocity then
                        PortalPlayerController:ClearBounceCache()
                        PortalPlayerController:CacheVelocity(bounceVelocity)
                    end
                    PortalPlayerController:SetPlayerVelocity(PortalPlayerController:GetPlayerVelocity())
                    playerOnGround = false
                end
            end
        end
        currentPlayerOrigin = Player:GetAbsOrigin()
        return 0
    end, 0.1)

    -- Currently flings only exist in sp_a1_intro6
    -- This should be made dynamic if campaign is expanded
    if GetMapName() == "sp_a1_intro6" then
        Player:SetContextThink("DisableFlingTriggers", function()

            if Convars:GetBool("portal_physical_flings") then
                for _, triggerName in ipairs(mapFlingTriggers) do
                    local trigger = Entities:FindByName(nil, triggerName)
                    if trigger then
                        hideFlingTrigger(trigger)
                    end
                end
            end

            return 0.5
        end, 0.1)
    end
end

function PortalPlayerController:Disable()
    Player:SetContextThink("PortalFallThink", nil, 0)
    Player:SetContextThink("DisableFlingTriggers", nil, 0)
end

ListenToPlayerEvent("vr_player_ready", function(params)
    currentPlayerOrigin = Player:GetAbsOrigin()

    -- SendToConsole("god 1")
    -- DoEntFire("speedmod", "modifyspeed", "1.6", 0, nil, nil)

    -- Just for testing enable always
    PortalPlayerController:Enable()
end)
