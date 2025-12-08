local nginx_signals = require("apiok/cmd/utils/nginx_signals")

local lapp = [[
Usage: apiok reload
]]

local function execute()
    nginx_signals.reload()
end

return {
    lapp = lapp,
    execute = execute
}