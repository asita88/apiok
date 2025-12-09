local version = setmetatable({
    major = 1,
    minor = 0,
    patch = 0,
}, {
    __tostring = function(v)
        return string.format("%d.%d.%d", v.major, v.minor, v.patch)
    end
})

return {
    __NAME = "APIOK",
    __VERSION = tostring(version),
    __VERSION_NUM = tonumber(string.format("%d%.2d%.2d",
            version.minor * 100,
            version.minor * 10,
            version.patch
    ))
}
