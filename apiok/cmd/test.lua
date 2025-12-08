
local nginx_signals = require "apiok/cmd/utils/nginx_signals"

local lapp = [[
Usage: apiok test
]]

local function execute()
    nginx_signals.test()
end

return {
    lapp = lapp,
    execute = execute
}