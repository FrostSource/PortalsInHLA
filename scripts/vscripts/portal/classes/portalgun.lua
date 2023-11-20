local MUZZLE_ATTACHMENT = "firebarrel"

local SND_EQUIP = "PortalGun.Equipped"
local SND_USE = "PortalGun.Use"
local SND_USE_LOOP = "PortalGun.UseLoop"
local SND_USE_FAILED = "PortalGun.UseFailed"
local SND_USE_FINISHED = "PortalGun.UseStop"

local PTX_PROJECTILE_BLUE = "particles/portal_projectile/portal_1_projectile_stream.vpcf"
local PTX_PROJECTILE_ORANGE = "particles/portal_projectile/portal_2_projectile_stream.vpcf"

---List of classnames that can be picked up by the gun
local PICKUP_CLASS_WHITELIST = {
    "prop_physics",
    "func_physbox",
    "prop_physics_override",
    "prop_physics_interactive",
}

---PortalGun related convars
Convars:RegisterConvar("portalgun_fire_delay", "0.2", "Min seconds between each portal fire press.", 0)
Convars:RegisterConvar("portalgun_held_button_fire_fire_delay", "0.5", "Min seconds between each portal fire held.", 0)
Convars:RegisterConvar("portalgun_use_old_pickup_method", "0", "Use the old code for holding objects", 0)
Convars:RegisterConvar("portalgun_pickup_attenuation", "0.1", "Speed of objects being force grabbed, lower is faster", 0)
Convars:RegisterConvar("portalgun_pickup_distance", "100", "Object hover distance from the portalgun origin", 0)
Convars:RegisterConvar("portalgun_pickup_rotate_scale", "0.5", "Speed of objects rotating to face portalgun, higher is faster [0-1]", 0)
Convars:RegisterConvar("portalgun_projectile_speed", "1200", "Speed of projectile particle", 0)
---@class PortalGun : EntityClass
local base = entity("PortalGun")

---Digital input button used to fire the blue portal.
base.bluePortalButton = DIGITAL_INPUT_ARM_GRENADE
---Digital input button used to fire the orange portal.
base.orangePortalButton = DIGITAL_INPUT_RELOAD
---Digital button used to pickup objects.
base.pickupButton = DIGITAL_INPUT_FIRE

---If the portal gun is allowed to fire any portals.
base.allowedToFire = true

---Max distance an object can be from the gun allowing it to be picked up.
base.pickupRange = 100
---Entity handle of the currently picked up entity.
---@type EntityHandle
base.__pickupEntity = nil

---Stops the pickup ability until trigger is released.
base.__disablePickupUntilTriggerRelease = false

base.orangePortalEnabled = true
base.bluePortalEnabled = true

base.finishedFiringAnimation = true

base.__ptxBarrel = -1
base.__ptxLight = -1

base.__timeSinceLastFire = 0
base.__timeSinceLastUsed = 0

---The hand that this gun is attached to.
---@type CPropVRHand
base.hand = nil

---If a portal fire button is currently held.
base.fireButtonIsHeld = false

---@param context CScriptPrecacheContext
function base:Precache(context)
    devprint("PortalGun precaching")
    PrecacheResource("particle", "particles/portalgun_barrel.vpcf", context)
    PrecacheResource("particle", "particles/portalgun_light.vpcf", context)
    PrecacheResource("particle", "particles/portal_projectile/portal_badsurface.vpcf", context)
    PrecacheResource("particle", PTX_PROJECTILE_BLUE, context)
    PrecacheResource("particle", PTX_PROJECTILE_ORANGE, context)
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
    -- Vive controller uses one button for grenade/reload, so we remap to burst fire
    RegisterPlayerEventCallback("vr_player_ready", function()
        if Player:GetVRControllerType() == 2 then
            self.orangePortalButton = 14
        end
        Input:TrackButton(self.bluePortalButton)
        Input:TrackButton(self.orangePortalButton)
        Input:TrackButton(self.pickupButton)

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
    end)

    self:RegisterAnimTagListener(function (tagName, status)
        self:AnimGraphListener(tagName, status)
    end)

    -- Update the global handle
    PortalManager.portalGun = self
end

function base:AnimGraphListener(tagName, status)
    if tagName == "Fired" and status == 2 then
        self.finishedFiringAnimation = true
    end
end

---Get if the portal gun is currently equipped in a hand.
---@return boolean
function base:IsEquipped()
    return self.hand ~= nil
end

---Detaches the gun from the currently attached hand glove.
function base:DetachFromHand()
    local parent = self:GetMoveParent()
    if parent then
        if parent:GetClassname() == "hlvr_prop_renderable_glove" then
            parent:SetRenderAlpha(255)
        end
        self.hand = nil
        self:SetParent(nil, "")
        self:SetOrigin(Vector())
        self:SetAngles(0, 0, 0)

        ---@TODO Move to disabling function
        self:PauseThink()
    end
end

---Attaches the gun to primary or secondary hand.
---@param useSecondary? boolean # If true, will attach to secondary hand.
function base:AttachToHand(useSecondary)
    if not Player.HMDAvatar then
        print("Warning - Cannot attach portal gun to hand outside of VR! " .. _sourceline())
    end

    self:DetachFromHand()

    local hand = useSecondary and Player.SecondaryHand or Player.PrimaryHand
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
        self:ResumeThink()
    end
end

---Create a failed portal opening effect.
---@param pos Vector
---@param dir Vector
---@param color Vector
local function createFailedPortalEffect(pos, dir, color)
    StartSoundEventFromPositionReliable("PortalGun.Shoot.Fail", pos)
    local pindex = ParticleManager:CreateParticle("particles/portal_projectile/portal_badsurface.vpcf", 0, thisEntity)
    ParticleManager:SetParticleControl(pindex, 0, pos + dir)
    ParticleManager:SetParticleControl(pindex, 2, color)
