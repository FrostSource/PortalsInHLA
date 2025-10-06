

local MIN_STEP_NORMAL = 0.7 -- Minimum normal Z for walkable surface

local MIN_CHASM_HEIGHT = 64

local playerOnGround = true
local playerGroundNormal = Vector(0, 0, 1)
local currentPlayerOrigin = Vector()
local currentPlayerVelocity = Vector()

local PLAYER_GIRTH = 7
local PLAYER_HEIGHT = 72

local MIN_FLING_SPEED = 300

local currentWhooshVolume = 0

local playerIsTeleporting = false

EasyConvars:RegisterConvar("portal_woosh_always", "0", "Always adjust the woosh instead of just when flinging")
EasyConvars:SetPersistent("portal_woosh_always", true)

EasyConvars:RegisterConvar("portal_player_speed_multiplier", "50", "Player controller estimated speed multiplier")
EasyConvars:SetPersistent("portal_player_speed_multiplier", true)

Convars:RegisterCommand("portal_playerphys", function (name, on)
    if on == "1" then
        PortalPlayerController:Enable()
    else
        PortalPlayerController:Disable()
    end
end, "", 0)

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
---@class PortalPlayerController
---@field currentPlayerPhys PortalPlayerPhys?
PortalPlayerController = {}

PortalPlayerController.enabled = false

---@type PortalPlayerPhys
PortalPlayerController.currentPlayerPhys = nil

---Setting pickup owner to player allows it to be carried through portals without dropping
---@param params PlayerEventItemPickup
ListenToPlayerEvent("item_pickup", function (params)
    if params.item then
        if not (Player.LeftHand.ItemHeld == params.item and Player.RightHand.ItemHeld == params.item)
            and params.item.portalPrevOwner == nil
        then
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
                params.item:SetOwner(params.item.portalPrevOwner)
                params.item.portalPrevOwner = nil

                for _, portal in ipairs(PortalManager:GetAllPortals()) do
                    if portal.trigger:IsTouching(params.item) then
                        portal:OnTriggerTouch({activator = params.item})
                        break
                    end
                end
            end, 0)
        end
    end
end)

local currentEnableStatus = nil

local teleportTime = 0
---@param params GameEventPlayerTeleportStart
ListenToGameEvent("player_teleport_start", function (params)
    if PortalPlayerController.enabled then
        -- Fix for areas that need playerphys disabled
        if Player:GetMoveType() == PlayerMoveType.TeleportBlink then
            currentEnableStatus = PortalPlayerController.enabled
            PortalPlayerController.enabled = false
        end

        -- print("TELEPORT START")
        playerIsTeleporting = true
        teleportTime = Time()

        -- Stop the player from portaling while teleporting
        Player:Attribute_SetIntValue("DoNotPortal", 1)
    end
end, nil)

---Keeps track of the last portal we portaled to
---Used to stop infinite portaling after teleport
---@type Portal?
local lastTpConnectedPortal = nil

---@param params GameEventPlayerTeleportFinish
ListenToGameEvent("player_teleport_finish", function (params)
    playerIsTeleporting = false

    if currentEnableStatus ~= nil then
        PortalPlayerController.enabled = currentEnableStatus
        currentEnableStatus = nil
    end

    if PortalPlayerController.enabled then
        -- print("TELEPORT END")

        if playerIsTeleporting and playerOnGround and not PortalPlayerController:TracePlayerSpace(Player:GetAbsOrigin() + Vector(0, 0, 0), Player:GetAbsOrigin() + Vector(0, 0, -MIN_CHASM_HEIGHT)).hit then
            print("This should only appear when teleporting into death chasm")
            local velocity = PortalPlayerController:GetPlayerVelocity()
            local velocity2d = Vector(velocity.x, velocity.y, 0)-- * Convars:GetFloat("portal_player_speed_multiplier")
            PortalPlayerController:SetPlayerVelocity(velocity2d)
        end

    end

    if Player:GetMoveType() == PlayerMoveType.TeleportBlink then
        -- Update player origin so there isn't a sudden jump in speed
        currentPlayerOrigin = Vector(params.positionX, params.positionY, params.positionZ)
    end

    -- Allow the player to portal
    Player:DeleteAttribute("DoNotPortal")
    local foundPortal = false

    -- After teleporting the trigger might have already activated
    -- so we need to check all of them and manually trigger them
    for _,portal in ipairs(PortalManager:GetAllPortals()) do
        if portal.trigger:IsTouching(Player) then
            foundPortal = true
            if lastTpConnectedPortal ~= portal then
                lastTpConnectedPortal = portal:GetConnectedPortal()
                portal:OnTriggerTouch({activator = Player})
            end
            break
        end
    end

    if not foundPortal then
        lastTpConnectedPortal = nil
    end
end, nil)

function PortalPlayerController:IsTeleporting()
    return playerIsTeleporting or ((Time() - teleportTime) < 0.3)
end

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
    -- debugoverlay:Line(Player:GetAbsOrigin(), Player:GetAbsOrigin() + Vector(0, 0, -2), 255, 255, 255, 255, false, 0)
    -- debugoverlay:Sphere(Player:GetAbsOrigin(), 1, 255, 255, 0, 255, true, 0)
    -- debugoverlay:Sphere(Player:GetAbsOrigin() + Vector(0, 0, -2), 1, 0, 0, 255, 255, true, 0)

    DebugIf("portal_debug_flings", function()
        debugoverlay:Box(trace.startpos + trace.min, trace.startpos + trace.max, trace.hit and 255 or 0, trace.hit and 0 or 255, 0, 170, false, 0)
    end)

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
        -- debugoverlay:Box(trace.startpos + trace.min, trace.startpos + trace.max, 255, 0, 0, 170, false, 0)
        return true
    else
        -- print("no git ground")
        -- playerOnGround = false
        playerGroundNormal = Vector(0, 0, 1)
        -- debugoverlay:Box(trace.startpos + trace.min, trace.startpos + trace.max, 0, 255, 0, 170, false, 0)
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

