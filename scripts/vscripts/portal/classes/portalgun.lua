local MUZZLE_ATTACHMENT = "firebarrel"

local SND_EQUIP = "PortalGun.Equipped"
local SND_USE = "PortalGun.Use"
local SND_USE_LOOP = "PortalGun.UseLoop"
local SND_USE_FAILED = "PortalGun.UseFailed"
local SND_USE_FINISHED = "PortalGun.UseStop"
local SND_TOGGLEEQUIP = "Inventory.Select"

local PTX_PROJECTILE_BLUE = "particles/portal_projectile/portal_1_projectile_stream.vpcf"
local PTX_PROJECTILE_ORANGE = "particles/portal_projectile/portal_2_projectile_stream.vpcf"

---List of classnames that can be picked up by the gun
local PICKUP_CLASS_WHITELIST = {
    "prop_physics",
    "func_physbox",
    "prop_physics_override",
    "prop_physics_interactive",
}

-- Highlight colors need to be lighter than originals
---@TODO See if it's possible to lighten color dynamically inside particle
local HIGHLIGHT_COLOR_BLUE = Color(0.4, 0.6, 0.9)
local HIGHLIGHT_COLOR_ORANGE = Color(0.9, 0.4, 0.2)

---PortalGun related convars
Convars:RegisterConvar("portalgun_fire_delay", "0.2", "Min seconds between each portal fire press.", 0)
Convars:RegisterConvar("portalgun_held_button_fire_fire_delay", "0.5", "Min seconds between each portal fire held.", 0)
Convars:RegisterConvar("portalgun_use_old_pickup_method", "0", "Use the old code for holding objects", 0)
Convars:RegisterConvar("portalgun_pickup_attenuation", "0.1", "Speed of objects being force grabbed, lower is faster", 0)
Convars:RegisterConvar("portalgun_pickup_distance_mod", "2", " Base object hover distance from the portalgun muzzle origin", 0)
Convars:RegisterConvar("portalgun_pickup_rotate_scale", "1.0", "Speed of objects rotating to face portalgun, higher is faster [0-1]", 0)
Convars:RegisterConvar("portalgun_projectile_speed", "4000", "Speed of projectile particle", 0)
Convars:RegisterConvar("portalgun_pickup_damping", "1", "Damping to apply to pickup speed, lower is slower", 0)
Convars:RegisterConvar("portalgun_pickup_range", "100", "Max distance an object can be picked up", 0)
Convars:RegisterConvar("portalgun_pickup_teleport_distance", "512", "Distance at which objects are teleported to the portalgun", 0)
Convars:RegisterConvar("portalgun_pickup_movement_adjust", "1", "Adjust the movement of the object being picked up by the player's movement to minimize interpolation lag", 0)

Convars:RegisterConvar("portalgun_is_physical", "1", "Portal gun is a physical weapon as opposed to furniture", 0)

---@class PortalGun : EntityClass
local base = entity("PortalGun")

---The PortalGun class (not the entity)
PortalGunClass = base

Input.AutoStart = true

---Digital input button used to fire the blue portal.
base.bluePortalButton = DIGITAL_INPUT_EJECT_MAGAZINE
---Digital input button used to fire the orange portal.
base.orangePortalButton = DIGITAL_INPUT_SLIDE_RELEASE
---Digital button used to pickup objects.
base.pickupButton = DIGITAL_INPUT_FIRE
---Digital button used to equip/unequip the gun.
base.equipButton = DIGITAL_INPUT_SHOW_INVENTORY

---If the portal gun is allowed to fire any portals.
base.allowedToFire = true

---Max distance an object can be from the gun allowing it to be picked up.
base.pickupRange = 100
---Entity handle of the currently picked up entity.
---@type EntityHandle
base.pickupEntity = nil

---Stops the pickup ability until trigger is released.
base.__disablePickupUntilTriggerRelease = false

base.orangePortalEnabled = true
base.bluePortalEnabled = true

base.finishedFiringAnimation = true

base.__ptxBarrel = -1
base.__ptxLight = -1

base.__timeSinceLastFire = 0
base.__lastUsedTime = 0
---@type PortalColor
base.__lastFiredColor = nil

---The hand that this gun is attached to.
---@type CPropVRHand
base.hand = nil

---If a portal fire button is currently held.
base.fireButtonIsHeld = false

---If the pickup ability is enabled
base.itemPickupEnabled = true

---If the item is allowed to be dropped
base.itemDropEnabled = true

