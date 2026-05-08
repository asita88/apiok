local nginx_signals = require "apiok/cmd/utils/nginx_signals"

local lapp = [[
Usage: apiok quit
]]

local function execute(args)
    nginx_signals.quit(args.apiok_home)
end

return {
    lapp = lapp,
    execute = execute
}