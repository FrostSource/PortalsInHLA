# Portals In HLA
This mod creates functional portals in HLA. **IT IS NOT A STANDALONE MOD**; it must be integrated into workshop maps and doesn't work with the campaign out of the box.

# To Use
Place `maps/prefabs/portal/portalmanager_required.vmap` at world origin (0,0,0). Map-wise, this is the heart of the logic. You can use `maps\prefabs\portal_spawner.vmap` to create portals in specific spots (like before you get the portal gun in the games). To use the portalgun, add `maps\prefabs\portalgun.vmap` somewhere into the map. The gun will be attached to the player's right hand. There is a DoNotGive setting on the prefab if you wish to give the player the gun somewhere later on in the map. You can do this by sending a RunScriptCode input to !player with the parameter SendToConsole('portalgun_give')


## Important Information:
The Scripts folder needs to go to the `Half-Life Alyx/game/hlvr_Addons/YOURADDON/` folder, otherwise the scripts won't work.

To restrict portalable surfaces, use the `OnlyFunc_BrushPortalable` setting on the PortalManager prefab, set a `PortalPrefix`, and place ALWAYS SOLID func_brush entities with the name you set as the prefix on the surfaces you wish to be portalable. 


### Prefab infos:
Through Map I/O, you can do things like only allow one color portal to be shootable, CloseAllPortals to enable things like the emancipation grill, or clean up and remove the portal entities by sending a Destroy input.

If you want to remove the portal gun from the player, send a kill input to @PortalGun.
