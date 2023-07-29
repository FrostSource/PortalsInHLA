if IsServer() then
    require "core"
    require "portal.classes.portal"
    require "portal.classes.portalgun"
    require "portal.portal_manager"

    if not IsVREnabled() then
        require "portal.novr"
    end
end