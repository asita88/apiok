
local nginx_signals = require "apiok/cmd/utils/nginx_signals"

local lapp = [[
Usage: apiok test
]]

local function execute(args)
    nginx_signals.test(args.apiok_home)
end

return {
    lapp = lapp,
    execute = execute
}