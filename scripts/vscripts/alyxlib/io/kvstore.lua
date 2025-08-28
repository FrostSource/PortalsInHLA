-- kvstore_safe.lua
local fileio = require("alyxlib.io.file")

local kvstore = {}
kvstore.data = {}

-- Load from disk (safe, no code execution)
function kvstore.load(path)
    local str, err = fileio.read(path)
    if not str then
        return false, err
    end
    local data = {}
    for line in str:gmatch("[^\r\n]+") do
        local k, v = line:match("^(.-)=(.*)$")
        if k and v then
            data[k] = v
        end
    end
    kvstore.data = data
    return true
end

-- Save to disk
function kvstore.save(path)
    local lines = {}
    for k,v in pairs(kvstore.data) do
        table.insert(lines, k .. "=" .. tostring(v))
    end
    return fileio.write(path, table.concat(lines, "\n"))
end

-- Set / Get
function kvstore.set(key, value)
    kvstore.data[key] = value
end

function kvstore.get(key)
    return kvstore.data[key]
end

return kvstore
