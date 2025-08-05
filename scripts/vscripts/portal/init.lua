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

if not IsVREnabled() then
    require "portal.novr"
end