function CleanVector(vec, threshold)
    threshold = threshold or 1e-6

    local x = math.abs(vec.x) < threshold and 0 or vec.x
    local y = math.abs(vec.y) < threshold and 0 or vec.y
    local z = math.abs(vec.z) < threshold and 0 or vec.z

    return Vector(x, y, z)
end

function PortalPlayerController:CheckGround()
    return CheckGround()
end

function PortalPlayerController:GetPlayerVelocity()
    local velocity = Vector()
    if IsValidEntity(self.currentPlayerPhys) then
        velocity = self.currentPlayerPhys.velocity
        -- print("Getting velocity from playerphys", velocity)
    else
        velocity = self:GetCachedVelocity()
        if not velocity then
            ---@TODO 100 seems too high, find good multiplier
            -- velocity = (Player:GetAbsOrigin() - currentPlayerOrigin) * 100
            velocity = currentPlayerVelocity
            -- print("Getting velocity from player", velocity)
        else
            -- print("Getting velocity from cache", velocity)
        end
    end

    return CleanVector(velocity)
end

function PortalPlayerController:SetPlayerVelocity(velocity)
    local playerPhys = self:GetOrCreatePlayerPhys(velocity)
    if playerPhys then
        playerPhys:SetVelocity(velocity)
    end
end

function PortalPlayerController:UpdatePlayerPosition(position)
    currentPlayerOrigin = position
end

function PortalPlayerController:GetOrCreatePlayerPhys(initialVelocity)
    if Player.HMDAnchor == nil then
        print("PortalPlayerController:GetOrCreatePlayerPhys: Player.HMDAnchor is nil, playerphys can't be created")
        return
    end

    if IsValidEntity(self.currentPlayerPhys) then
        if initialVelocity then
            self.currentPlayerPhys:SetVelocity(initialVelocity)
        end
        return self.currentPlayerPhys
    else
        playerOnGround = false
        local velocity = initialVelocity or self:GetPlayerVelocity()
        velocity = CleanVector(velocity)

        local model = "models/props/choreo/ghost_speaker.vmdl"
        -- if Convars:GetBool("portal_debug_flings") then
        --     model = "models/editor/axis_helper_thick.vmdl"
        -- end

        local physEnt = SpawnEntityFromTableSynchronous("prop_dynamic_override", {
            origin = Player:GetAbsOrigin(),-- + Vector(0,0,4),
            angles = Player.HMDAnchor:GetAngles(),
            targetname = "catapult_player_physics",
            vscripts = "portal/classes/playerphys",
            velocity_x = tostring(velocity.x),
            velocity_y = tostring(velocity.y),
            velocity_z = tostring(velocity.z),
            model = model,
            solid = "0",
            ScriptedMovement = "1",
        })--[[@as PortalPlayerPhys]]
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
    if IsFakeVREnabled() then
        print("PortalPlayerController:Enable: FakeVR is enabled, playerphys can't be enabled")
        return
    end
    if Player.HMDAnchor == nil then
        print("PortalPlayerController:Enable: Player.HMDAnchor is nil, playerphys can't be enabled")
        return
    end

    self.enabled = true
    Player:SaveBoolean("PortalPlayerController.enabled", self.enabled)

    self:UpdateWhooshSound(0)

    currentPlayerOrigin = Player:GetOrigin()

    Player:SetContextThink("PortalFallThink", function()

        currentPlayerVelocity = (Player:GetOrigin() - currentPlayerOrigin) * Convars:GetFloat("portal_player_speed_multiplier")
        if currentPlayerVelocity:Length() > 2000 then
            print("Player velocity too high", Player:GetOrigin(), currentPlayerOrigin)
        end

        if Convars:GetBool("portal_woosh_always") or self.currentPlayerPhys ~= nil then
            self:UpdateWhooshSound()
        end

        if playerOnGround and not playerIsTeleporting and not (Player:IsNoclipping() or Convars:GetBool("noclip_vr_enabled")) then
            if not CheckGround() then
                -- Check if fall height is high enough
                local trace = self:TracePlayerSpace(Player:GetAbsOrigin(), Player:GetAbsOrigin() + Vector(0, 0, -MIN_CHASM_HEIGHT))
                if not trace.hit then
                    print('player fall')
                    local bounceVelocity = self:GetCachedBounceVelocity()
                    if bounceVelocity then
                        self:ClearBounceCache()
                        self:CacheVelocity(bounceVelocity)
                    end
                    local velocity = self:GetPlayerVelocity()
                    self:SetPlayerVelocity(velocity)
                    playerOnGround = false
                end
            end
        end
        currentPlayerOrigin = Player:GetAbsOrigin()
        return 0
    end, 0)

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
        end, 0)
    end
end

function PortalPlayerController:Disable()
    self.enabled = false
    Player:SaveBoolean("PortalPlayerController.enabled", self.enabled)
    Player:SetContextThink("PortalFallThink", nil, 0)
    Player:SetContextThink("DisableFlingTriggers", nil, 0)
    self:UpdateWhooshSound(0)
end

ListenToPlayerEvent("vr_player_ready", function(params)
    currentPlayerOrigin = Player:GetAbsOrigin()

    -- SendToConsole("god 1")
    -- DoEntFire("speedmod", "modifyspeed", "1.6", 0, nil, nil)

    PortalPlayerController.enabled = Player:LoadBoolean("PortalPlayerController.enabled", PortalPlayerController.enabled)

    if PortalPlayerController.enabled then
        PortalPlayerController:Enable()
    end
end)