---Tracks if the generic pistol is equipped
base.physicalEquipped = false

---Used to keep forced pickup entities in the same position relative to the hand when unequipped
base.lastLocalPickupTransform = Vector()

local highlightPtfx = nil

---@type EntityHandle?
local lastNearestPickupEnt = nil

---@param context CScriptPrecacheContext
function base:Precache(context)

    debugprint_portalgun("PortalGun precaching")
    PrecacheResource("particle", "particles/portalgun_barrel.vpcf", context)
    PrecacheResource("particle", "particles/portalgun_light.vpcf", context)
    PrecacheResource("particle", "particles/portal_projectile/portal_badsurface.vpcf", context)
    PrecacheResource("particle", PTX_PROJECTILE_BLUE, context)
    PrecacheResource("particle", PTX_PROJECTILE_ORANGE, context)
    PrecacheResource("particle", "particles/portals/portal_close.vpcf", context)
    -- for debugging
    PrecacheModel("models/editor/point_aimat.vmdl", context)
    PrecacheModel("models/effects/cube_empty.vmdl", context)
end

---Called automatically on spawn
---@param spawnkeys CScriptKeyValues
function base:OnSpawn(spawnkeys)
end

---Called automatically on activate.
---Any self values set here are automatically saved
---@param loaded boolean
function base:OnReady(loaded)
    -- ListenToPlayerEvent("vr_player_ready", function()
        
    -- end)

    self:RegisterAnimTagListener(function (tagName, status)
        self:AnimGraphListener(tagName, status)
    end)

    -- Default current portal color
    if self.__lastFiredColor == nil then
        if self.bluePortalEnabled then
            self.__lastFiredColor = PortalManager.colors.blue
        elseif self.orangePortalEnabled then
            self.__lastFiredColor = PortalManager.colors.orange
        end
    end

    -- Update the global handle
    PortalManager.portalGun = self

    if Convars:GetBool("portalgun_is_physical") then
        self:InitPhysical()
    end

    -- if self.hand ~= nil then
    if self:IsEquipped() then
        self:SetupInputs()
    end
end

---@TODO Set color based on last shot portal
function base:CreateGunParticles()
    self.__ptxBarrel = ParticleManager:CreateParticle("particles/portalgun_barrel.vpcf", 1, self)
    self.__ptxLight = ParticleManager:CreateParticle("particles/portalgun_light.vpcf", 1, self)
    ParticleManager:SetParticleAlwaysSimulate(self.__ptxBarrel)
    ParticleManager:SetParticleAlwaysSimulate(self.__ptxLight)

    --ParticleManager:SetParticleControl(PortalGun.BarrelParticleIndex, 5,_G.PortalManager.ColorEnts[Colors.Blue]:GetOrigin())
    ParticleManager:SetParticleControlEnt(self.__ptxBarrel, 0, self, 5, "innerlaser", Vector(0,0,0), true)
    ParticleManager:SetParticleControlEnt(self.__ptxBarrel, 1, self, 5, "innerlaser_end", Vector(0,0,0), true)
    ParticleManager:SetParticleControl(self.__ptxBarrel, 5, Vector(0,0.4,1))
    ParticleManager:SetParticleControlEnt(self.__ptxLight, 0, self, 5, "light", Vector(0,0,0), true)
    ParticleManager:SetParticleControl(self.__ptxLight, 5, Vector(0,0.4,1))

    if self.__lastFiredColor ~= nil then
        self:SetGunParticlesColor(self.__lastFiredColor.color:ToDecimalVector())
    end
end

function base:DestroyGunParticles()
    if self.__ptxBarrel ~= -1 then
        ParticleManager:DestroyParticle(self.__ptxBarrel, true)
        self.__ptxBarrel = -1
    end
    if self.__ptxLight ~= -1 then
        ParticleManager:DestroyParticle(self.__ptxLight, true)
        self.__ptxLight = -1
    end
end

---@param color Vector
function base:SetGunParticlesColor(color)
    if self.__ptxBarrel ~= -1 then
        ParticleManager:SetParticleControl(self.__ptxBarrel, 5, color)
    end
    if self.__ptxLight ~= -1 then
        ParticleManager:SetParticleControl(self.__ptxLight, 5, color)
    end
end

function base:AnimGraphListener(tagName, status)
    if tagName == "Fired" and status == 2 then
        self.finishedFiringAnimation = true
    end
end

