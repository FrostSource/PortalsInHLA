

local MIN_STEP_NORMAL = 0.7 -- Minimum normal Z for walkable surface

local MIN_CHASM_HEIGHT = 64

local playerOnGround = true
local playerGroundNormal = Vector(0, 0, 1)
local currentPlayerOrigin = Vector()
local currentPlayerVelocity = Vector()

local PLAYER_GIRTH = 7
local PLAYER_HEIGHT = 96

---Controls player falling into chasms.
PortalPlayerController = {}

---@type PortalPlayerPhys?
PortalPlayerController.currentPlayerPhys = nil

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

ListenToPlayerEvent("vr_player_ready", function(params)
    SpawnEntityFromTableSynchronous("player_speedmod", {targetname='spd'})
    DoEntFire("spd", "modifyspeed", "2", 0, nil, nil)

    SendToConsole("god 1")
    currentPlayerOrigin = Player:GetAbsOrigin()
    Player:SetContextThink("PortalFallThink", function()
        -- if Time() - cacheTime > 0.1 then
        --     cacheVelocity = Vector(0, 0, 0)
        -- end

        currentPlayerVelocity = (Player:GetAbsOrigin() - currentPlayerOrigin) * 100
        local maxVelocity = 400 -- what it best?
        DoEntFire("@FallWhooshParam", "SetFloatValue", tostring(PortalPlayerController:GetPlayerVelocity():Length() / maxVelocity), 0, nil, nil)

        -- print(math.trunc(playerVelocity:Length(), 2))
        if playerOnGround and not (Player:IsNoclipping() or Convars:GetBool("noclip_vr_enabled")) then
            if not CheckGround() then
                -- Check if fall height is high enough
                local trace = PortalPlayerController:TracePlayerSpace(Player:GetAbsOrigin(), Player:GetAbsOrigin() + Vector(0, 0, -MIN_CHASM_HEIGHT))
                -- print(trace.hit)
                if not trace.hit then
                    print("Player falling")
                    -- PortalPlayerController:GetOrCreatePlayerPhys(playerVelocity * 100)
                    PortalPlayerController:SetPlayerVelocity(PortalPlayerController:GetPlayerVelocity())
                    playerOnGround = false
                end
            end
        end
        currentPlayerOrigin = Player:GetAbsOrigin()
        return 0
    end, 0)
end)
