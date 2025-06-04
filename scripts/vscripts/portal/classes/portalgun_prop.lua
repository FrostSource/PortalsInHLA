--[[
    A physical prop_physics version of the portal gun.
    When the player grabs this prop with their primary hand, OnUser1 is fired.

    Attach to Misc > Entity Scripts = portal/classes/portalgun_prop
]]

if thisEntity then
    ---@param params PlayerEventItemPickup
    ListenToEntityPickup(thisEntity, function(params)
        if params.hand == Player.PrimaryHand then
            thisEntity:EntFire("FireUser1")
        end
    end)
end