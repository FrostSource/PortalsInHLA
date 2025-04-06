---@param spawnkeys CScriptKeyValues
function Spawn(spawnkeys)
    print(Debug.EntStr(thisEntity), "SpawnFlags: " .. tostring(spawnkeys:GetValue("spawnflags")))
end