---Get if the portal gun is currently equipped in a hand.
---@return boolean
function base:IsEquipped()
    if Convars:GetBool("portalgun_is_physical") then
        return Player:GetWeapon() == self
    else
        return self.hand ~= nil
    end
end

---Things needed to be called when the player first equips the gun
function base:InitPhysical()
    -- Done once
    for _, child in ipairs(self:GetChildrenMemSafe()) do
        child:Kill()
    end

    -- Hide ammo text in panels related to the gun
    local panelsToFind = 2
    local ent = Entities:First()
    while ent ~= nil do
        if ent:GetClassname() == "hl_vr_weapon_switch_panel" then
            ent:EntFire("AddCSSClass", "AmmoContainHidden")
            panelsToFind = panelsToFind - 1
            if panelsToFind == 0 then
                break
            end
        end
        ent = Entities:Next(ent)
    end

    -- Used to stop the player from shooting (removes dryfire sound)
    if not Entities:FindByName(nil, "_PortalGunPlayerProxy") then
        SpawnEntityFromTableSynchronous("logic_playerproxy", { targetname = "_PortalGunPlayerProxy"})
    end

    -- Should be done every equip
    self:AttachToHand(false)

    ---@param params PlayerEventWeaponSwitch
    ListenToPlayerEvent("weapon_switch", function (params)
        print("Weapon switch", params.item_class)
        print("Is equipped", self.physicalEquipped)
        print(Time())
        if params.item == self then
            self:AttachToHand()
            StartSoundEvent(SND_EQUIP, self)
        else
            -- Only cleanup if the gun is being unequipped
            if self.physicalEquipped then
                self:DetachFromHand()
            end
        end
    end)
end

---Detaches the gun from the currently attached hand glove.
function base:DetachFromHand()
    if Convars:GetBool("portalgun_is_physical") then

        local glove = Player.PrimaryHand:GetGlove()
        if glove then
            glove:SetRenderingEnabled(true)
        end

        self.physicalEquipped = false
        EntFire(self, "_PortalGunPlayerProxy", "SetCanAttackEnable")

        self:DestroyGunParticles()

        if not self.itemDropEnabled and self.pickupEntity ~= nil then
            self.lastLocalPickupTransform = Player.PrimaryHand:TransformPointWorldToEntity(self:GetPickupPosition())
        else
            self:PauseThink()
        end
    else
        local parent = self:GetMoveParent()
        if parent then
            if parent:GetClassname() == "hlvr_prop_renderable_glove" then
                parent:SetRenderAlpha(255)
            end
            self:DropEntity()
            self.hand = nil
            self:SetParent(nil, "")
            self:SetOrigin(Vector())
            self:SetAngles(0, 0, 0)

            ---@TODO Move to disabling function
            self:PauseThink()
        end
    end
end

---Attaches the gun to primary or secondary hand.
---@param useSecondary? boolean # If true, will attach to secondary hand.
function base:AttachToHand(useSecondary)
    if not Player.HMDAvatar then
        warn("Warning - Cannot attach portal gun to hand outside of VR! " .. Debug.GetSourceLine(1))
    end

    local hand = useSecondary and Player.SecondaryHand or Player.PrimaryHand

    if Convars:GetBool("portalgun_is_physical") then
        -- This should only be used to force the gun into the hand
        -- Equipping is done through standard Alyx inventory

        -- ---@TODO Check for already attached?
        -- hand:AddHandAttachment(self)

        local glove = Player.PrimaryHand:GetGlove()
        if glove then
            glove:SetRenderingEnabled(false)
        end

        self.physicalEquipped = true
        EntFire(self, "_PortalGunPlayerProxy", "SetCanAttackDisable")

        -- StartSoundEvent(SND_EQUIP, self)

        -- Only show portal colors if the gun was fired
        ---@TODO Is this desired?
        if self.__lastFiredColor ~= nil then
            self:CreateGunParticles()
        end

        self:SetupInputs()
        self:ResumeThink()
    else

        self:DetachFromHand()

        local glove = hand:GetGlove()

        if glove then
            -- these don't exist do they..
            -- local attachment = primary and "hand_r" or "hand_l"

            self.hand = hand
            self:SetParent(glove, "")
            -- self:SetLocalOrigin(Vector(-7.5, -1, -2.2))
            -- self:SetLocalAngles(0,180,0)
            self:SetLocalOrigin(Vector(5.5, 0, -1))
            self:SetLocalAngles(0,0,0)
            self:SetOwner(Player)
            glove:SetRenderAlpha(0)

            StartSoundEvent(SND_EQUIP, self)

            ---@TODO Move to enabling function
            -- self:ResumeThink()

            self:SetupInputs()
            self:ResumeThink()
        end
    end
