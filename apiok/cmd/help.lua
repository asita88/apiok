local function execute()
    print([[
    Usage: apiok [action] <argument>
    help:       show this message, then exit
    start:      start the apiok server
    quit:       quit the apiok server
    stop:       stop the apiok server
    restart:    restart the apiok server
    reload:     reload the apiok server
    test:       test the apiok nginx config
    env:        check apiok running environment
    version:    print apiok's version
    ]])
end

local lapp = [[
Usage: apiok help
]]


return {
    lapp = lapp,
    execute = execute
}