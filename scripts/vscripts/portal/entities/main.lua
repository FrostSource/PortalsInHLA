
function Precache(context)
    print("Main portal precache")
    PrecacheResource("particle", "particles/portal_effect_parent.vpcf", context)
    PrecacheResource("model", "models/vrportal/portalshape.vmdl", context)
end

print("Main portal entity initiated")