end

---Try to fire a portal in the gun's current direction.
---@param color PortalColor
---@return boolean
function base:TryFirePortal(color)
    local time = Time() - self.__timeSinceLastFire
    if (self.fireButtonIsHeld and time >= Convars:GetFloat("portalgun_held_button_fire_fire_delay")) or time >= Convars:GetFloat("portalgun_fire_delay") then
        self.__timeSinceLastFire = Time()

        self.hand:FireHapticPulse(1)

        self:SetGunParticlesColor(color.color:ToDecimalVector())
        self.__lastFiredColor = color

        debugprint_portalgun("Portal gun trying to fire portal", color)

        local portalIsBlue = color == PortalManager.colors.blue

        local attachmentIndex = self:ScriptLookupAttachment(MUZZLE_ATTACHMENT)
        local muzzleOrigin = self:GetAttachmentOrigin(attachmentIndex)
        local muzzleForward = self:GetAttachmentForward(attachmentIndex)

        -- Play portal shooting effects
        self:SetGraphParameterBool("bfired", true)
        -- local pindex = ParticleManager:CreateParticle("particles/portalgun_shooting.vpcf", 1, thisEntity)
        -- ParticleManager:SetParticleControl(pindex, 0, muzzleOrigin)
        -- ParticleManager:SetParticleControlForward(pindex, 1, muzzleForward)
        -- ParticleManager:SetParticleControl(pindex, 5, color.color:ToDecimalVector())
        if portalIsBlue then
            StartSoundEventFromPositionReliable("PortalGun.Shoot.Blue", muzzleOrigin)
        else
            StartSoundEventFromPositionReliable("PortalGun.Shoot.Orange", muzzleOrigin)
        end

        local result = PortalManager:TracePortalableSurface(muzzleOrigin, muzzleForward, Player)

        local mover = SpawnEntityFromTableSynchronous("info_particle_target", {
            origin = muzzleOrigin,
            -- model = "models/effects/cube_empty.vmdl",
            -- ScriptedMovement = "1",
        })
        -- mover:SetVelocity(muzzleForward * Convars:GetFloat("portalgun_projectile_speed"))
        local pindex = ParticleManager:CreateParticle(portalIsBlue and PTX_PROJECTILE_BLUE or PTX_PROJECTILE_ORANGE, 1, mover)
        -- ParticleManager:SetParticleControl(pindex, 2, color.color:ToVector())
        -- mover:EntFire("Kill", nil, (result.hit and VectorDistance(muzzleOrigin, result.pos) or 5000) / mover:GetVelocity():Length()  )

        ---@TODO Move this into a script?
        local startTime = Time()
        local secondsToReachTarget = 0.2
        mover:SetContextThink("MoveProjectile", function()
            local pos = LerpVectors(muzzleOrigin, result.pos, (Time() - startTime) / secondsToReachTarget)
            if Time() - startTime > secondsToReachTarget then
                mover:EntFire("Kill", nil, 2)
                ParticleManager:DestroyParticle(pindex, false)
                return nil
            end
            mover:SetOrigin(pos)
            return 0
        end, 0)

        if result.hit then

            -- FireUser1 for blue, FireUser2 or orange
            if not IsWorld(result.enthit) then
                EntFireByHandle(self, result.enthit, portalIsBlue and "FireUser1" or "FireUser2")
            end

            if not result.surfaceIsPortalable then
                -- PortalManager:CreateFailedPortalEffect(result.pos, result.normal, color.color:ToDecimalVector())
                PortalManager:CreateFailedPortalEffect(result.pos, result.normal, portalIsBlue and "blue" or "orange")
                return false
            end

            if PortalManager:TryCreatePortalAt(result.pos, result.normal, color) then
                if portalIsBlue then
                    StartSoundEventFromPositionReliable("Portal.Open.Blue", result.pos)
                else
                    StartSoundEventFromPositionReliable("Portal.Open.Orange", result.pos)
                end
                return true
            end

            -- Portal manager couldn't create portal
            return false

        end
    end

    -- Buttons aren't ready to fire
    return false
end

local modPickupDistance = 0
local modPickupOffset = Vector()

