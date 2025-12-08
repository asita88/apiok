local nginx_signals = require "apiok/cmd/utils/nginx_signals"

local lapp = [[
Usage: apiok quit
]]

local function execute()
    nginx_signals.quit()
end

return {
    lapp = lapp,
    execute = execute
}