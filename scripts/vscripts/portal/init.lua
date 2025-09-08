--[[
    Loads all necessary files for the Portal mod
    EXCEPT for AlyxLib
]]
require "portal.classes.portal"
require "portal.classes.portalgun"
require "portal.classes.portalgun_item"
require "portal.classes.portal_pair_manager"
require "portal.classes.playerphys"
require "portal.portal_manager"
require "portal.player_controller"

if IsInToolsMode() or Convars:GetInt("developer") > 0 then
    require "portal.debug"
    if not IsVREnabled() then
        if IsFakeVREnabled() then
            require "portal.fakevr"
        else
            require "portal.novr"
        end
    end
end