---Disable player collision with an entity.
---@param entity EntityHandle
function base:DisablePlayerCollisionsWith(entity)

    self:EnablePlayerCollisions()

    ---@TODO Reset name afterwards?
    local name = entity:GetName()
    local nameChanged = false

    -- Only one entity with a name will be affected so we change it temporarily
    if name == "" or #Entities:FindAllByName(name) > 1 then
        entity:SetEntityName(DoUniqueString("entity"))
        nameChanged = true
    end

    ---@type (string|EntityHandle)[]
    local collisionEnts = { "!player", Player.PrimaryHand, self }

    for _, ent in ipairs(collisionEnts) do
        local collisionPair = SpawnEntityFromTableSynchronous("logic_collision_pair", {
            targetname = "_portalgun_collision_pair",
            attach1 = type(ent) == "string" and ent or ent:GetName(),
            attach2 = entity:GetName(),
            startdisabled = "1"
        })

        -- Entity and name used need to be saved for disabling later (quirk of the collision pair)
        if nameChanged then
            collisionPair.disabledCollisionsEnt = entity
            collisionPair.disabledCollisionsName = entity:GetName()
        end
    end

    -- Reset name to avoid I/O issues
    if nameChanged then
        -- entity:Delay(function()
            if IsValidEntity(entity) then
                entity:SetEntityName(name)
            end
        -- end, 0.1)
    end
end

---Enable all player collisions.
function base:EnablePlayerCollisions()
    for _, pair in ipairs(Entities:FindAllByName("_portalgun_collision_pair")) do

        local disabledCollisionsEnt = pair.disabledCollisionsEnt--[[@as EntityHandle]]
        local disabledCollisionsName = pair.disabledCollisionsName--[[@as string]]
        local name = nil
        if disabledCollisionsEnt and disabledCollisionsName and IsValidEntity(disabledCollisionsEnt) then
            name = disabledCollisionsEnt:GetName()
            -- Same name as when disabled needs to be used (seems to be a quirk of the collision pair)
            disabledCollisionsEnt:SetEntityName(disabledCollisionsName)
        end

        pair:EntFire("EnableCollisions", 0)
        pair:EntFire("Kill", nil, 0.1)

        if name then
            ---@NOTE: Name is changed after delay so that the pair can use the temporary name
            disabledCollisionsEnt:Delay(function()
                disabledCollisionsEnt:SetEntityName(name)
            end, 0)
        end
    end
end

function base:GetPickupPosition()
    if self.pickupEntity == nil then
        return self:ShootPosition()
    end

    return self:ShootPosition()
        + (self:ShootForward() * (modPickupDistance + Convars:GetFloat("portalgun_pickup_distance_mod")))
        - modPickupOffset
end

---Updates the position of the currently held item
function base:UpdatePickupItemPosition(offset, immediately)
    local ent = self.pickupEntity

    if not self.itemPickupEnabled or ent == nil then
        return
    end

    if not IsValidEntity(ent) then
        self:DropEntity(true)
        return
    end

    -- Manipulate current pickup entity

    local desiredPosition
    if self:IsEquipped() then
        desiredPosition = self:GetPickupPosition()
    else
        desiredPosition = Player.PrimaryHand:TransformPointEntityToWorld(self.lastLocalPickupTransform)
    end

    offset = offset or Vector()
    desiredPosition = desiredPosition + offset

    if Convars:GetInt("portal_debug_portalgun") >= 1 then
        debugoverlay:Line(self:ShootPosition(), self:ShootPosition() + self:ShootForward() * 100, 0, 0, 255, 255, true, 0)
        debugoverlay:Sphere(desiredPosition, 1, 0, 255, 0, 255, true, 0)
        debugoverlay:Sphere(ent:GetCenter(), 1, 255, 0, 0, 255, true, 0)
        local d = CalcDistanceToLineSegment2D(ent:GetCenter(), self:ShootPosition(), self:ShootPosition() + self:ShootForward() * 100)
        debugoverlay:Text(ent:GetCenter(), 0, "Distance: " .. d, 0, 255, 0, 255, 255, 0)
    end

    local aimAt = VectorToAngles(self:GetPickupEntityLookDirection(ent))

    if immediately then
        ent:SetOrigin(desiredPosition)
        ent:SetQAngle(aimAt)
        return
    end

    if VectorDistance(desiredPosition, ent:GetOrigin()) > Convars:GetInt("portalgun_pickup_teleport_distance") then
        ent:SetOrigin(desiredPosition)
        ent:SetQAngle(aimAt)
        return
    end

    if Convars:GetBool("portalgun_use_old_pickup_method") then
        local amountBy = VectorDistance(self:GetOrigin(), ent:GetOrigin()) / 50
        local amount = min(amountBy, 2)
        if VectorDistance(desiredPosition, ent:GetOrigin()) < 25 then
            ent:ApplyAbsVelocityImpulse(-GetPhysVelocity(ent) / 2)
        else
            ent:ApplyAbsVelocityImpulse( ((desiredPosition - ent:GetOrigin()) * amount) - (GetPhysVelocity(ent) / 2) )
        end
    else
        local velocity = (desiredPosition - ent:GetOrigin()) / Convars:GetFloat("portalgun_pickup_attenuation")
        velocity = velocity - GetPhysVelocity(ent)
        ent:ApplyAbsVelocityImpulse(velocity * Convars:GetFloat("portalgun_pickup_damping"))

        local currentAngles = ent:GetAngles()
        local angVel = RotationDeltaAsAngularVelocity(currentAngles, aimAt)
        local strength = Convars:GetFloat("portalgun_pickup_rotate_scale")
        angVel = angVel * strength

        SetPhysAngularVelocity(ent, angVel)
    end
