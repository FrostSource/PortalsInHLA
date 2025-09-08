Convars:RegisterCommand("portal_fire_portalgun_blue", function ()
    if PortalManager.portalGun then
        PortalManager.portalGun:TryFirePortal(PortalManager.colors.blue)
    end
end, "", 0)
Convars:RegisterCommand("portal_fire_portalgun_orange", function ()
    if PortalManager.portalGun then
        PortalManager.portalGun:TryFirePortal(PortalManager.colors.orange)
    end
end, "", 0)

ListenToPlayerEvent("vr_player_ready", function(params)
    print("Player is in fakevr mode...")
    SendToConsole("bind 1 portal_fire_portalgun_blue")
    SendToConsole("bind 2 portal_fire_portalgun_orange")
end)