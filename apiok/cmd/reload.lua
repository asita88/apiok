local nginx_signals = require("apiok/cmd/utils/nginx_signals")

local lapp = [[
Usage: apiok reload
]]

local function execute(args)
    nginx_signals.reload(args.apiok_home)
end

return {
    lapp = lapp,
    execute = execute
}