end

function base:GetPickupEntityLookDirection(ent)
    -- Example of special rotation entities
    if ent:GetModelName() == "models/npcs/personality_sphere/sphere_physics.vmdl" then
        return (Player:EyePosition() - ent:GetOrigin()):Normalized()
    else
        -- Default face portalgun
        ---@TODO Capture angles when picked up to maintain original angle?
        return (self:GetOrigin() - ent:GetOrigin()):Normalized()
    end
end

---Forces the gun to pick up an entity
---@param entity EntityHandle|nil # Pass nil as a failed pickup
function base:PickupEntity(entity)
    if entity == nil then
        StartSoundEventFromPositionReliable(SND_USE_FAILED, self:GetAbsOrigin())
        return
    end

    if not IsValidEntity(entity) then
        warn("Portal gun attempted to pick up invalid entity " .. Debug.EntStr(entity))
        return
    end

    self.pickupEntity = entity

    StartSoundEventFromPositionReliable(SND_USE, self:GetAbsOrigin())
    StartSoundEvent(SND_USE_LOOP, self)

    -- Fire output for hammer use
    entity:FireOutput("OnPhysGunOnlyPickup", self, self, nil, 0)

    -- Disable player collisions to avoid cheat flying
    self:DisablePlayerCollisionsWith(entity)

    -- Destroy old highlight
    self:DestroyHighlight()

    -- Drop the item from the player's hands
    if Player:IsHolding(entity) then
        entity:Drop()
    end

    -- Adjust the pickup distance based on the size of the entity
    modPickupDistance = self.pickupEntity:GetBiggestBounding()
    modPickupOffset = self.pickupEntity:GetCenter() - self.pickupEntity:GetOrigin()

end

---Drops the currently held item.
---
---If this is called within the think you must also return nil from the think or an error will occur.
function base:DropEntity(dontStopThink)
    -- Only drop the item if it's enabled
    if not self.itemDropEnabled then
        return
    end

    self.pickupEntity = nil
    lastNearestPickupEnt = nil
    -- self.__pickupEntity = nil
    if not dontStopThink then
        self:SetContextThink("PortalGunPickupAbility", nil, 0)
    end
    self:SetGraphParameterBool("bTargeting", false)
    StopSoundEvent(SND_USE_LOOP, self)
    self:EnablePlayerCollisions()
end

