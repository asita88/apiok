local nginx_signals = require "apiok/cmd/utils/nginx_signals"

local lapp = [[
Usage: apiok stop
]]

local function execute(args)
    nginx_signals.stop(args.apiok_home)
end

return {
    lapp = lapp,
    execute = execute
}