end

---Try to fire a portal in the gun's current direction.
---@param color PortalColor
---@return boolean
function base:TryFirePortal(color)
    local time = Time() - self.__timeSinceLastFire
    if (self.fireButtonIsHeld and time >= Convars:GetFloat("portalgun_held_button_fire_fire_delay")) or time >= Convars:GetFloat("portalgun_fire_delay") then
        self.__timeSinceLastFire = Time()

        self.hand:FireHapticPulse(1)

        -- Set the gun color particles
        ParticleManager:SetParticleControl(self.__ptxBarrel, 5, color.color:ToDecimalVector())
        ParticleManager:SetParticleControl(self.__ptxLight, 5, color.color:ToDecimalVector())

        if PortalManager:Debugging() then
            print("Trying to fire portal", color)
        end

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

        local mover = SpawnEntityFromTableSynchronous("prop_dynamic_override", {
            origin = muzzleOrigin,
            model = "models/effects/cube_empty.vmdl",
            ScriptedMovement = "1",
        })
        mover:SetVelocity(muzzleForward * Convars:GetFloat("portalgun_projectile_speed"))
        local pindex = ParticleManager:CreateParticle(portalIsBlue and PTX_PROJECTILE_BLUE or PTX_PROJECTILE_ORANGE, 1, mover)
        ParticleManager:SetParticleControl(pindex, 2, color.color:ToVector())
        mover:EntFire("Kill", nil, (result.hit and 5000 or VectorDistance(muzzleOrigin, result.pos)) / mover:GetVelocity():Length())

        if result.hit then

            -- FireUser1 for blue, FireUser2 or orange
            if not IsWorld(result.enthit) then
                EntFireByHandle(self, result.enthit, portalIsBlue and "FireUser1" or "FireUser2")
            end

            if not result.surfaceIsPortalable then
                createFailedPortalEffect(result.pos, result.normal, color.color:ToDecimalVector())
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

function base:DropItem()
    self.__disablePickupUntilTriggerRelease = true
    self.__pickupEntity = nil
end

function base:HandlePickupAbility()
    if self.__pickupEntity ~= nil then
        -- Manipulate current pickup entity
        if not IsValidEntity(self.__pickupEntity) then
            self.__pickupEntity = nil
            return
        end
        local ent = self.__pickupEntity

        local desiredPosition = self:GetOrigin() + self:GetForwardVector() * Convars:GetFloat("portalgun_pickup_distance")
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
            ent:ApplyAbsVelocityImpulse(velocity)

            local aimAt = nil
            -- Example of special rotation entities
            if ent:GetName() == "@Wheatly" then
                aimAt = (Player:EyePosition() - ent:GetOrigin()):Normalized()
            else
                -- Default face portalgun
                ---@TODO Capture angles when picked up to maintain original angle
                aimAt = (self:GetOrigin() - ent:GetOrigin()):Normalized()
            end
            local newAim = ent:GetForwardVector():Slerp(aimAt, Convars:GetFloat("portalgun_pickup_rotate_scale")--[[@as number]])
            ent:SetForwardVector(newAim)
        end
    else
        -- Find new pickup entity
        local muzzleIndex = self:ScriptLookupAttachment(MUZZLE_ATTACHMENT)
        local muzzleOrigin = self:GetAttachmentOrigin(muzzleIndex)
        local muzzleForward = self:GetAttachmentForward(muzzleIndex)
        ---@type TraceTableLine
        local traceTable = {
            startpos = muzzleOrigin,
            endpos = muzzleOrigin + muzzleForward * self.pickupRange,
            ignore = self,
        }
        TraceLine(traceTable)
        if traceTable.hit and vlua.find(PICKUP_CLASS_WHITELIST, traceTable.enthit:GetClassname()) then
            StartSoundEventFromPositionReliable(SND_USE, self:GetAbsOrigin())
            StartSoundEvent(SND_USE_LOOP, self)
            self.__pickupEntity = traceTable.enthit

            -- Delay between fail sounds
            if self.__timeSinceLastUsed < 0.2 then
                self.__timeSinceLastUsed = self.__timeSinceLastUsed + 0.1
            else
                StartSoundEventFromPositionReliable(SND_USE_FAILED, self:GetAbsOrigin())
                self.__timeSinceLastUsed = 0
            end

            ---@TODO Modulate hover distance based on object size
        end
    end
end

---Main entity think function. Think state is saved between loads
function base:Think()


    if self:IsEquipped() then

        if not self.__disablePickupUntilTriggerRelease and Input:Button(self.hand, self.pickupButton) then
            self:HandlePickupAbility()
        else
            if self.__disablePickupUntilTriggerRelease then
                self.__disablePickupUntilTriggerRelease = false
            end
            if self.__pickupEntity ~= nil then
                self.__pickupEntity = nil
                StopSoundEvent(SND_USE_LOOP, self)
                StartSoundEventFromPositionReliable(SND_USE_FINISHED, self:GetAbsOrigin())
            end
            if self.allowedToFire then
                if Input:Button(self.hand, self.bluePortalButton) then
                    if self.bluePortalEnabled then
                        self:TryFirePortal(PortalManager.colors.blue)
                    end
                    self.fireButtonIsHeld = true
                elseif Input:Button(self.hand, self.orangePortalButton) then
                    if self.orangePortalEnabled then
                        self:TryFirePortal(PortalManager.colors.orange)
                    end
                    self.fireButtonIsHeld = true
                else
                    self.fireButtonIsHeld = false
                end
            end
        end
    end

    return 0
end

--Used for classes not attached directly to entities
return base