function base:SetupInputs()

    Input:StopListeningByContext(self)

    -- Vive controller uses one button for grenade/reload, so we remap to burst fire
    if Player:GetVRControllerType() == 2 then
        self.orangePortalButton = DIGITAL_INPUT_TOGGLE_BURST_FIRE
    end

    if Convars:GetBool("portalgun_is_physical") then
        self.hand = Player.PrimaryHand
    end

    Input:ListenToButton("press", self.hand, self.pickupButton, 1, function (_, params)
        if self:IsEquipped() and self.itemPickupEnabled then
            if not self.__disablePickupUntilTriggerRelease then
                self:PickupEntity(lastNearestPickupEnt)
            end
        end
    end, self)

    Input:ListenToButton("release", self.hand, self.pickupButton, 1, function (_, params)
        if not self:IsEquipped() then
            return
        end

        -- Do not drop item if disabled
        if not self.itemDropEnabled then
            return
        end

        if self.__disablePickupUntilTriggerRelease then
            self.__disablePickupUntilTriggerRelease = false
        end

        if self.pickupEntity ~= nil then
            self:DropEntity()
            StartSoundEventFromPositionReliable(SND_USE_FINISHED, self:GetAbsOrigin())
        end
    end, self)

    Input:ListenToButton("press", self.hand, self.bluePortalButton, 1, function (_, params)
        if self:IsEquipped() and self.allowedToFire and self.pickupEntity == nil then
            if self.bluePortalEnabled then
                self:TryFirePortal(PortalManager.colors.blue)
            end
            self.fireButtonIsHeld = true
        end
    end, self)

    Input:ListenToButton("press", self.hand, self.orangePortalButton, 1, function (_, params)
        if self:IsEquipped() and self.allowedToFire and self.pickupEntity == nil then
            if self.orangePortalEnabled then
                self:TryFirePortal(PortalManager.colors.orange)
            end
            self.fireButtonIsHeld = true
        end
    end, self)

    -- Physical gun uses standard Alyx inventory so this isn't needed
    if not Convars:GetBool("portalgun_is_physical") then
        Input:ListenToButton("press", self.hand, self.equipButton, 1, function (_, params)
            StartSoundEvent(SND_TOGGLEEQUIP, self)
            if self:IsEquipped() then
                self:DetachFromHand()
                self:SetRenderingEnabled(false)
                self:DestroyGunParticles()
            else
                self:AttachToHand()
                self:SetRenderingEnabled(true)
                self:CreateGunParticles()
            end
        end, self)
    end

    -- Assume setting up inputs means gun is equipped
    self:ResumeThink()

end

-- function base:FixTeleportPickup()
-- end

-- ---@param params GameEventPlayerTeleportStart
-- base:GameEvent("player_teleport_start", function (self, params)
--     if IsValidEntity(self.pickupEntity) then
--         self.pickupEntity:SetParent(self, "")
--     end
-- end)
-- ---@param params GameEventPlayerTeleportFinish
-- base:GameEvent("player_teleport_finish", function (self, params)
--     if IsValidEntity(self.pickupEntity) then
--         self.pickupEntity:SetParent(nil, "")
--     end
-- end)

---Get the nearest entity that can be picked up by the gun.
---@return EntityHandle?
function base:GetNearestPickupEntity()
    local muzzleIndex = self:ScriptLookupAttachment(MUZZLE_ATTACHMENT)
    local muzzleOrigin = self:GetAttachmentOrigin(muzzleIndex)
    local muzzleForward = self:GetAttachmentForward(muzzleIndex)
    ---@type TraceTableLine
    local traceTable = {
        startpos = muzzleOrigin,
        endpos = muzzleOrigin + muzzleForward * Convars:GetInt("portalgun_pickup_range"),
        ignore = self,
    }

    TraceLine(traceTable)

    if traceTable.hit
    and not vlua.find(PortalManager.disabledPickupNames, traceTable.enthit:GetName())
    and vlua.find(PICKUP_CLASS_WHITELIST, traceTable.enthit:GetClassname()) then
        return traceTable.enthit
    end

    return nil
end

---Highlights a new entity.
---@param entityToHighlight EntityHandle
function base:CreateHighlight(entityToHighlight)
    local scale = entityToHighlight:GetAbsScale()
    local bounds = entityToHighlight:GetBounds()
    local height = (bounds.Maxs.z - bounds.Mins.z) * scale
    local width = math.max(bounds.Maxs.x - bounds.Mins.x, bounds.Maxs.y - bounds.Mins.y) * scale
    local zoffset = bounds.Mins.z * scale

    self:DestroyHighlight()
    highlightPtfx = ParticleManager:CreateParticle("particles/portalgun_target_modelglow.vpcf", 0, self)
    ParticleManager:SetParticleControlEnt(highlightPtfx, 0, entityToHighlight, 5, nil, Vector(0,0,128), true)
    ParticleManager:SetParticleControl(highlightPtfx, 1, Vector(width, zoffset, height))
    ParticleManager:SetParticleControl(highlightPtfx, 4, Vector(scale, scale, scale))

    if entityToHighlight:GetModelName() == "models/props/metal_box_dirty.vmdl" then
        if entityToHighlight:GetMaterialGroupHash() == 722709575 then
            ParticleManager:SetParticleControl(highlightPtfx, 8, HIGHLIGHT_COLOR_ORANGE:ToDecimalVector())
            return
        end
    end

    local lastCol = self.__lastFiredColor
    if lastCol ~= nil then
        if lastCol.name == "blue" then
            ParticleManager:SetParticleControl(highlightPtfx, 8, HIGHLIGHT_COLOR_BLUE:ToDecimalVector())
        elseif lastCol.name == "orange" then
            ParticleManager:SetParticleControl(highlightPtfx, 8, HIGHLIGHT_COLOR_ORANGE:ToDecimalVector())
        end
    else
        -- Default color when no portals are active
        ParticleManager:SetParticleControl(highlightPtfx, 8, Vector(0.7, 0.8, 0.9))
    end
