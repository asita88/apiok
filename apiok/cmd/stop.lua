local nginx_signals = require "apiok/cmd/utils/nginx_signals"

local lapp = [[
Usage: apiok stop
]]

local function execute()
    nginx_signals.stop()
end

return {
    lapp = lapp,
    execute = execute
}