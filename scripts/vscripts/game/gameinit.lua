if IsServer() then
    require "core"
    require "portal.classes.portal"
    require "portal.classes.portalgun"
    require "portal.classes.portal_pair_manager"
    require "portal.portal_manager"

    if not IsVREnabled() then
        require "portal.novr"
    end
end