end

---Destroys the highlight particle if it exists.
---@param immediately? boolean
function base:DestroyHighlight(immediately)
    if highlightPtfx ~= nil then
        ParticleManager:DestroyParticle(highlightPtfx, immediately == true)
        highlightPtfx = nil
    end
end

---Plays the fizzle animation
function base:Fizzle()
    self:SetGraphParameterBool("bFizzle", true)
end

function base:ShootPosition()
    return self:GetAttachmentNameOrigin("muzzle")
end

function base:ShootForward()
    return self:GetAttachmentNameForward("muzzle")
end

local prevPlayerPos = nil

function base:Think()

    if self.pickupEntity ~= nil then
        local moveVector = Vector()
        if Convars:GetBool("portalgun_pickup_movement_adjust") then
            -- Track player movement to stop item lagging behind
            if prevPlayerPos == nil then
                prevPlayerPos = Player:GetOrigin()
            end
            moveVector = (Player:GetOrigin() - prevPlayerPos) * 10
            prevPlayerPos = Player:GetOrigin()
        end

        self:UpdatePickupItemPosition(moveVector)
    elseif self.itemPickupEnabled then
        local nearestPickupEnt = self:GetNearestPickupEntity()
        if nearestPickupEnt then
            -- New nearest entity
            if nearestPickupEnt ~= lastNearestPickupEnt then
                lastNearestPickupEnt = nearestPickupEnt
                -- Display pickup effects
                self:SetGraphParameterBool("bTargeting", true)
                self:CreateHighlight(nearestPickupEnt)
            end
        else
            if lastNearestPickupEnt then
                lastNearestPickupEnt = nil
                self:DestroyHighlight()
                self:SetGraphParameterBool("bTargeting", false)
            end
        end
    end

    return 0
end

---Stops the gun from being able to pick up items
function base:DisableItemPickup()
    self.itemPickupEnabled = false
end

---Allows the gun to pick up items
function base:EnableItemPickup()
    self.itemPickupEnabled = true
end

---Disables the ability to pick up an entity by name
---@param name string
function base:DisableNamePickup(name)
    PortalManager:SetPickupNameEnabled(name, false)
end

---Allows the ability to pick up an entity by name
---@param name string
function base:EnableNamePickup(name)
    PortalManager:SetPickupNameEnabled(name, true)
end

---Disables the portal gun from picking up this named entity
function CEntityInstance:DisablePortalgunPickup()
    PortalManager:SetPickupNameEnabled(self:GetName(), false)
end

---Allows the portal gun to pick up this named entity
function CEntityInstance:EnablePortalgunPickup()
    PortalManager:SetPickupNameEnabled(self:GetName(), true)
end

---Stops the portal gun from dropping its currently held item
function base:DisableItemDrop()
    self.itemDropEnabled = false
end

---Allows the portal gun to drop its currently held item
function base:EnableItemDrop()
    self.itemDropEnabled = true

    -- Automatically drop the current item if the trigger is released
    -- This can be disabled if you want the item to stay held until the trigger is pressed again
    if not Player:IsDigitalActionOnForHand(self.hand:GetLiteralHandType(), self.pickupButton) then
        self:DropEntity()
    end
end

---Forces the portal gun to drop its currently held item (Hammer input)
function base:ForceDropItem()
    self:DropEntity()
    -- Require the trigger to be released before picking up again
    self.__disablePickupUntilTriggerRelease = true
end

function base:EnableBluePortalGun()
    self.bluePortalEnabled = true
end

function base:DisableBluePortalGun()
    self.bluePortalEnabled = false
end

function base:EnableOrangePortalGun()
    self.orangePortalEnabled = true
end

function base:DisableOrangePortalGun()
    self.orangePortalEnabled = false
end

function base:DeactivatePortalGun()
    self.allowedToFire = false
end

function base:ActivatePortalGun()
    self.allowedToFire = true
end

--Used for classes not attached directly to entities
return base