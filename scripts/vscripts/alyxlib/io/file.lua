-- fileio.lua
local __enable_ffi = 0x666ULL
local ffi = require("ffi")

ffi.cdef[[
    typedef struct _IO_FILE FILE;
    FILE *fopen(const char *filename, const char *mode);
    int fclose(FILE *stream);
    size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);
    size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
    int fseek(FILE *stream, long offset, int whence);
    long ftell(FILE *stream);
]]

-- On Windows: load the MSVCRT library
-- On Linux/macOS: fopen is available in ffi.C
local C
if ffi.os == "Windows" then
    ffi.cdef[[
        int _mkdir(const char *path);
        int _getcwd(char *buf, int size);
    ]]
    C = ffi.load("msvcrt")  -- Microsoft C runtime
else
    ffi.cdef[[
        int mkdir(const char *pathname, int mode);
        char *getcwd(char *buf, size_t size);
    ]]
    C = ffi.C
end
print(ffi.os)

local function getcwd()
    local size = 512
    local buf = ffi.new("char[?]", size)

    local cwd
    if ffi.os == "Windows" then
        cwd = C._getcwd(buf, size)
    else
        cwd = C.getcwd(buf, size)
    end

    if cwd ~= nil then
        return ffi.string(buf)
    else
        return nil, "failed to getcwd"
    end
end

print("Current working directory:", getcwd())

local fileio = {}

function fileio.mkdir(path)
    if ffi.os == "Windows" then
        return C._mkdir(path)
    else
        return C.mkdir(path, 511) -- 0777
    end
end

-- Write data safely to a file
function fileio.write(path, data)
    local f = C.fopen(path, "wb")
    if f == nil then
        return false, "fopen failed, errno=" .. ffi.errno()
    end

    local buf = ffi.new("char[?]", #data, data)
    local written = C.fwrite(buf, 1, #data, f)
    C.fclose(f)

    return written == #data
end

-- Read full file into a Lua string
function fileio.read(path)
    local f = C.fopen(path, "rb")
    if f == nil then
        return nil, "fopen failed, errno=" .. ffi.errno()
    end

    -- Seek to end to get size
    C.fseek(f, 0, 2) -- SEEK_END
    local size = C.ftell(f)
    C.fseek(f, 0, 0) -- SEEK_SET

    local buf = ffi.new("char[?]", size)
    C.fread(buf, 1, size, f)
    C.fclose(f)

    return ffi.string(buf, size)
end

return fileio
